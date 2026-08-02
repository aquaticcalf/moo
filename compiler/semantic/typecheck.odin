package semantic

import "compiler:frontend"

// infer the kind of an expression and report contradictions
infer_expr :: proc(expr: frontend.Expr, symbols: []Symbol, functions: []Function_Info, diagnostics: ^frontend.Diagnostics) -> frontend.Type {
    #partial switch e in expr {
    case frontend.Literal:
        if e.is_string {
            return .String
        }
        if e.is_boolean {
            return .Boolean
        }
        return .Integer
    case frontend.Variable:
        value_type, exists := find_symbol(symbols, e.name)
        if !exists {
            frontend.reportf(diagnostics, e.span, "'%s' has not been introduced yet; use '%s is ...' first", e.name, e.name)
            return .Unknown
        }
        return value_type
    case frontend.Grouping:
        return infer_expr(e.inner^, symbols, functions, diagnostics)
    case frontend.Call:
        function, exists := find_function(functions, e.name)
        if !exists {
            frontend.reportf(diagnostics, e.span, "'%s' is not a function", e.name)
        } else if len(e.arguments) != function.arity {
            frontend.reportf(diagnostics, e.span, "'%s' expects %d arguments, but got %d", e.name, function.arity, len(e.arguments))
        }
        for argument, index in e.arguments {
            argument_type := infer_expr(argument, symbols, functions, diagnostics)
            if exists && index < len(function.parameters) && argument_type != .Unknown {
                expected := functions[find_function_index(functions, e.name)].parameters[index]
                if expected == .Unknown {
                    functions[find_function_index(functions, e.name)].parameters[index] = argument_type
                } else if expected != argument_type {
                    frontend.reportf(diagnostics, e.span, "argument %d of '%s' has type %s, expected %s", index + 1, e.name, argument_type, expected)
                }
            }
        }
        if exists && function.result != .Unknown {
            return function.result
        }
        return .Unknown
    case frontend.Binary:
        left := infer_expr(e.left^, symbols, functions, diagnostics)
        right := infer_expr(e.right^, symbols, functions, diagnostics)
        if left == .Unknown || right == .Unknown {
            return .Unknown
        }
        if left == .String && right == .String && e.op == .Add {
            return .String
        }
        if left != .Integer || right != .Integer {
            frontend.reportf(diagnostics, e.span, "arithmetic needs numbers or string concatenation")
            return .Unknown
        }
        return .Integer
    case frontend.Comparison:
        left := infer_expr(e.left^, symbols, functions, diagnostics)
        right := infer_expr(e.right^, symbols, functions, diagnostics)
        if left == .Unknown || right == .Unknown {
            return .Unknown
        }
        if left != right || (left != .Integer && left != .Boolean) {
            frontend.reportf(diagnostics, e.span, "comparisons need matching number or boolean values")
            return .Unknown
        }
        return .Boolean
    }
    return .Unknown
}

// check whether an expression is a directly written string literal
is_direct_string :: proc(expr: frontend.Expr) -> bool {
    literal, ok := expr.(frontend.Literal)
    return ok && literal.is_string
}

// turn an inferred kind into friendly diagnostic wording
type_name :: proc(value_type: frontend.Type) -> string {
    #partial switch value_type {
    case .Unknown: return "an unknown value"
    case .Integer: return "a number"
    case .Boolean: return "a boolean"
    case .String: return "a string"
    case .Nothing: return "nothing"
    }
    return "an unknown value"
}
