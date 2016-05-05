all: msim

msim: msim.d mips.d terminal.d
	dmd -O -inline msim.d mips.d terminal.d

clean:
	rm -f msim *.lst *.o *~
