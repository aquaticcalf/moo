package ir

import "core:strings"

import "compiler:frontend"

// the value kinds understood by the backend-neutral moo module
Value_Type :: enum {
    Integer,
    Boolean,
    String,
    Nothing,
}

// one variable and the type inferred for its stored value
Variable :: struct {
    name: string,
    type: Value_Type,
}

// one typed function signature available to a backend
Function :: struct {
    name: string,
    parameter_names: [dynamic]string,
    parameters: [dynamic]Value_Type,
    result: Value_Type,
    body: [dynamic]Statement,
}

// a compiler-owned module between language analysis and native backends
Module :: struct {
    program: frontend.Program,
    variables: [dynamic]Variable,
    functions: [dynamic]Function,
    expressions: [dynamic]Expression,
    statements: [dynamic]Statement,
}

// lower a checked moo program into a typed backend-neutral module
lower :: proc(program: frontend.Program) -> Module {
    module := Module{program = program}
    collect_variables(program.statements[:], &module.variables)
    collect_functions(program.statements[:], &module.functions)
    collect_call_parameter_types(program.statements[:], &module.functions)
    refresh_function_results(program.statements[:], &module.functions)
    collect_expressions(program.statements[:], &module.expressions)
    for statement in program.statements {
        lowered, ok := lower_statement(statement)
        if ok { append(&module.statements, lowered) }
    }
    resolve_module_calls(&module)
    return module
}

// release backend metadata while leaving the source program untouched
destroy_module :: proc(module: ^Module) {
    for function in module.functions {
        for name in function.parameter_names { delete(name) }
        delete(function.parameter_names)
        delete(function.parameters)
        for statement in function.body { destroy_statement(statement) }
        delete(function.body)
    }
    delete(module.functions)
    delete(module.variables)
    for expression in module.expressions {
        destroy_expression(expression)
    }
    delete(module.expressions)
    for statement in module.statements { destroy_statement(statement) }
    delete(module.statements)
}

// collect expressions so backend lowering has typed values available
collect_expressions :: proc(stmts: []frontend.Stmt, expressions: ^[dynamic]Expression) {
    for stmt in stmts {
        switch s in stmt {
        case frontend.Show:
            append(expressions, lower_expression(s.expr))
        case frontend.Variable_Decl:
            append(expressions, lower_expression(s.expr))
        case frontend.Variable_Assign:
            append(expressions, lower_expression(s.expr))
        case frontend.Return:
            append(expressions, lower_expression(s.expr))
        case frontend.If_Block:
            append(expressions, lower_expression(s.condition))
            collect_expressions(s.body[:], expressions)
            if s.else_if != nil { collect_if_expressions(s.else_if, expressions) }
            collect_expressions(s.else_body[:], expressions)
        case frontend.Function:
            collect_expressions(s.body[:], expressions)
        }
    }
}

// collect expressions from an otherwise-if chain
collect_if_expressions :: proc(block: ^frontend.If_Block, expressions: ^[dynamic]Expression) {
    if block == nil { return }
    append(expressions, lower_expression(block.condition))
    collect_expressions(block.body[:], expressions)
    if block.else_if != nil { collect_if_expressions(block.else_if, expressions) }
    collect_expressions(block.else_body[:], expressions)
}

// collect typed function signatures from declarations
collect_functions :: proc(stmts: []frontend.Stmt, functions: ^[dynamic]Function) {
    for stmt in stmts {
        if function, ok := stmt.(frontend.Function); ok {
            signature := Function{name = function.name, result = .Nothing}
            for parameter in function.parameters {
                append(&signature.parameter_names, strings.clone(parameter))
                append(&signature.parameters, Value_Type.Integer)
            }
            for statement in function.body {
                if returned, is_return := statement.(frontend.Return); is_return && returned.has_value {
                    signature.result = frontend_expression_type_with_parameters(returned.expr, function.parameters[:], signature.parameters[:])
                }
                lowered, ok := lower_statement(statement)
                if ok { append(&signature.body, lowered) }
            }
            append(functions, signature)
        }
    }
}

refresh_function_results :: proc(stmts: []frontend.Stmt, functions: ^[dynamic]Function) {
    for stmt in stmts {
        if function, ok := stmt.(frontend.Function); ok {
            for statement in function.body {
                if returned, is_return := statement.(frontend.Return); is_return && returned.has_value {
                    for index in 0..<len(functions) {
                        if functions[index].name == function.name {
                            functions[index].result = frontend_expression_type_with_parameters(returned.expr, function.parameters[:], functions[index].parameters[:])
                        }
                    }
                }
            }
        }
    }
}

