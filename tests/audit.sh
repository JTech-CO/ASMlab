#!/bin/sh
# Runtime audit only: libc/CRT allowed; libm, BLAS, LAPACK, Python/JS are not.
set -eu
binary=${1:-./bin/asmlab}
[ -f "$binary" ] || { echo "Missing executable: $binary" >&2; exit 1; }
needed=$(readelf -d "$binary" | grep '(NEEDED)' || true)
printf '%s\n' "$needed"
count=$(printf '%s\n' "$needed" | grep -c '(NEEDED)' || true)
[ "$count" -eq 1 ] && printf '%s\n' "$needed" | grep -q '\[libc.so.6\]' || {
  echo 'FAIL: expected libc.so.6 as the only shared dependency' >&2; exit 1;
}
imports=$(nm -D --undefined-only "$binary")
if printf '%s\n' "$imports" | grep -Ei '[[:space:]](sin|cos|sqrt|log|pow|exp|cblas_.*|dgemm_|dgesv_|Py_.*)(@|$)'; then
  echo 'FAIL: external math/interpreter import found' >&2; exit 1
fi
stack=$(readelf -W -l "$binary" | grep GNU_STACK)
printf '%s\n' "$stack"
if printf '%s\n' "$stack" | grep -q 'RWE'; then
  echo 'FAIL: executable stack' >&2; exit 1
fi
objdump -d -Mintel "$binary" | grep -q 'mulpd' || exit 1
objdump -d -Mintel "$binary" | grep -q 'sqrtpd' || exit 1
echo 'PASS: libc only; no external math/interpreter imports; non-executable stack; SSE2 kernels present.'
