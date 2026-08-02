package frontend

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
