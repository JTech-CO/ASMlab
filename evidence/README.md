# Evidence index - ASMlab v0.3.0

`release-summary.json`, `native/`, `runtime/`, `l3/` and the root build/guard logs are **current v0.3.0 measurements**.

- Native gate: 30,074 assertions, zero failures.
- Runtime foundation/reference gate: 41,249 assertions, zero failures.
- L3 exact-decimal/integration gate: 106,510 assertions, zero failures; empty-root tests not skipped.
- Release total: 177,833 assertions. Repeated corpus/profile/ABI assertions are included; not that many unique expressions.
- Guards: 6 native + 9 runtime + 9 L3 = 24, separately counted.

`baseline-0.1.0/`, `baseline-0.1.1/` and `baseline-v0.2.0/` contain historical records, not proof of current execution. The source-comparison report in baseline-v0.2.0 compares the original archive with this release. Historical paths/binary hashes refer to historical packages and must not be used to validate current files.

The packaged bin/*.build.json describes current native output. Selected build/**/*.o and *.map files are included for verification. Rebuilding creates new build metadata; it does not retroactively alter this preserved evidence snapshot.

Remote GitHub Actions and separate Windows/WSL/Pi hardware were not run. No timing/performance superiority or all-input correctness claim.
