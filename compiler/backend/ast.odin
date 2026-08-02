package backend

import "core:fmt"
import "core:strings"

import "compiler:ir"
import "compiler:frontend"

// walk all nested statements and emit a string constant for each shown string
collect_strings :: proc(stmts: []frontend.Stmt, string_lengths: ^[dynamic]int, builder: ^strings.Builder) {
    for stmt in stmts {
        #partial switch s in stmt {
        case frontend.Show:
            if literal, ok := s.expr.(frontend.Literal); ok && literal.is_string {
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
        case frontend.If_Block:
            collect_strings(s.body[:], string_lengths, builder)
            if s.else_if != nil {
                // gather the nested if's strings by collecting its own body
                collect_nested_strings(s.else_if, string_lengths, builder)
            }
            collect_strings(s.else_body[:], string_lengths, builder)
        case frontend.Function:
            collect_strings(s.body[:], string_lengths, builder)
        case frontend.Return:
            if literal, ok := s.expr.(frontend.Literal); ok && literal.is_string {
                bytes := decode_string(literal.text)
                append(string_lengths, len(bytes))
                write(builder, fmt.aprintf("@.str.%d = private unnamed_addr constant [%d x i8] c\"", len(string_lengths) - 1, len(bytes)))
                for value in bytes { write_byte(builder, value) }
                line(builder, "\", align 1")
                delete(bytes)
            }
        case frontend.Variable_Decl:
        case frontend.Variable_Assign:
        }
    }
}

// collect strings from a nested (heap allocated) if block and its chain
collect_nested_strings :: proc(block: ^frontend.If_Block, string_lengths: ^[dynamic]int, builder: ^strings.Builder) {
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
collect_variables :: proc(stmts: []frontend.Stmt, variable_names: ^[dynamic]string, builder: ^strings.Builder) {
    for stmt in stmts {
        #partial switch s in stmt {
        case frontend.Variable_Decl:
            if !slice_contains(variable_names[:], s.name) {
                append(variable_names, strings.clone(s.name))
                line(builder, fmt.aprintf("@var.%s = global i32 0", sanitize(s.name)))
            }
        case frontend.If_Block:
            collect_variables(s.body[:], variable_names, builder)
            if s.else_if != nil {
                collect_nested_variables(s.else_if, variable_names, builder)
            }
            collect_variables(s.else_body[:], variable_names, builder)
        case frontend.Show:
        case frontend.Variable_Assign:
        case frontend.Function:
            for parameter in s.parameters {
                if !slice_contains(variable_names[:], parameter) {
                    append(variable_names, strings.clone(parameter))
                    line(builder, fmt.aprintf("@var.%s = global i32 0", sanitize(parameter)))
                }
            }
            collect_variables(s.body[:], variable_names, builder)
        case frontend.Return:
        }
    }
}

