package frontend

// delete all of the memory allocated to an expression tree
destroy_expr :: proc(expr: Expr) {
    switch e in expr {
    case Literal:
        if e.is_string {
            delete(e.text)
        }
    case Variable:
    // nothing to free, the name lives in the source text
    case Comparison:
        destroy_expr(e.left^)
        destroy_expr(e.right^)
        free(e.left)
        free(e.right)
    case Binary:
        destroy_expr(e.left^)
        destroy_expr(e.right^)
        free(e.left)
        free(e.right)
    case Grouping:
        destroy_expr(e.inner^)
        free(e.inner)
    case Call:
        for argument in e.arguments {
            destroy_expr(argument)
        }
        delete(e.arguments)
        delete(e.name)
    }
}

// delete all of the memory allocated to the collection of statements while compilation
destroy_stmts :: proc(stmts: ^[dynamic]Stmt) {
    for i in 0..<len(stmts) {
        stmt := &stmts[i]
        switch &s in stmt {
        case Show:
            destroy_expr(s.expr)
        case Variable_Decl:
            destroy_expr(s.expr)
            delete(s.name)
        case Variable_Assign:
            destroy_expr(s.expr)
            delete(s.name)
        case Return:
            if s.has_value {
                destroy_expr(s.expr)
            }
        case Function:
            for parameter in s.parameters {
                delete(parameter)
            }
            delete(s.parameters)
            destroy_stmts(&s.body)
        case If_Block:
            destroy_stmt(&s)
        }
    }
    delete(stmts^)
}

// recursively delete an if block and everything inside it
destroy_stmt :: proc(if_block: ^If_Block) {
    destroy_expr(if_block.condition)
    destroy_stmts(&if_block.body)
    destroy_stmts(&if_block.else_body)
    if if_block.else_if != nil {
        destroy_stmt(if_block.else_if)
        free(if_block.else_if)
    }
}

// delete all of the memory allocated to the collection of statements while compilation
destroy_program :: proc(program: ^Program) {
    destroy_stmts(&program.statements)
}

// delete all of the memory allocated to the collection of errors while compilation
destroy_diagnostics :: proc(diagnostics: ^Diagnostics) {
    for index := 0; index < len(diagnostics.errors); index += 1 {
        delete(diagnostics.errors[index].message)
    }
    delete(diagnostics.errors)
}

// delete all of the memory allocated to the parse result while compilation
destroy_parse_result :: proc(result: ^Parse_Result) {
    destroy_program(&result.program)
    destroy_diagnostics(&result.diagnostics)
}
