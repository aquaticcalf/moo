package backend

import "core:fmt"
import "core:strings"

import "compiler:ir"

// emit typed ir statements at the current llvm insertion point
emit_typed_statements :: proc(builder: ^strings.Builder, statements: []ir.Statement, state: ^Emit_State) {
    for statement in statements {
        #partial switch value in statement {
        case ir.Assign_Statement:
            result := emit_typed_value(builder, value.value, state)
            line(builder, fmt.aprintf("  store %s %s, ptr @var.%s", result.type, result.value, sanitize(value.name)))
        case ir.Show_Statement:
            result := emit_typed_value(builder, value.value, state)
            if result.type == "ptr" {
                line(builder, fmt.aprintf("  %%show.%d = call i32 @puts(ptr %s)", state.counter, result.value))
            } else {
                line(builder, fmt.aprintf("  %%show.%d = call i32 @printf(ptr @.fmt.int, i32 %s)", state.counter, result.value))
            }
            state.counter += 1
        case ir.Return_Statement:
            if value.has_value {
                result := emit_typed_value(builder, value.value, state)
                line(builder, fmt.aprintf("  ret %s %s", result.type, result.value))
            } else {
                line(builder, "  ret void")
            }
        case ir.If_Statement:
            condition := emit_typed_expr(builder, value.condition, &state.counter)
            truth := fmt.aprintf("%%typed.cond.%d", state.counter)
            state.counter += 1
            line(builder, fmt.aprintf("  %s = icmp ne i32 %s, 0", truth, condition))
            number := state.label_counter
            state.label_counter += 1
            then_label := fmt.aprintf("typed.then.%d", number)
            merge_label := fmt.aprintf("typed.merge.%d", number)
            line(builder, fmt.aprintf("  br i1 %s, label %%%s, label %%%s", truth, then_label, merge_label))
            line(builder, fmt.aprintf("%s:", then_label))
            emit_typed_statements(builder, value.body[:], state)
            line(builder, fmt.aprintf("  br label %%%s", merge_label))
            line(builder, fmt.aprintf("%s:", merge_label))
        }
    }
}

// check whether typed statements contain a return terminator
typed_contains_return :: proc(statements: []ir.Statement) -> bool {
    for statement in statements {
        switch value in statement {
        case ir.Return_Statement:
            return true
        case ir.If_Statement:
            if typed_contains_return(value.body[:]) || typed_contains_return(value.else_body[:]) {
                return true
            }
        case ir.Show_Statement, ir.Assign_Statement:
        }
    }
    return false
}
