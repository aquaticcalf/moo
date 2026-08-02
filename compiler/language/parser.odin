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
    if !has_errors(&diagnostics) {
        semantic_check(program, &diagnostics)
    }
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
    parse_block(tokens, &index, diagnostics, &program.statements)
    return program
}

// parse a sequence of statements; stops when a Dedent (or Eof) is reached
parse_block :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics, stmts: ^[dynamic]Stmt) -> bool {
    for index^ < len(tokens) {
        token := tokens[index^]
        #partial switch token.kind {
        case .Newline:
            index^ += 1
            continue
        case .Eof:
            return true
        case .Dedent:
            return true
        case .Keyword_If:
            if !parse_if_block(tokens, index, diagnostics, stmts) {
                return false
            }
        case .Keyword_Otherwise:
            reportf(diagnostics, token.span, "unexpected 'otherwise'")
            skip_to_line_end(tokens, index)
        case .Identifier:
            if index^ + 1 < len(tokens) && tokens[index^ + 1].kind == .Keyword_Is {
                if !parse_variable_decl(tokens, index, diagnostics, stmts) {
                    return false
                }
            } else if index^ + 1 < len(tokens) && tokens[index^ + 1].kind == .Keyword_Becomes {
                if !parse_variable_assign(tokens, index, diagnostics, stmts) {
                    return false
                }
            } else {
                reportf(diagnostics, token.span, "expected 'show', 'if', 'name is value' or 'name becomes value'")
                skip_to_line_end(tokens, index)
            }
        case .Keyword_Show:
            if !parse_show(tokens, index, diagnostics, stmts) {
                return false
            }
        case .Keyword_Make:
            if !parse_function(tokens, index, diagnostics, stmts) {
                return false
            }
        case .Keyword_Give:
            if !parse_return(tokens, index, diagnostics, stmts) {
                return false
            }
        case:
            reportf(diagnostics, token.span, "expected a statement")
            skip_to_line_end(tokens, index)
        }
    }
    return true
}

// skip until the end of the current logical line
skip_to_line_end :: proc(tokens: []Token, index: ^int) {
    for index^ < len(tokens) &&
        tokens[index^].kind != .Newline &&
        tokens[index^].kind != .Eof &&
        tokens[index^].kind != .Dedent {
        index^ += 1
    }
}

// parse "show <expression>"
parse_show :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics, stmts: ^[dynamic]Stmt) -> bool {
    token := tokens[index^]
    index^ += 1

    expression, ok := parse_expression(tokens, index, diagnostics)
    if !ok {
        skip_to_line_end(tokens, index)
        return false
    }
    append(stmts, Show{span = token.span, expr = expression})

    if index^ < len(tokens) && tokens[index^].kind != .Newline && tokens[index^].kind != .Eof && tokens[index^].kind != .Dedent {
        reportf(diagnostics, tokens[index^].span, "expected the line to end after show")
        skip_to_line_end(tokens, index)
    }
    return true
}

// parse a function declaration: "make name(parameters):"
parse_function :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics, stmts: ^[dynamic]Stmt) -> bool {
    token := tokens[index^]
    index^ += 1
    if index^ >= len(tokens) || tokens[index^].kind != .Identifier {
        reportf(diagnostics, token.span, "expected a function name after 'make'")
        skip_to_line_end(tokens, index)
        return false
    }
    name := strings.clone(tokens[index^].text)
    index^ += 1
    parameters: [dynamic]string
    if index^ >= len(tokens) || tokens[index^].kind != .LParen {
        reportf(diagnostics, token.span, "expected '(' after the function name")
        delete(name)
        skip_to_line_end(tokens, index)
        return false
    }
    index^ += 1
    for index^ < len(tokens) && tokens[index^].kind != .RParen {
        if tokens[index^].kind != .Identifier {
            reportf(diagnostics, tokens[index^].span, "expected a parameter name")
            delete(name)
            delete(parameters)
            skip_to_line_end(tokens, index)
            return false
        }
        append(&parameters, strings.clone(tokens[index^].text))
        index^ += 1
        if index^ < len(tokens) && tokens[index^].kind == .Comma {
            index^ += 1
        } else if index^ < len(tokens) && tokens[index^].kind != .RParen {
            reportf(diagnostics, tokens[index^].span, "expected ',' between parameters")
            delete(name)
            delete(parameters)
            skip_to_line_end(tokens, index)
            return false
        }
    }
    if index^ >= len(tokens) || tokens[index^].kind != .RParen {
        reportf(diagnostics, token.span, "expected ')' after parameters")
        delete(name)
        delete(parameters)
        return false
    }
    index^ += 1
    if index^ >= len(tokens) || tokens[index^].kind != .Colon {
        reportf(diagnostics, token.span, "expected ':' after the function header")
        delete(name)
        delete(parameters)
        skip_to_line_end(tokens, index)
        return false
    }
    index^ += 1
    body: [dynamic]Stmt
    if !parse_indented_body(tokens, index, diagnostics, &body) {
        delete(name)
        delete(parameters)
        destroy_stmts(&body)
        return false
    }
    if index^ < len(tokens) && tokens[index^].kind == .Dedent {
        index^ += 1
    }
    append(stmts, Function{span = token.span, name = name, parameters = parameters, body = body})
    return true
}

