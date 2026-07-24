package build

import "core:fmt"
import "core:os"
import "compiler:build/llvm"
import "compiler:build/native"
import "compiler:language"

Build_Result :: struct {
    executable: string,
    ir_path: string,
    stdout: string,
    stderr: string,
    message: string,
    ok: bool,
}

Build_Options :: struct {
    source_path: string,
    ir_path: string,
    executable: string,
}

compile :: proc(program: language.Program, options: Build_Options) -> Build_Result {
    ir_path := options.ir_path
    if ir_path == "" {
        ir_path = fmt.aprintf("%s.ll", options.source_path)
    }

    ir := llvm.emit_program(program)
    if err := os.write_entire_file_from_string(ir_path, ir); err != nil {
        return Build_Result{ir_path = ir_path, message = "could not write llvm ir"}
    }

    executable := options.executable
    if executable == "" {
        output, path_ok := native.output_path(options.source_path)
        if !path_ok {
            return Build_Result{ir_path = ir_path, message = "could not choose an output path"}
        }
        executable = output
    }

    process := native.compile(ir_path, executable)
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

    result.ok = true
    return result
}

run :: proc(executable: string) -> native.Process_Result {
    return native.run(executable)
}
