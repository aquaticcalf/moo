package app

import "core:fmt"
import "compiler:build"
import "compiler:language"

print_usage :: proc() {
    fmt.println("usage : ")
    fmt.println("  moo help")
    fmt.println("  moo check file.moo")
    fmt.println("  moo build file.moo")
    fmt.println("  moo run file.moo")
    fmt.println("  moo clean")
}

print_diagnostics :: proc(diagnostics: language.Diagnostics) {
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

print_process_output :: proc(stdout, stderr: string) {
    if len(stdout) > 0 { fmt.print(stdout) }
    if len(stderr) > 0 { fmt.eprint(stderr) }
}

run :: proc(args: []string) -> int {
    if len(args) == 0 {
        print_usage()
        return 1
    }

    command := args[0]
    if command == "help" && len(args) == 1 {
        print_usage()
        return 0
    }

    if command == "clean" && len(args) == 1 {
        cache_dir, message, ok := build.clean()
        if !ok {
            fmt.eprintf("%v\n", message)
            return 1
        }
        fmt.printf("cleaned %v\n", cache_dir)
        return 0
    }

    if len(args) == 1 && (command == "check" || command == "build" || command == "run") {
        fmt.printfln("expected a filename after \"moo %s\"", command)
        return 1
    }

    if len(args) != 2 || (command != "check" && command != "build" && command != "run") {
        print_usage()
        return 1
    }

    parsed := language.parse_file(args[1])
    defer language.destroy_parse_result(&parsed)
    if !parsed.ok {
        print_diagnostics(parsed.diagnostics)
        return 1
    }

    if command == "check" {
        fmt.printf("ok: %v\n", args[1])
        return 0
    }

    result := build.compile(parsed.program, build.Build_Options{
        source_path = args[1],
        source_hash = parsed.source_hash,
    })
    print_process_output(result.stdout, result.stderr)
    if !result.ok {
        fmt.eprintf("%v\n", result.message)
        return 1
    }

    if command == "build" {
        published, message, published_ok := build.publish(result, args[1])
        if !published_ok {
            fmt.eprintf("%v\n", message)
            return 1
        }
        if result.cached {
            fmt.printf("cached %v\n", published)
        } else {
            fmt.printf("built %v\n", published)
        }
        return 0
    }

    run_result := build.run(result.executable)
    print_process_output(run_result.stdout, run_result.stderr)
    if !run_result.started {
        fmt.eprintf("%v\n", run_result.message)
    }
    return run_result.exit_code
}