// parse "give expression"
parse_return :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics, stmts: ^[dynamic]Stmt) -> bool {
    token := tokens[index^]
    index^ += 1
    expression, ok := parse_expression(tokens, index, diagnostics)
    if !ok {
        skip_to_line_end(tokens, index)
        return false
    }
    append(stmts, Return{span = token.span, expr = expression})
    return true
}

// parse "name becomes expression"
parse_variable_assign :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics, stmts: ^[dynamic]Stmt) -> bool {
    token := tokens[index^]
    index^ += 2

    expression, ok := parse_expression(tokens, index, diagnostics)
    if !ok {
        skip_to_line_end(tokens, index)
        return false
    }
    append(stmts, Variable_Assign{span = token.span, name = strings.clone(token.text), expr = expression})

    if index^ < len(tokens) && tokens[index^].kind != .Newline && tokens[index^].kind != .Eof && tokens[index^].kind != .Dedent {
        reportf(diagnostics, tokens[index^].span, "expected the line to end after reassignment")
        skip_to_line_end(tokens, index)
    }
    return true
}

// parse "name is expression"
parse_variable_decl :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics, stmts: ^[dynamic]Stmt) -> bool {
    token := tokens[index^]
    index^ += 2 // consume the name and the 'is'

    expression, ok := parse_expression(tokens, index, diagnostics)
    if !ok {
        skip_to_line_end(tokens, index)
        return false
    }
    append(stmts, Variable_Decl{span = token.span, name = strings.clone(token.text), expr = expression})

    if index^ < len(tokens) && tokens[index^].kind != .Newline && tokens[index^].kind != .Eof && tokens[index^].kind != .Dedent {
        reportf(diagnostics, tokens[index^].span, "expected the line to end after assignment")
        skip_to_line_end(tokens, index)
    }
    return true
}

// parse an "if ...: <body>" possibly followed by "otherwise" branches
parse_if_block :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics, stmts: ^[dynamic]Stmt) -> bool {
    if_token := tokens[index^]
    index^ += 1

    condition, ok := parse_expression(tokens, index, diagnostics)
    if !ok {
        skip_to_line_end(tokens, index)
        return false
    }

    // the ':' that ends the condition line
    if index^ >= len(tokens) || tokens[index^].kind != .Colon {
        reportf(diagnostics, tokens[index^ - 1].span, "expected ':' after the if condition")
        skip_to_line_end(tokens, index)
        destroy_expr(condition)
        return false
    }
    index^ += 1

    if_block := If_Block{span = if_token.span, condition = condition}

    if !parse_indented_body(tokens, index, diagnostics, &if_block.body) {
        destroy_stmt(&if_block)
        return false
    }

    // consume the dedent that ended the if body, if any
    if index^ < len(tokens) && tokens[index^].kind == .Dedent {
        index^ += 1
    }

    // an "otherwise" chain may follow at the same level.
    // the plain "otherwise:" applies to the innermost "otherwise if" written so far.
    current := &if_block
    for index^ < len(tokens) && tokens[index^].kind == .Keyword_Otherwise {
        index^ += 1
        if index^ < len(tokens) && tokens[index^].kind == .Keyword_If {
            // otherwise if <condition>: <body>
            nested := new(If_Block)
            nested.span = tokens[index^].span
            index^ += 1
            nested_cond, cok := parse_expression(tokens, index, diagnostics)
            if !cok {
                destroy_stmt(&if_block)
                return false
            }
            nested.condition = nested_cond
            if index^ >= len(tokens) || tokens[index^].kind != .Colon {
                reportf(diagnostics, tokens[index^ - 1].span, "expected ':' after the otherwise if condition")
                destroy_stmt(&if_block)
                return false
            }
            index^ += 1
            if !parse_indented_body(tokens, index, diagnostics, &nested.body) {
                destroy_stmt(&if_block)
                return false
            }
            if index^ < len(tokens) && tokens[index^].kind == .Dedent {
                index^ += 1
            }
            current.else_if = nested
            current = nested
        } else {
            // plain otherwise: <body> attaches to the innermost block
            if index^ >= len(tokens) || tokens[index^].kind != .Colon {
                reportf(diagnostics, tokens[index^ - 1].span, "expected ':' after 'otherwise'")
                destroy_stmt(&if_block)
                return false
            }
            index^ += 1
            if !parse_indented_body(tokens, index, diagnostics, &current.else_body) {
                destroy_stmt(&if_block)
                return false
            }
            if index^ < len(tokens) && tokens[index^].kind == .Dedent {
                index^ += 1
            }
            current.has_else_body = true
            break
        }
    }

    append(stmts, if_block)
    return true
}

// parse the indented body of a block: expects an Indent then statements
parse_indented_body :: proc(tokens: []Token, index: ^int, diagnostics: ^Diagnostics, body: ^[dynamic]Stmt) -> bool {
    if index^ < len(tokens) && tokens[index^].kind == .Newline {
        index^ += 1
    }
    if index^ >= len(tokens) || tokens[index^].kind != .Indent {
        reportf(diagnostics, tokens[index^ - 1].span, "expected an indented block")
        return false
    }
    index^ += 1
    parse_block(tokens, index, diagnostics, body)
    return true
}

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
