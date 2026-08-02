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

// helper state shared across emission so nested blocks get distinct names
Emit_State :: struct {
    counter: int,
    label_counter: int,
    string_index: int,
}

// finally, constructing the llvm code
emit_program :: proc(program: language.Program) -> string {
    builder: strings.Builder
    strings.builder_init(&builder)

    line(&builder, "; moo llvm module")
    line(&builder, "declare i32 @puts(ptr)")
    line(&builder, "declare i32 @printf(ptr, ...)")
    line(&builder, "")

    state := Emit_State{}
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
    line(&builder, "")
    line(&builder, "define i32 @main() {")
    line(&builder, "entry:")

    emit_statements(&builder, program.statements[:], &state, string_lengths[:])

    line(&builder, "  ret i32 0")
    line(&builder, "}")

    delete(string_lengths)
    for name in variable_names {
        delete(name)
    }
    delete(variable_names)
    return strings.to_string(builder)
}

// walk all nested statements and emit a string constant for each shown string
collect_strings :: proc(stmts: []language.Stmt, string_lengths: ^[dynamic]int, builder: ^strings.Builder) {
    for stmt in stmts {
        switch s in stmt {
        case language.Show:
            if literal, ok := s.expr.(language.Literal); ok && literal.is_string {
                bytes := decode_string(literal.text)
                append(string_lengths, len(bytes))

                write(builder, fmt.aprintf(
                    "@.str.%d = private unnamed_addr constant [%d x i8] c\"",
                    len(string_lengths) - 1,
                    len(bytes),
                ))
                for value in bytes {
                    write_byte(builder, value)
                }
                line(builder, "\", align 1")
                delete(bytes)
            }
        case language.If_Block:
            collect_strings(s.body[:], string_lengths, builder)
            if s.else_if != nil {
                // gather the nested if's strings by collecting its own body
                collect_nested_strings(s.else_if, string_lengths, builder)
            }
            collect_strings(s.else_body[:], string_lengths, builder)
        case language.Variable_Decl:
        case language.Variable_Assign:
        }
    }
}

// collect strings from a nested (heap allocated) if block and its chain
collect_nested_strings :: proc(block: ^language.If_Block, string_lengths: ^[dynamic]int, builder: ^strings.Builder) {
    if block == nil {
        return
    }
    collect_strings(block.body[:], string_lengths, builder)
    if block.else_if != nil {
        collect_nested_strings(block.else_if, string_lengths, builder)
    }
    collect_strings(block.else_body[:], string_lengths, builder)
}

// walk all nested statements and emit a global for each variable
collect_variables :: proc(stmts: []language.Stmt, variable_names: ^[dynamic]string, builder: ^strings.Builder) {
    for stmt in stmts {
        switch s in stmt {
        case language.Variable_Decl:
            if !slice_contains(variable_names[:], s.name) {
                append(variable_names, strings.clone(s.name))
                line(builder, fmt.aprintf("@var.%s = global i32 0", sanitize(s.name)))
            }
        case language.If_Block:
            collect_variables(s.body[:], variable_names, builder)
            if s.else_if != nil {
                collect_nested_variables(s.else_if, variable_names, builder)
            }
            collect_variables(s.else_body[:], variable_names, builder)
        case language.Show:
        }
    }
}

// collect variables from a nested if block and its chain
collect_nested_variables :: proc(block: ^language.If_Block, variable_names: ^[dynamic]string, builder: ^strings.Builder) {
    if block == nil {
        return
    }
    collect_variables(block.body[:], variable_names, builder)
    if block.else_if != nil {
        collect_nested_variables(block.else_if, variable_names, builder)
    }
    collect_variables(block.else_body[:], variable_names, builder)
}

// emit a list of statements at the current insertion point
emit_statements :: proc(builder: ^strings.Builder, stmts: []language.Stmt, state: ^Emit_State, string_lengths: []int) {
    for stmt in stmts {
        switch s in stmt {
        case language.Variable_Decl:
            value := emit_expr(builder, s.expr, &state.counter)
            line(builder, fmt.aprintf(
                "  store i32 %s, ptr @var.%s",
                value,
                sanitize(s.name),
            ))
        case language.Variable_Assign:
            value := emit_expr(builder, s.expr, &state.counter)
            line(builder, fmt.aprintf(
                "  store i32 %s, ptr @var.%s",
                value,
                sanitize(s.name),
            ))
        case language.Show:
            if literal, ok := s.expr.(language.Literal); ok && literal.is_string {
                line(builder, fmt.aprintf(
                    "  %%show.%d = call i32 @puts(ptr getelementptr inbounds ([%d x i8], ptr @.str.%d, i64 0, i64 0))",
                    state.counter,
                    string_lengths[state.string_index],
                    state.string_index,
                ))
                state.string_index += 1
                state.counter += 1
            } else {
                value := emit_expr(builder, s.expr, &state.counter)
                line(builder, fmt.aprintf("  %%show.%d = call i32 @printf(ptr @.fmt.int, i32 %s)", state.counter, value))
                state.counter += 1
            }
        case language.If_Block:
            emit_if_block(builder, s, state, string_lengths)
        }
    }
}

