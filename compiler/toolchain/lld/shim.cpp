#include "shim.h"

#include <cstdio>
#include <string>

#include <lld/Common/Driver.h>
#include <llvm/Support/raw_ostream.h>

#ifdef _WIN32
LLD_HAS_DRIVER(coff)
#else
LLD_HAS_DRIVER(elf)
#endif

// link native objects in-process through the lld library
extern "C" int moo_lld_link(int argc, const char **arguments, char *error, int error_size) {
    std::string output;
    llvm::raw_string_ostream output_stream(output);
    llvm::ArrayRef<const char *> args(arguments, static_cast<size_t>(argc));
#ifdef _WIN32
    bool success = lld::coff::link(args, output_stream, output_stream, false, false);
#else
    bool success = lld::elf::link(args, output_stream, output_stream, false, false);
#endif
    output_stream.flush();
    if (!success && error != nullptr && error_size > 0) {
        std::snprintf(error, static_cast<size_t>(error_size), "%s", output.c_str());
    }
    return success ? 0 : 1;
}
