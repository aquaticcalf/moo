package language

// one inferred name and its value kind
Symbol :: struct {
    name: string,
    type: Type,
}

// check the complete program without requiring written type annotations
semantic_check :: proc(program: Program, diagnostics: ^Diagnostics) {
    symbols: [dynamic]Symbol
    defer delete(symbols)
    check_statements(program.statements[:], &symbols, diagnostics)
}

// look up an already introduced name
find_symbol :: proc(symbols: []Symbol, name: string) -> (Type, bool) {
    for symbol in symbols {
        if symbol.name == name {
            return symbol.type, true
        }
    }
    return .Unknown, false
}

// remember a newly introduced name
set_symbol :: proc(symbols: ^[dynamic]Symbol, name: string, type: Type) {
    append(symbols, Symbol{name = name, type = type})
}

// check a sequence of statements and infer every value used inside it
check_statements :: proc(stmts: []Stmt, symbols: ^[dynamic]Symbol, diagnostics: ^Diagnostics) {
    for stmt in stmts {
        #partial switch s in stmt {
        case Show:
            value_type := infer_expr(s.expr, symbols[:], diagnostics)
            if value_type == .Unknown {
                continue
            }
            if value_type != .Integer && value_type != .String && value_type != .Boolean {
                reportf(diagnostics, s.span, "cannot show this value")
            }
            if value_type == .String && !is_direct_string(s.expr) {
                reportf(diagnostics, s.span, "string values can currently only be shown directly")
            }
        case Variable_Decl:
            value_type := infer_expr(s.expr, symbols[:], diagnostics)
            if value_type == .Unknown {
                continue
            }
            if value_type == .String {
                reportf(diagnostics, s.span, "string variables are not supported yet; show the string directly")
                continue
            }
            if _, exists := find_symbol(symbols[:], s.name); exists {
                reportf(diagnostics, s.span, "'%s' already exists; use '%s becomes ...' to change it", s.name, s.name)
                continue
            }
            set_symbol(symbols, s.name, value_type)
        case Variable_Assign:
            value_type := infer_expr(s.expr, symbols[:], diagnostics)
            old_type, exists := find_symbol(symbols[:], s.name)
            if !exists {
                reportf(diagnostics, s.span, "'%s' has not been introduced yet; use '%s is ...' first", s.name, s.name)
                continue
            }
            if value_type != .Unknown && old_type != value_type {
                reportf(diagnostics, s.span, "'%s' is %s, but the new value is %s", s.name, type_name(old_type), type_name(value_type))
            }
        case If_Block:
            condition_type := infer_expr(s.condition, symbols[:], diagnostics)
            if condition_type != .Unknown && condition_type != .Boolean && condition_type != .Integer {
                reportf(diagnostics, s.span, "an if condition must be a number or a comparison")
            }
            check_statements(s.body[:], symbols, diagnostics)
            if s.else_if != nil {
                check_if_chain(s.else_if, symbols, diagnostics)
            }
            check_statements(s.else_body[:], symbols, diagnostics)
        }
    }
}

// check an otherwise-if chain recursively
check_if_chain :: proc(block: ^If_Block, symbols: ^[dynamic]Symbol, diagnostics: ^Diagnostics) {
    condition_type := infer_expr(block.condition, symbols[:], diagnostics)
    if condition_type != .Unknown && condition_type != .Boolean && condition_type != .Integer {
        reportf(diagnostics, block.span, "an if condition must be a number or a comparison")
    }
    check_statements(block.body[:], symbols, diagnostics)
    if block.else_if != nil {
        check_if_chain(block.else_if, symbols, diagnostics)
    }
    check_statements(block.else_body[:], symbols, diagnostics)
}

// infer the kind of an expression and report contradictions
infer_expr :: proc(expr: Expr, symbols: []Symbol, diagnostics: ^Diagnostics) -> Type {
    #partial switch e in expr {
    case Literal:
        if e.is_string {
            return .String
        }
        return .Integer
    case Variable:
        value_type, exists := find_symbol(symbols, e.name)
        if !exists {
            reportf(diagnostics, e.span, "'%s' has not been introduced yet; use '%s is ...' first", e.name, e.name)
            return .Unknown
        }
        return value_type
    case Grouping:
        return infer_expr(e.inner^, symbols, diagnostics)
    case Binary:
        left := infer_expr(e.left^, symbols, diagnostics)
        right := infer_expr(e.right^, symbols, diagnostics)
        if left == .Unknown || right == .Unknown {
            return .Unknown
        }
        if left != .Integer || right != .Integer {
            reportf(diagnostics, e.span, "arithmetic needs numbers")
            return .Unknown
        }
        return .Integer
    case Comparison:
        left := infer_expr(e.left^, symbols, diagnostics)
        right := infer_expr(e.right^, symbols, diagnostics)
        if left == .Unknown || right == .Unknown {
            return .Unknown
        }
        if left != right || (left != .Integer && left != .Boolean) {
            reportf(diagnostics, e.span, "comparisons need matching number or boolean values")
            return .Unknown
        }
        return .Boolean
    }
    return .Unknown
}

// check whether an expression is a directly written string literal
is_direct_string :: proc(expr: Expr) -> bool {
    literal, ok := expr.(Literal)
    return ok && literal.is_string
}

// turn an inferred kind into friendly diagnostic wording
type_name :: proc(value_type: Type) -> string {
    #partial switch value_type {
    case .Unknown: return "an unknown value"
    case .Integer: return "a number"
    case .Boolean: return "a boolean"
    case .String: return "a string"
    }
}
