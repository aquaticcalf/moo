package build

import "core:fmt"
import "core:os"

import "compiler:backend"
import "compiler:toolchain"
import "compiler:ir"
import "compiler:frontend"

// this holds all details of a build result ( output )
Build_Result :: struct {
    executable: string,
    ir_path: string,
    stdout: string,
    stderr: string,
    message: string,
    cached: bool,
    ok: bool,
}

// this holds all details of a build environment ( input )
Build_Options :: struct {
    source_path: string,
    source_hash: u64,
    ir_path: string,
    executable: string,
}

// the small input needed to turn a checked moo program into an artifact
Build_Request :: struct {
    source_path: string,
    source_hash: u64,
}

// compile a checked program while keeping cache and artifact paths internal
compile_source :: proc(program: frontend.Program, request: Build_Request) -> Build_Result {
    return compile(program, Build_Options{
        source_path = request.source_path,
        source_hash = request.source_hash,
    })
}

// this is the part where we convert the code -> llvm -> binary
compile :: proc(program: frontend.Program, options: Build_Options) -> Build_Result {
    ir_path := options.ir_path
    if ir_path == "" {
        generated_path, path_message, path_ok := artifact_path(options.source_path, options.source_hash, ".ll")
        if !path_ok {
            return Build_Result{message = path_message}
        }
        ir_path = generated_path
    }

    executable := options.executable
    if executable == "" {
        executable_suffix := ""
        when ODIN_OS == .Windows {
            executable_suffix = ".exe"
        }
        generated_path, path_message, path_ok := artifact_path(options.source_path, options.source_hash, executable_suffix)
        if !path_ok {
            return Build_Result{ir_path = ir_path, message = path_message}
        }
        executable = generated_path
    }

    marker_path := fmt.aprintf("%s.complete", executable)
    if os.exists(ir_path) && os.exists(executable) && os.exists(marker_path) {
        return Build_Result{
            executable = executable,
            ir_path = ir_path,
            cached = true,
            ok = true,
        }
    }

    module := ir.lower(program)
    defer ir.destroy_module(&module)
    ir := backend.emit_program(module)
    if err := os.write_entire_file_from_string(ir_path, ir); err != nil {
        return Build_Result{ir_path = ir_path, message = "could not write llvm ir"}
    }

    process := toolchain.compile(ir_path, executable)
    result := Build_Result{
        executable = executable,
        ir_path = ir_path,
        stdout = process.stdout,
        stderr = process.stderr,
    }
    if !process.started {
        result.message = process.message
        return result
    }
    if !process.ok {
        result.message = "llvm clang could not build the program"
        return result
    }
    if err := os.write_entire_file_from_string(marker_path, "moo cache v1\n"); err != nil {
        result.message = "could not write cache marker"
        return result
    }

    result.ok = true
    return result
}

// run just runs the binary
run :: proc(executable: string) -> toolchain.Process_Result {
    return toolchain.run(executable)
}
