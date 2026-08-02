package language

import "core:os"

// is the character a letter?
is_letter :: proc(c: byte) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

// the actual file reader that enables the parser
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

// helper for scanning a word and returning kind
word_kind :: proc(word: string) -> (Token_Kind, bool) {
    if word == "show" {
        return .Keyword_Show, true
    }
    if word == "is" {
        return .Keyword_Is, true
    }
    if word == "if" {
        return .Keyword_If, true
    }
    if word == "otherwise" {
        return .Keyword_Otherwise, true
    }
    if word == "becomes" {
        return .Keyword_Becomes, true
    }
    if word == "make" {
        return .Keyword_Make, true
    }
    if word == "give" {
        return .Keyword_Give, true
    }
    return {}, false
}

// look ahead after the word "is" to see if a comparison phrase follows
// returns the comparison op, the number of source bytes consumed, and whether one was found
read_comparison :: proc(source: string, offset: int) -> (Comparison_Op, int, bool) {
    // skip spaces after "is"
    pos := offset
    for pos < len(source) && (source[pos] == ' ' || source[pos] == '\t') {
        pos += 1
    }

    // read the words separated by spaces, remembering where each one ends
    words: [dynamic]string
    ends: [dynamic]int
    defer delete(words)
    defer delete(ends)
    for pos < len(source) && is_letter(source[pos]) {
        start := pos
        for pos < len(source) && is_letter(source[pos]) {
            pos += 1
        }
        append(&words, source[start:pos])
        append(&ends, pos)
        // skip one space between words
        if pos < len(source) && source[pos] == ' ' {
            pos += 1
        }
    }

    // longest phrases first, so "greater than or equal to" is not taken as "greater than"
    if len(words) >= 5 && words[0] == "greater" && words[1] == "than" && words[2] == "or" && words[3] == "equal" && words[4] == "to" {
        return .Greater_Or_Equal, ends[4] - offset, true
    }
    if len(words) >= 5 && words[0] == "less" && words[1] == "than" && words[2] == "or" && words[3] == "equal" && words[4] == "to" {
        return .Less_Or_Equal, ends[4] - offset, true
    }
    if len(words) >= 2 && words[0] == "equal" && words[1] == "to" {
        return .Equal, ends[1] - offset, true
    }
    if len(words) >= 3 && words[0] == "not" && words[1] == "equal" && words[2] == "to" {
        return .Not_Equal, ends[2] - offset, true
    }
    if len(words) >= 2 && words[0] == "greater" && words[1] == "than" {
        return .Greater, ends[1] - offset, true
    }
    if len(words) >= 2 && words[0] == "less" && words[1] == "than" {
        return .Less, ends[1] - offset, true
    }
    return {}, 0, false
}

// mapping tokens to their values
scan :: proc(source: string, diagnostics: ^Diagnostics) -> [dynamic]Token {
    tokens: [dynamic]Token
    line := 1
    column := 1
    offset := 0

    // indentation stack, starting with the top level at depth 0
    indents: [dynamic]int
    append(&indents, 0)
    // how deep the current line is indented, and whether we already processed it
    at_line_start := true
    line_depth := 0

    for offset < len(source) {
        c := source[offset]

        if at_line_start {
            // measure the indentation of this line
            depth := 0
            scan := offset
            for scan < len(source) && (source[scan] == ' ' || source[scan] == '\t') {
                depth += 1
                scan += 1
            }

            // blank lines or comment-only lines do not affect indentation
            if scan >= len(source) || source[scan] == '\n' || source[scan] == '#' {
                if scan < len(source) && source[scan] == '#' {
                    // comment-only line: skip it entirely without touching indentation
                    offset = scan
                    for offset < len(source) && source[offset] != '\n' {
                        offset += 1
                        column += 1
                    }
                    at_line_start = true
                    continue
                }
                if scan >= len(source) {
                    break
                }
                // blank line: let it fall through to the newline handler below
                at_line_start = false
                continue
            }

            // a real line: reconcile indentation with the stack
            top := indents[len(indents) - 1]
            if depth > top {
                append(&tokens, Token{kind = .Indent, span = Span{line = line, column = top + 1}})
                append(&indents, depth)
            } else if depth < top {
                for len(indents) > 1 && depth < indents[len(indents) - 1] {
                    append(&tokens, Token{kind = .Dedent, span = Span{line = line, column = depth + 1}})
                    pop(&indents)
                }
            }
            at_line_start = false
            continue
        }

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
            at_line_start = true
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
            kind, is_keyword := word_kind(word)
            if word == "is" {
                // check whether an assignment "x is 3" or a comparison "x is equal to y"
                cop, consumed, is_comp := read_comparison(source, offset)
                if is_comp {
                    append(&tokens, Token{kind = .Comparison, text = word, span = span, op = cop})
                    offset += consumed
                    column += consumed
                } else {
                    append(&tokens, Token{kind = .Keyword_Is, text = word, span = span})
                }
            } else if is_keyword {
                append(&tokens, Token{kind = kind, text = word, span = span})
            } else {
                append(&tokens, Token{kind = .Identifier, text = word, span = span})
            }
            continue
        }

        if c >= '0' && c <= '9' {
            start := offset
            start_column := column
            for offset < len(source) && source[offset] >= '0' && source[offset] <= '9' {
                offset += 1
                column += 1
            }

            append(&tokens, Token{
                kind = .Number,
                text = source[start:offset],
                span = Span{line = line, column = start_column},
            })
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

        if c == '#' {
            // a comment runs to the end of the line
            offset += 1
            column += 1
            for offset < len(source) && source[offset] != '\n' {
                offset += 1
                column += 1
            }
            continue
        }

        if c == '+' || c == '-' || c == '*' || c == '/' || c == '(' || c == ')' || c == ':' || c == ',' {
            kind: Token_Kind
            switch c {
            case '+': kind = .Plus
            case '-': kind = .Minus
            case '*': kind = .Star
            case '/': kind = .Slash
            case '(': kind = .LParen
            case ')': kind = .RParen
            case ':': kind = .Colon
            case ',': kind = .Comma
            }
            append(&tokens, Token{
                kind = kind,
                text = source[offset:offset + 1],
                span = Span{line = line, column = column},
            })
            offset += 1
            column += 1
            continue
        }

        reportf(diagnostics, Span{line = line, column = column}, "invalid character")
        offset += 1
        column += 1
    }

    // unwind any remaining indentation at the end of the file
    for len(indents) > 1 {
        append(&tokens, Token{kind = .Dedent, span = Span{line = line, column = column}})
        pop(&indents)
    }
    delete(indents)

    append(&tokens, Token{kind = .Eof, span = Span{line = line, column = column}})
    return tokens
}

// hash, this is used in finding a unique path in build step
hash_source :: proc(source: string) -> u64 {
    value_hash: u64 = 14695981039346656037
    for value in source {
        value_hash = value_hash ~ u64(value)
        value_hash *= 1099511628211
    }
    return value_hash
}
