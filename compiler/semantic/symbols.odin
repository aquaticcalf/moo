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
    parameters: [dynamic]frontend.Type,
    result: frontend.Type,
}

// find a function declaration by its source name
find_function_index :: proc(functions: []Function_Info, name: string) -> int {
    for function, index in functions { if function.name == name { return index } }
    return -1
}

find_function :: proc(functions: []Function_Info, name: string) -> (Function_Info, bool) {
    for function in functions {
        if function.name == name {
            return function, true
        }
    }
    return {}, false
}

