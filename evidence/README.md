# Verification evidence

- `release-summary.json`: current v0.2.0 full gate, 71,319 assertions.
- `native/`: current default release/debug regression, Native Gate, baseline comparison and original guard set.
- `runtime/`: current runtime independent tests, module/dependency/differential checks, reference regression and runtime guard set.
- `build-test.log`, `guard-tests.log`: current local commands and stdout/stderr.
- `baseline-0.1.1/`: preserved historical v0.1.1 Native Gate evidence, not current execution.
- `baseline-0.1.0/`: preserved historical GAS-bridge evidence, not a current native build.

Reports are finite tests and provenance records, not formal proof, signatures or remote CI attestations. Reproduce current results with `make test` and `make test-guards`.
