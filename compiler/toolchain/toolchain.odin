package toolchain

import "core:fmt"
import "core:os"

// this is the process that compiles the ir code into a binary
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

