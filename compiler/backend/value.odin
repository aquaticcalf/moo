package backend

import "compiler:ir"

// the llvm type and value produced for one typed moo expression
LLVM_Value :: struct {
    type: string,
    value: string,
}

// map one moo value type to its llvm representation
llvm_type :: proc(value_type: ir.Value_Type) -> string {
    switch value_type {
    case .Integer: return "i32"
    case .Boolean: return "i32"
    case .String: return "ptr"
    case .Nothing: return "void"
    }
    return "void"
}

// create a typed llvm value
make_value :: proc(value_type: ir.Value_Type, value: string) -> LLVM_Value {
    return LLVM_Value{type = llvm_type(value_type), value = value}
}
