NASM ?= nasm
CC ?= cc
LD ?= ld
PYTHON ?= python3

.PHONY: all release debug reference foundation run demo test native-gate runtime-test verify audit disasm validate-gas clean test-guards l3-test empty-root-test workspace-test
all: release

# Always rebuild. A failed tool lookup/build must not leave a stale success.
release:
	$(PYTHON) tools/build_native.py --profile release --nasm "$(NASM)" --cc "$(CC)" --ld "$(LD)"
debug:
	$(PYTHON) tools/build_native.py --profile debug --nasm "$(NASM)" --cc "$(CC)" --ld "$(LD)"
reference:
	$(PYTHON) tools/build_native.py --profile release --backend libc-reference --nasm "$(NASM)" --cc "$(CC)" --ld "$(LD)"
foundation:
	$(PYTHON) tools/build_foundation.py --nasm "$(NASM)" --ld "$(LD)" --cc "$(CC)"

run: release
	./bin/asmlab
demo: release
	./bin/asmlab --bits -f examples/walkthrough.asmlab

# Full v0.4.0: Native + Foundation + exact decimal + L3 + dynamic workspace.
test: release debug reference foundation
	$(PYTHON) tools/release_gate.py --report-dir build/evidence
native-gate: release debug
	$(PYTHON) tools/native_gate.py --report-dir build/native-only
runtime-test: release debug reference foundation
	$(PYTHON) tools/runtime_gate.py --report-dir build/runtime-only

# No rebuild or NASM required; delivered objects/link maps are checked as well.
verify:
	$(PYTHON) tools/release_gate.py --report-dir build/verify-existing

workspace-test: release debug reference foundation
	$(PYTHON) tools/dynamic_gate.py --report-dir build/dynamic-only

l3-test: release debug reference foundation
	$(PYTHON) tools/l3_gate.py --report-dir build/l3-only

# Requires chroot privilege. Not needed for ordinary build/use.
empty-root-test:
	$(PYTHON) tests/l3_core.py --require-empty-root --report build/empty-root.json

test-guards:
	$(PYTHON) tests/gate_guards.py --report build/gate-guards.json
	$(PYTHON) tests/runtime_gate_guards.py --report build/runtime-gate-guards.json
	$(PYTHON) tests/l3_guards.py --report build/l3-gate-guards.json
	$(PYTHON) tests/dynamic_guards.py --report build/dynamic-gate-guards.json

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
	@echo "Unavailable for v0.4.0. Historical GAS bridge is not a release build path." >&2
	@exit 2

clean:
	rm -rf build
	rm -f bin/asmlab bin/asmlab-debug bin/asmlab-libc-reference bin/asmlab-runtime-smoke bin/asmlab-validation bin/*.build.json bin/BUILD_ORIGIN.txt
	rm -rf bin/tests
