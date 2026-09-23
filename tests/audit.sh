#!/bin/sh
# L3-Core ELF audit. Link-input manifests are checked separately before this.
set -eu
binary=${1:-./bin/asmlab}
if [ "${2:-native}" = reference ]; then
  exec sh "$(dirname "$0")/audit_reference.sh" "$binary" reference
fi
header=$(LC_ALL=C readelf -hW "$binary")
printf '%s\n' "$header" | grep -q 'Class:.*ELF64'
printf '%s\n' "$header" | grep -q 'Machine:.*X86-64'
printf '%s\n' "$header" | grep -q 'Type:.*EXEC'
programs=$(LC_ALL=C readelf -lW "$binary")
dynamic=$(LC_ALL=C readelf -dW "$binary")
printf '%s\n' "$programs"
! printf '%s\n' "$programs" | grep -q 'INTERP'
! printf '%s\n' "$dynamic" | grep -Eq '\(NEEDED\)|\(SONAME\)'
! printf '%s\n' "$programs" | grep -Eq 'GNU_STACK.*RWE|LOAD.*RWE'
printf '%s\n' "$programs" | grep -q 'GNU_STACK.*RW'
[ -z "$(LC_ALL=C nm --undefined-only "$binary")" ]
symbols=$(LC_ALL=C nm "$binary")
printf '%s\n' "$symbols" | grep -q ' T _start$'
printf '%s\n' "$symbols" | grep -q ' T rt_format_f64$'
printf '%s\n' "$symbols" | grep -q ' T rt_parse_f64$'
! printf '%s\n' "$symbols" | grep -Eq '(__libc_start_main|__errno_location|_IO_|\bstrtod$|\bprintf$|\bfopen$|\bmalloc$)'
LC_ALL=C objdump -d -Mintel "$binary" | grep -q mulpd
LC_ALL=C objdump -d -Mintel "$binary" | grep -q sqrtpd
echo 'PASS: L3-Core ELF64 x86-64 EXEC; own _start; no interpreter/NEEDED/undefined symbols; NX stack; no RWX LOAD; own decimal; SSE2.'
echo 'No dynamic linker means RELRO/NOW checks are inapplicable, not a general security certification. Non-PIE.'
