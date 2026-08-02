#ifndef MOO_LLVM_SHIM_H
#define MOO_LLVM_SHIM_H

// emit an object file from llvm ir without starting clang
int moo_llvm_emit_object(const char *ir_path, const char *object_path, const char *triple, char *error, int error_size);

#endif
