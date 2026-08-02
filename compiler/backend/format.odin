package backend

import "core:fmt"
import "core:strings"

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

