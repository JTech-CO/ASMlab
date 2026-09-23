NASM ?= nasm
CC ?= cc
PYTHON ?= python3

.PHONY: all release debug run demo test native-gate verify audit disasm validate-gas clean
all: release

# Deliberately rebuild: changing a tool/profile cannot reuse stale artifacts.
release:
	$(PYTHON) tools/build_native.py --profile release --nasm "$(NASM)" --cc "$(CC)"

debug:
	$(PYTHON) tools/build_native.py --profile debug --nasm "$(NASM)" --cc "$(CC)"

run: release
	./bin/asmlab

demo: release
	./bin/asmlab --bits -f examples/walkthrough.asmlab

test: native-gate
native-gate: release debug
	$(PYTHON) tools/native_gate.py --report-dir build/evidence

# Verify the already delivered binaries and their provenance, without NASM.
verify:
	$(PYTHON) tools/native_gate.py --report-dir build/verify-existing

audit:
	sh tests/audit.sh ./bin/asmlab
	sh tests/audit.sh ./bin/asmlab-debug

disasm: release debug
	objdump -d -Mintel bin/asmlab > build/release/asmlab.disassembly.txt
	objdump -d -Mintel bin/asmlab-debug > build/debug/asmlab.disassembly.txt

# Historical comparison only. NEVER part of all/test/native-gate/release.
validate-gas:
	@mkdir -p build/validation bin
	$(PYTHON) tools/validation_bridge.py . build/validation/asmlab.s
	as --64 -g -o build/validation/asmlab.o build/validation/asmlab.s
	$(CC) -no-pie -Wl,-z,noexecstack,-z,relro,-z,now -o bin/asmlab-validation build/validation/asmlab.o
	$(PYTHON) tests/verify.py ./bin/asmlab-validation
	sh tests/audit.sh ./bin/asmlab-validation

clean:
	rm -rf build
	rm -f bin/asmlab bin/asmlab-debug bin/asmlab-validation bin/*.build.json bin/BUILD_ORIGIN.txt
