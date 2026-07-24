package language

import "core:fmt"

Span :: struct {
    line: int,
    column: int,
}

Token_Kind :: enum {
    Eof,
    Newline,
    Keyword_Show,
    String,
}

Token :: struct {
    kind: Token_Kind,
    text: string,
    span: Span,
}

Show :: struct {
    text: string,
    span: Span,
}

Program :: struct {
    shows: [dynamic]Show,
}

Diagnostic :: struct {
    span: Span,
    message: string,
}

Diagnostics :: struct {
    path: string,
    errors: [dynamic]Diagnostic,
}

Parse_Result :: struct {
    program: Program,
    diagnostics: Diagnostics,
    ok: bool,
}

report :: proc(diagnostics: ^Diagnostics, span: Span, message: string) {
    append(&diagnostics.errors, Diagnostic{span = span, message = message})
}

reportf :: proc(diagnostics: ^Diagnostics, span: Span, format: string, args: ..any) {
    report(diagnostics, span, fmt.aprintf(format, ..args))
}

has_errors :: proc(diagnostics: ^Diagnostics) -> bool {
    return len(diagnostics.errors) > 0
}

destroy_program :: proc(program: ^Program) {
    for index := 0; index < len(program.shows); index += 1 {
        delete(program.shows[index].text)
    }
    delete(program.shows)
}

destroy_diagnostics :: proc(diagnostics: ^Diagnostics) {
    for index := 0; index < len(diagnostics.errors); index += 1 {
        delete(diagnostics.errors[index].message)
    }
    delete(diagnostics.errors)
}

destroy_parse_result :: proc(result: ^Parse_Result) {
    destroy_program(&result.program)
    destroy_diagnostics(&result.diagnostics)
}
