package ir

// resolve call result types after all function signatures are known
resolve_module_calls :: proc(module: ^Module) {
    for index in 0..<len(module.expressions) {
        module.expressions[index] = resolve_expression_calls(module.expressions[index], module.functions[:], module.variables[:])
    }
    for function_index in 0..<len(module.functions) {
        for statement_index in 0..<len(module.functions[function_index].body) {
            module.functions[function_index].body[statement_index] = resolve_statement_calls(module.functions[function_index].body[statement_index], module.functions[:], module.variables[:])
        }
    }
    for index in 0..<len(module.statements) {
        module.statements[index] = resolve_statement_calls(module.statements[index], module.functions[:], module.variables[:])
    }
}

// resolve calls nested in one typed statement
resolve_statement_calls :: proc(statement: Statement, functions: []Function, variables: []Variable) -> Statement {
    switch value in statement {
    case Show_Statement:
        result := value
        result.value = resolve_expression_calls(result.value, functions, variables)
        return result
    case Assign_Statement:
        result := value
        result.value = resolve_expression_calls(result.value, functions, variables)
        return result
    case Return_Statement:
        result := value
        if result.has_value { result.value = resolve_expression_calls(result.value, functions, variables) }
        return result
    case If_Statement:
        result := value
        result.condition = resolve_expression_calls(result.condition, functions, variables)
        for index in 0..<len(result.body) { result.body[index] = resolve_statement_calls(result.body[index], functions, variables) }
        for index in 0..<len(result.else_body) { result.else_body[index] = resolve_statement_calls(result.else_body[index], functions, variables) }
        return result
    }
    return statement
}

// return the known type of one typed expression
expression_type :: proc(expression: Expression) -> Value_Type {
    switch value in expression {
    case Literal_Value: return value.type
    case Variable_Value: return value.type
    case Grouping_Value: return expression_type(value.inner^)
    case Binary_Value: return value.type
    case Comparison_Value: return .Boolean
    case Call_Value: return value.type
    }
    return .Nothing
}

// resolve calls recursively in one typed expression
resolve_expression_calls :: proc(expression: Expression, functions: []Function, variables: []Variable) -> Expression {
    switch value in expression {
    case Literal_Value:
        return expression
    case Variable_Value:
        result := value
        for variable in variables {
            if variable.name == result.name { result.type = variable.type; break }
        }
        return result
    case Grouping_Value:
        result := value
        result.inner^ = resolve_expression_calls(result.inner^, functions, variables)
        return result
    case Binary_Value:
        result := value
        result.left^ = resolve_expression_calls(result.left^, functions, variables)
        result.right^ = resolve_expression_calls(result.right^, functions, variables)
        if expression_type(result.left^) == .String && expression_type(result.right^) == .String && result.op == .Add {
            result.type = .String
        }
        return result
    case Comparison_Value:
        result := value
        result.left^ = resolve_expression_calls(result.left^, functions, variables)
        result.right^ = resolve_expression_calls(result.right^, functions, variables)
        return result
    case Call_Value:
        result := value
        for index in 0..<len(result.arguments) { result.arguments[index] = resolve_expression_calls(result.arguments[index], functions, variables) }
        for function in functions {
            if function.name == result.name {
                result.type = function.result
                break
            }
        }
        return result
    }
    return expression
}
