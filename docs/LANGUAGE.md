# ASMlab 0.4.0 language reference

## Data model

Every value is a real, dense, row-major float64 matrix. A scalar is 1x1. Row vectors are 1xN and column vectors are Nx1, with positive dimensions. Each value has at most1,048,576 elements and must fit the session mapping quota (default64MiB), including old values/intermediates and staged commit copies. Empty arrays are unsupported. No separate arbitrary-precision integer type exists.

Names match `[A-Za-z_][A-Za-z_0-9]{0,30}` and are case-sensitive. `pi`, `e`, `ans`, and built-in function names are reserved. `pi` and `e` are float64 constants, not symbolic values. `ans` is initialized to zero and updated only after a successful expression.

## Grammar sketch

```text
statement  := [ identifier '=' ] expression
primary    := decimal | identifier | '(' expression ')'
            | identifier '(' arguments ')' | matrix
arguments := expression (',' expression){0,2}
matrix     := '[' row (';' row)* ']'
row        := expression (',' expression)*
prefix     := ('+' | '-') expression
postfix    := expression "'"
binary     := expression ('+'|'-'|'*'|'/'|'.*'|'./'|'^') expression
```

The implementation is a Pratt parser, not the directly left-recursive grammar above. Decimal tokens support `1`, `1.`, `.5`, `1.25e-3`, and `2E+5`. Hexadecimal floating literals, `Inf`, `NaN`, underscores in numbers, and implicit multiplication are not supported. The native `rt_decimal_from_cstr` wrapper invokes the own exact integer-rational parser after a token is scanned and copied into a bounded buffer. No `strtod` is linked into the native app. Decimal overflow is rejected; decimal underflow can round to a subnormal or zero.

Binding power from low to high: addition/subtraction 10; multiplication/division 20; unary signs 25; exponentiation 30; transpose 40. Exponentiation is right-associative. Thus `-2^2=-4`, `(-2)^2=4`, `2^-2=0.25`, and `2^3^2=512`.

An expression must consume the complete line before a `#` or `%` comment. A semicolon outside a matrix is not an assignment separator or output-suppression command. Put separate statements on separate lines. Matrix entries may be scalar expressions, but block concatenation is unsupported. `[1,2;3,4]` is valid; `[1 2;3 4]` is deliberately rejected.

## Operators

| Operator | Semantics |
|---|---|
| `+`, `-` | Same-shape elementwise operation, or scalar broadcast |
| `*` | Matrix multiplication if neither value is scalar; otherwise scalar multiplication |
| `.*` | Same-shape elementwise multiplication or scalar broadcast |
| `/` | Elementwise division by a scalar right operand only |
| `./` | Same-shape elementwise division or scalar broadcast |
| `^` | Scalar integer exponent in [-1024,1024]; 0^0=1 |
| unary `-` | Exact sign-bit flip of every element |
| postfix `'` | Real transpose, identical to transpose(A) |

No implicit expansion between a row vector and a column vector is performed. Shape mismatch raises an error.

## Functions

`sin(A)`, `cos(A)`, `sqrt(A)`, and `log(A)` apply to every element and retain the input shape. Angles are radians. `log` means natural logarithm. `transpose(A)` swaps dimensions. `sum(A)` returns one scalar containing the sum of **all** elements, not a vector of column sums. These original functions take exactly one argument. New calls below support their stated arity only.

## Dynamic functions and indexing

| Expression | Contract |
|---|---|
| `zeros(n[,m])`, `ones(n[,m])` | n×n with one argument; n×m with two |
| `eye(n[,m])` | square or rectangular diagonal ones |
| `size(A)` | row vector `[rows,cols]` |
| `size(A,1)` / `size(A,2)` | selected dimension |
| `linspace(a,b,n)` | scalar finite endpoints, positive integral n, row vector; n=1 returns b |
| `A(r,c)` | named variable only, 1-based scalar read with bounds/integer checks |

Maximum3 call arguments, with each function's arity checked before argument evaluation. Dimensions are positive integers and products are checked, never truncated or silently reshaped. Constructors are reserved identifiers. No linear indexing, slices, `end`, indexed assignment, empty arrays, or indexing a temporary call result is supported. Scalar fields returned by `size` are also float64.

`linspace` copies endpoint bits and uses the documented weighted floating formula for interior points; it need not match other libraries bitwise. Table/trace offsets remain explicitly zero-based diagnostic coordinates even though expression indexing is1-based.

Matrix products preflight `m*n*k <= 16,777,216`. There is no whole-session CPU-time quota.

## Commands

| Command | Action |
|---|---|
| `:help` | Print language and command summary |
| `:vars` | Preview up to64 entries including ans; newest user entries first |
| `:clear` | Invalidate the previous trace/AST, release all dynamic values, reset ans to0 |
| `:drop NAME` | Delete one user variable without changing ans; missing/reserved names error |
| `:memory` | Report used/peak/quota/live/maps/unmaps/user_variables; JSON mode has a `memory` record |
| `:quit`, `:exit` | End the session |
| `:trace on` | Capture subsequent expressions and show six-frame previews |
| `:trace off` | Disable retention for subsequent expressions |
| `:trace all` | Capture and display all retained frames for subsequent expressions |
| `:bits on`, `:bits off` | Toggle raw register bit presentation |
| `:step on`, `:step off` | Toggle automatic post-evaluation replay |
| `:replay` | Replay the most recent successful retained capture |

Commands operate on the current process only; workspace values are not saved across separate invocations. `-f` loads an expression script, not a serialized workspace. There is no save/load command or filesystem write operation in the language.

## CLI and output

```text
asmlab [--quiet|--json] [--all] [--bits] [--step]
       [--color|--no-color] [--memory-mib N] [-e EXPRESSION | -f FILE]
asmlab --help | --version
```

`--all` expands the printed trace limit but does not override quiet/JSON output. `--bits` controls raw-bit display. `--step` requires a real terminal to replay and does not consume batch expressions as navigation input. `--json` emits result/error JSON records, not traces. Interactive display commands can produce plain text, so do not mix them into a machine-output script.

A successful record contains `ok`, `rows`, `cols`, and row-major `data`. An error contains `ok:false`, a static `error` message, and a source-byte `position`. Exit status 0 means no reported error, 1 means at least one expression/command error, and 2 means invalid CLI usage or input-file I/O failure. Errors are written to the same output stream as results; JSON users should parse the `ok` field.

## Resource and lifetime rules

`--memory-mib N` accepts integers1..1024 before execution; default64. The quota charges page-rounded mappings, including allocator metadata and unused arena capacity. It is not totalRSS, CPU-time control or host OOM protection. The maximum elements per value is1,048,576 independently of quota. AST512, temporary Value512, recursion64, decimal token127bytes, input4095bytes and trace8192 remain bounded. Large literals can hit AST/input limits well below the array element cap; use constructors.

Successful assignment stages a new target and `ans` before replacing either. Allocation/evaluation failure preserves prior persistent state; previous temporary/trace state is invalidated by starting a new expression. Output errors after a successful commit do not undo that commit. `B=A` is a deep copy. `:clear` frees both temporary and persistent mappings; peak/cumulative counters are not reset.

Large tables preview at most16×16 with an explicit message. Quiet/JSON values are complete, not silently truncated. JSON `:memory` records do not contain `ok` because they are metadata rather than expressions. Colon display commands such as `:vars` remain human-readable; only mix documented machine-safe commands into JSON scripts.
