package llvm

import "core:fmt"
import "core:strings"
import "compiler:language"

write :: proc(builder: ^strings.Builder, text: string) {
    strings.write_string(builder, text)
}

line :: proc(builder: ^strings.Builder, text: string) {
    write(builder, text)
    write(builder, "\n")
}

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

write_byte :: proc(builder: ^strings.Builder, value: byte) {
    if value >= 32 && value <= 126 && value != '\\' && value != '"' {
        write(builder, string([]byte{value}))
        return
    }
    write(builder, fmt.aprintf("\\%02x", value))
}

emit_program :: proc(program: language.Program) -> string {
    builder: strings.Builder
    strings.builder_init(&builder)

    line(&builder, "; moo llvm module")
    line(&builder, "declare i32 @puts(ptr)")
    line(&builder, "")

    string_lengths: [dynamic]int
    for show, index in program.shows {
        bytes := decode_string(show.text)
        append(&string_lengths, len(bytes))

        write(&builder, fmt.aprintf(
            "@.str.%d = private unnamed_addr constant [%d x i8] c\"",
            index,
            len(bytes),
        ))
        for value in bytes {
            write_byte(&builder, value)
        }
        line(&builder, "\", align 1")
        delete(bytes)
    }

    line(&builder, "")
    line(&builder, "define i32 @main() {")
    line(&builder, "entry:")
    for _, index in program.shows {
        line(&builder, fmt.aprintf(
            "  %%show.%d = call i32 @puts(ptr getelementptr inbounds ([%d x i8], ptr @.str.%d, i64 0, i64 0))",
            index,
            string_lengths[index],
            index,
        ))
    }
    line(&builder, "  ret i32 0")
    line(&builder, "}")

    delete(string_lengths)
    return strings.to_string(builder)
}
