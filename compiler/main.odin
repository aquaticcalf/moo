package main

import "core:os"
import "compiler:app"

main :: proc() {
    os.exit(app.run(os.args[1:]))
}
