package native

import "core:fmt"
import "core:os"

Process_Result :: struct {
    exit_code: int,
    stdout: string,
    stderr: string,
    message: string,
    started: bool,
    ok: bool,
}

output_path :: proc(source_path: string) -> (string, bool) {
    output_name := os.stem(source_path)
    when ODIN_OS == .Windows {
        output_name = fmt.aprintf("%s.exe", output_name)
    }

    path, err := os.join_path({os.dir(source_path), output_name}, context.temp_allocator)
    if err != nil {
        return "", false
    }
    return path, true
}

compile :: proc(ir_path, executable: string) -> Process_Result {
    state, stdout, stderr, err := os.process_exec(
        os.Process_Desc{command = []string{"clang", ir_path, "-o", executable}},
        context.temp_allocator,
    )

    if err != nil {
        return Process_Result{message = fmt.aprintf("could not start clang: %v", err)}
    }

    return Process_Result{
        exit_code = state.exit_code,
        stdout = string(stdout),
        stderr = string(stderr),
        started = true,
        ok = state.success && state.exit_code == 0,
    }
}

run :: proc(executable: string) -> Process_Result {
    state, stdout, stderr, err := os.process_exec(
        os.Process_Desc{command = []string{executable}},
        context.temp_allocator,
    )

    if err != nil {
        return Process_Result{
            exit_code = 1,
            message = fmt.aprintf("could not run %v: %v", executable, err),
        }
    }

    return Process_Result{
        exit_code = state.exit_code,
        stdout = string(stdout),
        stderr = string(stderr),
        started = true,
        ok = state.success,
    }
}
