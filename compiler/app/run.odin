package app

import "core:fmt"

print_usage :: proc() {
    fmt.println("usage : ")
    fmt.println("  moo help")
    fmt.println("  moo check file.moo")
    fmt.println("  moo build file.moo")
    fmt.println("  moo run file.moo")
}

run :: proc(args: []string) -> int {
    if len(args) == 0 {
        print_usage()
        return 1
    }

    command := args[0]
    if command == "help" && len(args) == 1 {
        print_usage()
        return 0
    }

    if len(args) == 1 && (command == "check" || command == "build" || command == "run") {
        fmt.printfln("expected a filename after \"moo %s\"", command)
        return 1
    }

    if len(args) != 2 || (command != "check" && command != "build" && command != "run") {
        print_usage()
        return 1
    }

    fmt.println("ok")
    return 0
}
