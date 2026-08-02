package toolchain

import "core:fmt"

// this is the process result from the native linker
link_object :: proc(object_path, executable: string) -> Process_Result {
    command := []string{
        "ld.lld", "-z", "relro", "--hash-style=gnu", "--eh-frame-hdr",
        "-m", "elf_x86_64", "-dynamic-linker", "/lib64/ld-linux-x86-64.so.2",
        "/lib/x86_64-linux-gnu/crt1.o", "/lib/x86_64-linux-gnu/crti.o",
        "-L/lib/x86_64-linux-gnu", "-L/usr/lib/gcc/x86_64-linux-gnu/13",
        object_path, "-o", executable,
        "/lib/x86_64-linux-gnu/crtn.o", "-lc", "-lgcc", "-lgcc_s",
    }
    when ODIN_OS == .Windows {
        command = []string{"lld-link", object_path, fmt.aprintf("/out:%s", executable), "/subsystem:console"}
    }
    error_message, linked := link_in_process(command)
    if !linked {
        return Process_Result{
            exit_code = 1,
            stderr = error_message,
            started = true,
            message = "in-process lld could not link the program",
        }
    }
    return Process_Result{started = true, ok = true}
}

// emit llvm ir to an object and link it without starting clang
compile :: proc(ir_path, executable: string) -> Process_Result {
    object_path := fmt.aprintf("%s.o", executable)
    target := "x86_64-pc-linux-gnu"
    when ODIN_OS == .Windows {
        target = "x86_64-pc-windows-msvc"
    }
    error_message, emitted := emit_object(ir_path, object_path, target)
    if !emitted {
        return Process_Result{message = fmt.aprintf("llvm object emission failed: %s", error_message)}
    }
    return link_object(object_path, executable)
}
