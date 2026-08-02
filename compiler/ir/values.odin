package ir

import "compiler:frontend"

// a typed expression after language analysis
Expression :: union {
    Literal_Value,
    Variable_Value,
    Binary_Value,
    Comparison_Value,
    Grouping_Value,
    Call_Value,
}

// a literal with its inferred backend type
Literal_Value :: struct {
    type: Value_Type,
    value: i64,
    text: string,
}

// a typed variable read
Variable_Value :: struct {
    name: string,
    type: Value_Type,
}

// a typed arithmetic expression
Binary_Value :: struct {
    op: frontend.Bin_Op,
    left: ^Expression,
    right: ^Expression,
    type: Value_Type,
}

// a typed comparison expression
Comparison_Value :: struct {
    op: frontend.Comparison_Op,
    left: ^Expression,
    right: ^Expression,
}

// a typed parenthesized expression
Grouping_Value :: struct {
    inner: ^Expression,
    type: Value_Type,
}

// a typed function call expression
Call_Value :: struct {
    name: string,
    arguments: [dynamic]Expression,
    parameter_types: [dynamic]Value_Type,
    type: Value_Type,
}

// release a typed expression and its nested values
destroy_expression :: proc(expr: Expression) {
    switch value in expr {
    case Binary_Value:
        destroy_expression(value.left^)
        destroy_expression(value.right^)
        free(value.left)
        free(value.right)
    case Comparison_Value:
        destroy_expression(value.left^)
        destroy_expression(value.right^)
        free(value.left)
        free(value.right)
    case Grouping_Value:
        destroy_expression(value.inner^)
        free(value.inner)
    case Call_Value:
        for argument in value.arguments { destroy_expression(argument) }
        delete(value.arguments)
        delete(value.parameter_types)
    case Literal_Value, Variable_Value:
    }
}

// lower a language expression into a typed backend value
lower_expression :: proc(expr: frontend.Expr) -> Expression {
    switch value in expr {
    case frontend.Literal:
        value_type := Value_Type.Integer
        if value.is_string { value_type = .String }
        if value.is_boolean { value_type = .Boolean }
        return Literal_Value{type = value_type, value = value.value, text = value.text}
    case frontend.Variable:
        return Variable_Value{name = value.name, type = .Integer}
    case frontend.Binary:
        left := new(Expression)
        right := new(Expression)
        left^ = lower_expression(value.left^)
        right^ = lower_expression(value.right^)
        return Binary_Value{op = value.op, left = left, right = right, type = .Integer}
    case frontend.Comparison:
        left := new(Expression)
        right := new(Expression)
        left^ = lower_expression(value.left^)
        right^ = lower_expression(value.right^)
        return Comparison_Value{op = value.op, left = left, right = right}
    case frontend.Grouping:
        inner := new(Expression)
        inner^ = lower_expression(value.inner^)
        return Grouping_Value{inner = inner, type = .Integer}
    case frontend.Call:
        arguments: [dynamic]Expression
        for argument in value.arguments {
            append(&arguments, lower_expression(argument))
        }
        parameter_types: [dynamic]Value_Type
        for argument in value.arguments {
            argument_type := Value_Type.Integer
            if literal, ok := argument.(frontend.Literal); ok {
                if literal.is_string { argument_type = .String }
                if literal.is_boolean { argument_type = .Boolean }
            }
            append(&parameter_types, argument_type)
        }
        return Call_Value{name = value.name, arguments = arguments, parameter_types = parameter_types, type = .Integer}
    }
    return Literal_Value{type = .Integer}
}
