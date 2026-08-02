linux:
	mkdir -p build/linux && \
	cc -fPIC -c compiler/toolchain/llvm_shim.c $$(llvm-config --cflags) -o build/linux/llvm_shim.o && \
	ar rcs build/linux/libmoo_llvm_shim.a build/linux/llvm_shim.o && \
	cd compiler && \
	odin build . --collection:compiler=. -o:speed -out:../build/linux/moo -extra-linker-flags:"-Wno-override-module -L../build/linux -lmoo_llvm_shim $$(llvm-config --libs --system-libs)"

windows:
	mkdir -p build/windows && \
	cd compiler && \
	odin build . --collection:compiler=. -o:speed -out:../build/windows/moo -target:windows_amd64 -build-mode:obj && \
	clear && \
	echo "now run these commands from a native msvc developer prompt : " && \
 	echo "cl.exe /nologo /c /I%LLVM_ROOT%\\include compiler\\toolchain\\llvm_shim.c /Fo:build\\windows\\llvm_shim.obj" && \
 	echo "lib.exe /nologo build\\windows\\llvm_shim.obj /out:build\\windows\\libmoo_llvm_shim.lib" && \
 	echo "link.exe build\\windows\\moo.obj build\\windows\\llvm_shim.obj /out:build\\windows\\moo.exe /subsystem:console /nodefaultlib:libcmt.lib /nodefaultlib:libucrt.lib msvcrt.lib ucrt.lib ole32.lib bcrypt.lib kernel32.lib shell32.lib advapi32.lib"
