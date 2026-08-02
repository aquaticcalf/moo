package backend

import "core:fmt"
import "core:strings"

import "compiler:ir"
import "compiler:frontend"

// helper state shared across emission so nested blocks get distinct names
Emit_State :: struct {
    counter: int,
    label_counter: int,
    string_index: int,
    boolean_variables: [dynamic]string,
}

// finally, constructing the llvm code
emit_program :: proc(module: ir.Module) -> string {
    program := module.program
    builder: strings.Builder
    strings.builder_init(&builder)

    line(&builder, "; moo llvm module")
    line(&builder, "declare i32 @puts(ptr)")
    line(&builder, "declare i32 @printf(ptr, ...)")
    line(&builder, "")

    state := Emit_State{}
    for variable in module.variables {
        if variable.type == .Boolean {
            remember_boolean(&state.boolean_variables, variable.name)
        }
    }
    string_lengths: [dynamic]int

    // one constant for every string that gets shown, anywhere in the program
    collect_strings(program.statements[:], &string_lengths, &builder)
    if len(string_lengths) > 0 {
        line(&builder, "")
    }

    // a global slot for every variable and every string constant
    variable_names: [dynamic]string
    collect_variables(program.statements[:], &variable_names, &builder)
    line(&builder, "")

    // format string used to print integers: "%d\n"
    line(&builder, "@.fmt.int = private unnamed_addr constant [4 x i8] c\"%d\\0A\\00\", align 1")
    line(&builder, "@.true = private unnamed_addr constant [5 x i8] c\"true\\00\", align 1")
    line(&builder, "@.false = private unnamed_addr constant [6 x i8] c\"false\\00\", align 1")
    line(&builder, "")
    emit_functions(&builder, module, &state, string_lengths[:])
    line(&builder, "define i32 @main() {")
    line(&builder, "entry:")

    emit_statements(&builder, program.statements[:], &state, string_lengths[:])

    line(&builder, "  ret i32 0")
    line(&builder, "}")

    delete(string_lengths)
    for name in state.boolean_variables {
        delete(name)
    }
    delete(state.boolean_variables)
    for name in variable_names {
        delete(name)
    }
    delete(variable_names)
    return strings.to_string(builder)
}