// collect variables from a nested if block and its chain
collect_nested_variables :: proc(block: ^frontend.If_Block, variable_names: ^[dynamic]string, builder: ^strings.Builder) {
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
emit_statements :: proc(builder: ^strings.Builder, stmts: []frontend.Stmt, state: ^Emit_State, string_lengths: []int) {
    for stmt in stmts {
        #partial switch s in stmt {
        case frontend.Variable_Decl:
            value := emit_language_expr(builder, s.expr, &state.counter)
            line(builder, fmt.aprintf(
                "  store i32 %s, ptr @var.%s",
                value,
                sanitize(s.name),
            ))
            if literal, ok := s.expr.(frontend.Literal); ok && literal.is_boolean {
                remember_boolean(&state.boolean_variables, s.name)
            }
        case frontend.Variable_Assign:
            value := emit_language_expr(builder, s.expr, &state.counter)
            line(builder, fmt.aprintf(
                "  store i32 %s, ptr @var.%s",
                value,
                sanitize(s.name),
            ))
            if literal, ok := s.expr.(frontend.Literal); ok && literal.is_boolean {
                remember_boolean(&state.boolean_variables, s.name)
            }
        case frontend.Show:
            if variable, ok := s.expr.(frontend.Variable); ok && boolean_contains(state.boolean_variables[:], variable.name) {
                value := emit_language_expr(builder, s.expr, &state.counter)
                condition := fmt.aprintf("%%bool.cond.%d", state.counter)
                pointer := fmt.aprintf("%%bool.ptr.%d", state.counter)
                line(builder, fmt.aprintf("  %s = icmp ne i32 %s, 0", condition, value))
                line(builder, fmt.aprintf("  %s = select i1 %s, ptr getelementptr inbounds ([5 x i8], ptr @.true, i64 0, i64 0), ptr getelementptr inbounds ([6 x i8], ptr @.false, i64 0, i64 0)", pointer, condition))
                line(builder, fmt.aprintf("  %%bool.%d = call i32 @puts(ptr %s)", state.counter, pointer))
                state.counter += 1
            } else if literal, ok := s.expr.(frontend.Literal); ok && literal.is_boolean {
                label := "false"
                length := 6
                if literal.value != 0 {
                    label = "true"
                    length = 5
                }
                line(builder, fmt.aprintf(
                    "  %%show.%d = call i32 @puts(ptr getelementptr inbounds ([%d x i8], ptr @.%s, i64 0, i64 0))",
                    state.counter,
                    length,
                    label,
                ))
                state.counter += 1
            } else if literal, ok := s.expr.(frontend.Literal); ok && literal.is_string {
                line(builder, fmt.aprintf(
                    "  %%show.%d = call i32 @puts(ptr getelementptr inbounds ([%d x i8], ptr @.str.%d, i64 0, i64 0))",
                    state.counter,
                    string_lengths[state.string_index],
                    state.string_index,
                ))
                state.string_index += 1
                state.counter += 1
            } else {
                value := emit_language_expr(builder, s.expr, &state.counter)
                line(builder, fmt.aprintf("  %%show.%d = call i32 @printf(ptr @.fmt.int, i32 %s)", state.counter, value))
                state.counter += 1
            }
        case frontend.If_Block:
            emit_if_block(builder, s, state, string_lengths)
        case frontend.Function:
        case frontend.Return:
            value := emit_language_expr(builder, s.expr, &state.counter)
            line(builder, fmt.aprintf("  ret i32 %s", value))
        }
    }
}

// remember a variable whose inferred type is boolean
remember_boolean :: proc(names: ^[dynamic]string, name: string) {
    if !boolean_contains(names[:], name) {
        append(names, strings.clone(name))
    }
}

// check whether a variable is known to contain a boolean
boolean_contains :: proc(names: []string, name: string) -> bool {
    for item in names {
        if item == name { return true }
    }
    return false
}

// emit all typed moo functions before the executable entry point
emit_functions :: proc(builder: ^strings.Builder, module: ir.Module, state: ^Emit_State, string_lengths: []int) {
    for function in module.functions {
        parameters_builder: strings.Builder
        strings.builder_init(&parameters_builder)
        for parameter, index in function.parameter_names {
            if index > 0 { strings.write_string(&parameters_builder, ", ") }
            strings.write_string(&parameters_builder, fmt.aprintf("i32 %%%s", sanitize(parameter)))
        }
        parameters := strings.to_string(parameters_builder)
        line(builder, fmt.aprintf("define i32 @moo_%s(%s) %s", sanitize(function.name), parameters, "{"))
        line(builder, "entry:")
        for parameter in function.parameter_names {
            line(builder, fmt.aprintf("  store i32 %%%s, ptr @var.%s", sanitize(parameter), sanitize(parameter)))
        }
        emit_typed_statements(builder, function.body[:], state)
        if !typed_contains_return(function.body[:]) {
            line(builder, "  ret i32 0")
        }
        line(builder, "}")
        line(builder, "")
    }
}

