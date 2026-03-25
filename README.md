# Swab

A Luau bytecode decompiler, written entirely in Luau. You can feed it raw bytes, a string, or a live Script Instance and it'll hand you readable source back.

## Features

- Bytecode versions 3 through 6
- Full control flow recovery including if/elseif/else chains, while, repeat-until, numeric for, and generic for
- Expression folding that cleans up temporary registers into natural-looking code
- Accepts a `buffer`, a raw `string`, or a Roblox `Script` Instance directly
- Timeout protection so pathological bytecode can't hang you

## Usage

```luau
local Swab = require(path.to.Swab)
```

### From a bytecode buffer

```luau
local bytecode = buffer.fromstring(rawBytecodeString)
local source = Swab.Decompile(bytecode)
print(source)
```

### With an encode key

```luau
local source = Swab.Decompile(bytecode, 203)
```

### From a Script Instance

```luau
local source = Swab.Decompile(workspace.SomeScript)
```

### Using the global

When `getgenv` is available, Swab registers a global `decompile`:

```luau
print(decompile(workspace.SomeScript))
```

## Project Structure

```
init.luau              Entry point and public API
Opcodes.luau           Opcode definitions, formats, and aux flags
ControlFlow.luau       Control flow graph recovery (loops, branches)
ExpressionFolding.luau Dead code elimination, copy propagation, inlining
Formatter.luau         IR to Luau source emitter
Deserialiser/
  Reader.luau          Binary reader (LEB128, fixed-width integers, floats)
  Constant.luau        Constant type parsing (nil, bool, number, string, import, table, closure, vector)
  Instruction.luau     Instruction decoding and encode-key deobfuscation
  Function.luau        Function prototype fields (stack, params, upvalues, debug info)
  init.luau            Top-level deserialisation orchestration
Lifter/
  BlockDiscovery.luau  Basic block boundary detection from jump targets
  Instruction.luau     Bytecode to IR statement lifting (82 opcodes)
  init.luau            Per-function and per-chunk lifting entry points
```

---

## How It Works

Swab turns a flat stream of bytecode back into structured Luau source. The pipeline has five stages, each feeding the next:

```
Bytecode (binary)
  -> Deserialiser    Parse binary format, decode instructions
  -> Lifter          Convert opcodes into IR statements, discover basic blocks
  -> ControlFlow     Recover loops, branches, if-else chains
  -> ExpressionFolding   Simplify temporaries, inline single-use locals
  -> Formatter       Emit readable Luau source with recovered names
```

### Stage 1: Deserialisation

The deserialiser reads the raw bytecode buffer and produces a structured representation: a version number, a shared string table, an array of function prototypes, and a main-function index.

**Binary reader.** All integer sizes in Luau bytecode use either fixed-width reads (U8, U16, U32, F32, F64) or LEB128 variable-length encoding. LEB128 reads 7 bits per byte with a continuation bit in the MSB, so small values like string lengths and constant counts fit in a single byte. That saves roughly half the space compared to fixed U32s.

**String table.** Strings are stored once in a global table and referenced by index everywhere else (constants, debug info, import names). This deduplication is why you'll see `StringTable[K]` lookups throughout the code rather than inline string values.

**Constants.** Each function carries its own constant pool. There are 8 constant types:

| Tag | Type | What it stores |
|-----|------|----------------|
| 0 | Nil | Nothing beyond the tag byte |
| 1 | Boolean | A single U8 (0 = false) |
| 2 | Number | 8-byte double-precision float |
| 3 | String | LEB128 index into the string table |
| 4 | Import | Packed U32 with 1-3 levels of global access (e.g. `game.Workspace`) |
| 5 | Table | Pre-allocated table shape (array of key indices) |
| 6 | Closure | LEB128 function prototype index |
| 7 | Vector | Four F32 components (X, Y, Z, W) |

**Instruction decoding.** Each instruction is a 32-bit word in one of three formats:

| Format | Layout | Typical use |
|--------|--------|-------------|
| BC | `[Op:8][A:8][B:8][C:8]` | Arithmetic, table ops, calls |
| AD | `[Op:8][A:8][D:16 signed]` | Jumps, loads, loop control |
| E | `[Op:8][E:24 signed]` | Extended jumps, coverage |

The opcode byte is obfuscated with a multiplicative encode key: `ActualOp = (RawOp * EncodeKey) % 256`. The default key is 203. Twenty-three opcodes also carry an auxiliary word, which is a follow-up U32 with extra data for complex operations like `GETIMPORT`, `NAMECALL`, and `NEWTABLE`.

**Function prototypes.** Each function stores its max stack size, parameter count, upvalue count, vararg flag, the decoded instruction array, its constant pool, indices of child closures, and optional debug info (line mappings, local variable names and scopes, upvalue names). Line info uses a logarithmic interval compression scheme where lines are grouped every $2^{\text{LinegapLog2}}$ instructions with per-instruction signed-byte offsets and periodic absolute anchors.

**Bytecode versions 3-6** are supported. Version 4 and above added type annotation data, which the deserialiser just skips since it's not needed for decompilation. Version 0 means the compiler hit an error, so it gets rejected.

### Stage 2: Lifting

The lifter takes the flat instruction arrays from each function prototype and turns them into an intermediate representation, which is blocks of IR statements connected by edges.

**Block discovery.** Before lifting any instructions, the lifter scans the entire instruction stream to find basic block boundaries. Every jump target and every instruction after a jump or return marks the start of a new block. The result is a sorted list of PC ranges, where each range is one basic block that runs straight through with no internal branches.

Block start triggers include:
- PC 1 (always the entry block)
- Jump destinations (conditional and unconditional)
- Fallthrough after any branch, return, or `LOADB` with skip
- For-loop prep and loop-back targets

