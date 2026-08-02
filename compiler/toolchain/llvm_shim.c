#include "llvm_shim.h"

#include <stdio.h>
#include <string.h>

#include <llvm-c/Analysis.h>
#include <llvm-c/Core.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>

// write an error into the caller-owned error buffer
static void moo_error(char *error, int error_size, const char *message) {
    if (error == NULL || error_size <= 0) return;
    snprintf(error, (size_t)error_size, "%s", message);
}

// emit an object file from llvm ir without starting clang
int moo_llvm_emit_object(const char *ir_path, const char *object_path, const char *triple, char *error, int error_size) {
    LLVMInitializeNativeTarget();
    LLVMInitializeNativeAsmPrinter();

    LLVMMemoryBufferRef buffer = NULL;
    char *read_error = NULL;
    if (LLVMCreateMemoryBufferWithContentsOfFile(ir_path, &buffer, &read_error) != 0) {
        moo_error(error, error_size, read_error != NULL ? read_error : "could not read llvm ir");
        LLVMDisposeMessage(read_error);
        return 1;
    }

    LLVMContextRef context = LLVMContextCreate();
    LLVMModuleRef module = NULL;
    char *parse_error = NULL;
    if (LLVMParseIRInContext(context, buffer, &module, &parse_error) != 0) {
        moo_error(error, error_size, parse_error != NULL ? parse_error : "could not parse llvm ir");
        LLVMDisposeMessage(parse_error);
        LLVMDisposeMemoryBuffer(buffer);
        LLVMContextDispose(context);
        return 1;
    }

    LLVMSetTarget(module, triple);
    LLVMTargetRef target = NULL;
    char *target_error = NULL;
    if (LLVMGetTargetFromTriple(triple, &target, &target_error) != 0) {
        moo_error(error, error_size, target_error != NULL ? target_error : "could not find llvm target");
        LLVMDisposeMessage(target_error);
        LLVMDisposeModule(module);
        LLVMContextDispose(context);
        return 1;
    }

    LLVMTargetMachineRef machine = LLVMCreateTargetMachine(
        target,
        triple,
        "generic",
        "",
        LLVMCodeGenLevelDefault,
        LLVMRelocDefault,
        LLVMCodeModelDefault
    );
    if (machine == NULL) {
        moo_error(error, error_size, "could not create llvm target machine");
        LLVMDisposeModule(module);
        LLVMContextDispose(context);
        return 1;
    }

    char *emit_error = NULL;
    if (LLVMTargetMachineEmitToFile(machine, module, (char *)object_path, LLVMObjectFile, &emit_error) != 0) {
        moo_error(error, error_size, emit_error != NULL ? emit_error : "could not emit object file");
        LLVMDisposeMessage(emit_error);
        LLVMDisposeTargetMachine(machine);
        LLVMDisposeModule(module);
        LLVMContextDispose(context);
        return 1;
    }

    LLVMDisposeTargetMachine(machine);
    LLVMDisposeModule(module);
    LLVMContextDispose(context);
    return 0;
}
