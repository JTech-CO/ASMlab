#!/bin/sh
# Native Gate runtime audit: this is Level 2, NOT an external-runtime-free ELF.
set -eu
binary=${1:-./bin/asmlab}
[ -f "$binary" ] || { echo "Missing executable: $binary" >&2; exit 1; }
header=$(LC_ALL=C readelf -hW "$binary")
printf '%s\n' "$header" | grep -q 'Class:.*ELF64' || exit 1
printf '%s\n' "$header" | grep -q 'Machine:.*X86-64' || exit 1
printf '%s\n' "$header" | grep -q 'Type:.*EXEC' || exit 1
needed=$(LC_ALL=C readelf -dW "$binary" | grep '(NEEDED)' || true)
printf '%s\n' "$needed"
count=$(printf '%s\n' "$needed" | grep -c '(NEEDED)' || true)
[ "$count" -eq 1 ] && printf '%s\n' "$needed" | grep -q '\[libc.so.6\]' || {
  echo 'FAIL: expected libc.so.6 as the only shared dependency' >&2; exit 1;
}
imports=$(LC_ALL=C nm -D --undefined-only "$binary")
printf '%s\n' "$imports"
# An explicit allowlist catches hidden helper/math/process/network imports.
names=$(printf '%s\n' "$imports" | awk '{print $NF}' | sed 's/@.*//')
for name in $names; do
  case "$name" in
    __gmon_start__|__libc_start_main|__cxa_finalize|_ITM_deregisterTMCloneTable|_ITM_registerTMCloneTable|fclose|ferror|fflush|fgetc|fgets|fopen|isatty|memcpy|memset|printf|puts|strcmp|strlen|strtod) ;;
    *) echo "FAIL: unexpected dynamic function import: $name" >&2; exit 1;;
  esac
done
# stdin is a COPY relocation/data symbol, not an undefined function on this ELF.
LC_ALL=C readelf -rW "$binary" | grep 'COPY' || true
programs=$(LC_ALL=C readelf -lW "$binary")
stack=$(printf '%s\n' "$programs" | grep GNU_STACK)
printf '%s\n' "$stack"
printf '%s\n' "$stack" | grep -q 'RWE' && { echo 'FAIL: executable stack' >&2; exit 1; }
printf '%s\n' "$programs" | grep -q 'LOAD.*RWE' && { echo 'FAIL: RWX load segment' >&2; exit 1; }
printf '%s\n' "$programs" | grep -q GNU_RELRO || { echo 'FAIL: missing RELRO' >&2; exit 1; }
LC_ALL=C readelf -dW "$binary" | grep -Eq 'BIND_NOW|FLAGS_1.*NOW' || { echo 'FAIL: missing immediate binding' >&2; exit 1; }
LC_ALL=C objdump -d -Mintel "$binary" | grep -q mulpd || exit 1
LC_ALL=C objdump -d -Mintel "$binary" | grep -q sqrtpd || exit 1
echo 'PASS: ELF64 x86-64 EXEC; libc only; approved function imports; NX stack; no RWX LOAD; RELRO/NOW; SSE2.'
echo 'Level 2 only. No claim of complete security isolation or Level 3 independence.'
