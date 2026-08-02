package ir

import "core:strings"

import "compiler:frontend"

// the value kinds understood by the backend-neutral moo module
Value_Type :: enum {
    Integer,
    Boolean,
    String,
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
    collect_expressions(program.statements[:], &module.expressions)
    for statement in program.statements {
        lowered, ok := lower_statement(statement)
        if ok { append(&module.statements, lowered) }
    }
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
            signature := Function{name = function.name, result = .Integer}
            for parameter in function.parameters {
                append(&signature.parameter_names, strings.clone(parameter))
                append(&signature.parameters, Value_Type.Integer)
            }
            for statement in function.body {
                lowered, ok := lower_statement(statement)
                if ok { append(&signature.body, lowered) }
            }
            append(functions, signature)
        }
    }
}

// collect variable types from declarations in every block
collect_variables :: proc(stmts: []frontend.Stmt, variables: ^[dynamic]Variable) {
    for stmt in stmts {
        switch s in stmt {
        case frontend.Variable_Decl:
            if literal, ok := s.expr.(frontend.Literal); ok {
                value_type := Value_Type.Integer
                if literal.is_string { value_type = .String }
                if literal.is_boolean { value_type = .Boolean }
                append(variables, Variable{name = s.name, type = value_type})
            }
        case frontend.If_Block:
            collect_variables(s.body[:], variables)
            if s.else_if != nil { collect_if_variables(s.else_if, variables) }
            collect_variables(s.else_body[:], variables)
        case frontend.Function:
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

// look up the inferred type of a stored variable
variable_type :: proc(module: Module, name: string) -> (Value_Type, bool) {
    for variable in module.variables {
        if variable.name == name { return variable.type, true }
    }
    return .Integer, false
}
