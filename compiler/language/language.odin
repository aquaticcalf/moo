package language

import "core:fmt"

// span is a ( x, y ) coordinates system for the tokens in code
Span :: struct {
    line: int,
    column: int,
}

// token vocabulary
Token_Kind :: enum {
    Eof,
    Newline,
    Indent,
    Dedent,
    Keyword_Show,
    Keyword_Is,
    Keyword_If,
    Keyword_Otherwise,
    Identifier,
    Comparison,
    String,
    Number,
    Plus,
    Minus,
    Star,
    Slash,
    Colon,
    LParen,
    RParen,
}

// a token has a kind, the actual data and it's coordinates
Token :: struct {
    kind: Token_Kind,
    text: string,
    span: Span,
    op: Comparison_Op,
}

// what operators we have in an arithmetic expression
Bin_Op :: enum {
    Add,
    Sub,
    Mul,
    Div,
}

// what comparison phrases we have in a condition
Comparison_Op :: enum {
    Equal,
    Not_Equal,
    Greater,
    Less,
    Greater_Or_Equal,
    Less_Or_Equal,
}

// every expression is one of these five
Expr :: union {
    Literal,
    Variable,
    Comparison,
    Binary,
    Grouping,
}

// a literal is a value written directly in the code ( a number or a string )
Literal :: struct {
    span: Span,
    value: i64,
    is_string: bool,
    text: string,
}

// a variable is a reference to a named value that was assigned with 'is'
Variable :: struct {
    span: Span,
    name: string,
}

// a comparison compares two expressions with a comparison phrase
Comparison :: struct {
    span: Span,
    op: Comparison_Op,
    left: ^Expr,
    right: ^Expr,
}

// a binary operation combines two expressions with an operator
Binary :: struct {
    span: Span,
    op: Bin_Op,
    left: ^Expr,
    right: ^Expr,
}

// a grouping is an expression wrapped in parentheses
Grouping :: struct {
    span: Span,
    inner: ^Expr,
}

// a show is a statement that prints an expression
Show :: struct {
    span: Span,
    expr: Expr,
}

// a variable declaration or assignment using the 'is' operator
Variable_Decl :: struct {
    span: Span,
    name: string,
    expr: Expr,
}

// one "if condition:" branch with its indented body
If_Block :: struct {
    span: Span,
    condition: Expr,
    body: [dynamic]Stmt,
    // an "otherwise if ..." nests a new if as the else branch
    else_if: ^If_Block,
    // a plain "otherwise:" body
    else_body: [dynamic]Stmt,
    has_else_body: bool,
}

// every statement is one of these three
Stmt :: union {
    Show,
    Variable_Decl,
    If_Block,
}

// a program is a collection of statements
Program :: struct {
    statements: [dynamic]Stmt,
}

// diagnostic is an error message with its coordinates
Diagnostic :: struct {
    span: Span,
    message: string,
}

// diagnostics is file path and error list
Diagnostics :: struct {
    path: string,
    errors: [dynamic]Diagnostic,
}

// this is the main shape that contains all the details of a parse
Parse_Result :: struct {
    program: Program,
    diagnostics: Diagnostics,
    ok: bool,
    source_hash: u64,
}

// add an error to the errors list
report :: proc(diagnostics: ^Diagnostics, span: Span, message: string) {
    append(&diagnostics.errors, Diagnostic{span = span, message = message})
}

// add an error to the errors list with additional formatting
reportf :: proc(diagnostics: ^Diagnostics, span: Span, format: string, args: ..any) {
    report(diagnostics, span, fmt.aprintf(format, ..args))
}

// are there any errors?
has_errors :: proc(diagnostics: ^Diagnostics) -> bool {
    return len(diagnostics.errors) > 0
}

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