// check whether a function body contains a return statement
contains_return :: proc(stmts: []frontend.Stmt) -> bool {
    for stmt in stmts {
        #partial switch s in stmt {
        case frontend.Return:
            return true
        case frontend.If_Block:
            if contains_return(s.body[:]) || contains_return(s.else_body[:]) {
                return true
            }
            if s.else_if != nil && contains_return(s.else_if.body[:]) {
                return true
            }
        }
    }
    return false
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

// emit a typed ir expression lowered from the language tree
emit_expr :: proc(builder: ^strings.Builder, expr: frontend.Expr, counter: ^int) -> string {
    typed := ir.lower_expression(expr)
    value := emit_typed_expr(builder, typed, counter)
    ir.destroy_expression(typed)
    return value
}

// emit one typed ir expression as an llvm value
emit_typed_expr :: proc(builder: ^strings.Builder, expr: ir.Expression, counter: ^int) -> string {
    #partial switch value in expr {
    case ir.Literal_Value:
        return fmt.aprintf("%d", value.value)
    case ir.Variable_Value:
        name := fmt.aprintf("%%v.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = load i32, ptr @var.%s", name, sanitize(value.name)))
        return name
    case ir.Grouping_Value:
        return emit_typed_expr(builder, value.inner^, counter)
    case ir.Binary_Value:
        left := emit_typed_expr(builder, value.left^, counter)
        right := emit_typed_expr(builder, value.right^, counter)
        operation: string
        switch value.op {
        case .Add: operation = "add"
        case .Sub: operation = "sub"
        case .Mul: operation = "mul"
        case .Div: operation = "sdiv"
        }
        name := fmt.aprintf("%%t.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = %s i32 %s, %s", name, operation, left, right))
        return name
    case ir.Comparison_Value:
        left := emit_typed_expr(builder, value.left^, counter)
        right := emit_typed_expr(builder, value.right^, counter)
        predicate: string
        switch value.op {
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
    case ir.Call_Value:
        args: strings.Builder
        strings.builder_init(&args)
        for argument, index in value.arguments {
            if index > 0 { strings.write_string(&args, ", ") }
            strings.write_string(&args, fmt.aprintf("i32 %s", emit_typed_expr(builder, argument, counter)))
        }
        name := fmt.aprintf("%%t.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = call i32 @moo_%s(%s)", name, sanitize(value.name), strings.to_string(args)))
        return name
    }
    return "0"
}

// turn an expression into an i32 llvm value, naming the results %%t.n
emit_language_expr :: proc(builder: ^strings.Builder, expr: frontend.Expr, counter: ^int) -> string {
    #partial switch e in expr {
    case frontend.Literal:
        if e.is_string {
            // a string has no numeric value, this should not be reached
            return "0"
        }
        return fmt.aprintf("%d", e.value)
    case frontend.Variable:
        name := fmt.aprintf("%%v.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = load i32, ptr @var.%s", name, sanitize(e.name)))
        return name
    case frontend.Comparison:
        // used when a comparison appears in a value position: widen the i1 to i32
        cond := emit_condition(builder, expr, counter)
        name := fmt.aprintf("%%t.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = zext i1 %s to i32", name, cond))
        return name
    case frontend.Grouping:
        return emit_language_expr(builder, e.inner^, counter)
    case frontend.Call:
        arguments_builder: strings.Builder
        strings.builder_init(&arguments_builder)
        for argument, index in e.arguments {
            if index > 0 { strings.write_string(&arguments_builder, ", ") }
            strings.write_string(&arguments_builder, fmt.aprintf("i32 %s", emit_language_expr(builder, argument, counter)))
        }
        arguments := strings.to_string(arguments_builder)
        name := fmt.aprintf("%%t.%d", counter^)
        counter^ += 1
        line(builder, fmt.aprintf("  %s = call i32 @moo_%s(%s)", name, sanitize(e.name), arguments))
        return name
    case frontend.Binary:
        left := emit_language_expr(builder, e.left^, counter)
        right := emit_language_expr(builder, e.right^, counter)
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
