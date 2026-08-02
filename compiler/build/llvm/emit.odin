package llvm

import "core:fmt"
import "core:strings"

import "compiler:language"

// write a string to the builder
write :: proc(builder: ^strings.Builder, text: string) {
    strings.write_string(builder, text)
}

// write a line ( string + enter ) to the builder
line :: proc(builder: ^strings.Builder, text: string) {
    write(builder, text)
    write(builder, "\n")
}

// convert a string into bytes
decode_string :: proc(literal: string) -> [dynamic]byte {
    bytes: [dynamic]byte
    if len(literal) < 2 {
        append(&bytes, 0)
        return bytes
    }

    index := 1
    for index < len(literal) - 1 {
        value := literal[index]
        if value == '\\' && index + 1 < len(literal) - 1 {
            index += 1
            switch literal[index] {
            case 'n': value = '\n'
            case 'r': value = '\r'
            case 't': value = '\t'
            case '\\': value = '\\'
            case '"': value = '"'
            }
        }
        append(&bytes, value)
        index += 1
    }
    append(&bytes, 0)
    return bytes
}

// write a byte to the builder
write_byte :: proc(builder: ^strings.Builder, value: byte) {
    if value >= 32 && value <= 126 && value != '\\' && value != '"' {
        write(builder, string([]byte{value}))
        return
    }
    write(builder, fmt.aprintf("\\%02x", value))
}

// finally, constructing the llvm code
emit_program :: proc(program: language.Program) -> string {
    builder: strings.Builder
    strings.builder_init(&builder)

    line(&builder, "; moo llvm module")
    line(&builder, "declare i32 @puts(ptr)")
    line(&builder, "declare i32 @printf(ptr, ...)")
    line(&builder, "")

    // one constant for every string that gets shown
    string_lengths: [dynamic]int
    for show in program.shows {
        if literal, ok := show.expr.(language.Literal); ok && literal.is_string {
            bytes := decode_string(literal.text)
            append(&string_lengths, len(bytes))

            write(&builder, fmt.aprintf(
                "@.str.%d = private unnamed_addr constant [%d x i8] c\"",
                len(string_lengths) - 1,
                len(bytes),
            ))
            for value in bytes {
                write_byte(&builder, value)
            }
            line(&builder, "\", align 1")
            delete(bytes)
        }
    }

    // format string used to print integers: "%d\n"
    line(&builder, "@.fmt.int = private unnamed_addr constant [4 x i8] c\"%d\\0A\\00\", align 1")
    line(&builder, "")
    line(&builder, "define i32 @main() {")
    line(&builder, "entry:")

    counter := 0
    string_index := 0
    for show in program.shows {
        if literal, ok := show.expr.(language.Literal); ok && literal.is_string {
            line(&builder, fmt.aprintf(
                "  %%show.%d = call i32 @puts(ptr getelementptr inbounds ([%d x i8], ptr @.str.%d, i64 0, i64 0))",
                counter,
                string_lengths[string_index],
                string_index,
            ))
            string_index += 1
            counter += 1
        } else {
            value := emit_expr(&builder, show.expr, &counter)
            line(&builder, fmt.aprintf("  %%show.%d = call i32 @printf(ptr @.fmt.int, i32 %s)", counter, value))
            counter += 1
        }
    }
    line(&builder, "  ret i32 0")
    line(&builder, "}")

    delete(string_lengths)
    return strings.to_string(builder)
}

// turn an expression into an i32 llvm value, naming the results %%t.n
emit_expr :: proc(builder: ^strings.Builder, expr: language.Expr, counter: ^int) -> string {
    switch e in expr {
    case language.Literal:
        if e.is_string {
            // a string has no numeric value, this should not be reached
            return "0"
        }
        return fmt.aprintf("%d", e.value)
    case language.Grouping:
        return emit_expr(builder, e.inner^, counter)
    case language.Binary:
        left := emit_expr(builder, e.left^, counter)
        right := emit_expr(builder, e.right^, counter)
        operation: string
        switch e.op {
        case .Add: operation = "add"
        case .Sub: operation = "sub"
        case .Mul: operation = "mul"
        case .Div: operation = "sdiv"
        }
        name := fmt.aprintf("%%t.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = %s i32 %s, %s", name, operation, left, right))
        return name
    }
    return "0"
}
