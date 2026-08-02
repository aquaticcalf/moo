package semantic

import "compiler:frontend"

// check the complete program without requiring written type annotations
semantic_check :: proc(program: frontend.Program, diagnostics: ^frontend.Diagnostics) {
    symbols: [dynamic]Symbol
    functions: [dynamic]Function_Info
    defer delete(symbols)
    defer delete(functions)
    for stmt in program.statements {
        if function, ok := stmt.(frontend.Function); ok {
            if _, exists := find_function(functions[:], function.name); exists {
                frontend.reportf(diagnostics, function.span, "'%s' is already a function", function.name)
            } else {
                info := Function_Info{name = function.name, arity = len(function.parameters), result = frontend.Type.Unknown}
                for _ in function.parameters { append(&info.parameters, frontend.Type.Unknown) }
                append(&functions, info)
            }
        }
    }
    infer_function_parameters(program.statements[:], functions[:], diagnostics)
    infer_function_results(program.statements[:], &functions, diagnostics)
    check_statements(program.statements[:], &symbols, functions[:], diagnostics, false)
}

// infer parameter types from calls before checking function bodies
infer_function_parameters :: proc(stmts: []frontend.Stmt, functions: []Function_Info, diagnostics: ^frontend.Diagnostics) {
    symbols: [dynamic]Symbol
    defer delete(symbols)
    for stmt in stmts {
        #partial switch value in stmt {
        case frontend.Show:
            infer_expr(value.expr, symbols[:], functions, diagnostics)
        case frontend.Variable_Decl:
            value_type := infer_expr(value.expr, symbols[:], functions, diagnostics)
            set_symbol(&symbols, value.name, value_type)
        case frontend.Variable_Assign:
            infer_expr(value.expr, symbols[:], functions, diagnostics)
        case frontend.Return:
            if value.has_value { infer_expr(value.expr, symbols[:], functions, diagnostics) }
        case frontend.If_Block:
            infer_expr(value.condition, symbols[:], functions, diagnostics)
            infer_function_parameters(value.body[:], functions, diagnostics)
            infer_function_parameters(value.else_body[:], functions, diagnostics)
        case frontend.Function:
            local_symbols: [dynamic]Symbol
            for parameter in value.parameters { set_symbol(&local_symbols, parameter, .Unknown) }
            infer_function_parameters_with_symbols(value.body[:], functions, diagnostics, local_symbols[:])
            delete(local_symbols)
        }
    }
}

infer_function_parameters_with_symbols :: proc(stmts: []frontend.Stmt, functions: []Function_Info, diagnostics: ^frontend.Diagnostics, symbols: []Symbol) {
    for stmt in stmts {
        #partial switch value in stmt {
        case frontend.Show: infer_expr(value.expr, symbols, functions, diagnostics)
        case frontend.Variable_Decl: infer_expr(value.expr, symbols, functions, diagnostics)
        case frontend.Variable_Assign: infer_expr(value.expr, symbols, functions, diagnostics)
        case frontend.Return: if value.has_value { infer_expr(value.expr, symbols, functions, diagnostics) }
        case frontend.If_Block:
            infer_expr(value.condition, symbols, functions, diagnostics)
            infer_function_parameters_with_symbols(value.body[:], functions, diagnostics, symbols)
            infer_function_parameters_with_symbols(value.else_body[:], functions, diagnostics, symbols)
        case frontend.Function:
        }
    }
}

// infer return types before checking calls that use a function
infer_function_results :: proc(stmts: []frontend.Stmt, functions: ^[dynamic]Function_Info, diagnostics: ^frontend.Diagnostics) {
    for stmt in stmts {
        if function, ok := stmt.(frontend.Function); ok {
            local_symbols: [dynamic]Symbol
            defer delete(local_symbols)
            function_index := find_function_index(functions[:], function.name)
            for parameter, parameter_index in function.parameters {
                parameter_type := frontend.Type.Integer
                if function_index >= 0 && parameter_index < len(functions[function_index].parameters) {
                    parameter_type = functions[function_index].parameters[parameter_index]
                }
                set_symbol(&local_symbols, parameter, parameter_type)
            }
            for body_stmt in function.body {
                if returned, rok := body_stmt.(frontend.Return); rok {
                    value_type := frontend.Type.Nothing
                    if returned.has_value {
                        value_type = infer_expr(returned.expr, local_symbols[:], functions[:], diagnostics)
                    }
                    for index := 0; index < len(functions); index += 1 {
                        if functions[index].name == function.name {
                            functions[index].result = value_type
                        }
                    }
                    break
                }
            }
        }
    }
}

