package toolchain

// call the in-process llvm object emitter supplied by the c shim
foreign import "system:moo_llvm_shim"
foreign moo_llvm_shim {
    moo_llvm_emit_object :: proc(ir_path, object_path, triple: cstring, error: cstring, error_size: int) -> int ---
}

// convert a moo string into a null-terminated c string
make_cstring :: proc(value: string) -> [dynamic]byte {
    result: [dynamic]byte
    for character in value { append(&result, byte(character)) }
    append(&result, 0)
    return result
}

// emit an object file from llvm ir without starting clang
emit_object :: proc(ir_path, object_path, triple: string) -> (string, bool) {
    ir_name := make_cstring(ir_path)
    object_name := make_cstring(object_path)
    target_name := make_cstring(triple)
    defer delete(ir_name)
    defer delete(object_name)
    defer delete(target_name)
    error: [1024]byte
    result := moo_llvm_emit_object(cstring(&ir_name[0]), cstring(&object_name[0]), cstring(&target_name[0]), cstring(&error[0]), len(error))
    if result != 0 {
        return string(error[:]), false
    }
    return "", true
}
