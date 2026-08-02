package semantic

import "compiler:frontend"

// one inferred name and its value kind
Symbol :: struct {
    name: string,
    type: frontend.Type,
}

// one function signature known during semantic checking
Function_Info :: struct {
    name: string,
    arity: int,
    result: frontend.Type,
}

// find a function declaration by its source name
find_function :: proc(functions: []Function_Info, name: string) -> (Function_Info, bool) {
    for function in functions {
        if function.name == name {
            return function, true
        }
    }
    return {}, false
}

