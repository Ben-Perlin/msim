all: masm msim

masm: src-masm/*.d
	make -C src-masm
	rm -f masm
	ln src-masm/masm masm

msim: masm src/msim.d src/mips.d src/terminal.d
	dmd -O -inline src/msim.d src/mips.d src/terminal.d

clean:
	rm -f masm msim *.lst *.o src/*~ src-masm/*~ *~
