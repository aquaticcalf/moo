package main

import "core:os"
import "core:fmt"

import "compiler:cli"
import "compiler:build"
import "compiler:frontend"
import "compiler:semantic"

// this is the actual entry point to the compiler binary
main :: proc() {
    os.exit(run(os.args[1:]))
}

// this defines what happens when we run the compiler
run :: proc(args: []string) -> int {
    if len(args) == 0 {
        cli.print_usage()
        return 1
    }

    command := args[0]
    if command == "help" && len(args) == 1 {
        cli.print_usage()
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
        cli.print_usage()
        return 1
    }

    parsed := frontend.analyze_file(args[1])
    defer frontend.destroy_analysis(&parsed)
    if parsed.ok {
        semantic.semantic_check(parsed.program, &parsed.diagnostics)
        if frontend.has_errors(&parsed.diagnostics) {
            parsed.ok = false
        }
    }
    if !parsed.ok {
        cli.print_diagnostics(parsed.diagnostics)
        return 1
    }

    if command == "check" {
        fmt.printf("ok: %v\n", args[1])
        return 0
    }

    result := build.compile_source(parsed.program, build.Build_Request{
        source_path = args[1],
        source_hash = parsed.source_hash,
    })
    cli.print_process_output(result.stdout, result.stderr)
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
    cli.print_process_output(run_result.stdout, run_result.stderr)
    if !run_result.started {
        fmt.eprintf("%v\n", run_result.message)
    }
    return run_result.exit_code
}
