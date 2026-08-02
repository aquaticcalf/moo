linux:
	mkdir -p build/linux && \
	cc -fPIC -c compiler/toolchain/llvm/shim.c $$(llvm-config --cflags) -o build/linux/llvmshim.o && \
	c++ -fPIC -c compiler/toolchain/lld/shim.cpp $$(llvm-config --cxxflags) -I/usr/lib/llvm-20/include -o build/linux/lldshim.o && \
	ar rcs build/linux/libmoo_llvmshim.a build/linux/llvmshim.o && \
	ar rcs build/linux/libmoo_lldshim.a build/linux/lldshim.o && \
	cd compiler && \
	odin build . --collection:compiler=. -o:speed -out:../build/linux/moo -extra-linker-flags:"-Wno-override-module -L../build/linux -lmoo_llvmshim -lmoo_lldshim -L/usr/lib/llvm-20/lib -llldELF -llldCommon $$(llvm-config --libs --system-libs) -lz -lzstd -ltinfo -lm -ldl -lpthread -lstdc++"

windows:
	mkdir -p build/windows && \
	cd compiler && \
	odin build . --collection:compiler=. -o:speed -out:../build/windows/moo -target:windows_amd64 -build-mode:obj && \
	clear && \
	echo "now run these commands from a native msvc developer prompt : " && \
 	echo "cl.exe /nologo /c /I%LLVM_ROOT%\\include compiler\\toolchain\\llvm_shim.c /Fo:build\\windows\\llvmshim.obj" && \
 	echo "cl.exe /nologo /EHsc /c /I%LLVM_ROOT%\\include compiler\\toolchain\\lld_shim.cpp /Fo:build\\windows\\lldshim.obj" && \
 	echo "lib.exe /nologo build\\windows\\llvmshim.obj /out:build\\windows\\libmoo_llvmshim.lib" && \
 	echo "lib.exe /nologo build\\windows\\lldshim.obj /out:build\\windows\\libmoo_lldshim.lib" && \
 	echo "link.exe build\\windows\\moo.obj build\\windows\\libmoo_llvmshim.lib build\\windows\\libmoo_lldshim.lib /LIBPATH:%LLVM_ROOT%\\lib LLVM-C.lib lldCOFF.lib lldCommon.lib /out:build\\windows\\moo.exe /subsystem:console /nodefaultlib:libcmt.lib /nodefaultlib:libucrt.lib msvcrt.lib ucrt.lib ole32.lib bcrypt.lib kernel32.lib shell32.lib advapi32.lib"
