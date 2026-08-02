package toolchain

import "core:strings"

foreign import "system:moo_lld_shim"
foreign moo_lld_shim {
    moo_lld_link :: proc(count: int, arguments: ^cstring, error: cstring, error_size: int) -> int ---
}

// link objects in-process through the lld library
link_in_process :: proc(arguments: []string) -> (string, bool) {
    c_arguments: [dynamic]cstring
    buffers: [dynamic][dynamic]byte
    defer delete(c_arguments)
    defer delete(buffers)
    for argument in arguments {
        buffer: [dynamic]byte
        for character in argument { append(&buffer, byte(character)) }
        append(&buffer, 0)
        append(&buffers, buffer)
        append(&c_arguments, cstring(&buffers[len(buffers) - 1][0]))
    }
    error: [4096]byte
    result := moo_lld_link(len(c_arguments), &c_arguments[0], cstring(&error[0]), len(error))
    if result != 0 { return string(error[:]), false }
    return "", true
}
