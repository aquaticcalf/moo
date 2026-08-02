package frontend

import "core:strconv"
import "core:strings"

// the lowest level of an expression: numbers, strings, parentheses and unary minus
parse_primary :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics) -> (Expr, bool) {
    if index^ >= len(tokens) {
        return nil, false
    }

    token := tokens[index^]
    #partial switch token.kind {
    case .Identifier:
        index^ += 1
        if index^ >= len(tokens) || tokens[index^].kind != .LParen {
            return Variable{span = token.span, name = strings.clone(token.text)}, true
        }
        index^ += 1
        arguments: [dynamic]Expr
        if index^ < len(tokens) && tokens[index^].kind != .RParen {
            for {
                argument, argument_ok := parse_expression(tokens, index, diagnostics)
                if !argument_ok {
                    delete(arguments)
                    return nil, false
                }
                append(&arguments, argument)
                if index^ < len(tokens) && tokens[index^].kind == .Comma {
                    index^ += 1
                    continue
                }
                break
            }
        }
        if index^ >= len(tokens) || tokens[index^].kind != .RParen {
            reportf(diagnostics, token.span, "expected ')' after function arguments")
            for argument in arguments { destroy_expr(argument) }
            delete(arguments)
            return nil, false
        }
        index^ += 1
        return Call{span = token.span, name = strings.clone(token.text), arguments = arguments}, true
    case .Keyword_True:
        index^ += 1
        return Literal{span = token.span, value = 1, is_boolean = true}, true
    case .Keyword_False:
        index^ += 1
        return Literal{span = token.span, value = 0, is_boolean = true}, true
    case .Number:
        index^ += 1
        value, ok := strconv.parse_i64(token.text)
        if !ok {
            reportf(diagnostics, token.span, "invalid number '%s'", token.text)
            return nil, false
        }
        return Literal{span = token.span, value = value}, true
    case .String:
        index^ += 1
        return Literal{span = token.span, is_string = true, text = strings.clone(token.text)}, true
    case .LParen:
        index^ += 1
        inner, ok := parse_expression(tokens, index, diagnostics)
        if !ok {
            return nil, false
        }
        if index^ >= len(tokens) || tokens[index^].kind != .RParen {
            reportf(diagnostics, token.span, "expected ')'")
            return nil, false
        }
        index^ += 1
        grouped := new(Expr)
        grouped^ = inner
        return Grouping{span = token.span, inner = grouped}, true
    case:
        reportf(diagnostics, token.span, "expected an expression")
        return nil, false
    }
}

// a unary minus turns an expression into 0 - expression
parse_unary :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics) -> (Expr, bool) {
    if index^ < len(tokens) && tokens[index^].kind == .Minus {
        token := tokens[index^]
        index^ += 1
        operand, ok := parse_unary(tokens, index, diagnostics)
        if !ok {
            return nil, false
        }
        left := new(Expr)
        right := new(Expr)
        left^ = Literal{span = token.span, value = 0}
        right^ = operand
        return Binary{span = token.span, op = .Sub, left = left, right = right}, true
    }
    return parse_primary(tokens, index, diagnostics)
}

// what binary operators exist and how tightly they bind (precedence)
binary_op :: proc(kind: Token_Kind) -> (Bin_Op, int, bool) {
    #partial switch kind {
    case .Plus:
        return .Add, 1, true
    case .Minus:
        return .Sub, 1, true
    case .Star:
        return .Mul, 2, true
    case .Slash:
        return .Div, 2, true
    }
    return {}, 0, false
}

// precedence climbing: this makes 2+3*4 parse as 2+(3*4)
parse_binary :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics, minimum: int) -> (Expr, bool) {
    left, ok := parse_unary(tokens, index, diagnostics)
    if !ok {
        return nil, false
    }

    for index^ < len(tokens) {
        op, precedence, is_op := binary_op(tokens[index^].kind)
        if !is_op || precedence < minimum {
            break
        }
        operator := tokens[index^]
        index^ += 1

        right, right_ok := parse_binary(tokens, index, diagnostics, precedence + 1)
        if !right_ok {
            return nil, false
        }

        left_node := new(Expr)
        right_node := new(Expr)
        left_node^ = left
        right_node^ = right
        left = Binary{span = operator.span, op = op, left = left_node, right = right_node}
    }

    return left, true
}

// a full expression: everything with a value, including a comparison
parse_expression :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics) -> (Expr, bool) {
    left, ok := parse_binary(tokens, index, diagnostics, 1)
    if !ok {
        return nil, false
    }

    // a comparison: "left is <phrase> right"
    if index^ < len(tokens) && tokens[index^].kind == .Comparison {
        comparison := tokens[index^]
        index^ += 1
        right, rok := parse_expression(tokens, index, diagnostics)
        if !rok {
            destroy_expr(left)
            return nil, false
        }
        left_node := new(Expr)
        right_node := new(Expr)
        left_node^ = left
        right_node^ = right
        return Comparison{span = comparison.span, op = comparison.op, left = left_node, right = right_node}, true
    }

    return left, true
}
