package frontend

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
    Keyword_Becomes,
    Keyword_Make,
    Keyword_Give,
    Keyword_True,
    Keyword_False,
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
    Comma,
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
    Call,
}

// a literal is a value written directly in the code ( a number or a string )
Literal :: struct {
    span: Span,
    value: i64,
    is_string: bool,
    is_boolean: bool,
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

// a call to a moo function
Call :: struct {
    span: Span,
    name: string,
    arguments: [dynamic]Expr,
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

// a reassignment using the friendly 'becomes' operator
Variable_Assign :: struct {
    span: Span,
    name: string,
    expr: Expr,
}

// a function declaration with inferred parameter and return types
Function :: struct {
    span: Span,
    name: string,
    parameters: [dynamic]string,
    body: [dynamic]Stmt,
}

// a return statement using the friendly 'give' keyword
Return :: struct {
    span: Span,
    expr: Expr,
    has_value: bool,
}

// inferred value kinds used by semantic checking
Type :: enum {
    Unknown,
    Integer,
    Boolean,
    String,
    Nothing,
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
    Variable_Assign,
    If_Block,
    Function,
    Return,
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
