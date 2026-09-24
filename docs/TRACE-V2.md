# ASMlab Trace v2 (v0.5.0)

Implemented JSON export and internal capture layout; not a remote service protocol or an untrusted-file loader. This file describes what is actually emitted, including intentional limits.

## Export

```sh
bin/asmlab --trace-json -e 'sqrt([1,4,9,16])+2' > trace.json
bin/asmlab --mode compute --trace-json -e 'sin(pi/4)' > compute.json
# In a session: :trace json exports the current successful snapshot.
```

Successful expression records are one JSON object per line. Human-oriented colon commands are not all JSON-safe; avoid mixing `:vars`, `:help`, etc. into a machine stream. No trace import/reload is implemented. Output writing/flush can fail; check process exit status. Output failure after a successful workspace commit does not roll back that commit.

## Envelope

| Field | Meaning |
|---|---|
| schema_version, format | `2`, `asmlab.trace` |
| ok | true for a successful expression snapshot |
| isa, backend | `x86_64`, `sse2`; not guest emulation or Wasm |
| build_id | SHA256 of ordered build input names/hashes + `/profile/backend`. Matches `source_build_id` sidecar. Not an ELF digest or signed attestation |
| mode | Mode used by this snapshot, not the current next-execution setting |
| expression_id | Process-local counter of expression attempts reaching the parser path; comments/commands do not consume it |
| source | Original input line as text, escaped as JSON |
| evaluation_mxcsr | `0x1f80` reset immediately before numerical evaluation |
| final_mxcsr | State captured after evaluator return, before commit/display |
| nodes | AST nodes by numeric ID, with type, label, anchor, span, shape, children |
| events | Actual retained watched-instruction snapshots, in execution order |
| result | Same `{ok,rows,cols,data}` value object as ordinary JSON; full row-major data, precision17 |

A failed `--trace-json` expression has `schema_version`, `format`, `ok:false`, `expression_id`, `source`, `error`, `position`, and `snapshot_available:false`. Syntax/evaluation/resource errors do not export freed node pointers or partial computed arrays. `:trace json` without a successful snapshot yields `{schema_version:2,ok:false,error:...}`. Blank/comment-only inputs produce no expression record.

## Capture policy

Observe: `policy=prefix`, `capacity=8192`, `retained`, `executed_watched`, `dropped`, `dispatcher_entries`. `retained+dropped=executed_watched=dispatcher_entries`. Only the first8192 records are stored; no invented later events. This counts selected watched instructions, not all CPU instructions or cycles.

Compute: `policy=disabled-compute`, retained0, dropped0, dispatcher_entries0, `executed_watched=null`. Null explicitly means unmeasured. No old trace is relabeled as Compute. Zero frames can also occur in Observe for literals/constructors/copies that require no watched arithmetic.

## AST and source

IDs are zero-based within one expression. `children` gives source-tree edges (call arguments/matrix entries included). `span=[start,end]` is a half-open byte range in the input ASCII line. Grouping parentheses may widen the grouped node's span because no separate group node exists. Operator `anchor` remains the previous parser's error anchor. `shape` is the successfully completed node's shape. Constructor integer initialization is not falsely added as an SSE2 event.

## Instruction event

Each record exposes `sequence` (1-based), `expression_id`, `node`, `span`, `stage`, `context`, `instruction`, `lanes`, `before`, `source`, `after`, `mxcsr_before`, `mxcsr_after`.

`instruction.pc` is the actual address of the watched SSE2 instruction in the precompiled central Observe dispatcher. It is **not a unique callsite for each occurrence**: node/stage/context/sequence distinguish repeated uses. Validate addresses against the matching build, not another profile. `instruction.opcode` includes the mnemonic/operands. `destination=XMM0`, `sources=[XMM0,XMM1]` name the register views captured by the observer; they are not a complete semantic read-set declaration (for example `sqrtpd` reads its explicit XMM1 source). No branch/stack/all-memory trace is implied.

`before` and `after` are XMM0's two little-lane-order 64-bit words. `source` is XMM1 immediately before execution. Values are strings `0x` plus16 lowercase hex digits, preserving signed zero and inactive lanes without JSON integer precision loss. Lane0 occupies the low64 bits. `lanes.hardware` is1 for scalar arithmetic,2 for packed/copy/XOR instructions; `lanes.active` says how many cells this algorithm step logically uses. Both full register lanes are preserved even when one is inactive. The stored before/after MXCSR values are actual snapshots, not reconstructed exception guesses.

## Algorithm and matrix context

Stages: `none`, `elementwise`, `negate`, `transpose-copy`, `sqrt`, `sum-accumulate`, `dot-product`, `dot-accumulate`, `dot-reduce`, `trig-range-reduction`, `trig-polynomial`, `trig-reconstruct`, `log-normalize`, `log-transform`, `log-polynomial`, `log-reconstruct`, `power-by-squaring`, `linspace-sample`, `index-read`.

These are descriptive tags attached at existing execution sites, not extra invented instruction events. `context.kind` is `output-element`, `input-element`, or `matmul-output` (reserved `none` exists). `element`, `row`, `col` are zero-based diagnostic indices, unlike1-based language indexing. `row=element/cols`, `col=element%cols`. `rows/cols` specify the context shape. Matrix multiplication supplies k at multiply/accumulate steps; `-1` means no meaningful k or final reduction. Sum uses input-element context. It is not a complete effective-address/memory-provenance log, and no user heap addresses are needed for these coordinates.

## Internal layout

The first96 bytes preserve the old frame prefix so legacy textual replay and instruction checks can coexist. A record is now192 bytes.

| Byte offset | uint64 field (unless stated otherwise) |
|---:|---|
| 0,8,16,24 | opcode ID, node ID, context element, actual instruction PC |
| 32,48,64 | 16 bytes each: XMM0 before, XMM1 source, XMM0 after |
| 80,88 | MXCSR after and before, each zero-extended from32 bits |
| 96,104 | sequence, expression ID |
| 112,120 | span start,end |
| 128,136,144 | stage ID, context kind ID, k (-1 sentinel) |
| 152,160,168 | active lanes, context rows,context cols |
| 176,184 | hardware lanes, schema version2 |

Fixed record storage uses1,572,864 bytes plus one192-byte scratch record. AST source starts are in a side table; N_END uses a formerly reserved AST word. These fixed buffers, screen cells and64-source history are outside the dynamic mapping quota. Memory ownership of temporary results remains as in v0.4.0.

## Trust and tests

Build identity, raw PC/bytes, event-to-node ranges, real XMM bits, MXCSR, capacity accounting, compute disassembly, mode/snapshot lifetime, and file-free PTY interaction are tested in `tests/observable_workbench.py`. Export is trusted local diagnostic data, not a cryptographic audit log. No test count proves every possible input or safe ingestion by an external consumer. Any future viewer must escape text and treat all exported source/name text as data rather than code.
