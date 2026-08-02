package frontend

// analyze one source file through the complete moo front end
analyze_file :: proc(path: string) -> Parse_Result {
    return parse_file(path)
}

// analyze source text through the complete moo front end
analyze :: proc(source, path: string) -> Parse_Result {
    return parse(source, path)
}

// release every allocation owned by an analysis result
destroy_analysis :: proc(result: ^Parse_Result) {
    destroy_parse_result(result)
}
