package language

import "core:fmt"

// span is a ( x, y ) coordinates system for the tokens in code
Span :: struct {
    line: int,
    column: int,
}

// token vocabulary
Token_Kind :: enum {
    Eof,
    Newline,
    Keyword_Show,
    String,
}

// a token has a kind, the actual data and it's coordinates
Token :: struct {
    kind: Token_Kind,
    text: string,
    span: Span,
}

// a show is a token without the kind attached to it?
Show :: struct {
    text: string,
    span: Span,
}

// a program is a collection of shows
Program :: struct {
    shows: [dynamic]Show,
}

// diagnostic is an error message with its coordinates
Diagnostic :: struct {
    span: Span,
    message: string,
}

// diagnostics is file path and error list
Diagnostics :: struct {
    path: string,
    errors: [dynamic]Diagnostic,
}

// this is the main shape that contains all the details of a parse
Parse_Result :: struct {
    program: Program,
    diagnostics: Diagnostics,
    ok: bool,
    source_hash: u64,
}

// add an error to the errors list
report :: proc(diagnostics: ^Diagnostics, span: Span, message: string) {
    append(&diagnostics.errors, Diagnostic{span = span, message = message})
}

// add an error to the errors list with additional formatting
reportf :: proc(diagnostics: ^Diagnostics, span: Span, format: string, args: ..any) {
    report(diagnostics, span, fmt.aprintf(format, ..args))
}

// are there any errors?
has_errors :: proc(diagnostics: ^Diagnostics) -> bool {
    return len(diagnostics.errors) > 0
}

// delete all of the memory allocated to the collection of shows while compilation
destroy_program :: proc(program: ^Program) {
    for index := 0; index < len(program.shows); index += 1 {
        delete(program.shows[index].text)
    }
    delete(program.shows)
}

// delete all of the memory allocated to the collection of errors while compilation
destroy_diagnostics :: proc(diagnostics: ^Diagnostics) {
    for index := 0; index < len(diagnostics.errors); index += 1 {
        delete(diagnostics.errors[index].message)
    }
    delete(diagnostics.errors)
}

// delete all of the memory allocated to the parse result while compilation
destroy_parse_result :: proc(result: ^Parse_Result) {
    destroy_program(&result.program)
    destroy_diagnostics(&result.diagnostics)
}
