# v0.3.0 toolchain provenance

Recorded for the local release build on 2026-09-23. These records identify the actual build tool and inputs; they are not a supply-chain security certification.

## How NASM was obtained

This build reused the toolchain ZIP attached during v0.1.1. Its ZIP and executable SHA256 were checked again. The earlier delivery obtained this **third-party prebuilt NASM executable** through a read-only public GitHub Actions artifact download from `holepunchto/nasm-runtime`. No new toolchain workflow was executed for v0.3.0. It was not an official NASM release binary and was not rebuilt from official NASM sources in this environment.

| Item | Exact value |
|---|---|
| Repository | `holepunchto/nasm-runtime` |
| Source/workflow commit | `dc64632dac89687983dd8fda6298d1d082d56ef1` |
| Workflow run | `35346088745` |
| Artifact | `linux-x64`, ID `10547595510` |
| Artifact ZIP SHA256 | `270ad7b412006b9db4d57bb280aa1f044341a1509c9e219373ef1b81fe5238d5` |
| Reported assembler | `NASM version 2.16.03 compiled on Sep 18 2026` |
| NASM executable SHA256 | `68aaba30052ccb89f01f1f00f00106ca7930d1003530474da3ef6f0f94912fa4` |

The artifact ZIP digest was compared with the digest reported by GitHub. The actual NASM executable was used with `-f elf64` to assemble ASMlab directly. This is **not** the NASM-to-GAS bridge. The toolchain artifact is not included in the ASMlab release ZIP.

Stable source records:

- https://github.com/holepunchto/nasm-runtime/actions/runs/35346088745
- https://github.com/holepunchto/nasm-runtime/blob/dc64632dac89687983dd8fda6298d1d082d56ef1/.github/workflows/prebuild.yml
- https://github.com/holepunchto/nasm-runtime/blob/dc64632dac89687983dd8fda6298d1d082d56ef1/CMakeLists.txt

The inspected CMake file installs `nasm` and `ndisasm` supplied through `find_port(nasm)`. The artifact metadata and hash do not independently establish that the binary has no undisclosed modifications. Rebuild with the distribution NASM package and rerun the gate for independent verification. Workflow artifact retention is finite; no expiring download token is embedded here.

## ASMlab build inputs

The full production application links eleven separately generated NASM objects directly with GNU ld, `-static --no-undefined -e _start`. No CRT, system archive or shared library is a production input. GCC/cc remains a linker driver only for development comparison targets. The independent smoke also uses ld; `decimal-native.so` and primitive/fault fixtures have no libc imports. The test `decimal-adapter.so` intentionally retains libc. No project C/C++ source compilation is performed.

- Release: NASM `-f elf64 -w+error -Ox`.
- Debug: NASM `-f elf64 -w+error -O0 -g -F dwarf`.
- Production link: static non-PIE, NX stack, GNU build ID, map file, own entry. RELRO/NOW dynamic-binding checks are not applicable without a dynamic linker. The separate reference retains RELRO/NOW.
- Release keeps `.symtab` for instruction/constant inspection; debug also includes DWARF.
- Default NASM warnings are errors. Optional diagnostics such as intentional cross-section relocation warnings are not all enabled.

[Release sidecar](../bin/asmlab.build.json) and [debug sidecar](../bin/asmlab-debug.build.json) record the exact command arrays, tool versions, binary/object/map SHA256 and build-input hashes. Build completion is not test completion; [native gate](../evidence/native/gate-summary.json) is separate.

The default build/test path cannot automatically fall back to GNU as. The old bridge remains historical source but is unsupported by the v0.3.0 multi-object build; `make validate-gas` explicitly fails. `make verify` checks delivered source inventories, binaries, objects and link maps; `make test` creates a new native build before testing.

## Environment and limits

Actual environment details are captured in [environment.txt](../evidence/native/environment.txt). These are local container results. The configured Ubuntu 22.04/24.04 workflow has not been remotely run by this delivery. No official build attestation, cross-toolchain byte-identical reproducibility, WSL/Pi execution, or all-input numerical proof is claimed.

[Foundation object/target provenance](../bin/runtime-foundation.build.json) records exact target membership. Selected `.o` and `.map` files are included in the verification ZIP so checks can be repeated without NASM. They can be regenerated with `make test`.
