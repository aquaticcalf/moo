package cli

import "core:fmt"

import "compiler:frontend"

// sometimes i forget what commands i even have
print_usage :: proc() {
    fmt.println("usage : ")
    fmt.println("  moo help")
    fmt.println("  moo check file.moo")
    fmt.println("  moo build file.moo")
    fmt.println("  moo run file.moo")
    fmt.println("  moo clean")
}

// this shows any errors in the moo files
print_diagnostics :: proc(diagnostics: frontend.Diagnostics) {
    for diagnostic in diagnostics.errors {
        fmt.eprintf(
            "%v:%v:%v: %v\n",
            diagnostics.path,
            diagnostic.span.line,
            diagnostic.span.column,
            diagnostic.message,
        )
    }
}

// what?
print_process_output :: proc(stdout, stderr: string) {
    if len(stdout) > 0 { fmt.print(stdout) }
    if len(stderr) > 0 { fmt.eprint(stderr) }
}
