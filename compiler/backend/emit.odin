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
    string_lengths: []int,
}

// finally, constructing the llvm code
emit_program :: proc(module: ir.Module) -> string {
    program := module.program
    builder: strings.Builder
    strings.builder_init(&builder)

    line(&builder, "; moo llvm module")
    line(&builder, "declare i32 @puts(ptr)")
    line(&builder, "declare i32 @printf(ptr, ...)")
    line(&builder, "declare i64 @strlen(ptr)")
    line(&builder, "declare ptr @malloc(i64)")
    line(&builder, "declare ptr @strcpy(ptr, ptr)")
    line(&builder, "declare ptr @strcat(ptr, ptr)")
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
    state.string_lengths = string_lengths[:]
    if len(string_lengths) > 0 {
        line(&builder, "")
    }

    // a typed global slot for every variable
    for variable in module.variables {
        initializer := "0"
        if variable.type == .String { initializer = "null" }
        line(&builder, fmt.aprintf("@var.%s = global %s %s", sanitize(variable.name), llvm_type(variable.type), initializer))
    }
    line(&builder, "")

    // format string used to print integers: "%d\n"
    line(&builder, "@.fmt.int = private unnamed_addr constant [4 x i8] c\"%d\\0A\\00\", align 1")
    line(&builder, "@.true = private unnamed_addr constant [5 x i8] c\"true\\00\", align 1")
    line(&builder, "@.false = private unnamed_addr constant [6 x i8] c\"false\\00\", align 1")
    line(&builder, "")
    emit_functions(&builder, module, &state, string_lengths[:])
    line(&builder, "define i32 @main() {")
    line(&builder, "entry:")

    emit_typed_statements(&builder, module.statements[:], &state)

    line(&builder, "  ret i32 0")
    line(&builder, "}")

    delete(string_lengths)
    for name in state.boolean_variables {
        delete(name)
    }
    delete(state.boolean_variables)

    return strings.to_string(builder)
}