// look up an already introduced name
find_symbol :: proc(symbols: []Symbol, name: string) -> (frontend.Type, bool) {
    for symbol in symbols {
        if symbol.name == name {
            return symbol.type, true
        }
    }
    return .Unknown, false
}

// remember a newly introduced name
set_symbol :: proc(symbols: ^[dynamic]Symbol, name: string, type: frontend.Type) {
    append(symbols, Symbol{name = name, type = type})
}

// check a sequence of statements and infer every value used inside it
check_statements :: proc(stmts: []frontend.Stmt, symbols: ^[dynamic]Symbol, functions: []Function_Info, diagnostics: ^frontend.Diagnostics, inside_function: bool) {
    for stmt in stmts {
        #partial switch s in stmt {
        case frontend.Show:
            value_type := infer_expr(s.expr, symbols[:], functions, diagnostics)
            if value_type == .Unknown {
                continue
            }
            if value_type != .Integer && value_type != .String && value_type != .Boolean {
                frontend.reportf(diagnostics, s.span, "cannot show this value")
            }

        case frontend.Variable_Decl:
            value_type := infer_expr(s.expr, symbols[:], functions, diagnostics)
            if value_type == .Unknown {
                continue
            }
            if _, exists := find_symbol(symbols[:], s.name); exists {
                frontend.reportf(diagnostics, s.span, "'%s' already exists; use '%s becomes ...' to change it", s.name, s.name)
                continue
            }
            set_symbol(symbols, s.name, value_type)
        case frontend.Variable_Assign:
            value_type := infer_expr(s.expr, symbols[:], functions, diagnostics)
            old_type, exists := find_symbol(symbols[:], s.name)
            if !exists {
                frontend.reportf(diagnostics, s.span, "'%s' has not been introduced yet; use '%s is ...' first", s.name, s.name)
                continue
            }
            if value_type != .Unknown && old_type != value_type {
                frontend.reportf(diagnostics, s.span, "'%s' is %s, but the new value is %s", s.name, type_name(old_type), type_name(value_type))
            }
        case frontend.If_Block:
            condition_type := infer_expr(s.condition, symbols[:], functions, diagnostics)
            if condition_type != .Unknown && condition_type != .Boolean && condition_type != .Integer {
                frontend.reportf(diagnostics, s.span, "an if condition must be a number or a comparison")
            }
            check_statements(s.body[:], symbols, functions, diagnostics, inside_function)
            if s.else_if != nil {
                check_if_chain(s.else_if, symbols, functions, diagnostics, inside_function)
            }
            check_statements(s.else_body[:], symbols, functions, diagnostics, inside_function)
        case frontend.Function:
            local_symbols: [dynamic]Symbol
            defer delete(local_symbols)
            function_index := find_function_index(functions, s.name)
            for parameter, index in s.parameters {
                if _, exists := find_symbol(local_symbols[:], parameter); exists {
                    frontend.reportf(diagnostics, s.span, "parameter '%s' is repeated", parameter)
                } else {
                    parameter_type := frontend.Type.Integer
                    if function_index >= 0 && index < len(functions[function_index].parameters) {
                        parameter_type = functions[function_index].parameters[index]
                    }
                    set_symbol(&local_symbols, parameter, parameter_type)
                }
            }
            check_statements(s.body[:], &local_symbols, functions, diagnostics, true)
        case frontend.Return:
            if !inside_function {
                frontend.reportf(diagnostics, s.span, "'give' can only be used inside a function")
            } else if s.has_value {
                infer_expr(s.expr, symbols[:], functions, diagnostics)
            }
        }
    }
}

// check an otherwise-if chain recursively
check_if_chain :: proc(block: ^frontend.If_Block, symbols: ^[dynamic]Symbol, functions: []Function_Info, diagnostics: ^frontend.Diagnostics, inside_function: bool) {
    condition_type := infer_expr(block.condition, symbols[:], functions, diagnostics)
    if condition_type != .Unknown && condition_type != .Boolean && condition_type != .Integer {
        frontend.reportf(diagnostics, block.span, "an if condition must be a number or a comparison")
    }
    check_statements(block.body[:], symbols, functions, diagnostics, inside_function)
    if block.else_if != nil {
        check_if_chain(block.else_if, symbols, functions, diagnostics, inside_function)
    }
    check_statements(block.else_body[:], symbols, functions, diagnostics, inside_function)
}
