package language

import "core:strings"

parse_file :: proc(path: string) -> Parse_Result {
    diagnostics := Diagnostics{path = path}
    text, ok := read_text(path, &diagnostics)
    if !ok {
        return Parse_Result{diagnostics = diagnostics}
    }

    return parse(text, path)
}

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

    return Parse_Result{program = program, diagnostics = diagnostics, ok = true}
}

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

        if index >= len(tokens) || tokens[index].kind != .String {
            reportf(diagnostics, token.span, "expected text after show")
            for index < len(tokens) && tokens[index].kind != .Newline && tokens[index].kind != .Eof {
                index += 1
            }
            continue
        }

        text := tokens[index]
        append(&program.shows, Show{text = strings.clone(text.text), span = text.span})
        index += 1

        if index < len(tokens) && tokens[index].kind != .Newline && tokens[index].kind != .Eof {
            reportf(diagnostics, tokens[index].span, "expected the line to end after show")
            for index < len(tokens) && tokens[index].kind != .Newline && tokens[index].kind != .Eof {
                index += 1
            }
        }
    }

    return program
}