// infer function parameter types from every call site
collect_call_parameter_types :: proc(stmts: []frontend.Stmt, functions: ^[dynamic]Function) {
    for stmt in stmts {
        switch value in stmt {
        case frontend.Show:
            collect_call_types(value.expr, functions)
        case frontend.Variable_Decl:
            collect_call_types(value.expr, functions)
        case frontend.Variable_Assign:
            collect_call_types(value.expr, functions)
        case frontend.Return:
            if value.has_value { collect_call_types(value.expr, functions) }
        case frontend.If_Block:
            collect_call_types(value.condition, functions)
            collect_call_parameter_types(value.body[:], functions)
            collect_call_parameter_types(value.else_body[:], functions)
        case frontend.Function:
            collect_call_parameter_types(value.body[:], functions)
        }
    }
}

// infer one call's argument types into its function signature
collect_call_types :: proc(expr: frontend.Expr, functions: ^[dynamic]Function) {
    switch value in expr {
    case frontend.Call:
        for function_index := 0; function_index < len(functions); function_index += 1 {
            if functions[function_index].name != value.name { continue }
            for argument, index in value.arguments {
                if index >= len(functions[function_index].parameters) { break }
                if literal, ok := argument.(frontend.Literal); ok {
                    if literal.is_string { functions[function_index].parameters[index] = .String }
                    if literal.is_boolean { functions[function_index].parameters[index] = .Boolean }
                }
            }
        }
        for argument in value.arguments { collect_call_types(argument, functions) }
    case frontend.Binary:
        collect_call_types(value.left^, functions)
        collect_call_types(value.right^, functions)
    case frontend.Comparison:
        collect_call_types(value.left^, functions)
        collect_call_types(value.right^, functions)
    case frontend.Grouping:
        collect_call_types(value.inner^, functions)
    case frontend.Literal, frontend.Variable:
    }
}

frontend_expression_type_with_parameters :: proc(expr: frontend.Expr, names: []string, types: []Value_Type) -> Value_Type {
    #partial switch value in expr {
    case frontend.Variable:
        for name, index in names { if name == value.name && index < len(types) { return types[index] } }
    case frontend.Binary:
        left := frontend_expression_type_with_parameters(value.left^, names, types)
        right := frontend_expression_type_with_parameters(value.right^, names, types)
        if left == .String || right == .String { return .String }
    case frontend.Grouping:
        return frontend_expression_type_with_parameters(value.inner^, names, types)
    }
    return frontend_expression_type(expr)
}

// infer the source type of an expression for storage declarations
frontend_expression_type :: proc(expr: frontend.Expr) -> Value_Type {
    switch value in expr {
    case frontend.Literal:
        if value.is_string { return .String }
        if value.is_boolean { return .Boolean }
        return .Integer
    case frontend.Grouping:
        return frontend_expression_type(value.inner^)
    case frontend.Binary:
        if frontend_expression_type(value.left^) == .String && frontend_expression_type(value.right^) == .String && value.op == .Add { return .String }
        return .Integer
    case frontend.Comparison:
        return .Boolean
    case frontend.Variable, frontend.Call:
        return .Integer
    }
    return .Integer
}

// collect variable types from declarations in every block
collect_variables :: proc(stmts: []frontend.Stmt, variables: ^[dynamic]Variable) {
    for stmt in stmts {
        switch s in stmt {
        case frontend.Variable_Decl:
            value_type := frontend_expression_type(s.expr)
            append(variables, Variable{name = s.name, type = value_type})
        case frontend.If_Block:
            collect_variables(s.body[:], variables)
            if s.else_if != nil { collect_if_variables(s.else_if, variables) }
            collect_variables(s.else_body[:], variables)
        case frontend.Function:
            for parameter in s.parameters {
                if _, exists := variable_type_from_list(variables[:], parameter); !exists {
                    append(variables, Variable{name = parameter, type = .Integer})
                }
            }
            collect_variables(s.body[:], variables)
        case frontend.Variable_Assign, frontend.Show, frontend.Return:
        }
    }
}

// collect variables from an otherwise-if chain
collect_if_variables :: proc(block: ^frontend.If_Block, variables: ^[dynamic]Variable) {
    if block == nil { return }
    collect_variables(block.body[:], variables)
    if block.else_if != nil { collect_if_variables(block.else_if, variables) }
    collect_variables(block.else_body[:], variables)
}

variable_type_from_list :: proc(variables: []Variable, name: string) -> (Value_Type, bool) {
    for variable in variables { if variable.name == name { return variable.type, true } }
    return .Integer, false
}

// look up the inferred type of a stored variable
variable_type :: proc(module: Module, name: string) -> (Value_Type, bool) {
    for variable in module.variables {
        if variable.name == name { return variable.type, true }
    }
    return .Integer, false
}
