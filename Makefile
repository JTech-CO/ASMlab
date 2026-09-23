NASM ?= nasm
CC ?= gcc
PYTHON ?= python3
ASM_SOURCES := $(wildcard src/*.asm) $(wildcard include/*.inc)
NASMFLAGS := -f elf64 -g -F dwarf -Wall
LDFLAGS := -no-pie -Wl,-z,noexecstack,-z,relro,-z,now

.PHONY: all clean run demo test audit disasm validate-gas
all: bin/asmlab

build/asmlab.o: $(ASM_SOURCES)
	@mkdir -p build bin
	$(NASM) $(NASMFLAGS) -I./ -o $@ src/asmlab.asm

bin/asmlab: build/asmlab.o
	$(CC) $(LDFLAGS) -o $@ $<
	@printf '%s\n' 'NASM native build' > bin/BUILD_ORIGIN.txt

run: all
	./bin/asmlab

demo: all
	./bin/asmlab --bits -f examples/walkthrough.asmlab

test: all
	$(PYTHON) tests/verify.py ./bin/asmlab
	sh tests/audit.sh ./bin/asmlab

audit:
	sh tests/audit.sh ./bin/asmlab

disasm: all
	objdump -d -Mintel bin/asmlab > build/asmlab.disassembly.txt

# Explicit local verification path only. This does NOT test NASM itself.
# The runtime remains x86-64 machine code from the authored assembly routines.
validate-gas:
	@mkdir -p build bin
	$(PYTHON) tools/validation_bridge.py . build/asmlab.validation.s
	as --64 -g -o build/asmlab.validation.o build/asmlab.validation.s
	$(CC) $(LDFLAGS) -o bin/asmlab-validation build/asmlab.validation.o
	$(PYTHON) tests/verify.py ./bin/asmlab-validation
	sh tests/audit.sh ./bin/asmlab-validation

clean:
	rm -rf build
	rm -f bin/asmlab bin/asmlab-validation bin/BUILD_ORIGIN.txt
