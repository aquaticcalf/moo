package backend

import "core:fmt"
import "core:strings"

import "compiler:frontend"

// emit an if / otherwise if / otherwise chain with basic blocks
emit_if_block :: proc(builder: ^strings.Builder, block: frontend.If_Block, state: ^Emit_State, string_lengths: []int) {
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
emit_condition :: proc(builder: ^strings.Builder, expr: frontend.Expr, counter: ^int) -> string {
    if comp, ok := expr.(frontend.Comparison); ok {
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

