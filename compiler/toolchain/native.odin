package toolchain

import "core:fmt"
import "core:os"

// this is a generic process output tracking system
Process_Result :: struct {
    exit_code: int,
    stdout: string,
    stderr: string,
    message: string,
    started: bool,
    ok: bool,
}

// this helps in figuring out the file extension based on the operating system
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

// this is the process that runs a binary
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
