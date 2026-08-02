package ir

import "compiler:frontend"

// a typed statement in the backend-neutral module
Statement :: union {
    Show_Statement,
    Assign_Statement,
    If_Statement,
    Return_Statement,
}

// a typed output statement
Show_Statement :: struct {
    value: Expression,
}

// a typed variable write
Assign_Statement :: struct {
    name: string,
    value: Expression,
}

// a typed return statement
Return_Statement :: struct {
    value: Expression,
    has_value: bool,
}

// a typed conditional statement
If_Statement :: struct {
    condition: Expression,
    body: [dynamic]Statement,
    else_body: [dynamic]Statement,
}

// release a typed statement and all nested values
destroy_statement :: proc(stmt: Statement) {
    switch value in stmt {
    case Show_Statement:
        destroy_expression(value.value)
    case Assign_Statement:
        destroy_expression(value.value)
    case Return_Statement:
        if value.has_value { destroy_expression(value.value) }
    case If_Statement:
        destroy_expression(value.condition)
        for child in value.body { destroy_statement(child) }
        for child in value.else_body { destroy_statement(child) }
    }
}

// lower one language statement into backend-neutral statements
lower_statement :: proc(stmt: frontend.Stmt) -> (Statement, bool) {
    switch value in stmt {
    case frontend.Show:
        return Show_Statement{value = lower_expression(value.expr)}, true
    case frontend.Variable_Decl:
        return Assign_Statement{name = value.name, value = lower_expression(value.expr)}, true
    case frontend.Variable_Assign:
        return Assign_Statement{name = value.name, value = lower_expression(value.expr)}, true
    case frontend.Return:
        if value.has_value {
            return Return_Statement{value = lower_expression(value.expr), has_value = true}, true
        }
        return Return_Statement{has_value = false}, true
    case frontend.If_Block:
        result := If_Statement{condition = lower_expression(value.condition)}
        for child in value.body {
            lowered, ok := lower_statement(child)
            if ok { append(&result.body, lowered) }
        }
        for child in value.else_body {
            lowered, ok := lower_statement(child)
            if ok { append(&result.else_body, lowered) }
        }
        return result, true
    case frontend.Function:
        return {}, false
    }
    return {}, false
}
