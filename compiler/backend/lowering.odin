package backend

import "core:fmt"
import "core:strings"

import "compiler:ir"

// emit a typed ir expression and preserve its llvm type at the seam
emit_typed_value :: proc(builder: ^strings.Builder, expr: ir.Expression, state: ^Emit_State) -> LLVM_Value {
    switch value in expr {
    case ir.Literal_Value:
        if value.type == .String {
            index := state.string_index
            state.string_index += 1
            length := 0
            if index < len(state.string_lengths) { length = state.string_lengths[index] }
            pointer := fmt.aprintf("getelementptr inbounds ([%d x i8], ptr @.str.%d, i64 0, i64 0)", length, index)
            return make_value(.String, pointer)
        }
        return make_value(value.type, fmt.aprintf("%d", value.value))
    case ir.Variable_Value:
        name := fmt.aprintf("%%v.%d", state.counter)
        state.counter += 1
        line(builder, fmt.aprintf("  %s = load %s, ptr @var.%s", name, llvm_type(value.type), sanitize(value.name)))
        return make_value(value.type, name)
    case ir.Grouping_Value:
        return emit_typed_value(builder, value.inner^, state)
    case ir.Binary_Value:
        if value.type == .String && value.op == .Add {
            left := emit_typed_value(builder, value.left^, state)
            right := emit_typed_value(builder, value.right^, state)
            left_length := fmt.aprintf("%%strlen.%d", state.counter)
            state.counter += 1
            right_length := fmt.aprintf("%%strlen.%d", state.counter)
            state.counter += 1
            size_base := fmt.aprintf("%%strsize.base.%d", state.counter)
            state.counter += 1
            size := fmt.aprintf("%%strsize.%d", state.counter)
            state.counter += 1
            buffer := fmt.aprintf("%%strbuf.%d", state.counter)
            state.counter += 1
            line(builder, fmt.aprintf("  %s = call i64 @strlen(ptr %s)", left_length, left.value))
            line(builder, fmt.aprintf("  %s = call i64 @strlen(ptr %s)", right_length, right.value))
            line(builder, fmt.aprintf("  %s = add i64 %s, %s", size_base, left_length, right_length))
            line(builder, fmt.aprintf("  %s = add i64 %s, 1", size, size_base))
            line(builder, fmt.aprintf("  %s = call ptr @malloc(i64 %s)", buffer, size))
            line(builder, fmt.aprintf("  call ptr @strcpy(ptr %s, ptr %s)", buffer, left.value))
            line(builder, fmt.aprintf("  call ptr @strcat(ptr %s, ptr %s)", buffer, right.value))
            return make_value(.String, buffer)
        }
        return make_value(value.type, emit_typed_expr(builder, expr, &state.counter))
    case ir.Comparison_Value:
        return make_value(.Boolean, emit_typed_expr(builder, expr, &state.counter))
    case ir.Call_Value:
        return make_value(value.type, emit_typed_expr(builder, expr, &state.counter))
    }
    return make_value(.Nothing, "")
}
