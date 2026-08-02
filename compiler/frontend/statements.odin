package frontend

import "core:strings"

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
    if index^ >= len(tokens) || tokens[index^].kind == .Newline || tokens[index^].kind == .Dedent || tokens[index^].kind == .Eof {
        append(stmts, Return{span = token.span, has_value = false})
        return true
    }
    expression, ok := parse_expression(tokens, index, diagnostics)
    if !ok {
        skip_to_line_end(tokens, index)
        return false
    }
    append(stmts, Return{span = token.span, expr = expression, has_value = true})
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
