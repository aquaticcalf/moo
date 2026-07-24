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
    cached: bool,
    ok: bool,
}

Build_Options :: struct {
    source_path: string,
    source_hash: u64,
    ir_path: string,
    executable: string,
}

cache_directory :: proc() -> (string, bool) {
    home, err := os.user_home_dir(context.temp_allocator)
    if err != nil {
        return "", false
    }
    cache_dir, join_err := os.join_path({home, ".moo"}, context.temp_allocator)
    if join_err != nil {
        return "", false
    }
    return cache_dir, true
}

artifact_path :: proc(source_path: string, source_hash: u64, suffix: string) -> (string, string, bool) {
    cache_dir, path_ok := cache_directory()
    if !path_ok {
        return "", "could not find the user cache directory", false
    }
    if err := os.make_directory_all(cache_dir); err != nil && err != .Exist {
        return "", fmt.aprintf("could not create cache directory: %v", err), false
    }

    name := fmt.aprintf("%s-%x%s", os.stem(source_path), source_hash, suffix)
    path, err := os.join_path({cache_dir, name}, context.temp_allocator)
    if err != nil {
        return "", fmt.aprintf("could not join cache path: %v", err), false
    }
    return path, "", true
}

compile :: proc(program: language.Program, options: Build_Options) -> Build_Result {
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

    ir := llvm.emit_program(program)
    if err := os.write_entire_file_from_string(ir_path, ir); err != nil {
        return Build_Result{ir_path = ir_path, message = "could not write llvm ir"}
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
    if err := os.write_entire_file_from_string(marker_path, "moo cache v1\n"); err != nil {
        result.message = "could not write cache marker"
        return result
    }

    result.ok = true
    return result
}

publish :: proc(result: Build_Result, source_path: string) -> (string, string, bool) {
    destination, path_ok := native.output_path(source_path)
    if !path_ok {
        return "", "could not choose a publish path", false
    }

    if err := os.copy_file(destination, result.executable); err != nil {
        return "", fmt.aprintf("could not copy executable: %v", err), false
    }
    return destination, "", true
}

clean :: proc() -> (string, string, bool) {
    cache_dir, path_ok := cache_directory()
    if !path_ok {
        return "", "could not find the user cache directory", false
    }
    if !os.exists(cache_dir) {
        return cache_dir, "", true
    }

    entries, err := os.read_all_directory_by_path(cache_dir, context.temp_allocator)
    if err != nil {
        return cache_dir, fmt.aprintf("could not read cache: %v", err), false
    }
    for entry in entries {
        if entry.type == .Directory {
            if err := os.remove_all(entry.fullpath); err != nil {
                return cache_dir, fmt.aprintf("could not remove cache entry: %v", err), false
            }
        } else {
            if err := os.remove(entry.fullpath); err != nil {
                return cache_dir, fmt.aprintf("could not remove cache entry: %v", err), false
            }
        }
    }
    return cache_dir, "", true
}

run :: proc(executable: string) -> native.Process_Result {
    return native.run(executable)
}