**IR production.** Each instruction maps to one or more IR nodes. The IR is expression-based, with expression tags (Nil, Boolean, Number, String, Binary, Unary, Index, Call, MethodCall, Closure, Table, VarArg, Select) and statement tags (Assign, Return, If, While, NumericFor, GenericFor, SetList, Close).

Some notable patterns:

- **Arithmetic** (ADD, SUB, MUL, etc.) becomes `Binary(Left, Right, Op)`. The `*K` variants substitute a constant for the right operand.
- **Table access** uses three forms: register-indexed (`GETTABLE`), constant-key (`GETTABLEKS`, which becomes dot notation), and numeric-indexed (`GETTABLEN`, adjusted to 1-based).
- **Method calls** span two instructions: `NAMECALL` sets up the self and method name, then `CALL` executes it. The lifter merges these into a single `MethodCall` node.
- **Imports** pack up to three levels of global access into one U32 aux word. `GETIMPORT` decodes this by extracting 10-bit chunks: `Global(K0)`, then optionally `Index(_, K1)`, then optionally `Index(_, K2)`.
- **Loop preps** (`FORNPREP`, `FORGPREP`) emit initialiser statements and jump ahead to the loop test. The loop-back instructions (`FORNLOOP`, `FORGLOOP`) emit the iteration test and conditional back-edge.

Each block ends up with a list of IR statements and a set of edges pointing to successor blocks by index.

### Stage 3: Control Flow Recovery

This is where flat blocks become structured code. The control flow pass walks the block graph and recovers loops, if-else chains, and break/continue semantics.

**Loop detection.** Any edge pointing to a block index less than or equal to the current block is a back-edge, signalling a loop. The loop header is the target block, and the loop body extends from the header to the farthest block that jumps back to it.

Four loop types are recovered:

- **Numeric for**: the header block ends with `NumForNext`. The preceding `NumForInit` provides start, limit, and step. The body is everything between header+1 and the loop end.
- **Generic for**: same pattern with `GenericForInit`/`GenericForNext`. Iterator variables are extracted and formatted as `for k, v in iterator do`.
- **While**: the header starts with an `If` condition. If the true branch enters the loop body and the false branch exits, it's `while condition do`. If the branches are flipped, the condition gets negated.
- **Repeat-until**: the condition shows up at the end of the loop body instead of the top. The last block tests a condition and either loops back or falls through.

**If-else recovery.** Non-loop conditional blocks produce if-then-else structures. The pass checks for single-exit guard patterns (early return, break, continue) and collapses them. Elseif chains are built when an else block contains nothing but another if.

**Visited tracking.** A shared `GlobalVisited` set prevents the pass from re-entering blocks it has already structured. This is essential for avoiding infinite loops on bytecode with complex or adversarial control flow.

### Stage 4: Expression Folding

The structured IR at this point is correct but verbose. The compiler uses temporary registers pretty liberally and lifting preserves them all. Expression folding cleans this up through several passes applied repeatedly until nothing changes (fixed-point iteration):

**Dead code elimination.** If a local is assigned an expression with no side effects and is never read, the assignment is removed entirely.

**Copy propagation.** `local a = b` where `b` is another local: all subsequent uses of `a` get replaced with `b`, and the assignment is deleted, provided neither is reassigned in between.

**Single-use inlining.** If a local is assigned once and used exactly once, the right-hand side is substituted directly into the use site. `local t = foo(); bar(t)` becomes `bar(foo())`. Side-effect analysis makes sure this only happens when it's safe, so calls are never reordered past other calls.

**For-in iterator inlining.** The compiler often stores iterator components in temporaries before a generic for loop: `local v1, v2, v3 = pairs(t); for k, v in v1, v2, v3 do`. This pass folds them back into `for k, v in pairs(t) do`.

**Table constructor folding.** Sequential `t.key = value` assignments immediately after `local t = {}` are folded into the constructor: `local t = { key = value, ... }`. Bulk `SETLIST` assignments (array initialisers) fold in the same way.

**Empty if elimination.** If both branches of an if-statement end up empty after other passes remove their contents, the entire if is dropped. If only one branch is empty, the condition is flipped and the non-empty branch becomes the then-block.

### Stage 5: Formatting

The formatter walks the final structured IR and emits Luau source text.

**Name recovery.** If the bytecode was compiled with debug info, local variable names, upvalue names, and function names are recovered directly. Without debug info, the formatter falls back to generated names: `p0, p1, ...` for parameters, `v0, v1, ...` for locals, `u0, u1, ...` for upvalues.

**Operator precedence.** Binary expressions are parenthesised only when necessary, following Luau's precedence table (lowest to highest: `or`, `and`, comparisons, `..`, `+/-`, `*/ // %`, unary, `^`). Right-associative operators (`..` and `^`) handle grouping correctly.

**Number formatting.** Special values get idiomatic representations: NaN becomes `0/0`, infinity becomes `math.huge`. Integers below $2^{53}$ use `%g` formatting. Floats search for the shortest decimal representation (1-17 digits) that round-trips exactly.

**String escaping.** Control characters map to named escapes (`\n`, `\t`, `\0`, etc.) and everything else outside printable ASCII uses `\DDD` decimal byte escapes.

**Table constructors.** String keys that are valid identifiers use short syntax (`{key = value}`), everything else uses bracket syntax (`{[key] = value}`), and sequential numeric entries use positional syntax (`{value1, value2}`).

**Indentation.** Four spaces per nesting level. The formatter tracks depth through block entries and exits.

**Timeout.** The pre-scan phase, which resolves function names and upvalue names across the closure hierarchy, runs under a 10-second deadline. The main formatting pass gets 15 seconds. If either one expires, you get partial output back instead of hanging forever.

## License

[MIT](LICENSE)
