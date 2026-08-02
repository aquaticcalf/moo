package language

import "core:strconv"
import "core:strings"

// read the file and return parsed content
parse_file :: proc(path: string) -> Parse_Result {
    diagnostics := Diagnostics{path = path}
    text, ok := read_text(path, &diagnostics)
    if !ok {
        return Parse_Result{diagnostics = diagnostics}
    }

    return parse(text, path)
}

// takes the source code and parses it
parse :: proc(source: string, path: string) -> Parse_Result {
    diagnostics := Diagnostics{path = path}
    tokens := scan(source, &diagnostics)
    defer delete(tokens)

    if has_errors(&diagnostics) {
        return Parse_Result{diagnostics = diagnostics}
    }

    program := parse_tokens(tokens[:], &diagnostics)
    if has_errors(&diagnostics) {
        destroy_program(&program)
        return Parse_Result{diagnostics = diagnostics}
    }

    return Parse_Result{program = program, diagnostics = diagnostics, ok = true, source_hash = hash_source(source)}
}

// here is where each token gets a meaning to it
parse_tokens :: proc(tokens: []Token, diagnostics: ^Diagnostics) -> Program {
    program: Program
    index := 0

    for index < len(tokens) {
        token := tokens[index]
        if token.kind == .Newline {
            index += 1
            continue
        }
        if token.kind == .Eof {
            break
        }

        if token.kind != .Keyword_Show {
            reportf(diagnostics, token.span, "expected 'show'")
            index += 1
            continue
        }
        index += 1

        expression, ok := parse_expression(tokens, &index, diagnostics)
        if !ok {
            for index < len(tokens) && tokens[index].kind != .Newline && tokens[index].kind != .Eof {
                index += 1
            }
            continue
        }

        append(&program.shows, Show{span = token.span, expr = expression})

        if index < len(tokens) && tokens[index].kind != .Newline && tokens[index].kind != .Eof {
            reportf(diagnostics, tokens[index].span, "expected the line to end after show")
            for index < len(tokens) && tokens[index].kind != .Newline && tokens[index].kind != .Eof {
                index += 1
            }
        }
    }

    return program
}

// the lowest level of an expression: numbers, strings, parentheses and unary minus
parse_primary :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics) -> (Expr, bool) {
    if index^ >= len(tokens) {
        return nil, false
    }

    token := tokens[index^]
    #partial switch token.kind {
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

// a full expression: everything with a value
parse_expression :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics) -> (Expr, bool) {
    return parse_binary(tokens, index, diagnostics, 1)
}
