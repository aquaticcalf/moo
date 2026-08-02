linux:
	mkdir -p build/linux && \
	cd compiler && \
	odin build . --collection:compiler=. -o:speed -out:../build/linux/moo -extra-linker-flags:"-Wno-override-module"

windows:
	mkdir -p build/windows && \
	cd compiler && \
	odin build . --collection:compiler=. -o:speed -out:../build/windows/moo -target:windows_amd64 -build-mode:obj && \
	clear && \
	echo "now run this on windows : " && \
 	echo "link.exe build/windows/moo.obj /out:build/windows/moo.exe /subsystem:console /nodefaultlib:libcmt.lib /nodefaultlib:libucrt.lib msvcrt.lib ucrt.lib ole32.lib bcrypt.lib kernel32.lib shell32.lib advapi32.lib"
