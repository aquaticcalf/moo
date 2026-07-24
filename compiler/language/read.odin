package language

import "core:os"

is_letter :: proc(c: byte) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

read_text :: proc(path: string, diagnostics: ^Diagnostics) -> (string, bool) {
    data, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil {
        reportf(diagnostics, Span{line = 1, column = 1}, "could not read source file")
        return "", false
    }

    start := 0
    if len(data) >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
        start = 3
    }

    return string(data[start:]), true
}

scan :: proc(source: string, diagnostics: ^Diagnostics) -> [dynamic]Token {
    tokens: [dynamic]Token
    line := 1
    column := 1
    offset := 0

    for offset < len(source) {
        c := source[offset]

        if c == ' ' || c == '\t' || c == '\r' {
            offset += 1
            column += 1
            continue
        }

        if c == '\n' {
            append(&tokens, Token{kind = .Newline, span = Span{line = line, column = column}})
            offset += 1
            line += 1
            column = 1
            continue
        }

        if is_letter(c) {
            start := offset
            start_column := column
            for offset < len(source) && is_letter(source[offset]) {
                offset += 1
                column += 1
            }

            word := source[start:offset]
            span := Span{line = line, column = start_column}
            if word == "show" {
                append(&tokens, Token{kind = .Keyword_Show, text = word, span = span})
            } else {
                reportf(diagnostics, span, "unknown word '%s'", word)
            }
            continue
        }

        if c == '"' {
            start := offset
            start_column := column
            offset += 1
            column += 1
            closed := false

            for offset < len(source) && source[offset] != '\n' {
                if source[offset] == '\\' && offset + 1 < len(source) {
                    offset += 2
                    column += 2
                    continue
                }
                if source[offset] == '"' {
                    offset += 1
                    column += 1
                    closed = true
                    break
                }
                offset += 1
                column += 1
            }

            span := Span{line = line, column = start_column}
            if !closed {
                reportf(diagnostics, span, "a string must end before the line ends")
            }
            append(&tokens, Token{kind = .String, text = source[start:offset], span = span})
            continue
        }

        reportf(diagnostics, Span{line = line, column = column}, "invalid character")
        offset += 1
        column += 1
    }

    append(&tokens, Token{kind = .Eof, span = Span{line = line, column = column}})
    return tokens
}
