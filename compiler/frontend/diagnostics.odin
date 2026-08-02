package frontend

import "core:fmt"

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

