NASM ?= nasm
CC ?= cc
LD ?= ld
PYTHON ?= python3

.PHONY: all release debug reference foundation run demo test native-gate runtime-test verify audit disasm validate-gas clean test-guards
all: release

# Always rebuild. A failed tool lookup/build must not leave a stale success.
release:
	$(PYTHON) tools/build_native.py --profile release --nasm "$(NASM)" --cc "$(CC)"
debug:
	$(PYTHON) tools/build_native.py --profile debug --nasm "$(NASM)" --cc "$(CC)"
reference:
	$(PYTHON) tools/build_native.py --profile release --backend libc-reference --nasm "$(NASM)" --cc "$(CC)"
foundation:
	$(PYTHON) tools/build_foundation.py --nasm "$(NASM)" --ld "$(LD)" --cc "$(CC)"

run: release
	./bin/asmlab
demo: release
	./bin/asmlab --bits -f examples/walkthrough.asmlab

# Full v0.2.0 release gate: both application profiles + reference + foundation.
test: release debug reference foundation
	$(PYTHON) tools/release_gate.py --report-dir build/evidence
native-gate: release debug
	$(PYTHON) tools/native_gate.py --report-dir build/native-only
runtime-test: release debug reference foundation
	$(PYTHON) tools/runtime_gate.py --report-dir build/runtime-only

# No rebuild or NASM required; delivered objects/link maps are checked as well.
verify:
	$(PYTHON) tools/release_gate.py --report-dir build/verify-existing

test-guards:
	$(PYTHON) tests/gate_guards.py --report build/gate-guards.json
	$(PYTHON) tests/runtime_gate_guards.py --report build/runtime-gate-guards.json

audit:
	sh tests/audit.sh bin/asmlab
	sh tests/audit.sh bin/asmlab-debug
	$(PYTHON) tests/runtime_boundary.py --report build/boundary-audit.json

disasm: release debug
	objdump -d -Mintel bin/asmlab > build/release/asmlab.disassembly.txt
	objdump -d -Mintel bin/asmlab-debug > build/debug/asmlab.disassembly.txt

# The v0.1.0 single-unit GAS translator does not implement v0.2 module linking.
# Historical tool retained for provenance only; this is NOT a native fallback.
validate-gas:
	@echo "Unavailable for v0.2.0. Historical GAS bridge is not a release build path." >&2
	@exit 2

clean:
	rm -rf build
	rm -f bin/asmlab bin/asmlab-debug bin/asmlab-libc-reference bin/asmlab-runtime-smoke bin/asmlab-validation bin/*.build.json bin/BUILD_ORIGIN.txt
	rm -rf bin/tests