// emit an if / otherwise if / otherwise chain with basic blocks
emit_if_block :: proc(builder: ^strings.Builder, block: language.If_Block, state: ^Emit_State, string_lengths: []int) {
    n := state.label_counter
    state.label_counter += 1
    has_else := block.else_if != nil || block.has_else_body

    then_label := fmt.aprintf("if.then.%d", n)
    merge_label := fmt.aprintf("if.merge.%d", n)
    else_label := fmt.aprintf("if.else.%d", n)

    cond := emit_condition(builder, block.condition, &state.counter)

    if !has_else {
        // if with no else: branch straight to then or merge
        line(builder, fmt.aprintf("  br i1 %s, label %%%s, label %%%s", cond, then_label, merge_label))

        line(builder, fmt.aprintf("%s:", then_label))
        emit_statements(builder, block.body[:], state, string_lengths)
        line(builder, fmt.aprintf("  br label %%%s", merge_label))
    } else {
        line(builder, fmt.aprintf("  br i1 %s, label %%%s, label %%%s", cond, then_label, else_label))

        line(builder, fmt.aprintf("%s:", then_label))
        emit_statements(builder, block.body[:], state, string_lengths)
        line(builder, fmt.aprintf("  br label %%%s", merge_label))

        line(builder, fmt.aprintf("%s:", else_label))
        if block.else_if != nil {
            emit_if_block(builder, block.else_if^, state, string_lengths)
            line(builder, fmt.aprintf("  br label %%%s", merge_label))
        } else if block.has_else_body {
            emit_statements(builder, block.else_body[:], state, string_lengths)
            line(builder, fmt.aprintf("  br label %%%s", merge_label))
        } else {
            line(builder, fmt.aprintf("  br label %%%s", merge_label))
        }
    }

    line(builder, fmt.aprintf("%s:", merge_label))
}

// evaluate an expression as a boolean condition, returning an i1 register
emit_condition :: proc(builder: ^strings.Builder, expr: language.Expr, counter: ^int) -> string {
    if comp, ok := expr.(language.Comparison); ok {
        left := emit_expr(builder, comp.left^, counter)
        right := emit_expr(builder, comp.right^, counter)
        predicate: string
        switch comp.op {
        case .Equal: predicate = "eq"
        case .Not_Equal: predicate = "ne"
        case .Greater: predicate = "sgt"
        case .Less: predicate = "slt"
        case .Greater_Or_Equal: predicate = "sge"
        case .Less_Or_Equal: predicate = "sle"
        }
        name := fmt.aprintf("%%c.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = icmp %s i32 %s, %s", name, predicate, left, right))
        return name
    }
    // any other expression is true when it is not zero
    value := emit_expr(builder, expr, counter)
    name := fmt.aprintf("%%c.%d", counter^)
    counter^ += 1
    line(builder, fmt.aprintf("  %s = icmp ne i32 %s, 0", name, value))
    return name
}

// does a slice contain the given value?
slice_contains :: proc(slice: []string, value: string) -> bool {
    for item in slice {
        if item == value {
            return true
        }
    }
    return false
}

// make a name safe to use inside llvm identifiers
sanitize :: proc(name: string) -> string {
    builder: strings.Builder
    strings.builder_init(&builder)
    for c in name {
        if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
            strings.write_byte(&builder, byte(c))
        } else {
            strings.write_byte(&builder, '_')
        }
    }
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
    case language.Variable:
        name := fmt.aprintf("%%v.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = load i32, ptr @var.%s", name, sanitize(e.name)))
        return name
    case language.Comparison:
        // used when a comparison appears in a value position: widen the i1 to i32
        cond := emit_condition(builder, expr, counter)
        name := fmt.aprintf("%%t.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = zext i1 %s to i32", name, cond))
        return name
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
