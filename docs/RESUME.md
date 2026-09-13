# RESUME — starting point for the next session

Written at the end of a long session on the bytecode backend's FFI surface,
then corrected and extended by the three sessions that followed it - the unary
operators, construct coverage, and descending FOR.
Read this first; the details live in `docs/bytecode-gaps.md`.

    HEAD            find it with:  git log --oneline -1
    commits         426
    fixtures        92 in tests/bc/
    foreign natives 25 in vm/obc_vm.adb
    state           all suites green, zero warnings, tree clean

The header names no commit hash on purpose: `HEAD` and `commits` describe the
same commit, this file cannot name its own, and a stale hash is worse than a
command. Verify with `git rev-list --count HEAD` and `ls tests/bc/*.ob2 | wc -l`.

## 1. Where things stand

**All seven suites pass** — run them before touching anything, to confirm the
starting point is what this file claims:

    export AEGIR_ROOT=/home/rroland/src/aegir
    export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share
    export XDG_RUNTIME_DIR=/tmp/alrrt TMPDIR=/tmp
    timeout 900  tests/run_bc.sh
    timeout 600  tests/run_vm.sh
    timeout 3000 tests/run_stress.sh
    timeout 1800 tests/run_m1.sh          # the guest build; catches Aegir-side breaks
    timeout 300  tests/bytecode_gaps.sh   # the executable half of the checklist
    timeout 300  tests/coverage.sh        # every lexer token kind is exercised
    timeout 900  tests/differential.sh    # both backends, three-way vs the golden

`make build` / `make vm-host` / `make tools-host` / `make vm-aegir`, all with
`AEGIR_ROOT=...`, build clean with zero warnings.

### 20 FFI procedures work, each probe-verified

    Convert.ToInt / ToReal / FromInt
    Files.Delete / Rename
    Env.Get / Set
    Args.Get
    XYplane.Open / Clear / Dot / IsDot / Key
    In.Open / String / Name / Char / Int / LongInt / Real

Verified by **effect** where possible (a file deleted, an env var round-tripped,
a plane cell set then read), and by output where not. `tests/bytecode_gaps.sh`
asserts the working set and **fails when a gap is fixed**, so an entry cannot
outlive its gap.

## 2. What changed this session

- **The default is refusal.** An imported-module call with no bytecode emission
  now refuses instead of building Ada text that bytecode discards. Before this,
  `Math.cos (0.0)` compiled, ran, and printed `0.000`; `Strings.Length ("abcd")`
  printed `16`. Refusal is the default and the implemented set is the allowlist
  — the previous shape enumerated what was *missing* and went stale silently,
  which is how those two got through.
- **The expression path exists.** `IsDot`/`Key` were the first primitives to
  *return* a value; every earlier helper wrote through an address. The imported
  *function* call had no bytecode branch at all.
- **`VM_Platform` gained** `Get_Env`/`Set_Env`, `Arg_Get`, `Delete_File`,
  `Rename_File`, `Get_Line`. `vm_main` now forwards arguments after the image as
  the interpreted program's own.
- **`docs/bytecode-gaps.md` is the checklist**, and its section A is generated
  from the compiler's refusals rather than maintained by hand:

      grep -o '"bytecode backend: [^"]*"' compiler/o2c_compiler.adb | sort -u

### ...and the session after that one: the unary operators

- **`not`/`~` and unary `-` emitted no opcode.** They compiled, ran, and stored
  the operand unchanged — `x := -y` printed the value of `y`, `if not f` took
  the true branch for a true `f`. Silent wrong images, and invisible to section
  A because they never *refuse*. Both now emit (`Neg`/`Rneg` for a sign,
  `b = 0` for `not`), `tests/bc/unops.ob2` locks them by value, and
  `bytecode_gaps.sh` asserts them — see §3a.
- **The `SET or` entry this file used to carry was wrong**, and the way it was
  wrong is the useful part: see §3a and `docs/bytecode-gaps.md` section C.

## 3. Next tasks, in order

### 3a. DONE — but not the task this section named. Read the correction.

**The entry this section used to carry was WRONG, and the wrongness is the
finding.** It said `or` on a SET is "accepted by the Ada backend and rejected by
the bytecode backend". It is accepted by NEITHER. The operand-type check at
`o2c_compiler.adb:4443` runs **before** the `Bytecode_Mode` test, so SET operands
raise the same `O2c_Error` in either mode — a front-end limit, not a backend
divergence, and therefore something a differential could never have found: both
backends agree.

Measured, not inferred — by calling the Ada-text entry point
`O2c_Compiler.Compile` (the M1 door, which never sets `Bytecode_Requested`):

    c := a or b;          Ada mode: O2c_Error   bytecode: O2c_Error
    c := a + b;           Ada mode: compiles    bytecode: compiles, runs
    f := (1=1) or (2=3);  Ada mode: compiles    bytecode: refuses, loudly

The site's two mode branches had been crossed: `" or "` is emitted on the
BOOLEAN branch, which bytecode refuses two lines earlier, while the SET branch
is the one that raises.

**What that construct was actually hiding.** `not` / `~` and unary `-` emitted
**no opcode at all** — neither implemented nor refused. They compiled, ran, and
stored the operand unchanged:

    x := -y     printed  7   for y = 7      (not -7)
    g := not f  printed  1   for f = true   (not 0)

Silent wrong images — the exact failure the "default is refusal" work exists to
eliminate — and invisible to the checklist, which is generated from the
compiler's *refusals* and so cannot see a construct that never refuses.

**Both fixed.** `Neg`/`Rneg` are now emitted for a unary sign (`LONGINT` still
refuses, consistently with its other arithmetic), and `not b` is emitted as
`b = 0`, which needs no new opcode because a BOOLEAN is 0/1 in this VM.
`tests/bc/unops.ob2` locks both by value and `bytecode_gaps.sh` asserts them.
The change is depth-neutral by construction, so the `FOR` header's `BY`
discard — and every other stack site — is unaffected.

**What is left at this site** is the loud half, now recorded in
`bytecode_gaps.sh` as `blocked`: `&` and `or` on BOOLEAN values. Both need
AND/OR opcodes, and the spec has none — `docs/obc-image.md` puts BOOLEAN at
0x66/0x67/0x68 (BEQ/BNE/BTEST) with 0x72–0x7F reserved.

### 3b. DONE — `tests/coverage.sh`, and it is not a grep

The language's surface is the lexer's token kinds
(`compiler/o2c_lexer.ads`, `Tok_*`). A construct with no fixture cannot be
checked by a differential, because a construct no test uses cannot disagree.

The check is now standing, and it differs from what this section originally
prescribed in the two places that mattered. The original was: *grep the corpus
for each `Tok_*` spelling and require a hit.* It reported "exactly two token
kinds with no fixture anywhere — `>=` and `or`", and **both halves of that were
wrong: the real number is seven, and a hit says nothing about whether the
construct works.**

- **The corpus must be `tests/bc` only.** The grep also walked `samples` and
  `tests/vm`. `~`, `loop`, `exit` and `by` all appear in `samples/hello.ob2`,
  which no test and no Makefile target compiles, and `tests/vm/*.asm` is
  assembly whose comments are full of keyword-shaped words. So four constructs
  read as "covered" while three of them were silently wrong in bytecode.
- **The tokens must come from the lexer, not a pattern.** `tools/o2c_tokscan`
  lexes the corpus and reports the kinds that occur, so a token inside a comment
  cannot count and `>=` cannot be confused with `>` followed by `=`.
- **Every unexercised kind must be exempt or a RECORDED known gap** with a probe
  pinning its current behaviour, so the list cannot decay: a gap that is
  silently fixed fails the check.

What the seven were, and what became of them:

    TOK_GE  `>=`      works - no fixture.  Now tests/bc/relops.ob2 (value-locked,
                      and written so `>=`/`>` differ on a = b, which a single
                      mis-emitted opcode could not survive).
    TOK_BY  `by`      works - no fixture.  Now tests/bc/forstep.ob2.  Worth a
                      fixture because the step is used from its TEXT, not the
                      stack, so a stray slot is invisible in a golden.
    TOK_LOOP/TOK_EXIT  SILENTLY WRONG - the body ran once, EXIT did nothing, so
                      an infinite loop terminated.  FIXED (3e).
    TOK_AMP `&`       refuses loudly.  Known gap, pinned in coverage.sh.
    TOK_OR  `or`      refuses loudly.  Known gap, pinned in coverage.sh.
    TOK_AND `AND`     reserved by the lexer and never parsed - a grammar hole,
                      not a missing operator.  Known gap, pinned.
    TOK_ERROR         not a construct - exempt.

Descending FOR was the one gap coverage could NOT see, and it is worth keeping
as the demonstration of *why* the caveat at the end of this section matters:
its tokens (`FOR`, `TO`, `BY`, `MINUS`) are all exercised by ascending loops,
so the token check passed while the construct was broken. **It is fixed now**
(3f) and held by `tests/bc/fordown.ob2` like any other construct — but the
lesson it taught stands, and it has no live example any more:

    a construct that is fully covered AND wrong is invisible to coverage.

`for i := 3 to 1` summing to 0 was never the bug — that is correct Oberon-2,
since a descent needs an explicit negative step, and it is what the first
reading mistook for the gap. The bug was that `by -1` could not be written at
all, so no descent was expressible, and only a *descent* can assert that.

**The lesson: coverage says where to look, not what is there.** It found the
constructs no test reached; it could not tell that three of them were wrong, and
a construct that is wrong while fully covered is invisible to it by
construction. That is 3c's job.

### 3c. DONE — `tests/differential.sh`, and it is a HOST sweep

The premise this section carried was wrong, and the wrongness is the useful part:
it said "the Ada side needs the **guest** toolchain, so this runs in the guest".
It does not. The Ada side's output is Ada source, and that source's **entire**
runtime dependency across the corpus is `Aegir_User.Console` — three
subprograms — because the builtin modules are emitted as pure Ada (Convert.ToInt
converts a string by hand) and `Out` is inlined into Console calls. Measured
with `grep -ho 'Aegir_User\.[A-Za-z_.]*'` over the emitted units of every
fixture. So `tests/ada_host/` supplies those three on the host, and the whole
differential — 59 fixtures, both backends, three-way compare — runs in **14
seconds** with no QEMU, no cross-compile and no initrd.

That reframing is the point. A check that needs a guest boot per fixture would
never have run often enough to be worth having; at 14s this is a suite.

**THE THREE-WAY COMPARISON is the design**, and it is why a two-way diff of the
backends would be worse. There are three numbers, not two:

    golden   the expectation, checked in
    ada      what the Ada backend's OWN output does when run
    vm       what the bytecode image does when run

    ada == golden, vm != golden   ->  THE VM IS WRONG       (a bytecode bug)
    vm  == golden, ada != golden  ->  THE GOLDEN IS SUSPECT
    all three differ              ->  look; possibly a front-end bug
    all three agree               ->  the golden is CORROBORATED

And that is exactly what the section asked for: it distinguishes "the VM is
wrong" from "both differ from the golden" by construction, rather than by
reading a two-way diff.

**What it found, on its first run.** Zero VM bugs and zero wrong goldens — the
good news, and now evidence rather than hope:

    corroborated by both backends : 41
    VM wrong                      :  0
    golden suspect                :  1   (withguard - see below)
    ada refused (its own gap)     : 10   (Threads; procedure values)
    ada emits Ada that won't build:  7   (see below)

So every disagreement in the corpus is the ADA side failing, not the VM. Seven
fixtures make the Ada backend emit Ada that does not compile — a name colliding
with a declaration (`gcscalar`, `recmix`, `recreal`), a component used before
its record ends (`nested`), a type name that does not denote a type (`list`,
`newloop`), and one `expected type Boolean` (`realarr`). Those are Ada-backend
bugs, and the Ada backend is being retired, so they are **recorded** in the
script rather than fixed.

**It also caught a regression of its own making** — which is the strongest
argument for having it. The `by -1` fix (3f) started emitting the step's source
text into the Ada, and Ada rejects `i := i + -(1)` ("parentheses required for
unary minus"). Nothing else in the repo writes a descending `by`, so nothing
else could have noticed; the differential found it on the run that introduced it.

**`withguard` is the one golden suspect, and it resolved to the Ada side being
wrong.** The fixture guards a `P` (base) as its extension with a body that never
mentions the guarded variable. The VM and the golden print `425` — the body is
**skipped** — and the Ada side prints `4295`, running it. Oberon's `WITH` is a
*conditional* region: the body runs only if the guard holds, and the trap
belongs to the `v(T)` designator form (which is separate, and already tested by
the VM's `guardbad`). So the VM and the golden are right and the Ada side does
not implement the guard at all. The classification flagged exactly the right
fixture, and the investigation settled it.

**It is a GATE, not a report.** Every non-corroborated outcome must be a
RECORDED, reasoned Ada-side limit: an unlisted disagreement FAILS (so a new one
cannot appear quietly), and an entry that stops applying FAILS too (so the list
cannot outlive its cause). Verified by tampering — mis-recording one entry's code
and adding a bogus entry for a corroborated fixture produced exactly the two
expected failures, with nothing else.

Coverage finds what no test reaches; the differential finds what a test reaches
but the VM gets wrong. **Neither alone is enough** — that is the whole finding,
and it is argued at length in `docs/bytecode-gaps.md`.

### 3d. RE-SIZED — measured, and the sizing above is WRONG

The section below says this item was "declared **sized** rather than open".  That
sizing is disproved, and this note is its correction - the deliverable of the
attempt, not a fix.

**What the item actually requires.**  A user program must be able to CALL
`Files.Old`/`New`/`Read`/`Write`/`Close` - procedures of an imported module.  That
is a **cross-module call**, and bytecode has never had one:

- before this attempt, a call into an imported module was refused
  (`X.y is not yet supported`), which is why nothing in the corpus - 48 fixtures,
  all main modules with local procedures - ever exercised it;
- making the callee's code exist in the image (scoping the module) is necessary
  but NOT sufficient.  The call is emitted, its id/target/arity are all correct
  (3t), the argument provably ARRIVES (u5), and the value comes back WRONG (u6) -
  while every equivalent LOCAL shape works (e1/e2/e3: field offsets 0 and 64, via
  parameter, via return, `new`, `len`, `ARRAY OF CHAR` indexing).

So the gap is **how a value crosses a module boundary**.  It is not
Files-specific: it would bite any imported call.

**Sizing, honestly.**  This is the same class as the record/type coverage that
`samples/hello.ob2` refuses at - 530 lines, 18 imports, refused at its `type`
block - i.e. **milestone** work, not wiring.  The mistake was treating it as
wiring and working it probe by probe; the correct output of that discovery was
this note, on the first day.

**Reproductions, kept here because no harness can hold them.**
`bytecode_gaps.sh` records constructs that REFUSE; this one compiles and answers
wrongly, so nothing machine-checked can pin it.  Three small main modules:

    (* u5: is the argument even received?  Old on a missing path stores -1,
       New stores 0.  SAME Length for both => the argument is ignored. *)
    f1 := Files.Old("/tmp/o2c_u5_absent.txt");
    f2 := Files.New("/tmp/o2c_u5_created.txt");
    n1 := Files.Length(f1); n2 := Files.Length(f2);   (* measured: different -> arrives *)

    (* u6: the values themselves.  Correct is -1 and 0. *)
    (* measured: n1 NONNEGATIVE, n2 NONZERO - both wrong, and they differ *)

    (* e3: the field is NOT at offset 0.  FileDesc = record name: A64;
       size: longint end, so size is at 64 - and every earlier probe put its
       field first, which is why this case was never covered.  Measured: ok. *)

**State now.**  `Files` is NOT scoped (`Compiled_Builtin (... Scoped => False)`
with the reason in the source), so a user call refuses LOUDLY rather than
answering wrongly - the hazard that scoping otherwise creates, as the Math entry
above describes.  Everything the attempt fixed stays landed and gated: the
body-frame balance, the `R.Typ` clobber, the argument double-push, `LEN`, and
`ARRAY OF CHAR` indexing - five real bytecode gaps, with `lenopen` as a new
fixture and 48 fixtures corroborated by both backends.


### 3d. `Files.Old` / `Read` / `Write` / `Close` / `New`

Deferred, and it was declared **sized** rather than open. Measuring it corrected
the sizing in two places, and the correction is the useful part — the original
claim is kept below the marker so the error is not repeated.

**What the measurement changed.** The claim was "every statement in the module is
already supported… the only non-bytecode parts are the FFI primitives". Two
*data* gaps sat in front of the FFI wiring, and both are now fixed (3g):

- **`p^.field[i]` — an array field reached through a pointer — was refused**, and
  not only for `Files`: any program doing it failed. The message blamed the
  array's length; the length was fine and the address was wrong.
- **A `LONGINT` record field was refused**, because the allowed-type list omitted
  it. `Files.FileDesc` is exactly `name: A64; size: longint`, so the module could
  not even have its own types laid out.

So the real sequence for 3d is: (1) those two — **done, see 3g**; (2) the ~12
intrinsics (`FStat`/`FRead`/`FWrite`/`FClose`/`FDel`/`FRename`, `EnvGet`/`EnvSet`,
`ArgGet`, `PlaneOpen`/`PlaneClear`/`PlaneDot`, `InReset`/`InString`/`InName`)
as bytecode native calls — several counterpart natives already exist from the FFI
work; (3) the ordering change below.

**The next wall was** `Files.Open`'s `r.f := f` — an assignment to a **pointer
field** — which said "assigning through a pointer designator is not yet
supported". **That is now fixed too (3h)**, and the measurement has moved on:
`Files` gets past its types and its statements and stops at **LONGINT**, which is
where step 2 of the sequence starts (the ~12 intrinsics, several of which compute
in LONGINT).

And one thing the sizing missed entirely: **no fixture consumes any of it yet.**
The three data gaps above were worth fixing on their own merits (all three are
user-visible), but the rest of 3d is capability with no caller.

The original sizing, kept for the record:

- The types are ordinary (`File` = pointer to a record; `Rider` = a record).
- **Every statement in the module is already supported** by the bytecode
  backend — record and pointer assignment, field access, comparison, array
  indexing, `new`. The only non-bytecode parts are the FFI primitives.
- So the module needs **compiling, not reimplementing**: its primitive calls
  become native calls, exactly as `Convert.ToInt`'s call site does.
- **The obstacle is ordering, not capability.** `Compile_Multi` calls
  `O2c_BC.Begin_Mode` *after* the builtin and library compiles, so builtins are
  always parsed in Ada mode. Moving it earlier would put **every** builtin into
  bytecode mode, and Math/Reals do REAL arithmetic the backend still refuses in
  places. **Scope it to the modules that can actually compile** — Files, Env,
  Args, XYplane, In — leaving Strings, Texts, Math, MathL, Input, Term on the
  Ada path, no worse off than today.

### 3e. DONE — `LOOP` / `EXIT`

The third member of the silent wrong-image class, and the worst: found by 3b's
coverage check, not by a fixture. `Parse_Loop` and `Parse_Exit` appended only
Ada text, so in bytecode mode `LOOP` emitted no back-jump and `EXIT` emitted
nothing. **An infinite loop terminated**: `loop i := i + 1 end` printed 1.

Fixed by giving bytecode what the Ada text gets for free: a top label and a
back-jump in `Parse_Loop`, and an exit label — recorded per depth in
`Bc_Loop_Exit` alongside the text-label array `Loop_Lbl`, both bounded by the
same checked limit — that `Parse_Exit` jumps to. Leaving a nested `WHILE`/`FOR`
needs no unwinding: frames are frame slots and every loop is jumps.

`tests/bc/loopexit.ob2` is written for that last point. Its fourth case is an
`EXIT` from inside a nested `WHILE`, and if the exit target were the `WHILE`'s
the program would not print a wrong number — **it would never terminate**,
which is why the fixtures run under a timeout. Coverage cannot see a wrong exit
target; only executing it can.

For the next silent-image hunt: coverage found this only because `loop`/`exit`
had NO fixture. A construct that is exercised AND wrong is invisible to
coverage — descending FOR was exactly that case (3f), and it is 3c's job to
catch the next one.

### 3f. DONE — descending `FOR` (`by -1`), and two reasons it was unreachable

A descending loop could not be written at all, and the diagnosis in the previous
version of 3b had the wrong culprit: it indicted `for i := 3 to 1`, which
running its body zero times is *correct* Oberon-2 — a descent needs an explicit
negative step. The bug was that the step could not be given one.

**Two walls, one behind the other**, which is why it looked like a semantics
question rather than a parse question:

- `Parse_For` validated the step by scanning its Ada **image** for digits. Unary
  minus wraps the literal as `-(1)`, so `by -1` failed on the `(` — and the scan
  even allowed a leading `-` on purpose, so it was a bug in the check, not a
  missing feature. It also refused `by SOME_CONST`, whose text is a name.
- Behind it, `O2c_BC.For_Enter`/`For_Next` wrote the step with
  `Put_U32 (U32 (Step) and 16#FFFF_FFFF#)`. That mask never runs: a NUMERIC
  conversion of a negative `Integer` to `U32` raises `CONSTRAINT_ERROR` first.
  So nothing could have encoded a descent even once the parse succeeded — the
  failure surfaced as an exception inside the emitter, not as a diagnostic.

Fixed by taking the step from the parsed expression's **value**
(`B.Folds`/`B.Val`, which is what "integer constant" always meant) and encoding
it as a two's-complement bit pattern through an unchecked conversion from
`Interfaces.Integer_32` — the form the opcode's `i32 step` and the VM's decode
already assume. A zero step is now refused loudly, since it can never advance
the loop variable; a variable step is still refused, on the same rule as before.

The VM needed no change: `Op_For_Enter` derives the direction from from-vs-to
and steps by `abs (Step)`, so it supported descending all along.

`tests/bc/fordown.ob2` holds it: `by -1`, `by -2`, a negative `by` from a
`CONST`, a non-literal bound, ascending unchanged, the no-`BY` case (0
iterations, documenting the semantics above), and an iteration count. Every
descending case prints a wrong number rather than failing if the step arrives as
positive or zero. `run_bc.sh` also asserts the two refusals, so the relaxation
is shown not to be a free-for-all.

### 3g. DONE — the two data gaps that blocked `Files`, both refused by omission

Found by measuring 3d rather than by reading it: extract each scoped builtin out
of the compiler and compile it **in bytecode mode**. `Env`, `Args`, `XYplane` and
`In` failed on their intrinsics, as predicted — but `Files` failed *earlier*, on
its own types.

**1. An array field reached through a pointer — `p^.field[i]` — was refused.**
Not a `Files` detail: any program doing it failed, with

    bytecode error: an array needs a non-zero length

and the length was never the problem. The index path pushed a **globals** slot
while the object lives on the heap and its address was already on the stack;
`Total_Slots` of a POINTER is `0`, and the globals path rejects a zero-length
array, so the complaint landed on the array. Fixed by asking the question the
field path two branches up already asks — pointer base means *add this field's
byte offset to the address on the stack*, otherwise it is a run in the globals.
The message pointed at the wrong thing, which is why it read like a type
limitation and survived.

**2. A `LONGINT` record field was refused** — the allowed-type list simply
omitted `T_Long`. A list like that refuses **by omission**, and the diagnostic
named only the types that *were* allowed, so the missing entry was invisible.
That is the same mistake the assignment list had already been fixed for
elsewhere, with the same reasoning: LONGINT is a 64-bit slot, exactly like
INTEGER, so it needs no conversion and no new opcode. `Files.FileDesc` is
`name: A64; size: longint`, so it could not have its own types laid out.

`tests/bc/ptrfld.ob2` holds both by value (writes a byte-per-element array field
through a pointer, reads it back, then reads a LONGINT field after it), and
`bytecode_gaps.sh` asserts both compile at all — the part a golden cannot state.

**The next wall is now recorded rather than rediscovered**: `Files.Open` does
`r.f := f`, an assignment to a **pointer field**, which is the "assigning through
a pointer designator" refusal. `bytecode_gaps.sh` pins it as `blocked`, so step 2
of 3d starts from a known list.

Worth noting how the differential behaved here. `ptrfld`'s first version tripped
the Ada backend's case-collision bug (`type P` beside `var p` — Ada is
case-insensitive, Oberon is not), so the gate FAILED the run: a new,
non-corroborated fixture is exactly what it is for. That also fixed a **wrong
diagnosis** in the recorded list, which had logged those three entries as bare
name conflicts; they are now named as one category. The fixture was then renamed
to `Ptr` so it can be corroborated at all — both backends print `AC91` — rather
than adding a fourth instance of a known Ada-side limitation.

Two small process notes, both the same shape as earlier ones: the recorded list
gained its first commentary and the reader immediately parsed the comments as
fixtures named `# CASE is the cause ...` (now skipped), and `digits` is an Ada
reserved word.

### 3h. DONE — pointer fields, and the spelling that was unusable

The third and last of the data gaps in front of `Files`, and the one with the
most in it. **There are two spellings of a pointer field and only one was
recognised:**

    next: Node     a field whose type names its OWN record - the linked-list
                   idiom.  Nothing names the pointer, so the field carries the
                   RECORD's user type rather than a pointer's.
    f: File        a field declared with a NAMED pointer type.  This is what
                   Files uses, and it was not recognised as a leaf at all.

So `q^.next := p` worked while `r.f := f` and `h.p := q` were refused - one
construct, two spellings, one of them unusable. With no match the walk fell
through to the post-loop "the view is a pointer" case, which classifies the whole
designator as a bare pointer and hands it to the assignment path that refuses
designators by design - hence a message about *designators* for what is really a
missing leaf case.

**Four places had to agree, and the third is why this was not a one-line fix:**

1. The **leaf condition** must accept both spellings (a predicate,
   `Ptr_Field_Of`, now used in both places that ask the question).
2. `D.Ptr_Field` must be set for both, or the store uses the integer opcode on
   an address.
3. The **intermediate** case - walking *into* a pointer field - must load the
   pointer for both spellings.  Skipping it for the named one is not a refusal
   but a **wrong address**, so fixing only the leaf would have converted a
   refusal into a silent wrong answer, which is the trade this backend exists to
   refuse.  Fixing it then exposed a second bug in the same block: `Load_Fld_P`
   reads *from* the address on the stack, and a **record variable** base had
   never pushed one (a pointer base does, at the top of the chain), so `h.p^.n`
   came out as `operand-stack depth violation` until the base push was mirrored
   there.
4. The Ada-mode classification of a pointer leaf had to stay `D_Scalar` for the
   self-referential spelling and become `D_Ptr` for the named one.  `D_Scalar`
   carries no user type, so the named spelling needed `D_Ptr` - that is how
   `Files.Base*`'s `return r.f` was failing as "a pointer with no type" - but
   sending the self-referential spelling there instead turned list.ob2's
   recorded ADA_BROKEN into a pointer-type mismatch, a fresh failure in a
   fixture this change was not about.

`tests/bc/ptrfield.ob2` pins it by value (write a pointer into a field, read
through the field, NIL through it, re-point it) and both backends corroborate it.
`bytecode_gaps.sh` asserts all three shapes compile, including the linked-list
spelling the corpus depends on.

**How it was actually found, since the reasoning did not.** Four theories died to
measurement, in this order: the emitter blamed the array's length (wrong); the
first fix broke `Files.Base*` with "RETURN value type mismatch" (no types named,
so useless); naming the types said "a pointer with no type"; and a temporary
raise inside the walk printed `kind=D_Scalar ptr_field=TRUE d_ut=3`, which
located it exactly. The two RETURN messages now name the types they disagreed
about, permanently, because "mismatch" alone cannot distinguish the value being
the wrong shape from the TYPE having been recorded wrong. And
`D.K := (if D.Ptr_Field and then UTypes (...) ...)` is load-bearing, not
decoration: without `D.Ptr_Field and then` it indexes `UTypes (0)` and crashed on
every record with an INTEGER in it.

### 3i. DONE — LONGINT arithmetic, which was refused wholesale

The first thing step 2 needed, and a whole language gap. **Every** LONGINT
operator refused with one message — `+`, `-`, `*`, `DIV`, `MOD` and unary `-` —
while assignment and comparison worked.

That was a **precaution, not a limitation**: a LONGINT is the same 8-byte slot as
an INTEGER in this VM, so the integer opcode *is* the LONGINT opcode. The check
was written when that was not yet certain and never revisited — the same shape as
the record-field list in 3g, costing the same thing: a construct the language has
that one backend will not compile. Mixed INTEGER/LONGINT needs nothing either, as
`Int_Like` only mixes when the other side is a literal, and a literal is already
the wider type's slot.

`tests/bc/longarith.ob2` asserts each operator by **result**, because the existing
`longint.ob2` only ever assigned and compared — no test could have noticed. Its
last case is the point of a LONGINT: `1000000000 * 3` does not fit in 32 bits, so
anything quietly narrowed would print `WIDE-BAD`.

**What is left is the LITERAL, which is a different thing**, and is recorded so
it is not mistaken for the arithmetic gap again. A LONGINT literal above
`INTEGER'Last` cannot be written, because the parser types an integer literal as
INTEGER; the Ada backend accepts it, so this *is* a divergence — and it is why
`longarith.ob2` builds 3e9 by multiplication instead of writing it.

One entry in `bytecode_gaps.sh` had to change hands rather than merely be added,
which is that file working as intended: the assertion that unary minus on LONGINT
**refuses** is now an assertion that it negates, checked by value.

**Measured result:** `Files` gets past LONGINT too and now stops at
**`Files.FRename`** — an intrinsic. That is step 2's actual subject: what remains
is the ~15 intrinsic primitives, not anything about the language.

### 3j. DONE — two `ARRAY OF` parameter gaps, and the first two intrinsics

**The user-visible half first, because it was not about `Files` at all.**
`Out.String (s)` inside a procedure — `s: array of char` — failed with

    o2c error: bytecode emitter: operand-stack underflow

a message about the **stack** for a problem with a **string**, which is why it
read as an emitter bug rather than as an unimplemented case. Two things were
missing and both are about where an open array's bytes are:

- a bare `ARRAY OF CHAR` pushed **nothing**: the caller's address sits in the
  parameter's own first slot and nothing put it on the stack;
- `Out.String` on a CHAR array is an inline print **loop over a globals run**,
  and an `ARRAY OF` parameter is not in the globals — its `UT` is 0, because an
  open array has no type of its own — so the loop was skipped and the
  pool-string native ran on an address.

The same push also fixes **string comparison** between open arrays, which needs
two addresses. `tests/bc/arrparam.ob2` holds both by value, calling one
procedure with arrays of **three different lengths** so a stale bound prints the
wrong text rather than nothing.

**Then the first two intrinsics.** `FDel` and `FRename` refused in bytecode mode
even though their natives (`o2c_fdel` id 9, `o2c_frename` id 10) already exist —
their branches append to the Ada body only, which is *why* they refused: with no
`O2c_BC` call a bytecode program would have compiled, run, and quietly done
nothing. Both now emit the native call once their argument addresses are on the
stack. They are not reachable from a user module (the compiler gates them on the
`Files` module), so there is no source-level check to write and none was added:
what proves them is the **module** compiling, which is the measurement this whole
sequence runs on.

**Measured result, and the state of the path:** `Files` gets past both, and now
stops at

    o2c error: bytecode backend: '&' is not yet supported

— `Files.Wait`'s `while (i < 400) & (FStat (path) < 0)`, the BOOLEAN `&` that
`bytecode_gaps.sh` already records as *blocked*. So what remains is: the BOOLEAN
operator opcodes, then the four natives (`FStat`/`FRead`/`FWrite`/`FClose`),
after which the module compiles and step 3 (the `Begin_Mode` ordering) is the
last thing between it and a program that calls `Files.Old`.

### 3k. DONE — BOOLEAN `&`/`or`, a crash on a module with no body, and the silent four

Three things, in the order they surfaced.

**BOOLEAN `&` and `or` had no opcode.** Both refused loudly (`'&' is not yet
supported`, `BOOLEAN operators are not yet supported`) while the spec had
reserved `0x72–0x7F` for exactly this, immediately after `BEQ`/`BNE`/`BTEST`.
They take the first two of that block — `BAND` 0x72, `BOR` 0x73 — so nothing is
renumbered and a BOOLEAN operation sits with the BOOLEAN operations. The `Op`
enum member still goes at the **end** of the enum: that order is fixed and
separate from the byte mapping, which is what makes the reserved block usable at
all. The operands are tested against ZERO rather than against 1, so the answer is
right for any truthy value, and the result is canonical 0/1. Both are strict —
the operands are already evaluated, so there is nothing to short-circuit.
`tests/bc/boolops.ob2` asserts seven cases by value, the last of which crosses
this change with the earlier `not` fix (`not (a & b)`).

**A module with no statement part crashed the emitter.** `Files` is written that
way — declarations and `end Files.` — and `Begin_Body` was called only when a
`BEGIN` was found. `Body_Proc` stayed 0 and `Encode` indexed the procedure table
at 0: a `CONSTRAINT_ERROR` inside the emitter, not a diagnostic, on a construct
the language allows. The body is now opened unconditionally, because a body with
no statements is still a body and the image still needs an entry.
`tests/bc/nobody.ob2` locks it, with an intentionally empty golden: what is being
asserted is that it compiles and runs.

**And then the discovery that matters most.** With those two fixed the whole
`Files` module **compiled** — and that was wrong. Four of its intrinsics
(`FStat`, `FRead`, `FWrite`, `FClose`) set a type and emitted **no opcode at
all**, so a bytecode program would have compiled, run, and used whatever was on
the stack — in practice the ADDRESS the argument had just pushed. Nothing
refused, because the default-refusal rule covers imported-module *calls* and
these are internal primitives of the builtin module: a different shape of call
site. They now refuse loudly until they have natives to call, which is what
`docs/bytecode-gaps.md` A.2 records. **A module compiling is not evidence that it
is right**, and this is the second time that lesson has been paid for.

**State of the path:** `Files` refuses at `Files.FStat` — the first of the four
natives still missing (ids 26–29: `o2c_fstat`, `o2c_fread`, `o2c_fwrite`,
`o2c_fclose`, each needing a `VM_Platform` seam function in the spec **and both
bodies**, host and Aegir). After those, the module compiles, and step 3 (the
`Begin_Mode` ordering) is what makes it callable.

### 3l. DONE — the four natives, and the Aegir trap sprung for real

`o2c_fstat` (26), `o2c_fread` (27), `o2c_fwrite` (28) and `o2c_fclose` (29),
appended after the input group with their arities and their "returns a value"
flags, plus four `VM_Platform` functions in the spec and — the part that
matters — **both** bodies.

**The trap was sprung, and only `run_m1` caught it.** Three host suites passed
with the Aegir body missing a `use type Interfaces.Unsigned_64;`, so the guest
build failed on operators that were not directly visible:

    vm_platform.adb:92:43: error: operator for type "Interfaces.Unsigned_64"
    is not directly visible

That is exactly what the trap list predicts — the three host suites cannot see
this file — and it is worth recording that the prediction held.

**The natives are verified BY EFFECT**, not by compiling. The intrinsics are
gated on the module being `Files`, so `tests/bc/filesintr.ob2` IS a module named
`Files`, which is what makes them reachable at all:

    absent      FStat on a path that was just deleted reports -1
    write=0     FWrite puts a byte at offset 0
    size=1      ... and Stat then reports ONE byte, read from the filesystem
    read=0Q     FRead replaces a buffer holding something else, and what it
                reads is the byte that was written
    close=0

`read=0Q` is what makes it a real test: the buffer held `z` first, so a read
that did nothing would print `z`. The file is deleted first, so "absent" is a
fact rather than an assumption, and deleted again at the end, so the fixture is
hermetic and idempotent.

**That fixture is deliberately bytecode-only.** A user module named `Files` gets
the intrinsics but not the emitted `O2c_F*` helper BODIES, which live only in the
builtin module — so its Ada output references helpers it does not define. The
differential flags it, and it is recorded with that reason rather than hidden:
the fixture's subject is the four natives, and the VM side verifies them.

**State of the path:** the whole `Files` module compiles to bytecode with real
native calls, and the four primitives are verified by effect. What is left of 3d
is **step 3** — the `Begin_Mode` ordering — which is what lets a *user* program
call `Files.Old`/`Read`/`Close` rather than only the module compiling.

### 3m. DONE — the body frame, the ordering, and bytecode builtins

**The root cause was an asymmetric begin/end pair**, and finding it took three
diagnoses, two of them wrong.  Recording the wrong ones because they are the
trap: (1) "the export record carries no bytecode id" - plausible, wrong;
(2) "main-module vs library compilation" - wrong; (3) the trace.

What the refusal said once it NAMED the procedure:

    bytecode backend: call to an unknown procedure 'Bracket'

`Bracket` is `Term`'s first procedure.  Instrumenting `Decl_Procedure` and the
call site showed it gets no id at all while the second and third procedures do:

    TRC reset bytecode=TRUE
    TRC call 'Bracket' idx= 9 bcproc= 0 n_sym= 11
    TRC decl 'Ch'     idx=10 id=50
    TRC decl 'Clear'  idx=11 id=51

The id is assigned only when

    if O2c_BC.Bytecode_Mode and then not O2c_BC.Proc_Open then

and `Proc_Open` is not a mode flag - it is frame state:

    function Proc_Open return Boolean is (Cur_Proc /= 0);

`Begin_Body` opens the module body's frame (`Body_Proc := Begin_Proc (0, 0)`) and
**nothing ever closed it**.  So the next module's FIRST procedure saw the frame
still open, skipped `Begin_Proc` - and its `end` still called `End_Proc`, which
is unconditional (`o2c_compiler.adb:6176`).  That closed the leaked frame, which
is why the damage healed from the second procedure on.  One procedure per module
lost its id, and its first call site is where it surfaced.

**Why it was invisible until the ordering changed**: `Begin_Mode` calls `Reset`,
which wiped the frame, and `Begin_Mode` used to run after the builtins and just
before the main module.  The ordering change did not break the main module - it
exposed a leak that had always been there, hidden by `Reset`.

**The fix** is two pieces, both landed here:

1. `O2c_BC.End_Body`, the matching close for `Begin_Body`, called at the START of
   every module compile.  At module start no procedure frame can legitimately be
   open, so this is exactly the missing balance.  It closes the BODY frame only
   (`Cur_Proc = Body_Proc`) - a procedure frame left open is a different bug and
   closing it here would hide it.
2. The ordering change, now working: `Begin_Mode` before the builtins, a
   `Scoped` flag per module, the main module switched on afterwards.

**The scoped set is measured, not chosen** (each module compiled alone, bytecode
mode, library shape):

    scoped (compile)   Texts, Files, Math, Term, MathL, Err
    emitter gap        Strings, Reals, Input   (operand-stack underflow)
    intrinsic sites    Env, Args, XYplane, In, Convert - whose natives
                       (6/7/8, 11-21) already exist and need only the wiring
                       the Files intrinsics got in 3l

A builtin left out costs nothing: every module is parsed and its Ada text emitted
either way, so `Scoped => False` is exactly the old behaviour.

**Verified**: `sum` compiles (5504 bytes, the scoped builtins' code is now in the
image) and RUNS CORRECTLY - `bc slice ok` / `406`, the sum of 1..28 - where it
used to fail with `call to an unknown procedure 'Bracket'`.  All seven suites
green, 47 corroborated by both backends, zero warnings.

**What is left of 3d**: a USER program calling `Files.Old` now reaches a clean,
explicit refusal rather than confusion -

    o2c error: bytecode backend: Files.Old is not yet supported

That is the FFI default-refusal allowlist, and it is the last step: let a
qualified user call resolve to the procedure that is now IN the image, through
the export record (`X_Entry`), which is where a bytecode id must travel between
modules.  (`X_Entry` genuinely has no such field - it was the right fix, just
not the cause of the regression.)

### 3n. DONE — the bytecode id crosses the module boundary

A qualified call to an imported procedure now resolves to the procedure that is
in the image, and the piece that carries the id is the export record:

    type X_Entry is record
       ...
       Bc : Natural := 0;      --  the bytecode procedure id, when the code is
                               --  in the image (0 = not compiled to bytecode)

`Bc /= 0` IS the signal a call site uses: the factor path pushes the actuals with
`Bc_Push_Arg` and calls `O2c_BC.Call_Proc (Xs (XI).Bc)` when the id is there, and
keeps its loud refusal when it is not.  `Files.Old` went from

    bytecode backend: Files.Old is not yet supported

to an actual call.

**One trap here is worth its own line**: the export has to read the procedure's
OWN symbol index, and `N_Sym` is NOT it by then - a parameter interns a symbol
while the heading is parsed.  Reading `Syms (N_Sym).Bc_Proc` gave 0, and the
trace of the two sides is what showed it:

    TRC SET 'Old' n_sym= 1 id= 8      <- the id IS assigned, to symbol 1
    TRC EXP 'Old' n_sym= 2 bc= 0      <- the export read symbol 2

Hence the `PSym` local, set where the procedure's symbol is created.

**And the finding that matters more than the feature:**

    "COMPILES CLEANLY" IS NOT THE STANDARD FOR SCOPING A MODULE.

Six modules compile to bytecode cleanly.  A construct with no emission does not
refuse - it leaves whatever is on the stack, and the callee runs WRONG in
silence.  Math is the counter-example, and only *calling* it found it:

    procedure sin(x: real): real; begin return Sin(x) end sin;

The builtin `Sin(x)` is emitted as Ada text only, so a scoped Math returned its
own argument - `sin(1.5)` printed `1.500`, with no error anywhere.  Verified by
making the call, before narrowing.

So the scoped set is now **Files alone**: 3d needs it and it is the one whose
bodies have been verified by effect (`tests/bc/filesintr.ob2`).  Everything else
is `Scoped => False`, which costs nothing - every module is parsed and its Ada
text emitted either way - and a user call into one keeps its loud refusal.
`Math.sin` is back to `Math.sin is not yet supported` rather than a wrong number.

**Verified**: `sum` compiles and runs correctly (`bc slice ok` / `406`); a user
call to `Files.Old` emits a real call; `Math.sin` refuses loudly; all seven
suites green, 47 corroborated, zero warnings.

**What is left of 3d**: two things, both now named.  (1) A qualified user call to
`Files.Old` is blocked one step past the call by an unrelated limit -
`pointer type mismatch assigning f`, imported pointer-type identity - so the call
cannot yet be verified by effect from a user module.  (2) The STATEMENT path
(`Files.Read`/`Write`/`Close`/`Register`) still refuses; it needs the same
treatment the factor path just got.


### 3o. IN PROGRESS — the first cross-module call with an open-array formal

Attempting the end-to-end check (`f := Files.Old(nm)` then `Files.Length(f)`)
surfaced two things, both measured, neither landed yet.

**1. `X_Ret_UT` is not `Import_Type` for this case.**  The factor path already
resolves a pointer result with `R.Ptr_UT := X_Ret_UT (XI)`
(`o2c_compiler.adb:3519`), and the assignment still fails:

    o2c error: pointer type mismatch assigning f

Replacing that with `Import_Type (Owner, Member)` - split out of the qualified
`Xs (XI).Ret_Nm` - makes the assignment type-check.  So for a POINTER result
whose target is a RECORD type of the exporting module, `X_Ret_UT` does not
produce the id the assignment needs, and `Import_Type` does.  That part is
understood and worth keeping.  (It does NOT fix the next problem.)

**2. The image is then malformed at verification.**  With the assignment fixed,
the program compiles (2400 bytes) and the VM rejects the image:

    vm: internal error in phase 3: STORAGE_ERROR (stack overflow or erroneous
    memory access)
    vm: malformed code

Prime suspect, and it fits the evidence: **`Files.Old`'s formal is an OPEN ARRAY**
(`Old(name: array of char)`), which travels as TWO slots - the address and the
length - while the factor call path pushes one value per actual.  That path was
modelled on the FFI sites (`XYplane.IsDot (x, y)`), which take only scalars, so
an open-array actual has never been exercised through it.  The statement path and
the local call path both know about the length slot; the factor path does not yet.

**Next step, in this order:** push an open-array actual as (address, length) on
the factor path the way the local call path does, then re-run the end-to-end
check.  Note `Files.New` has the same formal shape, so the same fix serves both,
and `Files.Length(f)` - a pointer argument, one slot - is the control case that
should pass immediately once the open-array actual is right.

The tree is left at the verified commit; none of the above is committed.


### 3p. DONE — both blockers were one mistake, and what is left is inside the callee

The two findings in 3o turned out to be facets of the same error, and the
diagnosis in 3o was right about the shape but wrong about where the fix goes.

**1. `R.Typ` was being clobbered.**  `X_Ret_UT` ALREADY calls `Import_Type`
(`o2c_compiler.adb:586`) and the factor path already sets
`R.Typ := T_Ptr` with it (3518-3519).  The new call emission then set

    R.Typ := (if Xs (XI).Ret then Xs (XI).Typ else T_Int);

which OVERWROTE that with the export's scalar sentinel - and that is what
produced `pointer type mismatch assigning f`.  My hand-rolled replacement looked
like the fix only because it set `R.Typ := T_Ptr` again.  The fix is to set
nothing: the type was already right.

**2. The open-array actual was pushed twice.**  `Parse_Actual` pushes an OPEN
formal's address AND its length itself (`o2c_compiler.adb:2294`, `2295`, `2308`),
and in that branch only.  The factor path then pushed `Bc_Push_Arg` on top, one
value too many.  Guarded now:

    if not X_Formal (XI, K).Open then
       Bc_Push_Arg (Arg_R (K));
    end if;

This is why the FFI arms never hit it: `XYplane.IsDot (x, y)` and `Dot (x, y,
mode)` push their scalars by hand and have no open formal.

**What is left, and it is a different bug.**  With both fixed the program
compiles and the VM now reports a specific internal error instead of a vague one:

    vm: internal error in phase 3: CONSTRAINT_ERROR (obc_vm.adb:2129 range check
    failed)

Line 2129 is `Top`'s `return Stack (SP - 1)` - an OPERAND-STACK UNDERFLOW during
execution, so a balance inside the CALLEE.  The call itself works (`sum` passes,
and the call site is reached); what is unbalanced is a construct in `Files`'
bodies that no fixture has ever exercised - the candidates in `Old` are
`new(f)`, `len(name)` on an open array, and `f^.name[i] := name[i]`, the nested
array-field-index store.  Each is a small, separately testable construct, and
that is where to look next: a fixture per construct, not a Files-shaped one.

So the sequence for 3d is now: exercise those constructs directly, fix whichever
is unbalanced, then the end-to-end check (`Files.Old` + `Files.Length`) should
pass - `Files.Length` being the one-slot control case.


### 3q. DONE — LEN; and the bisect that found it

The underflow in 3p was `LEN`, which had **no bytecode emission at all** - only
Ada text was produced:

    if Eq_No_Case (Cur.Text (1 .. Cur.Len), "LEN") then
       ...
       R.Text := To_Unbounded_String (LNm) & "'Length";
       R.Typ  := T_Int;                --  and nothing pushed

So `i < len (name)` left the comparison a value short, and the VM rejected the
whole image:

    vm: internal error in phase 3: CONSTRAINT_ERROR (obc_vm.adb:2129 range check
    failed)          --  Top's "return Stack (SP - 1)", an operand-stack underflow

**Where the length lives depends on the array**, which is why one emission is not
enough: a known-length array's length is its declared one (a constant at the use
site), and an `ARRAY OF` parameter's length is the CALLER's, in the parameter's
second slot (the `#alen-` slot the parameter linkage interns).  Both cases are
emitted; anything else refuses.

**The bisect is the reusable part.**  The constructs in `Files.Old` were tested
one at a time, as local procedures in main modules with no Files involved:

    c1  new(f) + f^.name[0] := "x" + read back ........ works
    c2  len(name) on an OPEN array .................... MALFORMED  <- this one
    c3  f^.name[i] := name[i] ......................... runs, copies NOTHING
    d1  f^.size := 7 through a pointer, read back ..... works
    d2  f^.name[i] := nm[i] from a GLOBAL array ....... works
    d3  read name[0] / name[i] of an OPEN parameter ... prints BLANKS

Each is a main module with no imports, so a failure cannot be about the call, the
module boundary or the builtin - only about the construct.  `c2` was the first
failure and the fix above is its fix.

**Fixture**: `tests/bc/lenopen.ob2`.  Its last two lines call the same procedure
with arrays of DIFFERENT lengths; a length taken from the declaration instead of
from the caller would pass the first two lines and fail those - which is the
point of writing it that way.  It is corroborated by BOTH backends (48 fixtures
corroborated now, up from 47): the Ada side and the VM agree on all four numbers.

**Still broken, and it is what breaks `Files.Old`** (which copies `name[i]` into
its record): reading an element of an `ARRAY OF` parameter - `d3`, constant and
variable index alike - prints blanks, in SILENCE.  `d2` shows it is specific to
the open array: the same store from a global array works.  So the next step is
the open-array element READ, and `d3` is its minimal reproduction.


### 3r. DONE — indexing an ARRAY OF CHAR (and a correction)

**Correction first, because 3q stated it too broadly.**  "Reading an element of
an ARRAY OF parameter is silently broken" was wrong, and a fair question exposed
it: `openarr.ob2` has indexed an open-array parameter all along -

    procedure Sum6 (a: array of integer): integer;
       for i := 0 to 5 do s := s + a[i] end;

- and it passes.  So do passing an open array, printing one with `Out.String`,
and (after 3q) taking its `len`.  Open arrays were working.  What was missing was
narrower: **indexing an `ARRAY OF CHAR`**.

**The cause** is a branch of its own that built only the Ada text:

    if Syms (Id).Typ = T_Char then
       if Cur.Kind /= Lex.Tok_LBracket then <bare string value ...> return R; end if;
       Next;      --  past '['
       R.Text := To_Unbounded_String (Nm) & " (" & Ix.Text & " + 1)";
       R.Typ  := T_Char;
       return R;                    --  and NOTHING was pushed
    end if;

The `+ 1` is there because a CHAR element is 1-based in the emitted Ada, while an
INTEGER array is not - which is exactly why this branch existed, and exactly why
it never reached the array path below it that knows how to EMIT.  In bytecode
mode `name[i]` therefore pushed nothing, the surrounding expression was a value
short, and the character read as blank - silently.

**The fix**: the bare-value shortcut now applies only when there is no `[`, so an
indexed CHAR access falls through to the shared array path (base load, bounds
check against the length that travelled with the array, then `Load_Idx_B` - the
same path that made the INTEGER case work).  The Ada text keeps its `+ 1`.

**Verified**: `d3` prints `abc` (constant and variable index), `c3` prints `ab`
(the store from an open-array element), the `Old`-shaped probe prints `abc`,
`openarr`'s image output is byte-identical to its golden, all seven suites green,
48 corroborated, zero warnings.  (Introducing a duplicate `return R;` on the way
warned as unreachable code; it was removed - zero warnings is not optional.)

**Next, and narrower again**: the end-to-end check now says `Files.Length` does
not report 0 for a file `Files.New` just made ("NOT zero" from `/tmp/probe/u3.ob2`).
That rules out what `Old` stores and points at what travels BACK across the module
boundary - a LONGINT result, or the pointer argument - rather than at any
construct inside the callee.


### 3s. IN PROGRESS — the fault is the cross-module CALL, not the constructs

The end-to-end failure is now pinned to the call, by elimination rather than by
argument:

    e1  Files.New + Files.Length rewritten as LOCAL procedures ... "local: zero"
    u3  the same code called across the module boundary ......... "NOT zero"

Same source, same shapes - `new(f)`, `f^.size := 0`, `len(name)`, the open-array
element copy, `f^.name[i] := name[i]`, a pointer return, a pointer parameter, a
field read through that parameter - and it works when the callee is local.  So
every construct inside `New` and `Length` is fine, and so is the result/parameter
machinery in general.  What breaks is calling them ACROSS the module boundary.

**The one thing measured about that call:** the unqualified call path emits its
call with NO argument code of its own (`o2c_compiler.adb:9266-9288` - just
`Call_Proc` or `Native_Call`), because `Parse_Actual` has already pushed the
actual: the value, or for an OPEN formal its address and length.  The qualified
path I added also pushed with `Bc_Push_Arg`, i.e. a second copy of every scalar
argument.

**Removing that second push did NOT fix the symptom** - `u3` still says "NOT
zero" - so the extra push is not the cause, and the change was reverted rather
than landed on reasoning alone.  It is still the right shape on the evidence
(the local path is the reference implementation and it pushes nothing), but a
change that alters nothing observable and is covered by no test is not a commit.

**Next, and it is a narrow question now**: is the CALL TARGET the right
procedure?  `Call_Proc` patches its operand from the fixup table at Encode, and
the id it is given is `Xs (XI).Bc`, captured when the exporting module was
compiled.  A wrong target would explain a callee that runs, returns a value and
returns the WRONG one without trapping - which is exactly what is observed.
`Proc_Entry` (`o2c_bc.adb:81`, filled in `Begin_Proc` at 677) is where to look,
and a trace of the target's identity at the call site is the cheapest way to
settle it.


### 3t. IN PROGRESS — what the cross-module call is NOT

`3s` asked whether the call targets the right procedure.  It does.  Tracing both
sides settles it:

    DBG decl 'New'    id= 2         (Files, declaring side)
    DBG decl 'Length' id= 3
    DBG call 'Files.New'    id= 2 npar= 1
    DBG call 'Files.Length' id= 3 npar= 1

The ids match, and so do the arities: `New` needs 2 slots (its `array of char`
formal is open) and the emitter records 2, `Length` needs 1 and the emitter
records 1.  So the id, the target and the argument COUNTS are all right.

**Two probes narrowed it further, and they disagree in an informative way.**

    u3  f := Files.New(nm); n := Files.Length(f);     runs, returns GARBAGE
    u4  n := Files.Length(Files.New(nm));             image is MALFORMED

`u3` stores a call's result in a variable and reads it back later; `u4` never
stores it - the inner call's result goes straight in as the next call's argument.
`u4` being malformed means the fault is in the CALL RESULT as an operand, not in
the assignment; and it is a verifier-visible stack/arity violation, which is a
much better clue than a wrong number.

**One oddity worth its own note**, found while looking for a depth invariant to
test: `Depth` (`o2c_bc.adb:95`) is reset by `Reset` and never at a procedure
boundary, so readings taken inside different procedures are not comparable, and
the per-image `Max_Depth` written at `o2c_bc.adb:1038` accumulates across the
whole compile rather than per frame.  That is not the cause of anything above,
but it means the emitter's own depth accounting cannot be used as the check it
looks like, and any debugging that assumes otherwise will mislead.

**Next**: the call RESULT as an operand.  `u4` is the reproduction, and it is
smaller than `u3`: no assignment, no variable, two calls.  What to compare is the
code the qualified path emits around `Call_Proc` versus the unqualified path
(`o2c_compiler.adb:9266-9288`), which emits nothing but the call because
`Parse_Actual` has pushed everything - including, for an actual that is itself a
CALL, the value that call already left on the stack.


### 3u. DONE — the duplicate push, and where the chase stops

`e2` was the probe that settled the shape of the problem: `u4`'s code (one call's
result used as the next call's argument) with LOCAL callees prints
`local nested: zero`, so nesting is fine, results-as-operands are fine, and the
difference is the qualified path's own emission - which is mine, and about
thirty lines of it.

The one structural difference was that it pushed `Bc_Push_Arg` for every actual
**in addition to** what `Parse_Actual` had already pushed.  The local call path
(`o2c_compiler.adb:9266-9288`) emits its `Call_Proc` with no argument code at all
precisely because `Parse_Actual` pushes - the value, or for an OPEN formal the
address and its length.

**Removing it is a real fix, measured on two cases rather than one:**

    u4  before: "vm: malformed code"      after: runs
    u3  before: garbage                   after: garbage

A rejected image became a running one.  (The earlier attempt at this same removal
was measured on `u3` alone, which is exactly how a real fix gets reverted as a
non-fix - and it was.  Measuring both is what makes it one.)

**What is left is a different class**, and it is where I stop chasing:

    u4 / u3 / useold2 all RUN now, and all return the WRONG VALUE

Since the call now pushes exactly what the local path pushes, the remaining
difference between a local and a qualified call is the FORMAL DESCRIPTOR.
`X_Formal` (`o2c_compiler.adb:562-575`) rewrites an imported formal whose exported
type is a user type into `F.Typ := T_Int` with `F.UT := Import_Type (...)`, so
`Parse_Actual` is handed a formal that looks scalar-with-a-user-type.  A pointer
pushed through that route - truncated to an integer width, or pushed as an
address rather than as a value - would give a callee that dereferences something
valid-looking and returns a plausible wrong number, with no trap.  That is the
next hypothesis, and `u3` is its reproduction.

**The stopping rule this section exists to state**: if a probe does not shrink the
reproduction or eliminate a hypothesis, stop and switch to natives rather than
chase.  This iteration shrank it (a rejected image became a running one), so it
continued; the next one has to do the same or 3d switches to making the rest of
the Files API FFI natives, as `Delete` and `Rename` already are.


### 3v. HYPOTHESIS TESTED AND DEAD — and the switch the stopping rule triggers

The bounded iteration on the formal descriptor (`3u`'s hypothesis) was run, and
it is **disproved**.

Measured first, which is what made the hypothesis look right:

    u3 (cross-module): PA in typ=T_INT  ut=4 open=FALSE
    e2 (LOCAL, works): PA in typ=T_STR  ut=3 open=FALSE

`X_Formal` was flattening a user-typed formal to `Typ := T_Int`, while the
identical LOCAL formal is described as `Typ = T_Str` with its user type - so a
pointer actual took the INTEGER route.  The change (described as the local case
describes it) was applied, and it does make the shapes match:

    u3 after:         PA in typ=T_STR  ut=4 open=FALSE     <- same as e2 now

and it changed NOTHING observable:

    u3  before: "NOT zero"      after: "NOT zero"
    u4  before: "NOT zero"      after: "NOT zero"

So the descriptor is not the cause, and the change was REVERTED rather than kept
on the strength of looking more correct - same standard as everywhere else: it
alters nothing observable and no test covers it.

**That is the trigger.**  `3u` states the rule: if a probe does not shrink the
reproduction or eliminate a hypothesis, stop and switch to natives rather than
chase.  The probe eliminated a hypothesis (worth keeping - nobody need tread it
again) but did not shrink the reproduction, and the iteration the user authorised
was explicitly "one more, bounded".  It is used up.

**The course from here is therefore the one chosen in advance**: stop scoping
`Files` and make the rest of its API (`Old`/`New`/`Read`/`Write`/`Close`/
`Register`/`Set`) FFI natives, the way `Delete`/`Rename` and the four positioned
primitives already are.  That removes the whole failure surface this section
documents: no Oberon bodies compiled to bytecode, no imported formal descriptors,
no cross-module value transport.  What it costs instead is VM-side file-handle
state, which is ordinary, testable work of the kind the existing 25 natives
already demonstrate.

Everything the chase produced stays valid and landed: the body-frame balance, the
`R.Typ` clobber, the argument double-push, `LEN` and `ARRAY OF CHAR` indexing are
real bytecode gaps closed, with `lenopen` as a new fixture and 48 fixtures
corroborated by both backends.


### 3w. TYPE COVERAGE — item 1, measured

Decision: type coverage first, because that is what a real program refuses at
BEFORE libraries or calls.  Scoped in public before any code, per the rule 3d
cost us.

**The boundary, read from the source.**  A variable declaration in bytecode mode
is accepted only if its type is a pointer, a procedure value, an array whose
element is `Int/Char/Bool/Real` with a non-zero length, or a record for which
`Chain_Fields_Allowed` holds (`o2c_compiler.adb:5279`, `Fields_Allowed` at 1286).
`Fields_Allowed` walks a record's fields, and for a field that is itself a
user type it accepts exactly three shapes: the record itself (Oberon's implicit
pointer), a POINTER, or a fixed array whose ELEMENT is a slot scalar
(`Int/Char/Bool/Set/Real/LReal`).  Nested arrays are outside it.

**Item 1, measured.**  The refusal now names the type it choked on - which is
what made this measurable at all, and is the same lesson as
`call to an unknown procedure`:

    o2c error: bytecode backend: non-INTEGER arrays, record extensions and
      records with non-INTEGER or user-typed fields are not yet supported
      ('Tote')

`samples/hello.ob2`:

    type Vector = array 4 of integer;
    type Mat    = array 2 of Vector;            <- element is an ARRAY
    type Tote   = record m: Mat; k: integer end;
    var  sac    : Tote;

So item 1 is **a record field that is an array of arrays**, and it refuses
correctly: the layout machinery carries one level of array-of-scalars, not two.
Everything else in the program's type block is already fine - `Vector`, `Pair`,
`Line`, `FLine`, the self-pointer chain `Node`/`NodeDesc`, and the local extension
`Circle = record (Shape)`.

**Named but NOT yet measured** (they come after item 1, so they cannot be
measured until it lands): `P3 = record (Geom.Point) z: integer end` - an
extension of an IMPORTED record - and whatever the refusal after that turns out
to be.  Marked as unmeasured rather than listed as known.

**The progress metric for this workstream**: `hello.ob2`'s refusal advances.
Each item that lands moves that message later in the program, so the checklist is
self-updating and the claim "item N is done" is checkable by anyone running one
command.  That is the shape this work should have had from the start.

**Item 1 is one level of array nesting in a record field.** The fixture that
pins it comes with the fix, not before: the work order is item, test, commit.


### 3x. ITEM 1 IS TWO HALVES — one measured, one not; attempt reverted

Attempted item 1 (record fields that are arrays of arrays) and **reverted it**,
because the attempt was half a fix and the half that was missing made things
worse in the way that matters.

**What the half proved.**  Two changes were needed and both were made - a
recursive `Total_Slots` (an array whose element is a user type is
`Arr_Len * Total_Slots (Elem_UT)` slots, not `Arr_Len`), the record-field rule,
and the declaration rule.  With them, the progress metric MOVED:

    hello.ob2 refuses at  'Tote'  ->  'Files.Rider'

So the layout half is real, and the checklist is now self-updating in practice
rather than in principle.  Item 2 is `Files.Rider` - an IMPORTED record.

**Why it still cannot land.**  The fixture that exercises two-level indexing says
so:

    type V4 = array 4 of integer;
    type M2 = array 2 of V4;
    var  m  : M2;
    (* for i in 0..1, j in 0..3:  m[i][j] := i * 10 + j;  then print *)

    expected:  0 1 2 3 10 11 12 13
    measured:  10 11 12 13 10 11 12 13

Both rows hold the same values, so the ROWS ALIAS: the first-level index stride is
0 or 1 where it must be `Total_Slots (V4)` = 4 slots.  The layout was fixed and
the ACCESS was not.  With the check open, that is not a refusal - it is a program
that compiles, runs, and answers wrongly, which is the one outcome this project
does not accept.  So the whole attempt was reverted rather than landing the size
fix unverified: with the check closed again, the size fix changes nothing
observable, and a change that alters nothing observable is not a commit.

**Item 1, restated with both halves named:**

    1a  size:   Arr_Len * Total_Slots (Elem_UT)          - known, one line,
                                                           measured to work
    1b  access: the first-level index stride, currently  - the missing half
                ignoring the element size

1a is recorded here so it is not rediscovered; it is re-applied WITH 1b in one
commit, because alone it is invisible and together they are testable by the
fixture above.

**And item 2 is already named**: `Files.Rider` is an IMPORTED record
(`record f: File; pos: longint; eof: boolean; res: integer; cur: A1 end`), so the
next thing after 1 is how a record's fields lay out when the record's
DESCRIPTION came from another module - which is a question this note does not
answer, and marks as unmeasured.


### 3y. 1b ANATOMY — why the rows aliased, and what the fix must touch

Reading the VM rather than guessing changes 1b's sizing, so it is recorded before
the attempt is made.

**The stride cannot be fixed in the index expression.**  `Op_Load_Idx_I` and
`Op_Store_Idx_I` scale the index by a HARD-CODED eight bytes:

    + System.Storage_Elements.Integer_Address (Idx)
      * System.Storage_Elements.Integer_Address (8);        (vm/obc_vm.adb:2826)

(`..._Idx_B` scales by one byte.)  So a subscript's stride is one slot by
construction, and an element that is a user type - `V4`, four slots - cannot be
reached by it at all.

**And the measured output identifies the defect exactly.**  If the outer
subscript on a user-typed element is DROPPED - `m[i]` yields the base address,
only `[j]` is applied, at stride 8 - then:

    i = 0 writes 0,1,2,3   to bytes 0, 8, 16, 24
    i = 1 writes 10..13    to the SAME bytes
    the print loop reads them back at the same addresses

which prints `10 11 12 13 10 11 12 13` - byte for byte the measured output.  The
model reproduces the observation, so the defect is not "a stride constant": it is

    (i)  the designator must NOT drop a subscript on a user-typed element, and
    (ii) an outer index on such an element needs its offset computed by the
         compiler - `base + idx * Total_Slots (Elem_UT) * 8` - because no opcode
         will do it.

**Why this is landable and safe to attempt.**  It touches the designator path,
which is where the `UTypes (0)` crash and the pointer-field subtlety came from -
but the fixture gates it: `m1` above must print `0 1 2 3 10 11 12 13`, and a wrong
answer fails it and reverts.  Item 1 therefore lands as 1a + 1b + the fixture in
one commit, or not at all, and the current state (refused at the declaration, per
the check at `o2c_compiler.adb:5279`) remains the safe one meanwhile.

Fixture, kept here because the commit that needs it will need it verbatim:

    type V4 = array 4 of integer;  type M2 = array 2 of V4;  var m: M2; i, j: integer;
    (* m[i][j] := i * 10 + j for i in 0..1, j in 0..3; then print each as
       Out.Int (m[i][j], 1) with Out.Char (" ") after it; expect
       0 1 2 3 10 11 12 13 *)


### 3z. ITEM 1: three patches, no effect — so the branch is unverified

Attempted item 1 whole - 1a (recursive size), 1b (the subscript step moves the
base for a user-typed element), 1c (a locally declared array records
`Elem_UT`) - and **reverted all of it**, because the fixture says the work is not
doing what it claims:

    m1 (two-level array)  expected: 0 1 2 3 10 11 12 13
                          measured: 10 11 12 13 10 11 12 13     (unchanged)

with the compiled image the same size (712 bytes) before and after 1b and 1c.
**Unchanged output AND unchanged image size means the emitted code did not
change**, i.e. the branch I patched is not the branch that runs for `m[i][j]`.
That is the finding, and it is worth more than another patch: I was editing a
subscript path on the strength of where it lives in the file, without evidence
that it executes.

1a alone is proven - the progress metric moved to `Files.Rider` with it and moved
back when the whole attempt was reverted - and it is one line, reproduced below.

**The next step is a trace, not a patch.**  The technique that cracked the earlier
cross-module case was instrumenting the two candidate paths and reading which one
fires (`PA in`/`PA out`).  The same applies here: instrument the designator's
subscript step to report base type, element type, `Elem_UT` and which branch is
taken, then run `m1`.  Until that says which code runs, any fix is a guess dressed
as a change - which is exactly what 1b and 1c were.

**State: item 1 is refused, not half-done** (`o2c_compiler.adb:5279`), so the safe
behaviour is unchanged: a nested-array variable is refused loudly rather than
laid out wrongly.  The fixture and 1a are kept in 3x/3y.


### 3aa. THE TRACE SAYS WHERE THE FIX IS *NOT* — the outer subscript never
### reaches the designator's index step

Instrumented the designator chain's subscript step and ran `m1` (with the
scaffolding in place so it compiles at all).  Two hits, and their content is the
whole answer:

    DESIG idx ut= 1 elem=T_INT elem_ut= 0 len= 4
    DESIG idx ut= 1 elem=T_INT elem_ut= 0 len= 4

`ut=1` is `V4` - `array 4 of integer`, `len=4`, a scalar element.  So the branch
fires for the INNER subscript.  There is no hit for `M2` (`len=2`, a user-typed
element).  **The outer subscript is not handled by that code at all.**

Which is exactly why 1b and 1c changed nothing observable: they edited a branch
that never runs for this expression, and unchanged output plus an unchanged image
size (712 bytes) was the tell.  The scaffolding - 1a, the two rules, the
`Elem_UT` recording, 1b, the trace - was reverted, because with the check open it
produces silently wrong answers and that is the one thing this backend exists not
to do.

**So the question is now narrow and factual**: what consumes the outer `[`?

The walker's own subscript step is the only one inside `Parse_Rec_Ptr_Chain`
(traced).  So the outer subscript is consumed BEFORE the walker is entered, or by
a branch that returns early.  That is a one-command question to answer with the
same technique: instrument the ENTRY of the walker (and the array handling that
precedes it) and print, per selector, the kind consumed and the current type.  If
the walker's loop sees only one `[` for `m[i][j]`, the outer one was taken before
it, and the fix belongs there.

**What is NOT in doubt**: 1a is one line and proven by the metric (`Tote` ->
`Files.Rider` with it, back on revert), and the fixture `m1` is the gate.  Both
are recorded in 3x/3y/3z.


### 3ab. WHERE THIS STANDS — and the process fix for the hunt itself

Reverted again: the instrumentation that was meant to name the outer subscript's
site was inserted by LINE NUMBER computed before the scaffold edits and applied
after them, so the markers landed inside multi-line statements and the compiler
rejected the file.  Nothing is left in the tree.

Measured so far, and still valid:

- the designator chain's subscript step fires only for `V4` (`ut=1`,
  `len=4`, scalar element) - the INNER subscript.  The outer one never reaches it;
- so the outer `[` is consumed by one of the six `Parse_Rec_Ptr_Chain` call sites
  (2215, 3506, 4079, 7435, 7991, 8297) or by a branch that returns early;
- 1a is proven by the metric; `m1` is the gate; the item stays refused.

**The process fix this attempt earned is now a repo-wide rule** in
`AGENTS.md` ("Probing the compiler: anchors, negatives, and sizing").

**And the honest read on the hunt**: locating a consumer inside a 11k-line
front end by instrument-and-rebuild is slow in this budget.  It is a
context-heavy, read-only question - which is what the explore subagent is for: it
can read the whole designator/selector path and report the site without spending
the editing budget on guesses.  Proposed rather than done, since it opens a new
exploration path and the guard on this turn said to stop.


### 3ac. DONE — item 1: multi-level arrays (and the site was not where I looked)

A record field that is an ARRAY OF ARRAYS now works, verified by a new fixture
(`tests/bc/nestedarr.ob2`, hand-computed golden, corroborated by both backends),
and the progress metric moved:

    hello.ob2 refuses at  'Tote'  ->  'Files.Rider'

Two halves, as 3x said, but **1b was not the code I had patched three times**:

    1a  `Total_Slots` for an array whose element is a user type is
        `Arr_Len * Total_Slots (Elem_UT)`, not `Arr_Len` - one line.
    1b  the `Elem_UT /= 0` branch inside `Parse_Rec_Ptr_Chain` (line 2073)
        already advanced the type and appended Ada text, and emitted NO ROW
        OFFSET.  The scalar-subscript branch I kept editing is never reached for
        a user-typed element: the `DESIG` trace showed it firing only for `V4`.

The fix lives at that branch and does not touch the wire format: scale the index
by `Total_Slots (Elem_UT) * 8`, add the array's base if it is not already on the
stack, then mark `D.Base_On_Stack` so the next subscript chains from THAT address
instead of re-deriving the array's and dropping the row.

**How it was found, because it is the part worth repeating**: four attempts of
mine failed - three of them harness mistakes (stale line numbers, a regex that ate
real code, anchors that matched more than one site), not wrong hypotheses - and
the site was named in one read-only pass by the **explore subagent**, which could
read the whole designator/selector path without spending the editing budget on
rebuilds.  Two rules this item earned, now cheap to follow:

Both rules from this item are now repo-wide, in `AGENTS.md` under
"Probing the compiler: anchors, negatives, and sizing".

**Item 2 is already visible**: `Files.Rider`, an IMPORTED record
(`record f: File; pos: longint; eof: boolean; res: integer; cur: A1 end`) - so the
next question is how a record lays out when its description came from another
module.


### 3ad. DONE — item 2: a record with a LONGINT field, by value

The checklist called item 2 "an imported record (`Files.Rider`)".  The CAUSE is
more general and was measured, not guessed: `Fields_Allowed`'s list of whole-slot
scalars omitted `T_Long`, so ANY record with a `longint` field was refused -
imported or local - and `Files.Rider` (`f: File; pos: longint; eof: boolean;
res: integer; cur: A1`) was simply the first one the program met.

The measurement that settled it, and the reason it is worth recording:

    hello.ob2     CHK rec=Files.Rider fld='pos' typ=T_LONG scalar=FALSE   <- refused
    e3 (old probe) no CHK line at all, and it PASSED

`e3` declared only a POINTER to such a record.  The field rule runs only for a
variable whose type IS the record, so the old probe never exercised it - the same
blind spot as the `array of char` probes and the offset-0 probes, caught this time
because both cases were measured rather than one (the rule AGENTS.md now carries).

**Fixed** in all three slot lists - a record field, a fixed array's element, and a
standalone array variable's element - since a LONGINT is one whole slot in every
one of those positions.  **Fixture**: `tests/bc/longfield.ob2`, which declares the
record BY VALUE precisely so the rule runs, and cannot pass against a pointer-only
shape.

**Metric**: `hello.ob2` now refuses at

    'Greeting' is not a constant INTEGER expression, so its value cannot be pushed

- i.e. the whole TYPE BLOCK of a 530-line, 18-import program is now accepted, and
the next blocker is a different class: a `CONST` whose value the backend cannot
push.  That is item 3.

All seven suites green, 50 fixtures corroborated by both backends (up from 49),
zero warnings.


### 3ae. ITEM 3 MEASURED — a string constant resolves, but the print path crashes

`Greeting` is a string constant:

    const Greeting = "hello from Oberon-2";     (hello.ob2:39)
    Out.String (Greeting);                      (hello.ob2:178)

The refusal is for any `S_Const` that did not fold to an integer, and the backend
does have a pool (`O2c_BC.Push_Str`) - used for string LITERALS - but `Sym` had no
field for a constant's text, so there was nothing to push.

**Three measurements, and the first one was a mistake worth recording.**

    CONST Greeting lit=FALSE folds=FALSE typ=T_STR text='"hello from Oberon-2"'

A string constant arrives as `typ=T_STR` with its text QUOTED, and **`V.Lit` is
FALSE** for a string - so the first capture, guarded on `V.Lit`, silently never
fired and the refusal stayed.  That is the "guard that cannot be true" mistake,
and the trace is what exposed it (the refusal alone looked like the fix doing
nothing).

**With the guard corrected the const resolves**: the progress metric moved off
`Greeting` entirely.  But the EMISSION crashes:

    raised CONSTRAINT_ERROR : o2c_compiler.adb:9066 index check failed

so `Out.String` on a constant takes a path that indexes something a
pool-pushed value does not satisfy.  `R.CStr := True` - the marker that serves a
whole-array-of-char variable - is evidently not what that path needs for a
constant, and a string LITERAL is the control case that says so: literals work,
and they set whatever is missing.  Reading 9066 against the literal path is the
next step, and it is one comparison, not a hunt.

**Reverted**, because a compiler that raises is worse than one that refuses, and
the item stays refused meanwhile.


### 3af. ITEM 3 — the refusal is gone, the VALUE is wrong; reverted

With the string-constant path in place the refusal disappears and the progress
metric advances again:

    hello.ob2:  'Greeting' ... -> 'Geom.Sqr is not yet supported'

but the fixture, which is what actually decides, prints the WRONG value:

    expected:  hello from Oberon-2
               again hello from Oberon-2
    measured:  0
               0 0

`0` is `Push_Int (Const_Val)` - the integer path, i.e. `Const_Text` was empty, so
the guard `Length (Const_Text) = 0` was true and the pool push never ran.  So the
capture at the declaration still does not fire, even though the 3ae trace showed
`text='"hello from Oberon-2"'` at that very point and the capture is inserted after
the symbol aggregate, not before it.  That is the remaining question and it is a
one-print answer: report `Length (Syms (N_Sym).Const_Text)` immediately after the
capture, and `Is_Open` / `AU` / `N` / `CArg` inside the `Out.String` handler.

Two things this attempt settled, both worth keeping:

- the `Out.String` handler indexed `UTypes (AU)` with `AU = 0` for anything that
  has no user type - an open array, and now a string constant pushed as a pool
  string.  Its own `AU > 0` test two lines below already assumed a guard that was
  missing from the `N` computation, and that asymmetry is what raised
  `CONSTRAINT_ERROR ... index check failed` the moment a constant was accepted;
- an early `return R` in the factor path is NOT equivalent to falling through: the
  shared tail consumes the identifier with `Next` and sets `R.Text`, and skipping
  it produced `expected ')' ... found ident 'Greeting'`.  The push has to be
  suppressed (a guard on the integer push), not short-circuited.

Reverted: a wrong answer is worse than a refusal, which is the whole point of this
backend.  Item 3 stays refused.

Fixture, kept here until it can pass (a registered fixture that cannot compile
breaks `run_bc`, which is why it did not stay in `tests/bc/`):

    module Strconst;
    import Out;
    const Greeting = "hello from Oberon-2";
    const Twice = "again";
    begin
      Out.String(Greeting); Out.Ln;
      Out.String(Twice); Out.Char(" "); Out.String(Greeting); Out.Ln
    end Strconst.

    golden:  hello from Oberon-2
             again hello from Oberon-2


### 3ag. ITEM 3 — three fixes, no change; handed to the subagent

The string-constant path now fires on both sides, proven by traces:

    CAPTURED 'Greeting' len= 21 text='"hello from Oberon-2"'
    USECONST 'Greeting' len= 21        (x3, once per use)

and `Out.String` still prints `0` - while the CONTROL case,
`Out.String ("a literal")`, prints its text.  Three further edits changed nothing:

- `R.CStr := False` (mirroring the literal, measured as typ=T_STR lit=FALSE
  cstr=FALSE against my cstr=TRUE) - no change;
- excluding `S_Const` from the `Find (A.Text) > 0` block in the `Out.String`
  handler, since a constant is not a variable and the literal never enters that
  block at all - no change;
- the `UTypes (AU)` guard for `AU = 0`.

The traces firing is what rules out the "edit silently did nothing" explanation:
these edits ARE in the compiler, and the behaviour is unchanged anyway.  Which
means the emission that produces `0` is somewhere else entirely, and I have been
guessing at code paths in an 11k-line front end for three turns - the identical
situation to item 1, which ended only when the question was handed to a read-only
pass.

So: reverted (a wrong answer must not land), and the question is now precise and
narrow enough to hand over:

    For `Out.String (<string CONST>)` in bytecode mode, where is the `0`
    emitted?  The argument's text IS interned with O2c_BC.Push_Str at the use
    site, and `Out.String ("literal")` works.  Find the code that emits the call
    for each of those two arguments and report the difference.

The fixture and its golden stay in 3af until a fix passes them.


### 3ah. DONE — item 3: string constants

A named string constant now works: `Out.String (Greeting)` prints its text.
Fixture `tests/bc/strconst.ob2` with a hand-computed golden, corroborated by both
backends (51 fixtures corroborated, up from 50).

**The fix is three parts**, and one of them is the whole bug:

1. `Const_Text : Unbounded_String` on the symbol record - a constant is not
   storage, so a string one travels as its text, exactly as a literal does;
2. the capture at the declaration, guarded on `V.Typ = T_Str` and NOT on
   `V.Lit`, which is measured FALSE for a string constant - the guard that could
   not be true;
3. the push at the use site, mirroring a LITERAL's shape: `Push_Str`, `CStr =
   False` (a literal is `cstr=FALSE`; `CStr` means "a whole ARRAY OF CHAR
   VARIABLE"), and - the decisive part - **the shared tail's two jobs, `Next`
   and `return`, done inside the branch**.

**Why that last part is the bug**, from the read-only pass: without it, control
fell through to the shared identifier tail's `Bc_Load`, which minted a ZERO global
and pushed `0` on top of the pool offset.  Native 1 pops one operand, took the 0,
and printed it:

    literal:  [LOAD_CONST <offset>, CALL_NATIVE 1,1]
    constant: [LOAD_CONST <offset>, LOAD_G <slot>, CALL_NATIVE 1,1]   <- extra

Two smaller real bugs fell out on the way: `Out.String` computed
`UTypes (AU).Arr_Len` with `AU = 0` for anything with no user type of its own -
its own `AU > 0` test two lines below already assumed that guard - and an early
`return R` in the factor path is NOT equivalent to falling through, because the
tail consumes the identifier with `Next`; skipping that produced
`expected ')' ... found ident`.

**Method note.** Three edits produced no observable change and the traces proved
they were in the compiler - so the emission was elsewhere and guessing had failed.
Handing the read-only question to the `explore` subagent named it in one pass, for
the second time (item 1 was the first).  That is now the established move for a
stall in this front end, and it is cheaper than a fourth guess.

**Metric**: `hello.ob2` now refuses at `Geom.Sqr is not yet supported` - the type
block and the constant are behind us, and the next item is a USER LIBRARY
procedure call, which is a different class from everything in 3w-3ah.  Its size is
not yet measured, and per the sizing rule it should be measured before it is
worked.


### 3ai. ITEM 4 SIZED — it is 3d, and it is milestone work

Measured before working it (the sizing rule), and the answer changes the plan.

**Why `Geom.Sqr` refuses**: the factor path's default refusal, i.e. its export
carries no bytecode id.  User libraries are compiled in ADA mode by
`Compile_Multi` - they are compiled *before* `Begin_Mode`, exactly as the builtins
were before 3m - so none of their procedures has an id.

**Libraries are NOT blocked by type coverage**: in library shape, `geom.ob2`
compiles to bytecode (856 bytes).  Two earlier attempts at this measurement were
harness artifacts of mine, both worth recording because they are the same two
mistakes already in AGENTS.md:

- compiling a library AS A MAIN MODULE gives M20 export errors
  (`exported VARIABLE 'origin': its RECORD type must be exported`), which is an
  artifact of the shape, not a property of the source;
- `sed 's/\*//g'` to strip export marks also strips MULTIPLICATION operators, so
  `x * x` became `x  x` and the compile died as `'k' is not a declared
  procedure`.  Stripping `*` only when it follows an identifier char, and
  checking `grep -n "x \* x"` afterwards, gives a harness that is actually the
  one intended.

**So item 4 is 3d.**  It needs:

    (a) user libraries compiled in bytecode mode - a Compile_Multi ordering
        change, the same SHAPE as the builtin scoping of 3m, whose compilation
        half is already landed (End_Body, 3m);
    (b) the cross-module VALUE TRANSPORT defect that 3d is parked on - measured
        there as: identical LOCAL shapes work (e1/e2/e3), cross-module returns a
        wrong value (u3) or a malformed image (u4).

That is milestone-sized, not a checklist item, and it is the same defect that
already defeated one attempt.  Recording it here rather than starting it: the
work is worth doing with the tools now available (the export-id threading landed
in 3l, the `explore` subagent has since named two sites in one pass each, and u3
and u4 are small reproductions), but it is a decision about where to spend a
milestone, not a next-step.

Metric unchanged: `hello.ob2` refuses at `Geom.Sqr`.


### 3aj. AUDIT — BLOCK: three widened acceptances, two of them high

An independent review of `git diff 37ebb6e..HEAD -- compiler/ vm/` (the
bytecode-mode and type-coverage work) returns **block**, and the findings are the
class the suites cannot see: new acceptances that can emit a WRONG VALUE where the
old code refused.

BLOCKING

1. o2c_compiler.adb:1105 (high).  `Fields_Allowed` now accepts a record field that
   is `ARRAY OF <user type>` (1315-1321), but `Total_Slots`' FIELD-array arm still
   sizes such a field as `N + Arr_Len` instead of
   `Arr_Len * Total_Slots (Elem_UT)` - the standalone-array arm (1081-1084) does it
   right.  So
       TYPE T = RECORD x, y: INTEGER END;
            P = RECORD a: ARRAY 2 OF T; b: INTEGER END
   gets Total_Slots(P) = 3 instead of 5, and `b` is placed inside `a`'s second row:
   silent aliasing and an undersized run where the old code refused.  This is 3ac's
   fix applied to one arm and not its sibling - the same asymmetry as the `AU > 0`
   case in 3ah, in my own work.

2. o2c_compiler.adb:2093 (high).  The row-stride block added in 3ac re-derives the
   base with NONE of the handling its sibling (2057-2071) was fixed for: no
   `Nested`, no `Is_Ptr` test.  For `p^.field[i]` with a field that is an array of
   records, `Base_On_Stack` is False and `Nested > 0`, so it calls `Global_Array`
   with `Total_Slots (pointer) = 0` (the "needs a non-zero length" refusal the
   2048-2056 comment says was fixed), and where the address IS already on the stack
   it adds the global base ON TOP of the offset address - wrong address plus a
   stray stack value.

3. o2c_compiler.adb:5091 (medium).  The const capture keys on `Typ = T_Str and
   Length (Text) > 0`, but `T_Str` is produced by non-literal paths too (3564,
   4138, 4184, 4868).  The use site (4255-4261) strips quotes only when both ends
   are `"`, otherwise it pushes the raw Ada text; an embedded doubled quote is
   never un-doubled.  The fixture uses the constant only with `Out.String`, so
   nothing covers it.  Review's own caveat: it could not positively trigger this -
   a `CONST t = s` chain appears to refuse because `R.Text` stays empty in bytecode
   mode - so the fix is to capture only on a genuine literal and refuse otherwise.

NON-BLOCKING: the removed char-index block is correctly folded into the array arm,
so nothing newly dead; `Ok_Arr` is properly guarded and a pointer element cannot
reach the stride-0 path; the `Depth > 8` guard is unreachable for arrays but
recursive array types cannot be declared, so no unbounded recursion was added.

REQUIRED, in the audit's words: recurse in the FIELD-array arm of `Total_Slots`;
give the row-stride block the same base derivation as its sibling; capture
`Const_Text` only for a genuine literal and refuse when a `T_Str` constant has none;
and add the fixtures the suites cannot see - an array-of-multi-slot-record field,
`p^.arrOfRecord[i]`, and a non-literal string constant.

So the stretch's tree is green by its tests and NOT trustworthy: three of the seven
changes widened what is accepted, and only the first fixture of each shape exists.
Nothing here is reverted yet; the two high findings are the next work, with their
fixtures, before any milestone.

### 3ak. AUDIT FIXES — attempted, reverted, and the two results identify the shape

Attempted all three of the audit's findings and reverted, because one of them
regressed a landed fixture.

1. `Total_Slots`' field-array arm -> recurse (`N := N + Total_Slots (field, Depth+1)`)
   instead of adding `Arr_Len`.  Compiles; `recarr` prints NOTHING.
   A measurement gap of mine: I discarded the VM's stderr, so "nothing" may be a
   trap.  The next attempt captures both streams - never conclude from a truncated
   failure.

2. The row-stride block derives its base as the scalar sibling does
   (`not Is_Ptr and then not Base_On_Stack -> Load_Addr_G (Global_Array (...) +
   Nested/8)`, else `Nested`).  **`ptrarr` passes** - the intent is right - but
   `nestedarr`, a landed fixture, then MISMATCHES.

3. Capture `Const_Text` only for a genuinely quoted literal (else the constant
   takes the loud refusal).  Untested: nothing exercises it yet.

**What the two results say together** is the useful part.  #2 works where the base
is a POINTER (`ptrarr`, where the sibling block does not run) and breaks where it
is a standalone array (`nestedarr`, where it evidently DOES).  So the sibling block
and mine are both satisfied at once, and the base is pushed twice.  The audit read
the control flow as "the sibling does not run for a user-typed element"; the
`nestedarr` regression says otherwise, at least for a standalone array.

So the fix is not a mirror, it is a SHARING: put the base derivation in the
sibling's own block - where it is already correct and already runs - and leave only
the row SCALING (`Push_Int (row bytes); Mul; Add; Base_On_Stack := True`) in the
user-element branch.  That is one edit instead of a duplicate, and it cannot
double-push by construction.

Fixtures for the next attempt (kept here; NOT in tests/bc/, because a registered
fixture that cannot compile - or that fails like `recarr` did - breaks run_bc, and
the differential globs tests/bc/*.out, so a stray golden breaks that too):

    module Recarr;                       (* record field that is an array of records *)
    import Out;
    type T = record x, y: integer end;
    type A2T = array 2 of T;             (* the type must be NAMED: an inline
                                            `a: array 2 of T` field is refused
                                            with "a field type expected" *)
    type P = record a: A2T; b: integer end;
    var r: P;
    begin
       r.a[0].x := 1; r.a[0].y := 2;
       r.a[1].x := 3; r.a[1].y := 4;
       r.b := 5;
       Out.Int(r.a[0].x, 1); Out.Char(" ");
       Out.Int(r.a[0].y, 1); Out.Char(" ");
       Out.Int(r.a[1].x, 1); Out.Char(" ");
       Out.Int(r.a[1].y, 1); Out.Char(" ");
       Out.Int(r.b, 1); Out.Ln
    end Recarr.                          (* golden: 1 2 3 4 5 *)

    module Ptrarr;                       (* the same, through a pointer *)
    import Out;
    type T = record x, y: integer end;
    type A2T = array 2 of T;
    type P = record a: A2T; b: integer end;
    type PP = pointer to P;
    var p: PP;
    begin
       new(p);
       p^.a[0].x := 6; p^.a[1].y := 7; p^.b := 8;
       Out.Int(p^.a[0].x, 1); Out.Char(" ");
       Out.Int(p^.a[1].y, 1); Out.Char(" ");
       Out.Int(p^.b, 1); Out.Ln
    end Ptrarr.                          (* golden: 6 7 8 *)

Both findings stay OPEN until those two fixtures pass, and `nestedarr` must still
pass with them.

### 3al. AUDIT FIXES, attempt 3 — two mechanisms pinned by measurement

Attempted again and reverted again, but this round produced MEASUREMENTS that pin
the mechanism, which the first two rounds did not.

**Measured 1: removing the base derivation from the user-element branch breaks a
landed fixture.**  With only the scaling left (`Push_Int (row bytes); Mul; Add`),
`nestedarr` fails with `vm: operand-stack depth violation`.  So the SCALAR SIBLING
BLOCK DOES NOT PUSH THE BASE for a user-typed element, and the branch must derive
it itself.  That contradicts 3ak's inference (drawn from `nestedarr` regressing
there) and settles the question in the opposite direction.

**Measured 2: the pointer-field case never reached the branch at all.**  In the
unfixed tree, `p^.a[0].x` refuses with

    bytecode error: an array needs a non-zero length

which is `Global_Array` being handed a POINTER's `Total_Slots` - zero.  That is
exactly what the audit predicted for its finding 2, now observed rather than
argued.

**So the fix is neither of the two attempted shapes**: derive the base in this
branch - as 3ac did, since nothing else will - but derive it the way the sibling
does, with the `Is_Ptr` and `Nested` handling, instead of calling `Global_Array`
on whatever the base type happens to be.  That is the audit's required change
verbatim; what failed was my two approximations of it, and the reason is visible
now: 3ak's version applied the sibling's `+ Nested/8` term to a case where the
sibling had already contributed nothing, and this round removed the derivation
outright on the strength of an inference the depth violation disproves.

**The next step is an instrumented run, not another patch**: print
`D.Base_On_Stack`, `Nested`, whether the base is on the stack at the scaling, and
the base type's `Is_Ptr`/`Total_Slots`, for BOTH `nestedarr`'s `m[i][j]` and
`recarr`'s `p^.a[i]`.  One print answers what three patches have not: which of the
two cases reaches the branch with a base, and which needs one built.

`recarr` and `ptrarr` fixtures remain in 3ak as sources.  Both findings stay OPEN,
and `nestedarr` must pass with them.

### 3am. AUDIT FIX 2 (high) — the pointer-field base, FIXED and corroborated

The instrumented run that 3al asked for gave the incoming state for both shapes,
and that is what settled it:

    standalone array (nestedarr):  base_ptr=FALSE base_slots=8  nothing on the stack
    pointer field    (recarr):     base_ptr=TRUE  base_slots=0  -> Global_Array

For the pointer field the base is a POINTER, so `Global_Array` was being handed
`Total_Slots (pointer) = 0` - the refusal "an array needs a non-zero length" WAS
the bug, exactly as the audit predicted.  The branch now derives the base the way
the scalar sibling does: the whole run at the walked slot when the base is not a
pointer and nothing is on the stack, `Nested` when there is an offset, and
otherwise the address the chain already has.

Landed with `tests/bc/recarr.ob2` (the pointer half), corroborated by BOTH
backends - 52 fixtures now, up from 51 - and every regression guard still passes:
`nestedarr`, `longfield`, `strconst`, `lenopen`, `filesintr`.

Two things about the way this one landed:

- the differential refused the fixture at first with `"p" conflicts with
  declaration at line 20` - Ada being case-insensitive, so `type P` collides with
  `var p`, which is the documented Ada-side limit that recmix/recreal are recorded
  for.  Rather than record another limit, the fixture was RENAMED (`PRec`, `ptr`),
  so it now corroborates instead of documenting a limitation;
- three attempts failed before this one, and what made the third work was a
  measurement rather than a patch: the incoming state of the branch for both
  shapes.  My two earlier attempts were approximations of the audit's required
  shape, and both were wrong in ways only that state could show.

### STILL OPEN - audit finding 1 (high): a record field that is an array of records

By value, the same shape still mis-sizes:

    type T = record x, y: integer end;
    type A2T = array 2 of T;                  (* two slots per element *)
    type PRec = record a: A2T; b: integer end;
    var r: PRec;
    (* r.a[0].x := 1; r.a[0].y := 2; r.a[1].x := 3; r.a[1].y := 4; r.b := 5 *)

    observed:  1 5 3 4 5        expected:  1 2 3 4 5

`b` reads back as `a[0].y`'s value, so `b`'s offset IS `a[0].y`'s: `Total_Slots
(A2T)` is still 2, not `2 * Total_Slots (T)` = 4.  The field-arm edit that makes
it recurse is in the tree, so the next question is measured, not guessed: is that
arm even reached for an array field, or does the offset come from elsewhere?

Its source is kept here and NOT in tests/bc/, because it fails and a failing
fixture breaks run_bc.

### 3an. PLAN — the IR refactor (M53's missing layer)

Decision: build the IR.  M53 records the architecture as STACK bytecode with a
THREE-ADDRESS IR underneath; the measurements below are that layer's absence.

    compiler/o2c_compiler.adb   12,263 lines   (parser + Ada backend + bytecode)
    O2c_BC.Bytecode_Mode           122 sites
    O2c_BC.* emitter calls         498         (from inside the parser)
    Append_Body                     87
    bytecode refusal strings        51         (hand-maintained, not derived)
    Parse_Factor                 1,753 lines, 105 emitter calls in it

So emission is inline in the recursive-descent parser, the two backends
interleave per construct, and there is no intermediate form.  What that costs,
measured this session: the silent-no-emission class is *inevitable* (nothing
forces a second code path to exist and "no case" is indistinguishable from "no
code"), and the calling convention is duplicated across sibling branches with
ad-hoc state (`D.Base_On_Stack`, `Nested`) - which is why one base-derivation fix
took three attempts.

**Target shape.**  A three-address IR (quads) with typed values, built by the
front end and consumed by the backend.  A LOWERING pass goes quads -> stack
ops, and that pass is where the calling convention lives - in ONE place, which
is the whole point.  The walker is TOTAL over node kinds, so an unhandled
construct is a compile error in the compiler rather than a silent image.

**Migration, stage by stage, each independently landable.**  The 51 fixtures
corroborated by BOTH backends are the regression net for every step, and the Ada
path keeps working throughout (the differential is the arbiter).

    M1  the seam: compiler/o2c_ir.ads/.adb - IR types, builders, a walker
        interface.  NO parser changes, so no fixture can move.  Lands alone.
    M2  one construct end to end: a scalar assignment to a local.  The parse
        builds IR for it and the bytecode for it is emitted FROM the IR; every
        other construct still goes through the inline path.  Proves the seam.
    M3  designators and subscripts - migrated first on purpose, because that is
        where the duplicated base derivation and the calling convention live.
    M4  calls, including the cross-module case that 3d is parked on: the
        convention moves into the lowering pass and stops being per-branch.
    M5  statements, then expressions, then the type/layout layer.
    M6  optionally, the Ada backend emits from the IR too - or is retired, which
        M53 already anticipates.

**Risks, named.**

- Two paths exist during migration.  Mitigated by one construct per commit and
  by the fixture net; the risk is real and it is the price of landing per stage
  instead of in one big step.
- A three-address IR needs the lowering pass to do real work (temporaries,
  evaluation order, stack discipline).  That is NEW work, not a reshuffle - and
  it is also the only place that can fix the class of bug that cost 3x.
- The Ada path must not move.  The differential arbitrates every step.

**Preconditions before M1.**  Close the two open silent-wrong findings, because
refactoring around a path that answers wrongly risks keeping it:

    1. the array-of-record FIELD size (Total_Slots (A2T) = 2, must be 4) - 3am;
    2. the const capture keyed on T_Str rather than a genuine literal - 3am/3aj.

Both are small, both are layout/front-end rather than IR, and both are the class
that must not be carried into the new pipeline.

### 3ao. PRECONDITIONS CLOSED — and the root cause was a THIRD copy of one rule

The two silent-wrong findings that gate the IR plan are closed, and the first one's
cause is the disease the plan exists to cure.

**Audit finding 1 (high) - the array-of-record field size.**  Root cause measured:
`Field_Offset` placed a field as `(N + F - 1) * 8`, i.e. **one slot per FIELD**,
ignoring `Total_Slots` entirely.  So in

    PRec = record a: A2T; b: integer end      (A2T = array 2 of a two-slot record)

`b` was placed at byte 8 - inside a[0], on top of a[0].y - which is exactly the
observed `1 5 3 4 5`.  That is a THIRD copy of the layout arithmetic, alongside
Total_Slots' array arm and its field arm; the field-arm edit of 3am changed nothing
because the offset never came from there.

Fixed by extracting `Field_Slots` - the ONE place the rule lives - and having BOTH
`Total_Slots` and `Field_Offset` call it, so they cannot disagree again.  Verified:
the reproduction prints `1 2 3 4 5`, and `tests/bc/recarr.ob2` now covers the
by-value half as well as the pointer half (golden `1 2 3 4 5` then `6 7 8`),
corroborated by both backends.

**Audit finding 3 (medium) - the const capture.**  Now requires a genuinely quoted
literal; a `T_Str` produced by any other path leaves `Const_Text` empty, so the
constant takes the loud refusal instead of pushing non-literal text as pool data.
`tests/bc/strconst.ob2` still passes, so the legitimate case is unaffected.

**Why this is the plan's pattern in miniature.**  Finding 1 was not a missing
feature or a slip: it was one rule written three times, and the fix was to write it
once where both callers must use it.  That is exactly what M3 of 3an does for the
base derivation, and what the lowering pass does for the calling convention.  A
small proof that the direction pays.

The IR plan's preconditions are therefore met and **M1 (the seam) is unblocked**.
All seven suites green, 52 fixtures corroborated by both backends, zero warnings.

### 3ap. M1a DONE - the IR seam lands, and nothing moves

`compiler/o2c_ir.ads/.adb` exist: the three-address IR over typed values, with a
closed `Op` set, builders, and the iteration interface a backend will walk.

    type Op is (Op_Nop, Op_Copy, Op_Add..Op_Ge, Op_Not/And/Or,
                Op_Load, Op_Store, Op_Addr_Local, Op_Addr_Global,
                Op_Label, Op_Jump, Op_Jump_False,
                Op_Arg, Op_Call, Op_Return, Op_Halt);

The set is CLOSED on purpose: every consumer cases over it, so an op with no
lowering is a build error in the consumer instead of a silently empty image -
which is the structural fix this whole plan exists for.  `Op_Arg` quads keep
calls three-address rather than needing an argument list in the quad.

The tables are HEAP-allocated and sized by `Init`: the compiler itself runs in
the guest, whose user stack is 256 KiB, so nothing large is declared statically.
Overflow is reported, never truncated, and the initial capacity is deliberately
modest (4_096 values / 16_384 quads / 1_024 labels) because M1 has no consumer
yet - sized for M2, to be revisited with a written justification when one
arrives, per the project's capacity rule.

**Reachability.**  `Init` is called once from `Compile_Multi`.  That is not
decoration: gprbuild compiles only what a main can reach, so an unreached unit
passes while checking nothing (AGENTS.md), and the call is behaviour-neutral.

**Verification.**  All seven suites green with 52 fixtures corroborated by both
backends - UNCHANGED, which is the point: M1a adds no behaviour and no fixture
may move.  Zero warnings.

**Two Ada rules that cost two builds here, both worth carrying forward**, since
the IR will declare more subprograms:

- a body that completes a declaration must repeat the spec's default
  expression, and it must match TEXTUALLY.  `Max_Values : Natural := 4_096` in
  the spec against `:= Default_Values` in the body is a mismatch even though the
  constant is that literal - which is why the body now uses the literal too;
- a forward declaration with a default plus a body with the same default is
  fine (that is how `Total_Slots`/`Field_Slots` were made mutually recursive),
  so the rule is about the pair being identical, not about where the default is
  written.

**M1b, next**: a host self-test that builds a small quad stream and checks the
dump, so the builders are VERIFIED rather than merely compiled - M1a's evidence
is that nothing changed, which is the right evidence for a seam and not enough
for a builder.

### 3aq. M1b DONE - the builders are verified, and the test caught its own bugs

`tools/o2c_ir_selftest.adb` builds a small quad stream, checks what came back,
and checks the two paths that must RAISE rather than answer.  It runs from
`tests/run_bc.sh`, so the 7-suite driver is unchanged and the builders can no
longer be "compiled but wrong":

    t := 7 ; *g := t ; L1: L2-independent ; t2 := t < 7 ; if !t2 goto L2 ;
    return t ; L2: halt

    AR 1  OP_COPY d= 2 s1= 1 ...  AR 8  OP_HALT d= 0 s1= 0 s2= 0

Checks: the quad count and each quad's op/dst/srcs in order (three-address, so
no operand is implied), the value kinds and payloads (the integer constant is 7,
a temp is one slot, a global kept its name, a label value is a label),
`Begin_Proc` restarting value numbering while KEEPING the quad stream, a
value-capacity overrun raising rather than truncating (the project's rule for
capacity tables), and an out-of-range quad id raising rather than being answered.

**The tool caught two bugs of its own on first run**, which is the evidence that
it is not a no-op: a `LV` that was declared and read but never assigned, and my
own quad arithmetic (eight quads emitted, nine asserted).  Both were fixed before
it passed - a self-test that passes first time on code nobody has run is usually
a self-test checking nothing, and this one demonstrably was not.

Zero warnings, all seven suites green, 52 fixtures corroborated by both backends.

**M2 next**: one construct end to end - a scalar assignment to a local - with the
parser building IR for it and its bytecode emitted FROM the IR, everything else
still inline.  That is where the seam starts to carry weight.

### 3ar. M2a DONE - the lowering pass, verified against the real emitter

`compiler/o2c_ir_lower.ads/.adb`: IR quads -> the bytecode emitter, in ONE place,
which is where the calling convention and the stack discipline will live instead
of being duplicated per branch in the parser.

Two design points that are the point of the whole exercise:

- **no `others` arm.**  `case Q.Op is` enumerates every member, so adding an Op
  to the IR without deciding how it lowers is a COMPILE ERROR here rather than a
  silently empty image.  That property only holds while there is no `others`, and
  it is the reason the op set is closed;
- **only `Op_Copy` is lowered**, and every other op says so by name:
  "O2c_Ir_Lower: OP_JUMP has no lowering yet".  Ops arrive with the construct
  that needs them, one stage at a time, so nothing here is an unverified arm.

**Verified against the real emitter**, in the self-test that already ran from
`tests/run_bc.sh`: `x := 5` (a quad the front end will build in M2b) lowers to
exactly two instructions, a global store lowers to two, the lowerer counts what
it did (so "the IR path ran" is a number rather than an assumption), and an op
with no lowering RAISES rather than passing.

**And it ran red before it ran green**, which is the useful part: interning a
local allocates a frame slot, so `O2c_BC.Local` requires an OPEN procedure, and
the test had it before `Begin_Proc`.  That is not a test detail - the compiler
must respect the same contract in M2b, and it is exactly the kind of ambient
requirement the old inline structure kept implicit, where it was invisible.

Three more context clauses were the compiler's to name, not mine to guess:
`with O2c_Ir` in the spec, `with O2c_Bc` and `use Ada.Strings.Unbounded` in the
body - the second because a spec's `use` does not reach its body.

All seven suites green, 52 fixtures corroborated by both backends, zero warnings.

**M2b next**: the parser builds IR for `x := <int literal>` with `x` a scalar
local, and its bytecode comes FROM the IR - the first construct whose evidence is
behavioural rather than structural.

### 3as. M2b DONE - the first construct runs through the IR

`x := <short integer literal>`, with x a scalar INTEGER variable, now builds a
quad in the parse and gets its bytecode FROM THE LOWERING: the inline
`Push_Int` + `Bc_Store` is not used for that shape at all.  Everything else takes
the old path unchanged.

**The narrowness is deliberate and written down in the code**, both bounds having
a reason rather than being guesses:

    * the literal must be SHORT (<= 9 digits), so `Integer'Value` in the IR path
      cannot raise where the inline path refuses cleanly - the inline path's
      behaviour for an over-long literal is a refusal, and a crash here would be
      a different answer to the same input;
    * x must be a scalar INTEGER (UT = 0), so nothing about pointers, records or
      real conversion is in play yet.

**Evidence that it RAN** - a temporary trace, which is the question a passing
suite cannot answer by itself:

    IR-ASSIGN i := 1     (lowered= 1)      <- sum.ob2
    IR-ASSIGN sum := 0   (lowered= 2)
    ...7 assignments through the IR in loopexit.ob2

The count comes from `O2c_Ir_Lower.Lowered`, so "the IR path ran" is a number
rather than an assumption.  The trace was then removed: a measurement, not
permanent noise.

**Evidence that it is RIGHT** - the whole corpus, because dozens of fixtures
contain exactly this statement:

    all seven suites green, 52 fixtures corroborated by BOTH backends

So the bytecode the lowering produced for the migrated construct is
behaviourally identical to what the inline path produced, across every fixture
that uses the shape - the first migration whose evidence is behavioural rather
than structural.  The Ada path is untouched (its text is still appended), so the
differential remains the arbiter.

One fact learned on the way: the lexer's token for an integer literal is
`Lex.Tok_Number`, not `Tok_Int` - the compiler said so, which is cheaper than my
having guessed it.

**Next, M3**: designators and subscripts, first on purpose - that is where the
duplicated base derivation and the calling convention live, and where one fix
took three attempts because the same rule was written in three places.

### 3at. M3a DONE - the base arithmetic has one home, and it is measurable

The base-derivation block existed in TWO copies in the parser.  Both now call
`O2c_Ir_Lower.Push_Base`, and the claim is checkable rather than rhetorical:

    Nested / 8   in compiler/o2c_compiler.adb ....... 0
    Nested / 8   in compiler/o2c_ir_lower.adb ....... 1

Those copies had disagreed, which is the whole reason this is worth doing: one
used a POINTER's `Total_Slots` - zero - so `ptr^.a[i]` refused outright with "an
array needs a non-zero length", and their shared ancestor had sized a record field
as one slot, so a field aliased the array before it.  One rule written three times,
each copy with its own idea of what a slot is.  Now: one rule, one place, with the
LOWERER owning it - so when designators do migrate, the lowering reuses this
rather than growing a fourth copy.

`Push_Base`'s signature is the interesting part: it takes `Global_Slots` (0 meaning
"the address is already on the stack"), `Nested` and the name.  The type model
stays where it belongs - the CALLER computes `Total_Slots`, because the lowerer
must not grow a dependency on `UTypes`.

**Verified** by the six guards that exercise both branches - `nestedarr` (the
standalone, user-typed element case), `recarr` (the pointer-field case),
`longfield`, `strconst`, `lenopen`, `filesintr` - all unchanged, plus the suites.
The change emits the same instructions; it moves them, it does not alter them.

**Process note, because it cost two attempts**: I twice wrote a replacement
expecting the two copies to be textually identical, and they were not - one had
comments inside the block, the other a different indentation.  The `assert` on the
occurrence count caught both BEFORE anything was written, so the tree never held a
half-applied patch.  "Measure, do not assume" applies to my own edits as much as to
the compiler's behaviour.

Next in M3: the calling convention, the other half of what is duplicated.

### 3au. M3b SIZED - the calling convention is duplicated TWICE, and in two shapes

Measured before touching it, because "the other half of what is duplicated" turned
out to be bigger than the phrase suggests:

    Parse_Expr        3,393 lines      where the call sites live
    Parse_Factor      1,753 lines
    Parse_Actual        150 lines      the argument convention - ONE home, good
    Call_Proc             2 sites      factor 3677 / statement 3829
    Native_Call        12+ sites       split across BOTH paths

The `Native_Call` list is the finding.  The same intrinsic families are dispatched
TWICE - once in the factor path (3193, 3389, 3713, 3743) and once in the statement
path (7409, 7443, 7706, 7739, 7767, 7797, 7832, 7878) - so every new intrinsic has
to be wired in two places, and the two can drift.  That is the same shape as the
base-derivation rule that was written three times (3ak-3at), one level up.

**Why it is not a small step.**  The two `Call_Proc` sites are structurally
different, not copies: the factor path resolves an EXPORT record and calls
`Xs (XI).Bc`, while the statement path resolves a local symbol, checks
`Foreign_Native` first, and falls back to `Syms (Idx).Bc_Proc`.  Unifying them means
deciding what a call site is, and that decision is exactly what the IR's `Op_Arg` /
`Op_Call` pair exists to carry - both are in the op set and both explicitly say
"has no lowering yet", which is the tracked reminder rather than a note.

**So the order, cheapest and best-covered first:**

    1. the `Out` family - the most-used, and present in EVERY fixture, so the
       52-corroborated net covers a mistake here immediately;
    2. the intrinsic families one at a time - Files, Env, Args, XYplane, In,
       Convert - each landing alone, each gated;
    3. the two `Call_Proc` paths LAST, because that is where 3d's cross-module
       transport defect lives and it needs the transport work first.

`Parse_Actual` is already the right shape (one home, six callers), so the argument
convention needs consolidating INTO it rather than extracting from scratch - the
cheapest piece of the whole area, and the first thing to look at when step 1 starts.

### 3av. M3b step 1 - the duplication CONFIRMED, and the region count is the gap

3au claimed the same intrinsic families are dispatched twice.  Confirmed with an
instance rather than left as inference:

    Native_Call (9, 1)     Files.Delete
      at 7409
      at 7767              <- the same call, the same arguments, two sites

So the claim holds.  What 3au got wrong is the SHAPE of it: the ids at 7409, 7443,
7706, 7739, 7767, 7797, 7832 and 7878 all sit BELOW the `Out` check at 9029, so
those two `Out`-keyed regions are not the pair - there appear to be at least THREE
places that dispatch module members:

    the factor / expression path        (~3150-3800, where Files FRead/FWrite/FClose
                                         live at the ids I added in 3l)
    a statement region                  (~7400-7900)
    the `Out`-headed statement dispatch (~9029-9220)

**Which is why the next step is the MAP and not an extraction.**  Consolidating the
pair I *thought* was the pair would extract the wrong thing, and this session has
already shown what that costs: 3ak patched a branch three times because the branch
that mattered was elsewhere.  Three short reads - the head of each region, to see
what keys it and what it emits - turn that into a known set, and then step 1 (the
`Out` family) is a pair with names rather than a guess.

Nothing landed in code this round, and that is the deliberate part: the evidence
said the target had moved.

### 3aw. THE MAP - 36 dispatch gates, three runtime regions, and one question

Every module-name comparison that gates a dispatch, grouped:

    ~3130, 3364          Mod_Name = "Files"    the intrinsic arms added in 3l -
                                              FStat/FRead/FWrite/FClose - plus
    3687-3741            XYplane                XYplane, all in the FACTOR path
    ~7198                 Env                  statement region A
    ~7383, 7414           Files
    ~7673                 Convert              statement region B
    ~7740, 7768           Files
    ~7798                 Env
    ~7836                 Args
    ~7880                 In
    ~7947-7985            XYplane
    10318-10918          Mod_Name = "Files"/"Env"   spec + manifest generation:
                                              NOT runtime dispatch, out of scope

So the runtime duplication is in THREE regions, not two, and the pair that names
itself is **Files in statement regions A and B** - both statement-shaped, both
dispatching the same ids (`Native_Call (9, 1)` at 7409 and again at 7767,
byte-identical).  That is step 1's target, now named rather than guessed.

**One question must be settled first**: there are TWO statement regions, ~7198-7515
and ~7673-7990, which is itself a smell - either one supersedes the other (dead
code kept alive by habit, which the suites would not notice if both are reachable),
or they serve genuinely different statement forms, in which case merging them
without understanding the difference is how a working path gets deleted.  The heads
of the two regions answer it: what KEYS each one, and whether one is reachable when
the other is not.

That is one targeted read, and it is the last one before acting on step 1 - after
which the consolidation is a known pair with a known difference, and the
52-corroborated net covers it because every fixture writes through these paths.

### 3ax. CORRECTION - M3b's premise was FALSE, and the map is what proved it

Three turns (3au, 3av, 3aw) worked on the claim that the intrinsic dispatch is
"duplicated twice".  **It is not.**  The map's last read shows the two regions are
COMPLEMENTARY, not copies:

    region A  keys on Mod_Name   - the module BEING COMPILED - so it fires when the
                                   builtin's own source calls its intrinsic, exactly
                                   like the Files arms I wired in 3l;
    region B  keys on MNm/MName  - a QUALIFIED NAME in user code - the general
                                   call dispatch for `Files.Delete (nm)` etc.

So `Native_Call (9, 1)` at 7409 and again at 7767 is TWO ROUTES FOR TWO SOURCES -
the module's own `Files.Delete` inside `Oak_Files_Src`, and a caller's - and both
are required.  They cannot drift into each other; there is nothing there to merge.
I read "the same id twice" as duplication without checking what KEYS each site, and
that is the error the session keeps repeating in new clothes: the art is not
reading the code, it is knowing what to ask of it.

**What IS repeated** is inside each region: per-member boilerplate, an
`elsif Member = ...` chain with its own argument handling for each intrinsic - the
12+ `Native_Call` sites are that boilerplate, not two copies of one thing.  That is
real, it is what the structural complaint was pointing at, and it is exactly what
the IR's `Op_Arg` / `Op_Call` pair exists to absorb: a call becomes a QUAD, and one
lowering handles every member instead of each member being hand-wired.

**So M3b is retired and its work is re-filed under M4** (calls), where the
per-member chains get replaced by quads.  M3 = designators, and M3a (the base
arithmetic, one home, measurable by grep) is its complete contribution; there is no
M3b.

**The toll, stated plainly**: three measuring turns to learn the target was not
there.  That is still cheaper than 3ak, where patching a branch three times cost
four reverts - but it is a toll, and the plan should carry the lesson: an M-number
is a guess until measured, and a "duplication" claim needs the KEYS checked before
it is called a target.

### 3ay. M4a DONE - the IR carries CALLS, and the arity is checked

The IR and its lowering now express a call into the VM's native surface:

    Op_Call_Native     appended to the closed op set, with Imm_1 = native id and
                       Imm_2 = arity;
    Quad_Info          gains two immediates - general, rather than a quad kind per
                       opcode;
    Op_Arg             pushes its argument IN ORDER, which is the calling
                       convention: the native surface takes its operands from the
                       stack, so order IS the interface;
    the lowering       CHECKS the Op_Arg run against the call's arity and raises on
                       a mismatch - the alternative is an image that fails
                       verification later, or worse, one that does not.

**The closed op set earned its keep on the first use.**  Adding `Op_Call_Native`
broke the lowerer's `case` - a COMPILE ERROR, exactly as designed, so the new op
could not be left un-lowered by accident.  That is the property the whole layer
exists for, demonstrated rather than asserted.

**Verified against the real emitter**, in the self-test that runs from
`tests/run_bc.sh`: two arguments and a native call lower to exactly three
instructions, and a call whose arity disagrees with the `Op_Arg` run raises rather
than emitting.

**One language rule learned**, and it is the kind that bites silently: a NAMED
aggregate still needs every component, so adding `Imm_1`/`Imm_2` broke three quad
literals in the tool.  `others => <>` is the fix, and it makes them survive the
next field too.  The compiler named all three sites, which is cheaper than my
having remembered.

All seven suites green, 52 corroborated by both backends, zero warnings.

**M4b next**: the first parser route through it - one member family, one route -
with the corpus as the net.  The two routes stay distinct on purpose (`Mod_Name`
for a module's own intrinsics, `MNm`/`MName` for a caller), as 3ax measured.

### 3az. M4b DONE - the first ROUTE through the IR, and the test caught a real bug

`Out.Ln` was chosen because it is the best-covered construct in the repo: present
in EVERY fixture, so the corpus is the net rather than a fixture I write.  The
inline `O2c_BC.Native_Call (2, 0)` became a quad that the lowering emits:

    O2c_Ir.Emit (Op_Call_Native, Imm_1 => 2, Imm_2 => 0);
    O2c_Ir_Lower.Emit_Quad (<that quad>);

No `Op_Arg` run precedes it, so this is also the arity check's EMPTY case.

**Evidence that it ran** - a temporary trace, as in M2b:

    IR-LN lowered= 1        <- the first Out.Ln in sum.ob2
    IR-LN lowered= 4        <- counter shared with M2b's two assignments

and the fixture matched its golden, with the image the SAME 352 bytes as before -
byte-identical emission.  The trace was then removed.

**And the self-test caught a real bug, for the second time.**  The new empty-run
check failed on first run:

    PROGRAM_ERROR: native 2 takes 0 arguments but 1 were pushed

because a PREVIOUS mismatched call had left the run counter dirty - so a failed
call poisoned the NEXT one's arity check.  Fixed by resetting the counter before
raising, with the count captured first so the message still reports it.  That is a
genuine robustness gap, found because the test lowers both boundaries - zero
arguments AND a mismatch - rather than one.

All seven suites green, 52 fixtures corroborated by both backends, zero warnings.

**M4c next**: the same pattern, one member at a time, now with a NON-empty Op_Arg
run - `Out.Char` (one argument) then `Out.Int` (two) - and then the other families.
Each is a route through machinery that is already verified, which is the point of
doing the lowering first.

### 3bf. M4f part 2 RE-SIZED - the loop needs a type CLASS, not just more ops

Measured, and it is a stage of its own rather than one member's migration.  The
`Out.String` loop's emission uses:

    Load_Local x5   Jump x4   Bin x4   Push_Int x3   Store_Local x2   Mark x2
    Jnz / Jmp x2    Native_Call   Lt   Load_Idx_B   Load_Addr_G   Global_Array
    Eq              Add

Beyond the five lowerings that exist, it needs:

1. **A TYPE CLASS on IR values.**  The emitter has separate ops per width - `Add`,
   `Sub`, `Mul`, `IDiv`, `IMod`, `Neg` with `Eq`/`Ne`/`Lt`/`Le`/`Gt`/`Ge` for
   integers, and `Radd`, `Rsub`, `Rmul`, `Rdiv`, `Rneg` with `Req`/`Rne`/`Rlt`/...
   for reals.  The IR carries `Typ : Natural`, an OPAQUE id the front end issues -
   and an opaque id cannot choose between `Add` and `Radd`.  That is a DESIGN GAP
   in M1, found by measuring the next consumer: the lowering needs the width, and
   "the front end resolves the rest" was not enough.
2. Integer comparison and arithmetic lowerings (`Op_Lt`, `Op_Eq`, `Op_Add`, ...).
3. An INDEXED BYTE LOAD.  `Load_Idx_B` takes [base, index] and scales by one byte;
   `Op_Load` is "d := *s1", a different shape - so a new op, not a reuse.
4. `Op_Discard`: the loop DROPS the address the designator chain pushed, because it
   derives its own.  In a fully-IR world that push would not happen; during a
   migration it does, so the drop has to be expressible.
5. The loop itself as six to eight quads, with that fixup interplay.

**So it is deferred, and "one member's migration" was wrong**: the type class is a
design addition, not a member wiring.

**Revised order:**

    i    the type class, plus the integer comparison/arithmetic lowerings - small,
         reusable, and the first thing ANY expression work needs;
    ii   a RUN-net for the FFI families: their bytecode_gaps probes only COMPILE,
         so before migrating them they need a fixture that runs;
    iii  the other families, mechanical once their arguments fit the ops;
    iv   Out.String's loop LAST - the biggest piece, with the thickest net, since
         every fixture prints through the paths around it.

Nothing in code this round: the measurement said the target was a stage, not a
member, and that is the second time in this session the sizing changed on contact
(3d was the first).

### 3bg. M4g (i) DONE - the type class closes the M1 gap

Every IR value now carries `Class : Type_Class` (`Tc_Word`, `Tc_Real`, `Tc_Byte`), and
the integer and real comparison/arithmetic ops lower.  This closes the gap 3bf found:
an OPAQUE type id cannot choose between `Add` and `Radd`, so the front end states the
width instead of leaving the lowering to guess.

**The width choice lives in ONE function, `Bc_Op (Op, Class)`, precisely so it can be
tested directly** - because an instruction COUNT cannot tell `Add` from `Radd`; both
are one instruction.  The self-test therefore checks the mapping itself:

    Bc_Op (Op_Add, Tc_Word) = Add      Bc_Op (Op_Add, Tc_Real) = Radd
    Bc_Op (Op_Lt,  Tc_Real) = Rlt

That is the same rigour that settled the jump polarity in 3be: for a choice that
cannot be seen in a count, settle it from the table rather than from the name.

**The OPERAND decides the width, not the destination.**  A comparison's destination is
a boolean word while its operands may be reals, so the op family follows `Src1`.  An
op with no byte form (arithmetic at `Tc_Byte`) raises rather than guessing.

**And a self-audit changed a TEST.**  My first check was labelled "a real add" while
the value's class still defaulted to `Tc_Word` - so it was exercising the word path
and its name claimed more than it did.  Caught by reading my own addition rather than
its verdict.  The fix gave the builders a DEFAULTED `Class` parameter, so existing
call sites are untouched and the check exercises the path it names.  A test whose
name overstates its coverage is the same defect as a comment that lies.

Self-test now makes 31 checks, up from 12 when the builders were first covered.  No
bytecode image changes: the front end does not set classes yet - that happens member
by member, starting with the loop that needed them.

**Next**: M4g (ii) a RUN-net for the FFI families, whose probes only compile; then
(iii) the mechanical members; then (iv) `Out.String`'s loop, which begins by marking
its values' classes - now possible.

### 3bh. M4g (ii) was unnecessary, and (iii) started with a loud off-by-one

**The run-net already existed.**  `bytecode_gaps.sh` does not merely compile the FFI
probes - it runs `vm_main` and ASSERTS the output: `Env.Set`/`Get` as a round trip
*and* as a read of a variable the VM did not set (the two together are what show it
reaches the real environment), both directions of `Args.Get`.  That suite is one of
the seven and it is green.  So writing a fixture would have duplicated work, and the
plan said to write one.  That is the third premise measurement has overturned in this
session - M3b's "duplication", the M4f part 2 sizing, and now this.

**M4g (iii) began: 14 of the 15 literal native sites migrated**, through a new
`Call_Native (Id, Arity)` helper.  The helper exists for two reasons: a migration
becomes one line, and the six DYNAMIC sites - whose id and arity are computed at
compile time - do not have to repeat their expression to get the right number of
`Op_Arg` quads.  The one site left is `(4, 1)`, which is the print LOOP, and belongs
to M4f part 2.

**And the helper had an off-by-one, which the run-net caught immediately.**  I wrote
`First := Quad_Count - Arity`.  Quad ids are 1-based and `Quad_Count` is the LAST one
emitted, so the first argument is `Quad_Count - Arity + 1`; one less lowers the
PREVIOUS call, and the failure named itself:

    O2c_Ir_Lower: native 2 takes 0 arguments but 2 were pushed

Note which sites were right: M4d and M4e wrote the arithmetic out explicitly
(`Quad_Count - 2`, `- 1`, `Quad_Count`) and worked.  GENERALISING it is what
introduced the error, and a general helper needs the boundary re-derived rather than
copied from the case it was factored out of.

**And my own harness hid the diagnosis for a round.**  I had redirected both the
compile's and the VM's output to /dev/null, so an EMPTY actual looked like "wrong
output" instead of "nothing ran" - the difference between debugging a value and
debugging a stage.  `AGENTS.md` says never suppress a build's output; the error was
one visible line away.

Verified: `ffi` prints 42 / 2.500 / 1234 matching its golden, plus `filesintr`,
`lenopen`, `sum`, `arrparam`; all seven suites green, 52 corroborated.

**Next**: the six remaining dynamic sites, one at a time - each needs its text read,
since their id and arity are expressions rather than literals.

### 3bi. M4g (iii) COMPLETE - 20 of 21 native sites, and the dynamic six were one token

**The whole family surface now goes through the IR**: 14 literal sites and 6 dynamic
ones, with exactly one raw emitter call left - the `(4, 1)` inside the print loop,
which is M4f part 2.  Both counts are asserted, and the survivor is named.

**The dynamic six were a one-token substitution.**  `O2c_BC.Native_Call` became
`O2c_Ir_Lower.Call_Native` with the ARGUMENT EXPRESSIONS LEFT TEXTUALLY UNTOUCHED:
the ten-line `if/elsif` chain that derives `In`'s id from the member name, the
`(if Two then (if Eq_No_Case (Nm, "FREAD") then 27 else 28) else 29)` pair, and
`Syms (Idx).Foreign_Native` with `Syms (Idx).Params` for the FFI path.  That is the
payoff for choosing the helper's signature to MATCH the emitter's `(Id, Arity)` before
writing any site - the opposite of M4d and M4e, where the arithmetic had to be spelled
out at each site and generalising it later introduced 3bh's off-by-one.

**The one site to skip was identified by its CONTEXT, not its line number**: the call
whose preceding line is `O2c_BC.Load_Local (V_Sl)`.  Line numbers move; the loop's
surroundings do not.

Verified: 20 `Call_Native` calls, exactly one `O2c_BC.Native_Call` left, asserted and
named; `ffi`, `filesintr`, `lenopen`, `sum` all match their goldens - and `ffi` is the
one that exercises four of the six dynamic sites, since `Convert`'s ids are computed
from the member name.  All seven suites green, 52 corroborated.

**What is left in the whole native surface is one loop.**  M4f part 2 now has every
piece it was missing except two of its own: `Op_Discard` and the indexed byte load.

### 3bj. M4f part 2, step 1 - the loop's four ops, and three things that failed loudly

The `Out.String` loop needs four ops that did not exist: `Op_Load_Local`,
`Op_Store_Local`, `Op_Load_Idx` and `Op_Discard`.  All four are appended (the enum is
append-only, like the opcode bytes) and lowered.  Appending is SAFE precisely because
the lowering's case has no `others` arm: an un-lowered op is a compile error, so
nothing can silently fall through.

All three problems in this step were reported by name rather than mis-executed:

1. **`Load_Idx_B` is an op value, not a procedure** - the emitter's `Bin` takes it,
   as the loop itself writes it.  A compile error, not a wrong answer.
2. **A local named in a quad must already be declared to the emitter.**
   `Local_Slot_Of` resolves the name through `O2c_BC.Local` and refused with
   `local is not in the frame: lt`.  That is the front end's side of the contract, and
   it is now written in the spec rather than left to be rediscovered.
3. **The convention, made explicit:** a STORE materialises its source (`Op_Copy`
   pushes), while a DESIGNATOR-SHAPED op takes its operands from the stack, already
   pushed by the front end - exactly `Op_Arg`'s rule.  My `Op_Load_Idx` arm pushed
   them again.

**And the way the third one surfaced is worth keeping.**  I was one step from
reasoning my way through the instruction counts, and instead made every count check
report its own delta.  The failure then said exactly what it saw - `got 4` against an
expected 2 - and the delta identified the double push immediately.  A check that
reports only "expected 2, failed" costs a debugging round; one that reports what it
measured costs nothing.  The self-test went from 31 checks to 36.

Note what the test encodes: its two explicit pushes before the indexed load ARE the
operands.  The test is asserting the contract, not working around it.

**Step 2 is the loop's quads**, and they are nearly all one-liners now:
`Op_Label`, `Op_Jump`, `Op_Jump_False`, `Op_Load_Local`, `Op_Load_Idx`,
`Call_Native (4, 1)`, `Op_Add`, `Op_Store_Local`, `Op_Discard`.  The corpus is the net,
since every fixture prints through it.

### 3bk. M4f part 2 DONE - the native surface is fully migrated

**`grep` now finds ZERO raw `O2c_BC.Native_Call` in the compiler**, asserted in the
patch itself.  The print loop is IR quads: `Op_Discard`, `Op_Store_Local`, `Op_Label`,
`Op_Lt` + `Op_Jump_False`, `Op_Load_Idx`, `Op_Ne` + `Op_Jump_False`,
`Call_Native (4, 1)`, `Op_Add`, `Op_Jump`, `Op_Label`.  The operand pushes stay as
emitter calls in the front end, because these ops DECLARE their operands rather than
emitting them - the rule Op_Arg set in 3ba, now applied to the designator chain too.

**It forced one rule into the open**: `Store_Value` had no `V_Temp` case because M2
had no temps.  A temp's home IS the operand stack - its producer leaves the value
there and the next quad takes it off - so storing to one emits NOTHING.  Emitting a
store would be an instruction the hand-written code never had.

**This is the first migration that is NOT byte-identical, and that is a real weakening
of the evidence.**  The hand-written loop used `Jump (Jnz, L_Bdy)` + `Jump (Jmp,
L_End)` where the IR's jump-when-false emits a single `Jz` (one instruction fewer, same
behaviour), and the terminator test flipped `Eq` + `Jnz` to `Ne` + `Jz` (the IR carries
jump-when-false, not jump-when-true).  M4b-M4e could be checked by identity; this one
is checked by the corpus and the differential, which is behavioural - sound, but a
different kind of proof.

**Two defects, one loud and one measured:**

- `Op_Lt` had no `Src1`, so the lowering read a `No_Value` for the OPERAND-CLASS
  lookup and raised `O2c_Ir: no such value`.  Four fixtures hit it, and precisely the
  four that reach the char-array loop.  `Src1` is now the index it genuinely compares.
- `Value_Id` needed qualifying, and `Typ` is `Natural` while `T_Int`/`T_Char` are
  `EType`, so they are passed as `EType'Pos (...)`.

**And my own sweep lied to me.**  It reported "67 ok / 14 bad", which reads as a
disaster; most of the 14 are negative fixtures whose refusals are CORRECT
(`proctype_bad`, `stubbad`, `threadstart_bad`, ...) plus three fixtures that have no
golden at all.  A crude "count the mismatches" sweep cannot tell a refusal-under-test
from a regression - the same blind spot AGENTS.md already records for the gap harness.

**And I called a wedge that was not one.**  I read `run_m1` starting at 20:54:06 and
concluded the gate had stalled, from a comparison against timings in earlier logs - but
that suite does two boots and it was 72 seconds in.  `pgrep` cost one command and would
have shown QEMU alive and working.  Checking beat inferring, again.

### 3bl. The metric's first real movement, measured and then REVERTED

`hello.ob2` has refused at `Geom.Sqr is not yet supported` for many steps despite all
the IR work.  This session asked the metric again and found the cause by reading the
ORDER of statements rather than guessing:

    line 12382   user libraries compiled here      <- Bytecode_Mode is whatever the
                                                      last builtin left, i.e. FALSE
    line 12393   O2c_BC.Bytecode_Mode := True       <- only the MAIN module

So a user library's procedures never got a `Bc_Proc`, the import table carried 0, and
the `Bc = 0` refusal was correct.  Builtins are different by design: the VM calls them
as natives, so they must NOT be emitted.

**One line - set `Bytecode_Mode := True` for the user-library loop - and the metric
moved past two refusals:**

    before:  bytecode backend: Geom.Sqr is not yet supported
    after:   bytecode backend: Geom.SetBase is an FFI primitive and is not yet supported

Sqr is the module's FIRST call; SetBase is a later one, so the change means Geom's own
bodies were genuinely being compiled.  The machinery is all in place and was built for
this: `Begin_Proc` returns a GLOBAL id, the export/import tables already carry
`Bc_Proc`, the call paths already consume it, and the double-push that broke u3/u4 is
already fixed (3677: "NOTHING is pushed here", with the note that the identical shape
worked with local callees).

**And it was reverted, deliberately.**  `hello.ob2` still does not compile - the change
moves the refusal along, it does not remove it - while it alters how EVERY user library
compiles, which is unverified and changes behaviour for programs the corpus does not
cover.  Keeping it would be churn in the tree for no user-visible gain, and the project
rule is not to start from a bad state.

**What is NOT measured, and must not be assumed:** why `SetBase` is called an "FFI
primitive".  `SetBase` in geom.ob2 is an ordinary procedure with a body.  The refusal
text at 7958 is a DEFAULT message, so it may be a misleading diagnosis of a different
cause - and the expression path looks the id up in `Xs (XI).Bc` while the statement
path uses `Syms (Idx).Bc_Proc`, which are two different lookups and only the first is
known to be wired to the export table.  That is a HYPOTHESIS from reading two call
sites, not a measurement, and the next step is to measure it rather than to act on it.

### 3bm. DONE — 3bl's hypothesis, measured: the metric leaves `Geom`

The hypothesis was right about the symptom and wrong about the lookup, and the
correction is the useful part.  **The imported-module statement path had no
bytecode lookup at all** — the `Syms (Idx).Bc_Proc` calls are the two *local*
statement sites (9462, 9624, the second of which also routes a foreign
procedure to `Call_Native`).  The imported statement site fell straight through
the FFI allowlist to the default refusal:

    Geom.SetBase is an FFI primitive and is not yet supported          (7969)

That message names whatever call reached the end of the chain.  It was never a
diagnosis of `SetBase`, which is an ordinary procedure with a body — so 3bl's
"may be a misleading diagnosis of a different cause" is now settled: it was
one, and the cause was a missing branch, not a wrong id.

**The fix is the expression path's branch (3661/3677), in the statement path:**

    if Xs (XI).Bc /= 0 then  O2c_BC.Call_Proc (Xs (XI).Bc);
    elsif <the FFI allowlist, unchanged>  ...

`Xs (XI).Bc` is the imported procedure's bytecode id and the export/import
tables already carry it.  `Parse_Actual` has pushed every actual, so NOTHING is
pushed here; the double-push is exactly what made u3/u4 the callee's garbage.

**The one line 3bl reverted comes back with it**, because it is what gives a
user library's procedures an id in the first place — 3bl's own reading, now
measured end to end instead of believed.

**Metric** — `hello.ob2`'s refusal, three states:

    Geom.Sqr is not yet supported                    HEAD, and many steps before
    Geom.SetBase is an FFI primitive ...             3bl's one line alone
    Strings.Pos is not yet supported                 now — past Geom entirely

**Verified**: gate25 — all seven suites green (`run_bc`, `run_vm`,
`run_stress`, `run_m1`, `bytecode_gaps`, `coverage`, `differential`), zero
warnings, metric reproduced by hand on the same tree.

**Not measured, and recorded rather than assumed**: `o2c_bc_host` takes library
sources as extra arguments and **no test script passes one**, so `hello.ob2` is
the only end-to-end exercise of this branch.  A green gate says nothing
regressed — it is not coverage of the thing that changed, and a host fixture
importing a user library is the next test this site should have.  **3bn closes
that gap** — and needed a THIRD call site to do it.

### 3bn. DONE — `Op_Call`: the call convention is in the lowering, and the net now exists

M4's stated point was that "the convention moves into the lowering pass and stops
being per-branch".  Natives got there in 3bi–3bk; calls did not.  Now they do, and
`grep -c 'O2c_BC.Call_Proc' compiler/o2c_compiler.adb` is **0**.

**What landed, in the order the plan named, each step landing alone:**

    compiler/o2c_ir_lower.ads/.adb   Call_Proc (Proc_Id, Arity), and the Op_Call arm
    tools/o2c_ir_selftest.adb        36 checks -> 44
    compiler/o2c_compiler.adb        six sites, and nothing else
    tests/bc/usercall.{ob2,lib.ob2,out}   the run-net that was missing

`Call_Proc` mirrors `Call_Native` deliberately: `Arity` declared `Op_Arg` quads,
then the call, then the lowering of exactly those quads.  The argument VALUES were
already pushed by the front end while it parsed them — `Op_Arg` declares, it does
not push (M4a was wrong about that, and 3u was the cost).  The `Op_Call` arm checks
the run against `Imm_2` with the native form's exact shape, resets the counter
BEFORE raising, and calls the emitter's `Call_Proc` with `Imm_1`.

**A Dst, and why an expression-position call may have none.** `CALL` already
leaves the result on the operand stack, and a temp's home *is* that stack
(`Store_Value`), so a call whose result feeds the surrounding expression declares
no `Dst` and emits nothing extra — which is precisely what the hand-written sites
did, and what makes the migration byte-identical.  A caller that wants the result
in a frame slot or a global names one.

**Six sites, and the sixth was the finding.**  Five were the ones the plan
enumerated (imported/expression 3678, local/expression 3832, imported/statement
7672, local/statement 9485, parameterless local/statement 9644).  The sixth was
**not on any list**: an imported PARAMETERLESS statement call, `M.Proc;`, has its
own region (~7996) with its own allowlist (XYplane.Clear, In.Open, XYplane.Open)
and its own default refusal — so it fell through and called an ordinary procedure
an "FFI primitive", the same misleading default 3bl found on the sibling site two
weeks of commits apart.  It was found by RUNNING a two-module program, not by
reading: `ULib.Set(7); ULib.Bump;` refused at `Bump` while `Set` (with arguments)
worked, which is what a missing branch looks like from outside.  A `Xs (XI).Bc /=
0` branch went in at the head of that region; `Set(7); Bump;` now prints 8.

**Evidence, and its kind.**  M4b–M4e were checked by byte-identity; 3bk showed the
IR can legitimately emit one instruction fewer.  Calls are the identity case after
all — `Op_Arg` emits no code and `Op_Call` emits the same `CALL` — so this
migration was checked that way, against a front end built from `HEAD` in a
worktree:

    12 of 12 corpus fixtures (proc, deepcall, fnexpr, callplain, arrparam, list,
      nested, withguard, dispatch, gcloop, gcscalar, threadstart)  IDENTICAL
    the imported paths, which no fixture reached: IDENTICAL too, and they RUN -
      a statement call with arguments prints 7, a call in an expression prints 3

**And the missing run-net is now a fixture**, which is what 3bm said the site
needed: `tests/bc/usercall.ob2` imports `usercall.lib.ob2` and exercises all three
imported forms in one program (statement with arguments, parameterless statement,
expression) — `Set(7)` then `Bump` then `Add(0)` prints `8`.  `run_bc.sh` and
`differential.sh` hand the library over when `<name>.lib.ob2` exists, so a fixture
enrols itself by its presence (the discovery loop's own rule) and no other
fixture's command line moves.  The Ada host front end takes NO library argument
(`N_Libs => 0`), so the Ada side refuses the import: that is recorded in the
differential's list as `usercall ADA_REFUSED`, which is why "ada refused" goes
10 -> 11 while **corroborated stays 52 and VM WRONG stays 0**.

**Verified**: gate26 — all seven suites green, zero warnings; the self-test's 44
checks; identity as above; the metric unchanged at `Strings.Pos` (correctly: this
stage moves no construct, it moves WHERE the convention lives).

**Still per-branch, and next:** `Op_Return`/`Op_Halt`; the designator chain
(`Op_Addr_Local`/`Op_Addr_Global`/`Op_Load`/`Op_Store`, M3's target); the BOOLEAN
trio, which waits on the AND/OR opcodes rather than on IR work; and
`Push_BC_Proc`/`Call_Indirect` — procedure values are a call form, so they are the
same convention from the other end.

### 3bo. DONE — the indexed access goes through the IR, and 72 of 72 images are identical

M3's target is the designator chain, and its smallest leaf is the indexed SCALAR
element — the last designator shape with no IR op on its STORE side:

    3 load sites, each a byte/word branch      O2c_BC.Bin (Load_Idx_B / _I)
    2 store sites, each a byte/word branch     O2c_BC.Bin (Store_Idx_B / _I)

`Op_Store_Idx` is appended (the enum's rule, and the case has no `others` arm so
every consumer had to decide about it).  The pair is deliberately NOT
`Op_Load`/`Op_Store`: those take an ADDRESS ("d := *s1"), while the emitter's
indexed ops take a base and an index it SCALES by `Imm_1` — the one fact the front
end has and the lowering must not have to re-derive.  `Load_Idx`/`Store_Idx
(Elem_Bytes)` are one-line helpers in the pattern `Call_Native`/`Call_Proc` set:
they no-op outside bytecode mode, emit the quad and lower it, so a site stays one
line.

**The size choice is a MAPPING, in one place, because a count cannot test it.**
`Load_Idx_B` and `Load_Idx_I` are ONE instruction each — the problem 3bg found with
`Add`/`Radd` — so `Bc_Load_Idx`/`Bc_Store_Idx` map 1 -> `_B` and 8 -> `_I` and
RAISE on any other size rather than guessing at a scale the emitter lacks.  The
self-test checks the TABLE, not a count (44 -> 48 checks), and the four-byte
refusal that was already in the test now exercises the new function.

`Op_Load_Idx` also gained the optional `Dst` that `Op_Call` has: a subscript INSIDE
an expression leaves its element on the operand stack, while the print loop's
`Dst => Lt` still stores.  Both boundaries are in the test.

**Evidence, and this time it is total**: every fixture with a golden compiles
byte-identically against a front end built from `HEAD` in a worktree —

    72 of 72 IDENTICAL, 0 differing, 0 refused by the old binary

which is the M4b-M4e class of proof, and it covers the CHAR-array and record
fixtures that share these paths (`arr`, `nestedarr`, `arrparam`, `openarr`,
`recarr`, `strch`, `gcloop`, `longfield`, ...).  Verified: gate27, all seven suites
green, zero warnings.

**What is left of M3, measured AFTER this change** (raw emissions still in the
parser):

    Load_Fld* / Store_Fld*   13   record fields — the same shape as this pair, but
                                  the choice is a THREE-way class (I / P / R)
                                  rather than a size, so it needs
                                  Emit_Fld (Kind, Off) and a table like Bc_Op's
    Load_Addr_G  17, Global_Array 12, Global 11
                                  the base derivation itself: Push_Base already
                                  owns the arithmetic (M3a), so these are its
                                  call sites plus the interning calls
    Load_Local   15               a local's slot, inline
    Bin          42               arithmetic: IR-able through Op_Add/... once the
                                  front end has an expression to build

So **the field family is next** — mechanical, the same helper-plus-table pattern,
with `rec`, `recmix`, `recreal`, `recarr`, `ptrfield` and `longfield` as the net.

### 3bp. DONE — record fields go through the IR, and the emitter's six ops became one

Done, and its shape taught the design difference the sizing had predicted: the
choice here is not a SIZE but a KIND.

    2 load sites   imported-module designator, main designator chain
    2 store sites  the same two, in statement position
    1 more site    a POINTER field at a COMPUTED offset, in the bound-procedure
                   chain — found by grepping for the OP, not by reading the plan

**`O2c_BC.Field (O, Off)` is new in the emitter**, and the six
`Load_Fld_*`/`Store_Fld_*` procedures are thin wrappers over it.  They differed
only in the opcode byte and `Byte_Of` already maps all six, so the only per-kind
thing left is whether a value comes out.  The wrappers keep their names and their
comments — a reader asking "what does a REAL field load do" still lands on
`Load_Fld_R` — while the two-byte offset encoding is now written ONCE, which is
the same argument the IR is built on.

**Recorded rather than changed**: the three stores do NOT model popping the value
(`Store_Fld` never called `Popped`).  A depth model that grew a pop here would move
`stack_max` in every image with a field — a behaviour change hiding inside a
refactor — so the comment says what is true instead.

**The IR side**: `Op_Load_Fld`/`Op_Store_Fld` appended; `Imm_1` is the offset the
front end computed, `Imm_2` the kind as an ordinal, and `Bc_Fld` maps
(kind, store) -> one of the six ops.  Same testability argument as `Bc_Load_Idx`:
all six are one instruction each, so the self-test checks the TABLE — and an
ordinal that is not one of the three RAISES (`Fld_Kind_Of`) instead of picking an
opcode by accident, because a wrong pick would be invisible in every count.
`Op_Load_Fld` takes `Op_Load_Idx`'s optional `Dst`; `Op_Store_Fld` consumes the
value from the stack.  Self-test 48 -> 53 checks.

**Evidence, again total**: **72 of 72** fixtures with a golden compile
byte-identically against a front end built from `HEAD` in a worktree — every
record fixture (`rec`, `recmix`, `recreal`, `recarr`, `ptrfield`, `longfield`,
`dispatch`, `withguard`) and, because the EMITTER changed too, the whole corpus.
Verified: gate28, all seven suites green, zero warnings.

**What is left, measured after this change** — with fields done, the rest is the
base derivation and the arithmetic around it:

    Load_Addr_G 17, Global_Array 12, Global 11
                                  the base derivation: Push_Base owns the
                                  arithmetic (M3a), so these are its call sites
                                  plus the interning calls
    Load_Local 15, Store_Local 1  a local's slot, inline
    Bin 42, Push_Int 24           arithmetic and constants: IR-able through
                                  Op_Add/... once the front end BUILDS expressions
                                  (M5, not M3)
    Mark 20, Jump 18, Dup_Top 8, Trap 6, Discard 5, Un 3
                                  control flow and stack shuffles, where the
                                  print loop already showed the shape

So **M3's remaining piece is the base derivation** (40 emissions), and the
`Bin`/`Push_Int` half is M5's.

### 3bq. M3 DONE — every address derivation is now ONE op, and the front end no longer calls Push_Base

The sizing said the base derivation was the heterogeneous one: a global array run,
a scalar global, a local's slot, with offsets added in some places and not others.
**Measured, it was uniform** — which is the opposite of the last two stages, and
worth recording as such.  Every one of the 17 sites is exactly

    O2c_BC.Load_Addr_G (O2c_BC.Global_Array (Name, Slots))     12 sites
    O2c_BC.Load_Addr_G (O2c_BC.Global (Name))                   5 sites

and the 5 scalar ones are the SAME thing with Slots = 1: `Global` and
`Global_Array` share one interning table and both return the already-interned slot
for a name, so `Global_Array (n, 1)` and `Global (n)` are indistinguishable — read
in the emitter, not assumed from the names.

**So the op is `Op_Addr_Global`, and the front end calls `Addr_Global (Name,
Slots, Nested)`**: it mints one V_Global value, emits the quad, and the lowering
hands `Push_Base` the three facts the front end has.  That is M3a's payoff made
literal: the lowering's whole body for this op is a call to the one home of the
arithmetic, with no second copy to drift from it.  All 19 sites (17 + the 2 that
already called Push_Base) now go through it, and:

    grep -c 'O2c_BC.Load_Addr_G'  compiler/o2c_compiler.adb   = 0
    grep -c 'Push_Base'           compiler/o2c_compiler.adb   = 0

**The interesting case is the one that emits nothing.**  `Slots = 0` means the
address is ALREADY on the operand stack — a pointer base, or an object the chain
has already stepped into — so the quad legitimately produces no instruction, and
`Slots = 0` with `Nested > 0` steps into the object (Push_Int + Add).  Unlike the
opcode tables of 3bo/3bp, those three cases have DIFFERENT instruction counts, so
the self-test checks them by count (53 -> 57 checks).

**Evidence**: **72 of 72** fixtures byte-identical against a front end built from
`HEAD` in a worktree, and the imported probes still print 7 / 3 / 8.  Verified:
gate29, all seven suites green, zero warnings.

**A capacity note, since this commit is a new CONSUMER of the IR tables.**  Every
migration moves an emission from a direct call to a quad, so `O2c_Ir`'s tables now
grow with the program where they used to not grow at all, and M1 left them at
4_096 values / 16_384 quads with a comment saying the capacity "must be revisited,
with a written justification, when a real consumer arrives".  The sizing: the
largest fixture is 736 bytes of code (~250 instructions at 1-5 bytes each, so
fewer than 250 quads of 16_384), `hello.ob2` at 530 lines is roughly 20x that, and
a fixture 65x gcloop would be needed to reach the quad cap.  It is not silently
full — `O2c_Ir.Emit` raises "too many quads" — so the ceiling stands as documented
rather than guessed at, and the next milestone that adds a consumer should re-run
this measurement rather than trust it.

**M3 is complete.**  What is left in the parser, measured after this change:

    Bin 42, Push_Int 24           arithmetic and constants - M5's, once the front
                                  end BUILDS expressions instead of emitting them
    Load_Local 15, Store_Local 1  a local's slot: the next family, and the one
                                  `Op_Addr_Local` was reserved for
    Mark 20, Jump 18, Dup_Top 8, Trap 6, Discard 5, Un 3
                                  control flow and stack shuffles
    Global 6, Load 1, Store 3     scalar global access, which the IR already
                                  models as V_Global operands of Op_Copy/Op_Store

### 3br. DONE — the operand family: the parser reads and writes variables through quads

The plan said "a local's slot, inline".  Measuring found two things the plan did
not know, and both made the stage smaller and more interesting than it looked:

1. **The operand seam already existed.**  `Bc_Load`/`Bc_Store` pick LOAD_L/STORE_L
   against the current frame versus LOAD_G/STORE_G against the globals block, with
   the parser's own warning attached: reading a zeroed global instead of a
   parameter is silent.  Sixteen call sites go through them, so re-routing those
   two BODIES covers all sixteen.
2. **The IR already had the model for "the value is on the stack" and had never
   learned it.**  `Store_Value (V_Temp)` emits nothing — a temp's home IS the
   operand stack — but `Push_Value` had no `V_Temp` case, so a *consumer* could
   not say the same thing.  Adding it is the mirror image of a case that has been
   there since the print loop.

**So a store is written as a source that IS the stack, not as an op with a hole.**
`Store_Local (Slot)` mints a temp and emits `Op_Store_Local (Src1 => temp)`; the
lowering pushes nothing for a temp and emits the store — one instruction, exactly
what the hand-written site emitted.  The alternative was `Src1 = No_Value` meaning
"already on the stack", which would have made one op mean two things; the project's
rule is that an op's contract should mean what it says.  The safety is the
emitter's: a temp that nothing produced still meets `Store_Local`'s `Popped (1)`
and underflows LOUDLY rather than storing nothing.

**What landed:**

    Push_Value        the V_Temp case (push nothing: the value is already there)
    Op_Copy           Dst now optional - with none, the copy IS the push an
    Op_Load_Local     expression wants (and the two that already had a Dst still
                      store, so the print loop is untouched)
    four helpers      Load_Local / Store_Local / Load_Global / Store_Global,
                      one line at a site, no-ops outside bytecode mode
    16 raw sites      every remaining `O2c_BC.Load_Local` in the parser
    Bc_Load/Bc_Store  bodies rerouted, which is 16 more callers

    grep -c 'O2c_BC.Load_Local|O2c_BC.Store_Local' compiler/o2c_compiler.adb = 0

**And one op is now measured as unnecessary.**  `Op_Addr_Local` was reserved in M1
for `d := &s1`, but this VM has no address-of-local: an open ARRAY parameter's base
is a VALUE load (its own slot, and slot+1 for the length), which is exactly what
this commit wired.  The enum is append-only, so the member stays — with the comment
saying it is reserved and why nothing needs it, which is the honest option when
deleting is not one.

**Evidence**: **72 of 72** fixtures byte-identical against a front end built from
`HEAD`, the imported probes still printing 7 / 3 / 8 — worth more than usual here
because `Push_Value` and two ops' contracts changed under the whole corpus.
Self-test 57 -> 60 checks (a no-Dst copy is one push; a no-Dst local load is one
instruction; a store whose source is the stack is one instruction).  Verified:
gate30, all seven suites green, zero warnings.

**What is left, and it is now the short list:**

    Bin 42, Push_Int 24       arithmetic and constants - M5's expression builder
    Mark 20, Jump 18          control flow
    Set_* 9, Band 1, Bor 1    the OPERATOR families - the other half of the
                              decision to do locals first, and the one that forces
                              a design choice: `and`/`or` on BOOLEANS emit
                              Band/Bor while on SETS they emit Set_Intersect/
                              Set_Union, and both operands are Tc_Word, so either
                              the SET ops are appended as their own quads or
                              Type_Class grows a Tc_Set and Bc_Op must then decide
                              every arithmetic op's behaviour at it
    Store 2, Global 4         scalar global access (Op_Copy with a V_Global Dst)
    Trap 6, Dup_Top 8, Discard 5, Un 3
                              stack shuffles and the bounds trap

### 3bs. DONE — the operator families, and the SET operators are their own quads

The recommendation 3br's sizing ended on, taken: **the SET operators become their own IR
ops** rather than `Type_Class` growing a `Tc_Set`.

    Op_Set_Union, Op_Set_Intersect, Op_Set_Diff, Op_Set_Symdiff, Op_Set_In,
    Op_Set_Single

with `Bc_Set` as the table beside `Bc_Op`.  The reason is the one that made a decision
necessary at all: `and`/`or` on BOOLEANS emit `Band`/`Bor` and on SETS emit
`Set_Intersect`/`Set_Union`, and **both operands are `Tc_Word`** — a SET is a 64-bit word —
so no width table can choose between them.  A `Tc_Set` class would have forced `Bc_Op` to
declare a behaviour for every arithmetic op at a width that has no arithmetic, and a table
full of raises has stopped being a table.  Six ops keep it a WIDTH table, and all six are
one instruction each, so the self-test checks the table — as it does for `Bc_Op`,
`Bc_Load_Idx` and `Bc_Fld`.

**BOOLEAN and/or went the other way, INTO the width table**, because a boolean IS a word in
this VM: `Bc_Op (Op_And, Tc_Word) = Band`, `Bc_Op (Op_Or, Tc_Word) = Bor`, and at `Tc_Real`
they raise.  That asymmetry — one family by width, one by op — is the entire content of the
decision, and both halves are pinned by the self-test.

**`Op_Not` stayed explicit, and is deliberately NOT in the table.**  `not b` IS `b = 0` in
this VM (§3a: a BOOLEAN is 0/1, which is why `Op_Btest` is a no-op), so its lowering is two
instructions — `Push_Int 0; Bin (Eq)` — and unlike a width or a table entry, **a count CAN
check that**.  Folding it into a table whose entries are all one instruction would have
thrown the check away, and an entry reading `Op_Not -> Eq` would have looked like a
mistake.

**One helper**, `Apply (O)`, for "an operator whose operands are already on the operand
stack" — the left one pushed when it was parsed, then the right.  Binary or unary is the
LOWERING's business, so a site does not have to know: `Op_Set_Single` is the unary one and
goes through the emitter's `Un`, which models its net-zero depth exactly as the
hand-written site did.

    grep -c 'O2c_BC.Band|O2c_BC.Bor|O2c_BC.Set_*' compiler/o2c_compiler.adb = 0
    11 sites migrated: 9 SET, the BOOLEAN pair, and the `not` pair

**Evidence**: **72 of 72** fixtures byte-identical against a front end built from `HEAD`,
with the SET and BOOLEAN fixtures printing their goldens (`set`, `setops`, `boolops`);
self-test 60 -> 68 checks; gate31 all seven suites green, zero warnings.

**Three ops are now measured as UNUSED, and it is the same measurement three times.**
`Op_Addr_Local` (3br) and `Op_Load` / `Op_Store` (the `d := *s1` and `*d := s1` forms) are
emitted by NOTHING in the parser:

    O2c_BC.Load (   ... 0 sites   <- the one that used to be here was
    O2c_BC.Store (  ... 2 sites      Load/Store (Global (n)), a module variable, which
    address-of-local ... 0 sites      the IR expresses as a V_Global operand of Op_Copy

and that is not an accident of this corpus: a POINTER dereference needs NO instruction in
this VM, because the address IS the value — what follows it is a field or an index access,
which has its own ops.  All three stay (the enum is append-only), each with a comment
saying it is reserved and why nothing needs it.

**What is left now — two subjects and the shuffles:**

    Bin 32 (from 42), Push_Int 23, Push_Str 5
                                  M5's expression builder: the front end emitting
                                  arithmetic AS IT PARSES
    Mark 20, Jump 18              control flow
    Trap 6, Dup_Top 8, Discard 5, Un 2
                                  the bounds trap and stack shuffles
    Store 2, Global 4             two global stores: Op_Copy with a V_Global Dst, which
                                  is exactly what Bc_Store already does
    Op_Return, Op_Halt            un-lowered, and nothing emits them yet

### 3bt. M5 STARTS — the expression operators, and the first image change that is a FIX

The measurement said the expression builder is M5.  It also said the first thing it needs
is not a new op but a way to state a WIDTH for an operand that has no value id: the 32
`Bin` sites choose the opcode INLINE, so every arithmetic operator is the same rule written
twice (`if Res = T_Int ... then Bin (Add) else Bin (Radd)`) - the duplication `Bc_Op`'s
table (3bg) exists to end.

**`Bin_Op (O, Class)` is the helper, and its Src1 is the whole idea.**  It mints a temp
that CARRIES the class and *declares* the left operand - already on the operand stack,
pushed by the sub-expression the parser had just read.  That is the only way a quad can
state a width, because a class lives on a VALUE and an operand pushed without one has none;
the lowering then calls `Bc_Op` - ONE table - instead of guessing.

    13 arithmetic emissions + 6 relational = 19 sites
    the six relationals went from TWO opcode names each to ONE name plus a class

**It found a real bug in EXISTING code, which is the part worth keeping.**  The arithmetic
arm's `Store_Value (Q.Dst)` was UNGUARDED.  Every other op migrated so far got the optional
Dst; this arm never needed one, because its only users were the print loop's conditions -
all of which store their result.  `Bin_Op` sends a bare push, and `Store_Value (No_Value)`
raised `O2c_Ir: no such value`: a value id of ZERO, reported two frames away from the
operator that omitted it.  Two wrong guesses about which call it was were settled by one
temporary `Put_Line` inside `Value_At`.  That is "put the diagnostic where the failure is"
again, and it is the third time this file has had to say so.

**And the first migration that changes an IMAGE - for a reason that is a fix.**  `constfold`
stopped compiling, loudly: `O2c_Ir_Lower: no emitter procedure is open`.  A CONSTANT
declaration's expression is parsed and folded BEFORE any procedure is open, and the old
direct `O2c_BC.Bin` cheerfully appended its arithmetic into the code buffer ahead of the
first procedure: dead bytes nothing ever jumped to, because every use site pushes the
FOLDED value.  A quad cannot hold that code - a quad's operands live in a frame - so
`Bin_Op`/`Apply` now return where there is no frame, and

    constfold.ob2   552 -> 544 bytes, golden output unchanged
    identity vs HEAD: 71 of 72 identical, 1 differing - constfold, by 8 bytes

This is the second migration that is not byte-identical (3bk was the first), and unlike
3bk's it is *explained* rather than merely behavioural: the code section got SMALLER by
dead code, and a fixture that folds constants is exactly where that shows.  `run_bc` is
green *including* constfold, which is the check that the fold still lands.

Self-test 68 -> 71 checks: the operator quad carries the CLASS (`Op_Sub` with a temp Src1
of class Tc_Real, and Tc_Word when no class is given - a count cannot see Add from Radd,
so the check is on the quad), and an operator OUTSIDE a procedure emits and lowers nothing
rather than failing, which is the folded-constant case above.

Verified: gate32, all seven suites green, zero warnings.

**What is left of M5, measured after this change:**

    Bin 32 -> 13, and the 13 are NOT expressions:
        Lt 3, Ge 3            the bounds checks the designator chain emits
        Add 1, Mul 1          the chain's OWN arithmetic: a row scale, a base add
        Eq 2                  CASE label matching, with its Dup_Top/Jump
        Str_Cmp 1, Copy_Str 1 the string family
        (one more whose op is a variable - the string compare - so 13)
    Push_Int 23, Push_Str 5   literals feeding ops that already declare their operands
    Mark 20, Jump 18, Dup_Top 8, Discard 5, Un 2, Trap 6
                              control flow, the bounds trap and stack shuffles
    Global 4, Store 2         two global stores and their interning

### 3bu. Control flow, part 1 — the label machinery, and IF / WHILE / REPEAT

**`Op_Jump_True` is appended**, and the reason is worth keeping.  The IR carried only
jump-when-false (3be settled its polarity from the VM's table), and the parser's conditions
test in BOTH directions — eight `Jnz` sites, four `Jz`.  One could rewrite a `Jnz` site as an
inverted condition plus `Jump_False`; 3bk showed the IR is sometimes one instruction shorter
and that is legitimate.  But here it would have changed the image of every `IF` for **no
behavioural gain**, and identity is the stronger evidence whenever it is available.  So the
op was appended instead: `Jump_True` is `Jnz` and says so.

**And the label namespace moved.**  The emitter has no label allocator — "the label namespace
belongs to the caller", as its own self-test comment says — so:

    compiler   New_Lbl      the emitter id (the counter that already owned the namespace)
                            + the IR label, RESERVED with the lowering
    lowering   Mark / Jump / Jump_False / Jump_True
                            take an IR LABEL and emit the quad; the mapping stays here

A statement site now names a label it was given and never sees the emitter's numbering — and
the nine `if O2c_BC.Bytecode_Mode then ... end if` blocks around the allocation and the
branches are GONE, because the helpers no-op outside bytecode mode.  The three statements got
SHORTER (IF 4 sites, WHILE 4, REPEAT 2), which is the first time in this workstream that a
migration removed lines from the parser rather than adding a call.

**The self-test caught a wrong expectation in the check itself.**  My first assertion was "the
Mark helper is one instruction" — the emitter's `Mark` records a label's POSITION and emits
**no** bytes, so the count is ZERO.  A "1" there would have meant a byte of code where a label
is.  The check now states the 0 the emitter does, with the reason in the message.

**Evidence**: **72 of 72** fixtures byte-identical against a front end built from `HEAD` in a
worktree (this migration is the identity case — the same Mark/Jnz/Jz/Jmp in the same order),
`run_bc` 123 goldens green, self-test 71 -> 76 checks.  Verified: gate33, all seven suites
green, zero warnings.

**What is left of the statements, measured by the LABELS each site uses:**

    12  the bounds checks (`L_In`/`L_Up`): Jnz to the trap, Mark to continue - designator
        chain internals, and they need a trap op before they can be quads
     8  Parse_Case (`Bc_L_Body`/`Bc_L_Next`/`Bc_L_End`): its label matching is
        Dup_Top; Push_Int; Eq; Jnz, so it needs an `Op_Dup` (append-only) first
     4  Parse_Loop / Parse_Exit (`L_Top`/`L_Exit` + the recorded exit label)
     2  Parse_For (an extra `Jz`/`Mark` beside For_Enter/For_Next, which carry their own
        labels as operands and are a different mechanism)
     2  Parse_With (`Bc_Top`/`Bc_Else`): the guard's skip
    16  Dup_Top 8, Discard 5, Un 2, Trap 6 - the shuffles and the trap itself

So the natural next slice is LOOP/EXIT + FOR + WITH (8 sites, no new op needed), then CASE
with `Op_Dup`, then the bounds regime with a trap op — and only then is the parser's
statement surface fully quad-built.

### 3bv. Control flow, part 2 — LOOP/EXIT and WITH, and where the guard belongs

Six sites: `Parse_Loop` (Mark `L_Top`, Jump `L_Top`, Mark `L_Exit`), `Parse_Exit` (a Jump into
the exit label recorded per LOOP depth) and `Parse_With` (Jump_False and Mark on `L_End`).
`Bc_Loop_Exit`'s element type moved to `O2c_Ir.Label_Id`, so EXIT's target is an IR label and
nothing outside the lowering knows the emitter's numbering.

**And it answered a question 3bu raised: WHERE THE GUARD BELONGS.**  Two of the three
statements lost their `if O2c_BC.Bytecode_Mode then` tests outright — `New_Lbl` and the four
branch helpers are no-ops outside bytecode mode — but `Parse_With` KEEPS one, now around only

    Bc_Load (VName ...)        resolves a slot through the emitter's tables
    O2c_BC.Type_Test (...)     builds a descriptor

because those are the calls that RAISE outside bytecode mode (`Global` refuses before
`Begin_Mode`).  So the rule is stated rather than guessed: **the guard is for the calls that
need the emitter, not for the branch** — and a guard kept "to be safe" hides which calls those
are, which is how a mode bug survives a migration that looked mechanical.

**Evidence**: **72 of 72** identical against a front end built from `HEAD` (this stage is the
identity case as well — the same allocations in the same order), `run_bc` 123 goldens green.
Verified: gate34, all seven suites green, zero warnings.

**What is left, measured — 22 Mark/Jump sites and the shuffles:**

    12 bounds checks + 6 Trap (0) + 3 Lt + 3 Ge + Dup_Top
                                the array index regime: needs Op_Dup and Op_Trap (append-only),
                                after which its pieces all already exist - Bin_Op for the
                                compare, Jump_True and Mark for the branch
     8 Parse_Case               its label matching is Dup_Top; Push_Int; Eq; Jnz, so Op_Dup
                                again, and everything else exists
     2 Parse_For                the two Marks feed For_Enter/For_Next, whose labels are
                                OPERANDS of the opcode (a fixup each) rather than Mark/Jump
                                pairs - so FOR needs its own ops or an exposed mapping, and it
                                is the one place where "hide the emitter's numbering" cannot
                                hold yet
     2 Un (Neg/Rneg), 5 Discard, 5 Push_Str, 23 Push_Int
                                the unary sign needs a Un_Op helper (Bin_Op's mirror); the rest
                                are pushes feeding ops that already declare their operands

### 3bw. DONE — the BOUNDS REGIME and CASE, with Op_Dup and Op_Trap

Two constructs landed together because they need the same two ops.  The bounds regime is 12
Mark/Jump, 6 `Trap (0)`, 6 comparisons and 6 `Dup_Top`; CASE is 8 Mark/Jump and two label-match
chains.  Two ops were appended and three helpers added:

    Op_Dup     -> Dup_Top        a bounds compare must not consume the index it tests
    Op_Trap    -> Trap (Imm_1)   the KIND byte the VM reads, hence an immediate
    Push_Int (V)                 a constant as a push: Op_Copy with a constant source and no
                                 Dst IS the push, so a site states the value and nothing else
    Dup / Trap / Discard         the ops, one line at a site

**The bounds clusters are the same twelve instructions written THREE times** — that is the
finding here, and it is the same shape 3aw called "per-member boilerplate".  Two copies sit in
the scalar-element path and one in the open-array path, differing only in how the length is
obtained (an `Arr_Len` constant, or the slot beside an open array's address).  They are three
identical call sequences now, and the shape is stated ONCE in the quad stream: dup, push 0,
compare, jump-if-in-range, trap, mark.

**CASE's own trap, recorded because it cost someone real time:** `Bc_L_Next` is where a failed
alternative resumes, and it is marked at the start of the NEXT alternative, never at its own —
marking it at its own made the failed comparisons re-run, which looped.  The comment was
already there; the migration moved the calls without touching the rule, which is the point of
having it written down.

    the parser's raw emissions after this stage: Mark 2 (both FOR's), Jump 0, Dup_Top 0,
    Trap 0, and the 5 remaining Bin sites are Str_Cmp, Copy_Str, one with a variable opcode,
    and the designator chain's own Mul and Add — none of them expressions

**Evidence**: **72 of 72** fixtures byte-identical against a front end built from `HEAD`
(this stage is the identity case too), `run_bc` 123 goldens green, self-test 76 -> 81 checks.
Verified: gate35, all seven suites green, zero warnings.

**What is left — and the statement surface is now nearly all quads:**

    FOR            2 Mark + For_Enter/For_Next: its labels are OPERANDS of the opcode (one
                   fixup each) rather than Mark/Jump pairs, so FOR needs Op_For_Enter/
                   Op_For_Next or an exposed mapping.  It is the one construct whose
                   mechanism differs, and the one place where hiding the emitter's
                   numbering cannot hold yet
    2 Un (Neg/Rneg) the unary sign: needs a Un_Op helper, Bin_Op's mirror
    5 Bin           the string family (Str_Cmp, Copy_Str) and one variable opcode
    16 Push_Int, 5 Push_Str, 4 Global, 2 Store, 4 Discard, 2 Type_Test
                   literals and global access, mostly one-line helper calls away

### 3bx. DONE — FOR and the unary sign, and a latent bug the migration exposed

FOR was the one construct whose labels are **operands of the opcode** (a fixup each) rather
than Mark/Jump pairs, so it needed ops where every other statement needed a branch helper:

    Op_For_Enter, Op_For_Next
    Imm_1 the loop variable's frame slot, Imm_2 the limit's slot,
    Src1 the label VALUE (resolved through the reservation like any other),
    Src2 a constant holding the STEP - a value, because a step can be NEGATIVE and
    Quad_Info's immediates are Natural

With `For_Enter`/`For_Next` helpers beside the Jump ones, the FOR site is five one-line calls
(`Discard`, `For_Enter`, `Mark`, `For_Next`, `Mark`), and hiding the emitter's numbering now
holds everywhere.

**And the unary sign exposed a LATENT BUG in an arm of two commits earlier.**  `Op_Neg` sat in
the arithmetic arm, which emits through `O2c_BC.Bin` — two operands in, one out.  A negate is
UNARY: the emitter's `Un` leaves the depth alone, so routing it through `Bin` tells the stack
model to pop a value nobody pushed - a wrong `stack_max` at best, "operand-stack underflow" at
worst.  Nothing emitted `Op_Neg`, because the front end called the emitter's `Un` directly, so
the bug was invisible from both sides: no site used it and no test covered it.  `Un_Op` now
declares the operand's class the way `Bin_Op` does, and the arm is `O2c_BC.Un`.

The self-test check for it is the interesting one, because a COUNT cannot see it: with a
zeroed depth, an op routed through `Bin` underflows LOUDLY, so the check is "a unary sign is
one instruction that does NOT pop" - the absence of the failure is the evidence.

**The parser's control-flow surface is now fully quad-built:**

    Mark 0, Jump 0, For_Enter/For_Next 0, Dup_Top 0, Trap 0, Un 0 - all through helpers
    what is left is literals and global access: Push_Int 16, Push_Str 5, Bin 5
    (Str_Cmp, Copy_Str, one variable opcode, and the designator chain's own Mul/Add),
    Global 4, Store 2, Discard 3, Type_Test 2

**Evidence, and one image changed — for the SECOND instance of a known class.**
**71 of 72** fixtures are byte-identical; `fordown` is 1144 -> 1136.  The 8 bytes are one
byte of CODE plus the padding that follows it, and the byte is `0x35` — `NEG`.  Which `NEG`,
and why, was settled by a probe rather than by reading: a fixture containing ONLY

    const STEP = -2;

and no FOR at all loses exactly that one `NEG` too (`old=1 new=0`, code section the same
size, and the use site pushes the folded constant).  So the cause is not FOR: it is the same
wart 3bt found — a CONSTANT DECLARATION's expression emitted into the module prologue, where
it is dead because the folded value is what every use site pushes — and `Un_Op`'s
`Proc_Open` guard is what removed this instance, exactly as `Bin_Op`'s removed the first.

That is the pattern worth carrying: **each helper that guards on `Proc_Open` removes one
instance of prologue dead code**, and the instances that remain are the RAW pushes
(`Push_Int` 16, `Push_Str` 5), which is why this was one byte and not more.  Migrating the
literals is the next stage, and it will remove the rest — the identity net is what made the
difference visible instead of silent.

Verified: gate36, all seven suites green, zero warnings; self-test 81 -> 85 checks.

### 3by. The literal tail — and the prologue dead code it was still carrying

3bx's own pattern said what came next: **each helper that guards on `Proc_Open` removes one
instance of prologue dead code**, and the instances that remained were the RAW pushes.  So
this stage migrated them — `Push_Int` 16 sites and `Push_Str` 5 — plus the last three
`Discard`s, the two `Store (Global (...))` writes, and the designator chain's own `Mul`/`Add`
(which are `Push_Int` + `Bin_Op`, not expressions).

`Push_Str` needed one thing the value model had carried since M1 with no consumer:
`Push_Value` had no `V_Const_Str` case.  A string constant's pool word is the OFFSET of its
text inside the CONST payload, which is what the VM's string ops consume, so the case is one
line — and the check is that a string constant is one push.

    the parser's raw emissions after this stage:
        Bin 3        Str_Cmp, Copy_Str, and one whose OPCODE IS A VARIABLE
        Type_Test 2  the WITH guard and the type guard
        Global 2     the mutex ops' slot argument
        Push_Word 1  a 64-bit SET mask
        Mutex_Lock / Mutex_Unlock, one each

**Which is to say: nothing left is a literal, a branch, a label, a frame slot or a variable
access.**  The four families that remain each have a design question of their own — strings,
the type test, the mutex ops, the 64-bit SET mask — and none of them is in anything else's
way.  The parser's emission surface is, for the constructs the language actually uses in the
corpus, quad-built.

**Evidence: 68 of 72 identical, and the four that differ LOST bytes — dead ones.**  The check
that settles it is not "the goldens pass" but the ENTRY OFFSET: the image's `entry` field
points at the module body, so code before it is unreachable by construction.  Measured:

    fixture     old: entry / code size   new: entry / code size   removed before the entry
    constfold        93 / 208                28 / 144             65 bytes = 13 pushes x 5
    constuse         38 / 160                28 / 152             10 bytes =  2 pushes x 5
    strconst         38 / 120                28 /  80             10 bytes =  2 pushes x 5
    fordown        1136 bytes            1128 bytes

A module-level literal is 5 bytes — `LOAD_CONST` plus its u32 pool index — and those pushes
fired in the DECLARATION part, before any procedure was open.  They are the third and largest
instance of the class 3bt found and 3bx predicted, and the new entry lands at a constant 28
bytes (the frame setup that is always there).  Every one of the four images is SMALLER, and
`run_bc` is green *including* all four.

Verified: gate37, all seven suites green, zero warnings; self-test 85 -> 86 checks.

### 3bz. THE METRIC LEVER — one line moves it past a whole library, and TWO blockers it exposes

Nothing in code this round: a measurement, a reverted experiment, and two minimal reproducers.
But it is the most useful measurement of the session, because it changes what "advance the
metric" means.

**The lever.**  `Compile_Builtin (Oak_Strings_Src, Scoped => False)` compiles the builtin with
`O2c_BC.Bytecode_Mode := Scoped` — so `False` means its BODIES are not emitted and its members
must be served by VM natives (the 20 wired procedures).  The bodies, however, are **right there
in the compiler**, written in the language this backend compiles.  Flipping that one flag:

    Scoped => False   hello.ob2 refuses at   bytecode backend: Strings.Pos is not yet supported
    Scoped => True    hello.ob2 refuses at   bytecode backend: Texts.OpenWriter is an FFI
                                             primitive and is not yet supported

Past the WHOLE Strings module, and into Texts.  That is a far bigger step than wiring
`Strings.Pos` as one more native, so the metric's next move is not a native at all.

**Blocker A — CORRECTED IN 3ca: the mechanism below is WRONG** (the trigger is a parameterless
FUNCTION, and the failing offset is in the BODY, which has no early return).  Kept as written
because the correction is the finding: the first diagnosis named the verifier when the emitter
is at fault, and only the offset said so.

**Blocker A, as first (wrongly) diagnosed — the VM's verifier and EARLY RETURNs.**  Its comment says it:

    This walk is linear, and by construction the code after a return is the next procedure in
    the payload, so the frame's depth is not carried across: reset it.

The assumption is false as soon as a procedure returns from the MIDDLE - and every library body
does.  Minimal reproducer (a function; a plain procedure with the same loops PASSES, which is
why it stayed hidden):

    module C2; import Out; var sl, sul: integer;
    procedure P: integer; var i: integer;
    begin for i := 0 to sl - sul do if i = 1 then return i end end; return -1 end P;
    begin sl := 5; sul := 2; Out.Int(P, 0); Out.Ln end C2.

    -> vm: operand-stack depth violation at code offset 1119

The same with a WHILE (`while i < 3 do if i = 1 then return i end; i := i + 1 end`) fails too,
and so does a FOR containing an `if` in a function even with NO return in the loop - so what
the verifier objects to is the depth it computes after walking through a mid-procedure
construct.  The emitter is not at fault: after a RET the verifier keeps walking the REST of the
procedure with a reset depth, and the loop's tail then drives it below zero.  **No fixture
returns early from inside a loop**, which is why a green corpus never said so.

**Blocker B — `var ARRAY OF` write-back is silently lost.**  `Strings.Cap` is declared
`Cap*(var s: array of char)` and its body writes `s[i] := CHR(...)`; called from a program it
printed the array UNCHANGED (`abc`, not `ABC`).  A silent wrong answer, not a refusal - the
class this backend exists to eliminate - and the corpus's ARRAY OF fixtures are all READS
(`Out.String`, comparison), so nothing covered the write.  (A first probe of mine was refused
correctly with "cannot assign elements of a value ARRAY OF parameter" - because I had left out
the `var` - which is how the DECLARATION's form came to be part of the evidence: the parameter
must be `var` to be assignable, and `Cap`'s is.)

**And one parse-level finding**: grouped parameters (`sub, s2: array of char`) are refused -
"expected ':' in a parameter".  Oberon-2 allows `a, b: T`, the Oakwood sources happen to write
every type out, so nothing had noticed.

**What this means for the plan.**  The metric's next step is NOT one VM native for `Strings.Pos`
- it is these two blockers, because the whole builtin library family comes with them, and both
are *backend/VM* defects rather than missing natives:

    1. the verifier needs a walk that follows a procedure's REAL control flow (or, at the
       least, one that does not reset at a mid-procedure RET) - and a fixture that returns from
       inside a loop, which needs blocker 1 fixed to exist at all
    2. `var ARRAY OF` write-back needs a fixture and a fix
    3. then `Scoped => True` for the libraries becomes a one-line-per-module advance

The experiment was REVERTED: a `Scoped => True` image is one the VM REFUSES to load, which is
worse than a refusal at compile time, and it would also have silently fixed `Strings.Length`
under `bytecode_gaps.sh`'s recorded gap.  Reverted to the documented state, and the metric is
back at `Strings.Pos` - which is the honest place for it to be until the two blockers are fixed.

### 3ca. CORRECTION — 3bz's Blocker A was misdiagnosed; the trigger is a PARAMETERLESS FUNCTION

3bz attributed its verifier violation to the VM's linear walk and its depth reset at `RET`,
which assumed "the code after a return is the next procedure".  **The mechanism was wrong**,
and the offset said so: the violation is reported *inside the module BODY*, and the body of the
reproducer has no early return at all.  What follows is what the bytes say.

**The trigger, narrowed to one construct.**  A user procedure with no parameters and a RESULT:

    procedure P: integer;
    begin return 7 end P;
    ...
      n := P;                     <- this fails, and it is the whole programme

fails (248-byte image, rejected).  A function WITH a parameter (`Q(x: integer)`) works, and so
does a parameterless PROCEDURE.  So it is specifically **a parameterless user function called in
an expression** - and the corpus cannot express one: the `(): T` spelling is refused by the
parser ("expected an identifier"), and the parenless spelling is what procedures use.  Three
probes were wrong before the byte dump was right; that is the same toll 3bq and 3wt paid, and it
is worth stating again: the offset and the bytes answered in one step what four theories could
not.

**What the image shows.**  e1's code contains NO `Call` opcode at all (0xC0 never appears), and
where the call should be it has

    Load_Const 0 ; RET           <- the CALLEE's return sequence
    Store_G n  ...               <- the store that expected the call's result

so the callee's return was emitted into the CALLER's code, and the body stores a value it never
pushed.  The verifier rejects it - correctly.  The fault is in the front end's expression path
for a bare procedure name with results, not in the VM.

**And the leverage is large**: this is exactly the shape the Oakwood library bodies are built
from (`function`-shaped procedures called in expressions), so it sits on the path 3bz identified.
The fix belongs with that path, and its test is e1 above.

    tests/bc/parfn.ob2  `procedure P: integer; begin return 7 end P;` used as `n := P` -
    a fixture the corpus has no way to write today, which is why nothing said so.

**What OBNC gives us, since the user pointed at it** (`/tmp/obnc-0.17.2`): the library ORACLE.
`lib/obnc/` holds the Oakwood sources (`Math.obn`, `Out.obn`, `Files.obn`, `In.obn`,
`Input.obn`, ...) **with tests**: `MathTest.obn`, `OutTest.obn`, `FilesTest.obn`, `InTest.obn`,
`InputTest.obn`, each with a `.sh` driver and an `.env` expectation file in places.  And
`tests/obnc/` is the compiler's own suite, split into `passing/` and `failing-at-compile-time/`
- which is the same two-way split `run_bc.sh` uses (goldens and negatives), and a far better
source of library fixtures than anything in `tests/bc` today.

### 3cb. FIXED — a parameterless FUNCTION call emitted NOTHING, and now has a fixture

3ca narrowed the defect to one shape; this is the fix, and it was four lines of emission that
had never been written.

**The site.**  `Parse_Factor`'s bare-procedure-name branch (the expression path) had:

    if Cur.Kind = Lex.Tok_LParen then   --  f(x): emits the call
       ...
    elsif Syms (Id).Params /= 0 then    --  f with no parens but formals: refused
       raise ...
    end if;                             --  and NOTHING for `Params = 0, no parens`

So `n := P` fell through both arms and emitted no call at all.  The result was a store of
whatever happened to be on the operand stack - the wrong-image class this backend exists to
eliminate - and the corpus had no way to say so: `(): T` is refused by the parser, so a
parameterless FUNCTION could not be written in a fixture.  The `else` arm now emits it, through
the same three-way dispatch the paren arm uses (`Foreign_Native` -> `Call_Native 0`,
`Bc_Proc = 0` -> refuse, else `Call_Proc (id, 0)`), and the result stays on the operand stack
where CALL left it.

**And the fixture the corpus could not write is now the test:**

    tests/bc/parfn.ob2   `procedure P: integer; begin return 7 end P;`
                         used as `n := P` AND as `P + 1` - one bare call and one inside an
                         expression

which prints 7 and 8.  It is enrolled by the discovery loop, and the Ada side has always
accepted this shape (`n := P;` is valid Ada), so the differential should CORROBORATE it rather
than record it - the first fixture in a while that both backends agree on.

**Why this one matters more than its size.**  It is the shape the Oakwood library bodies are
built from, so it sat directly on 3bz's path: the `Scoped => True` lever cannot move the metric
past a library that calls its own parameterless helpers in expressions.

Evidence: identity (unchanged for the corpus - the fix only adds emission where there was none),
`run_bc` including the new fixture, gate38; four theories were wrong before the byte dump was
right (3ca), which is why the fixture ships with the fix rather than after it.

### 3cc. FIXED — writes through a `var ARRAY OF` parameter emitted NOTHING

3bz's Blocker B: `Strings.Cap` printed its argument unchanged.  The cause was the same class as
3cb's - a statement that built only the Ada text - and it is now the second defect in a row
found by compiling a library body.

**The site** is the statement dispatcher's own branch for an element write through an ARRAY OF
parameter (`Cur.Kind = Tok_LBracket and then Syms (Idx).Open_Arr`).  It checked `By_Ref` -
refusing a write to a *value* parameter, correctly - then parsed the index and the value and
called `Append_Body` ... with **no `Bytecode_Mode` branch anywhere**.  So in bytecode mode the
whole statement vanished: the value expression was even PARSED and its push discarded.  The
fixture the corpus lacked is now `tests/bc/vararr.ob2`, which is `Cap`'s own shape (`for` over
`len(a)`, an `&` condition, CHAR arithmetic, `a[i] := CHR(...)`) applied to a `var ARRAY OF
char` - it prints `HELLO`.

**The first attempt at the fix was wrong in a way worth recording.**  I pushed the base inside
the `declare` block, next to the bounds check - and an expression's initialiser runs in the
DECLARATIVE part, so the index went on the stack FIRST: `[index, base]`.  The bounds check then
compared the *base* against 0 and trapped.  `vm: index out of range` was the whole diagnosis: the
trap said "the thing you are comparing is not the index", and the fix was to move one push above
the block.  That is the second time in two stages that the *loud* failure named the mistake while
a silent one would have been worse.

**What the branch does now**, mirroring the READ path exactly: push the caller's address (the
parameter's own slot), parse the index, `dup`/compare/`trap`/`mark` twice (0 and the length in
slot+1 - the same pair the read path uses), parse the value, then `Store_Idx` with an element
size of 1 for CHAR and 8 otherwise.  `[base, index, value]` is the order the VM's `Store_Idx_*`
pops, which is why the value is parsed last.

Evidence: identity (unchanged - no existing fixture wrote through an ARRAY OF parameter, which is
the point), `run_bc` including `vararr`, gate39; and the library symptom is gone: `Strings.Cap`
applied to `"hello"` now prints `HELLO` (probe `P9`).

### 3cd. The lever, retried — it advanced, and ONE library body still trips the verifier

3bz's two blockers are fixed, so the `Scoped => True` experiment was run again.  It got further
and it is still not landable, and both halves are measurements.

**What now works through the lever** (probe `P9`, and the metric):

    Strings.Length   prints 5        (was a recorded gap in bytecode_gaps.sh)
    Strings.Cap      prints HELLO    (was the silent no-op of 3bz/3cc)
    hello.ob2        refuses at      bytecode backend: Texts.OpenWriter is an FFI primitive ...
                                     the same place as 3bz - past the whole Strings module

So the two fixes paid off exactly where they were aimed: a library body that merely *compiles* is
no longer the bar; `Cap` and `Length` now *run*.

**What still fails**: `Strings.Pos` produces an image the VM REFUSES to load -

    vm: operand-stack depth violation at code offset 1124: depth -1, limit 18

which is why the flip is reverted again (a rejected image is worse than a refusal, and it is the
project's rule).

**The datum, and the diagnostic that produced it.**  The verifier's message used to name only the
offset, which left two candidates - a depth below zero and one above `stack_max` - that want
opposite fixes.  It now reports both numbers (the same move that found 3bt's bug, made permanent):
**the depth is -1 in every failure**, i.e. the walk *pops* where it believes the stack is empty,
never "over the limit".  One run, after five disproofs.

**Five candidates disproved, each working in ISOLATION** - recorded so the next session does not
re-walk them:

    one open-array formal      procedure One(a: array of char) called from the body      OK
    two open-array formals     procedure Two(a, b: array of char): integer               OK
    forwarding one level down  Outer(b) calls Inner(b)                                   OK
    a nested call with an open actual   Out.Int(One(s), 0)                               OK
    early returns              b3 (no loops) and w6 (loops, flag instead of return)      OK / FAIL
    nested calls, INTEGER formal        Out.Int(Tw(3), 0)   (fnexpr's shape)             OK

`Pos`'s body as a USER module (`b4`) fails identically, so it is not the builtin path; and a
variant of that body with NO early return (`w6`) fails too.  What is left is a combination: the
failing bodies all nest a `for` and a `while` with `&` conditions inside a FUNCTION that is
called with an open-array actual.  The next step is a systematic shrink of `w6` - and the tool
for it is now in place, because each attempt reports *depth -1 at offset N* instead of a symptom.

**What would unblock the lever**: this one shape, then `Scoped => True` per module.  And the
oracle for each is OBNC's `*Test.obn` (3ca), which is a better net than anything in `tests/bc`
for a library.

### 3ce. FIXED — a string LITERAL actual passed no length; and the lever's third stop

**The bug, and its reproducer is ten lines:**

    procedure One(a: array of char): integer;
    begin return len(a) end One;
    begin Out.Int(One("abc"), 0); Out.Ln end

`Parse_Actual`'s string-literal branch did `A := Parse_Expr; return A;` - pushing the literal's
ADDRESS and nothing else - while the VARIABLE branch beside it has always pushed address AND
length.  So an ARRAY OF formal called with a literal left its length slot holding whatever the
next actual had left there, the caller under-pushed by one, and the VM's verifier rejected the
whole image.  Fixed by pushing the literal's length as a constant (the count comes from the
source text, because a string in the CONST payload carries no length of its own), and pinned by
`tests/bc/litarg.ob2` - a literal actual and a variable one, both lengths checked, printing 3
and 8.

**How it was found is the part to keep.**  Six shapes were tested and DISPROVED one at a time
(one open formal, two, forwarding, a nested call with an open actual, nested calls with an INT
formal, an early return) - every one of them working in isolation, which is what a corpus of 85
fixtures had said all along.  What finally pointed at it was not reasoning but the diagnostic
that now reports **the depth and the limit** on a stack violation, and then the CAUSING
instruction: the depth was `-1` (not over-limit), and the instruction was `Call_Native`, i.e. the
consumer of a value that was never pushed.  The pattern fell out of the disproofs once they were
written down: **every failing case passed a string literal, every passing case did not.**

That diagnostic had one off-by-one of its own, worth recording: the offset is reported *after*
the arm has advanced `PC`, so the first version named the NEXT instruction.  It now captures the
opcode before the case - "report the instruction that caused it, not the one after it".

**And with that fix the lever moved, for real this time.**  `Strings` compiled from its own body
runs `Length`, `Pos` and `Cap`, and

    Scoped => True    hello.ob2 refuses at   bytecode backend: Texts.OpenWriter is an FFI ...

- the metric's first genuine movement in this whole workstream: past a whole library, to the next
one.  The refusal that stood there for twenty sessions is gone.

**It is still not landable, because a THIRD blocker appeared** - a smaller one each time:

    Scoped => True, and by hand:   Strings.Pos ("world", s) from a program
    -> vm: internal error in phase 3: STORAGE_ERROR (stack overflow ...)

`Length` alone runs; `Pos` crashes almost certainly by recursing into itself, i.e. **an
intra-module call inside a compiled library body resolves to the wrong procedure id**.  `Pos`
calls `Length(s)` twice, `Cap` calls `Length(s)`, which is exactly the shape that no fixture has
ever exercised: a call to a sibling procedure *inside a module whose bodies are emitted*.  So
`Scoped => False` is restored, `bytecode_gaps.sh` keeps its `Strings.Length` entry (with a
pointer here), and the metric is back at `Strings.Pos`.

**The three stops, in order, and each one smaller than the last:** a parameterless function
call emitted nothing (3cb); a literal actual passed no length (this); an intra-module call
inside a library body mis-resolves.  The next attempt at the lever starts there.

Evidence: `run_bc` green including `litarg`; the identity net unchanged for every other fixture;
gate42.

### 3cf. CORRECTION — the third blocker is a RUNTIME wild access, not the builtin path

3ce's entry ends with a hypothesis: `Strings.Pos` crashes because "an intra-module call inside a
compiled library body resolves to the wrong procedure id".  **The hypothesis is wrong**, and the
probe that disproves it took one command: the SAME body as a plain USER module (`b4`, and its
three variants `w6a`/`w6b`/`w6c`) crashes identically, and a user module has no `Scoped`, no
builtin and no library path at all.  The builtin is not implicated.

**What the crash actually is.**  The VM's own phases say it:

    Phase := 2;  Verify (...)              <- the verifier
    Phase := 3;  return Run_Context (...)  <- the interpreter
    exception when E : others => Note ("internal error in phase" ...)

so `internal error in phase 3: STORAGE_ERROR (stack overflow or erroneous memory access)` happens
**while the program is RUNNING**, and the catch-all then reports `Bad_Code` - which is the
"malformed code" line that follows.  The image is fine; the run walks somewhere it must not.

**And it was always there, masked by the verifier.**  Before 3ce, these four bodies failed
*verification* ("depth -1") and never ran.  Fixing the literal-length bug made them verify - and
then they crash.  So the verifier's complaint had been hiding a runtime defect, which is the
opposite of the usual relationship between those two and worth noting: a failure report can mask
a *different*, deeper failure.

**The boundary, measured:**

    S1    two sibling calls with open-array actuals, a simple body          runs, prints 32
    z1    one open formal, a literal actual                                 runs, prints 3
    b4/w6a/w6b/w6c   `Pos`'s body, or a variant of it                       CRASH in phase 3

`w6a` is the smallest known failure at 648 bytes, and it is the thing to bisect next.

**The diagnostic gap, named**: the handler that reports phase 3 lives OUTSIDE the interpreter, so
it has no `PC` and cannot say which instruction walked off.  The verifier learned to report its
depth, its limit and the causing opcode (3cd); the interpreter has not had the same treatment.
The next diagnostic step is inside `Run_Context`: either report `Ctx.PC` on the catch-all, or -
better, and matching the project's rule that a malformed image must be REJECTED rather than crash
the VM - check the address before dereferencing it and return a status with the PC attached.

### 3cg. THE METRIC MOVES — `Strings` compiles its own body, and the lever is LANDED

This is the milestone the last four stages were walking toward.  `Compile_Builtin
(Oak_Strings_Src, Scoped => True)` - one flag - and

    hello.ob2 refuses at   bytecode backend: Texts.OpenWriter is an FFI primitive ...

**past the whole Strings module**, where it had refused at `Strings.Pos` for twenty sessions.
`Length`, `Pos` and `Cap` all run, and they run *correctly*: `Pos ("world", s)` is 6, `Pos
("zzz", s)` is -1, `Cap` uppercases.

**And the crash that blocked it was the sixth defect on the path, with a one-line cause.**
`Strings.Pos` had stopped failing *verification* and started SIGSEGV-ing *inside the interpreter*
(`obc_vm.execute`), which `Run_Buffer`'s catch-all reports as `malformed code`.  The cause, once
the diagnostic said "phase 3" and gdb said which function:

    a string LITERAL actual pushed the literal's pool WORD - an OFFSET into the CONST
    payload, which is what Copy_Str indexes with - where an ARRAY OF CHAR formal is
    passed an ADDRESS.  The callee dereferenced offset 3.

That is the *second* half of 3ce's bug, and 3ce's fix is what made it reachable: before, the
image failed verification (loud) and never ran; after, it verified and crashed (silent).  A crash
is worse than a refusal, so it was fixed in the same commit series rather than left.

**The fix is a wire-format addition**, appended in the reserved range beside Band/Bor:

    Op_Str_Addr / 16#74#   pop a string WORD, push the ADDRESS of its characters
    emitter: Str_Addr op, Byte_Of 16#74#, and Resolve_Str (the PROCEDURE is named for
             what it does to the stack, because an enum literal and a subprogram cannot
             both be named in a statement - GNAT: "expect procedure name in procedure
             call", one of two build errors this cost)
    VM: the opcode, the interpreter arm (both bounds checked - a malformed image is
             rejected, never allowed to dereference), the verifier arm
    compiler: a literal actual resolves the word and then pushes its length

`tests/bc/litarg.ob2` grew both halves - `Put ("xyz")` for the length and `Get ("Qrs")` for the
dereference - so the bug that a literal actual used to be is now the fixture that holds it.

**The ledger, all six, and where each is now:**

    3cz  a parameterless function call emitted NOTHING                     fixed, parfn.ob2
    3cc  a `var ARRAY OF` element write emitted NOTHING                    fixed, vararr.ob2
    3ce  a literal actual passed no LENGTH                                 fixed, litarg.ob2
    3cg  a literal actual passed an OFFSET where an address was needed     fixed, litarg.ob2
         (two of these were SILENT wrong answers, one a verifier rejection, one a crash -
          and none of the four could be written as a fixture before the others were fixed)

**What the metric says now, and what is next.**  `Texts.OpenWriter` is the new refusal, so the
next library is Texts - and `Scoped => True` for it is the same one-line change, gated on
whatever its bodies need.  The corpus grew to 87 fixtures with `strlib.ob2` and `litarg.ob2`, and
`bytecode_gaps.sh` lost its `Strings.Length` entry in the same commit, which is the rule it
exists to enforce: "an entry that stops applying FAILS".

### 3ch. Texts — the lever moved again, and stopped on the ABI's OWN COUNT

`Compile_Builtin (Oak_Texts_Src, Scoped => True)`, one more flag:

    hello.ob2 refuses at   bytecode backend: Files.Old is not yet supported

past the WHOLE Texts module this time.  But a probe that USES Texts fails verification -

    Texts.OpenWriter (w); Texts.WriteString (w, "hi "); Texts.WriteInt (w, 42, 0); ...

    vm: operand-stack depth violation at code offset 1540: depth -1, limit 20, opcode 192

- and `192` is `Call`, the *causing* instruction.  So the flip is reverted again (metric back at
`Texts.OpenWriter`), and this time the cause is not a missing emission: it is a COUNT.

**What the VM's own code says.**  An `ARRAY OF` formal occupies TWO stack slots - the address and
the length that travels with it - while `NParams` counts it as ONE.  And:

    interpreter  when Op_Call:  if SP < Img.Procs (Callee).NParams then return Bad_Stack;
                                Push_Frame (Callee, PC + 5)
    verifier     when Op_Call:  Depth := Depth - NParams + NResults

`Push_Frame` moves the callee's SLOTS - which is why every open-array call has worked at runtime
all along - while the interpreter's *guard* and the verifier's *model* both use the FORMAL count.
So the drift is one per open-array formal, in the models only.

**Why the corpus never saw it.**  `Depth_Ok` is a BOUNDS check (`0 <= depth <= stack_max`), so a
drift of one is invisible until it crosses zero or the limit - and no fixture calls a procedure
with more than one open formal from a position deep enough for that.  `Texts.WriteString (var w;
s: array of char)` is exactly such a call, and multiple `Write*` calls in one body accumulate.

**And the fix has a shape, not a guess**: the procedure record needs the PARAMETER SLOT count
(the emitter knows it; `Push_Frame` already behaves as if it existed), and the verifier's CALL arm
and the interpreter's guard should both use it instead of `NParams`.  That is a record-format
change rather than an appended opcode, which is why it is the next session's work and not this
one's - and `Texts.WriteString`'s call, above, is its reproducer.

**A correction to the last four entries' framing**: the "depth -1" family was read as several
distinct causes, and two of them were real and fixed (3ce's missing length, 3cb's missing call).
What remains after those is THIS ONE: a model that counts formals where the machine moves slots.

### 3ci. A record ACTUAL — the fourth "no bytecode branch" path, and why it REFUSES

3ch's data (depth -1, causing opcode `Call`) went one step further and found a fourth path of
the same class as 3cb/3cc/3ce.  The reproducer is twelve lines:

    type W = record pos: integer end;
    var w: W;
    procedure Set (var x: W);
    begin x.pos := 7 end Set;
    begin w.pos := 1; Set (w); Out.Int (w.pos, 0); Out.Ln end

`Parse_Actual`'s record/array branch - "a variable of exactly this type" - checks the name,
copies its text and RETURNS: **no `Bytecode_Mode` emission at all.**  So the caller pushed
nothing where the callee's frame expected an address, and the verifier's depth went to -1 at the
call.  Same shape as 3cb (a parameterless call), 3cc (an ARRAY OF element write), 3ce (a literal
actual) - four paths, one habit.

**And the obvious fix makes things WORSE, which is the finding.**  Pushing the variable's address
is right, and it removed the verifier violation - and then `r1` printed **1** instead of **7**
and `r3` printed **0** instead of **3**.  The reason is on the CALLEE's side: inside the callee a
record formal's designator chain resolves its name as a GLOBAL, so `Push_Base` interns a run
called `x` and the store lands in a fresh zeroed global while the caller's record is untouched.
A loud verifier rejection had become a SILENT wrong answer.

So it **refuses**, which is the project's default and the honest state:

    o2c error: bytecode backend: a record or fixed-array actual is not yet supported ('w')

and `bytecode_gaps.sh` pins it as `blocked`, so the entry FAILS when the real fix lands.  That
fix is the same rule the ARRAY OF path already has - **a parameter's address is in its own slot,
so the chain loads it rather than interning a global** - and `r1`/`r3` are its reproducers.

**No fixture was passing a record actual** (the corpus's record work is globals and pointers),
which is why 88 fixtures never said a word.  `run_bc`, `bytecode_gaps` and `coverage` are green
with the refusal in place: a construct that cannot be expressed now says so, in the same shape as
its three predecessors.

### 3cj. Record actuals WORK — and with them Texts, so the metric is at Files

3ci's refusal is gone, replaced by the fix it named, and one more library came with it.

**The fix is ONE procedure where there were two copies.**  `Bc_Base` decides a record/array
base's address by three cases, and the copies got the first wrong:

    a VAR formal      its slot holds the CALLER's address, so the base is that value -
                      `Bc_Load` - not a global run of its name
    a LOCAL variable  has no address in this VM (3br's reserved Op_Addr_Local), so it REFUSES
    a GLOBAL          is a run in the image's globals block

Both copies of the base derivation called `Addr_Global` unconditionally, which is why a store
through a record formal landed in a fresh zeroed global.  And the *caller* side is one line -
push the variable's address - which 3ci deliberately withheld while the callee was broken,
because doing it first turned a loud verifier rejection into a silent wrong answer.

    r1   `Set (w)` then `Out.Int (w.pos, 0)`      1 -> 7
    r3   `Show (w)` reading `x.pos`               0 -> 3

`tests/bc/recactual.ob2` is that fixture - the one that could not exist an hour ago - and
`bytecode_gaps.sh`'s `blocked` entry is gone, leaving its history in a comment.  That entry would
have FAILED had it stayed, which is what it was for.

**And with the record actual fixed, Texts landed too.**  `Compile_Builtin (Oak_Texts_Src, Scoped
=> True)` - which every `Texts.OpenWriter` and `Texts.Write*` call was blocked on, since all of
them pass a `var Writer`:

    Texts.OpenWriter (w); Texts.WriteString (w, "hi "); Texts.WriteInt (w, 42, 0);
    Texts.Write (w, "!"); Texts.WriteLn (w)        ->  prints  hi 42!

    hello.ob2 refuses at   bytecode backend: Files.Old is not yet supported

**Two libraries in one session, and the ledger is now seven:**

    3cb  a parameterless function call emitted NOTHING                    fixed, parfn.ob2
    3cc  a `var ARRAY OF` element write emitted NOTHING                   fixed, vararr.ob2
    3ce  a literal actual passed no LENGTH                                fixed, litarg.ob2
    3cg  a literal actual passed an OFFSET where an address was needed    fixed, litarg.ob2
    3ci  a record actual emitted NOTHING                                  fixed, recactual.ob2
    3cj  ... and the callee resolved its name as a GLOBAL                 fixed, recactual.ob2
    3cg/3ch  Strings and Texts now compile their own bodies               strlib, textslib

`textslib.ob2`'s body also carries `Texts.Write`'s own `t[0] := ch` - an indexed write into a
LOCAL array - so the library fixture is testing the corpus's blind spot rather than repeating it.

**The next refusal is `Files`**, and its bodies are a different kind of test again: `Files` is
where the intrinsics (3l's `FStat`/`FRead`/`FWrite`/`FClose`) live, and its own body is what
`Files.*` in user code reaches.

### 3ck. Files COMPILES — and does not work, so the flip stays out

`Compile_Builtin (Oak_Files_Src, Scoped => True)` was measured, and it is the first library in
this run whose flip is not landable for a *behavioural* reason rather than a crash or a refusal:

**It compiles, and the metric moves past it:**

    hello.ob2 refuses at   bytecode backend: Math.ln is not yet supported

- a third library's bodies in the image, and the refusal now sits in Math.

**But the file operations do not work.**  A probe that writes three bytes through a Rider, reads
the length back and then reads the bytes:

    f := Files.New ("probe.txt"); Files.Register (f); Files.Set (r, f, 0);
    Files.WriteString (r, "abc"); Files.Close (r);
    if Files.Length (f) = 3 then Out.String ("3") else Out.String ("?") end;
    Files.Set (r, f, 0); Files.Read (r, c); Out.Char (c); ...

prints `?` and three blanks - so the length is not 3 and the writes did not land.  A SILENT wrong
answer, which is worse than the refusal it would replace, so:

    Compile_Builtin (Oak_Files_Src, Scoped => False);   --  restored

**Why, and it is the same shape as 3l.**  `Files` is the one library whose members are reached
today as VM NATIVES - `Files.Delete` and `Files.Rename` are in the wired set, and the intrinsics
(`FStat`/`FRead`/`FWrite`/`FClose`) are the Ada-level helpers of 3l, dispatched by MODULE NAME
when the builtin's own source calls them (§3aw's region A).  Flipping the module replaces those
native routes with CALLS TO THE BODIES, and the bodies were authored for the Ada path: the
intrinsic calls inside them are wired, but what the bodies compute around them is not right yet.

**So the probe above is the reproducer and the test**, and the next step is to find which of
`New`/`Register`/`Set`/`WriteString`/`Close`/`Length`/`Read` disagrees - the same bisect the
`Pos` work used, and it has the same kind of net: two of those (`Delete`, `Rename`) already have
fixtures from the wired-native era, and `filesintr.ob2` pins the intrinsics by EFFECT.

Nothing else changed: record actuals and the Texts flip are committed (3cj), the metric is back at
`Files.Old`, and the ledger stands at seven.

### 3cl. The Files bisect, measured: New is fine and NOTHING is written

3ck left the question "which of New/Register/Set/WriteString/Close/Length disagrees".  Two probes,
with the flip in, answered part of it and stopped at a wall worth naming:

    f := Files.New ("fb.txt");
    if f = NIL then Out.String ("new=NIL") else Out.String ("new=ok") end;   ->  new=ok
    Files.Register (f); Files.Set (r, f, 0); Files.WriteString (r, "abc");
    Files.Close (r);
    if Files.Length (f) = 3 then Out.String ("3") else Out.String ("NOT-3") end;

So `New` returns a VALID file object, the write lands NOWHERE (no file appears on the host, and
the earlier probe's file - the one that turned up in the repo root with a garbage name - is the
only trace any Files write has ever left), and `Length` disagrees.

The second probe was meant to read the rider's `f.name` back and was refused: "field 'f' of
Files.Rider is not exported", which is correct - and it is also the reason the NEXT step needs a
different instrument.  The name has to be observed through the library's own API (write a known
name, then ask `Files.Old`), not by reaching into a record.

**The shape of the remaining work, stated so the next session does not have to rediscover it:**
the Files bodies were authored for the Ada path, where the intrinsics are Ada-level helpers whose
behaviour the *host* compiler supplies.  In bytecode the same bodies reach the intrinsics through
3l's native dispatch, and everything *around* those calls - the FileDesc bookkeeping, the Rider's
position, the name handling - is what the two probes say is wrong.  That is a CLUSTER, not one
line: expect the same population of small defects as the Strings/Texts path had (six, in the
end), and expect the fixtures to come from OBNC's `FilesTest.obn` rather than from `tests/bc`.

The flip is out again; the metric is at `Files.Old`; the ledger still stands at seven.

### 3cm. The Files bisect, continued — every SHAPE is fine, so the suspect is the NATIVE ARGUMENT

3cl stopped at "New is fine and nothing is written".  Four more measurements, all with the flip in,
narrow it further - and two of them correct what the earlier entries implied.

**What is now PROVEN GOOD, shape by shape** (each a user module, none of them using Files):

    an indexed write into an ARRAY FIELD through a pointer      p^.n[0] := "Z"        ->  ZY
    Files.New's exact combination - a LOCAL pointer, an open-array formal, the 64-step
    name loop with its if/else, the field written through it                          ->  ZY
    Files.Set's shape - a `var Rider` record formal written field by field,
    including a POINTER field, read back                                              ->  7 same

**And the intrinsics ARE emitted inside the compiled library**: the image for a probe that only
calls `Files.Old` contains `CALL_NATIVE id=9 arity=1`, which is `FStat` (§3aw's region A, keyed on
the module being compiled).  So "the builtin's own body reaches its intrinsic" works, which was the
first thing to doubt.

**A correction to 3ck/3cl**: `Files.Length (f)` returning 0 after the write is *consistent* with
the write not landing - `New` sets `size := 0` and nothing increments it - so `Length` is not wrong
and this is not a second defect.  The failure is one thing: **the write through a Rider does not
reach the file.**

**So the suspect is the ARGUMENT CONVENTION for a native that takes an `array of char`.**  In the
library body `FStat (name)` passes an open-array formal, and the same shape appears in `Write`/
`WriteString`.  The question to measure next is narrow and mechanical: compare those call sites
against the `Out.String (s)` call sites, which are known to work, since both hand a native an
`array of char` argument - if one pushes an address and a length where the other pushes one word,
the mismatch is the whole bug, and it is the same formal-versus-slot question 3ch raised for CALL
and never resolved for CALL_NATIVE.

The flip is out; the metric is at `Files.Old`; the ledger stands at seven, with one correction.

### 3cn. A DISPROOF — the native argument convention is consistent, so look in the VM

3cm's "suspect" was the argument convention for a native taking an `array of char`: `FStat (name)`
in the library body against `Out.String (s)`, which works.  Both sites were read, and they AGREE,
so the hypothesis is dead:

    region A (the builtin's own body, Mod_Name = "Files"):
       FDel:  Parse_Expr pushes the address - "an ARRAY OF parameter pushes its caller's address
              and a module-level array pushes its globals address" - then Call_Native (9, 1)
    region B (user code):
       Files.Delete:  Addr_Global (name, slots)  --  ONE slot, the address  --  Call_Native (9, 1)

One argument, the address of the name, in both.  And that is right: a whole `array of char` used as
a VALUE pushes one word in this VM - the address - which is the same thing `Out.String` receives.
Two paths, same convention, and `Put ("xyz")`/`Get ("Qrs")` in `litarg.ob2` pin it from the other
side.

**So the disagreement is not in the compiler, and the next place to look is the VM's own file
natives** - `O2c_FDel`/`O2c_FStat`/`O2c_FWrite` and what they do with a FileDesc whose `name` field
the library just filled in 64 bytes of CHARACTERS, while `size: longint` sits at offset 64.  The
measurable question, and it is one command: does a *name* written through the library survive to
the host filesystem under THAT name?  The earlier probe's file turned up with garbage bytes in its
name, which is the strongest single clue in this whole hunt, and it is a clue about what the native
reads, not about what the compiler pushed.

Nothing changed in code this round: a hypothesis tested and killed, which is the outcome the method
section asks for.  The flip is out, the metric is at `Files.Old`, and the ledger stands at seven.

### 3co. Files: every SHAPE works, and the one that fails is IDENTICAL to one that works

3cn said the compiler was cleared and the VM's natives were next.  That was too fast.  Four more
measurements, and the last one changes the question.

**The one command 3cn asked for, run from a scratch directory:**

    Files.New ("out.txt"); Files.Register (f); Files.Set (r, f, 0);
    Files.WriteString (r, "abc"); Files.Close (r);
    -> a file appears with a GARBAGE NAME ('(p\x0f...') and the content b'((('

So the writes DO reach the host - the name and the bytes are both wrong - which rules out "nothing
is emitted" and points at values, not plumbing.

**Every shape, then, measured against it:**

    a 64-char array field + a longint, written through a pointer   (Files.FileDesc's layout)  ABC, size-ok
    a string LITERAL actual passed ACROSS a module boundary        Lib2.New ("out.txt")      out
    Files.New's own source, as a USER library                      (the same twelve lines)   out
    a `var Rider` written field by field, pointer field included                             7 same

Every one correct.  And the last one is the finding: **`Files.New` and `Lib2.New` are the same
twelve lines** - a local pointer, `new (f)`, the 64-step loop with `if i < len (s)`, the write
through `f^.name[i]` - and one is right while the other writes a garbage name.  The difference is
not the language, the layout, the open formal, the literal actual, or the module boundary: it is
that one is compiled as a BUILTIN (`Compile_Builtin`, `Scoped => True`) and the other as a user
library.

**So the next step is a byte comparison, not another probe**: dump `New`'s code out of a
Files-flipped image and out of the user-library image, and diff them.  They should be identical -
same source, same compiler - so a difference names the bug directly, and no difference means the
builtin path is fine and the fault is in what the module's FIRST compilation left behind.

The flip is out; the metric is at `Files.Old`; the ledger stands at seven.  Four of this session's
Files entries were hypotheses, and three of them died on contact with a measurement - which is the
case for measuring before editing that the method section keeps making, at a cost of one turn each.

### 3cp. The Files comparison, and its instrument — which does not exist yet

3co asked for a byte comparison of `New` between the builtin and user-library images.  Two facts
came out of setting it up, and neither is the comparison itself.

**The procedure table's stride is 24 bytes** (`Proc_Rec`), not the 16 the record's field layout
suggests - `code_off` u32, `frame_slots` u32, `n_params` u16, `n_results` u16, `stack_max` u32 is
20, and the record is padded.  My first parse read every other record as garbage (`nparams = 841`)
and would have produced a confident, wrong comparison; the VM's own constant corrected it.

**And the image carries no name map.**  Both images have only sections 3 (TYPES), 4 (CONST), 5
(DATA) and 6 (CODE) - no EXPORT, no DEBUG - so there is no way to ask an image "which procedure is
`New`".  That is why the harness has always taken names from the SOURCE and offsets from the
image, and it means the comparison needs a **disassembler over the proc table** rather than a name
lookup.

**So the instrument is the next step, not the finding.**  Two ways to get it, and the first is
cheap: emit the DEBUG section (the spec reserves id 7 for exactly this, *"source file names, line
table, procedure names"*, and the header already has the flags slot for it) and the comparison
becomes a lookup.  The second is a disassembler in the harness.

**Where the Files hunt stands after five entries:** the compiler is cleared (3cn), the native
argument convention is consistent (3cn), every language shape is correct including the exact layout
and the cross-module case (3co), the writes reach the host with the wrong values (3co), and the
one thing that differs between a working `New` and a broken one is that one is a BUILTIN.  Each of
those was a measurement, and three of them killed a hypothesis.  That is the method working, and it
is also slow - the honest read is that Files is a CLUSTER (3cl predicted six defects; the Strings
path had six) and that the same effort spent on a SWEEP for the class would cover more ground:
every instance of it so far - 3cb, 3cc, 3ce, 3ci - was a parser branch that appends Ada text with
no bytecode call and no refusal, and a scan for that shape would have found all four at once.

### 3cq. The SWEEP — the class had two more instances, and both were SILENT

The 3cp analysis said the four known instances of this class were all the same habit: a parser
branch that builds Ada text and emits no bytecode and no refusal.  So the sweep is mechanical: scan
every `Append_Body` site, take a window around it, and keep the ones with no emit and no `raise`.

    87 Append_Body sites, 11 candidates, 1 of them the definition itself

Three reviewed out as by-design - the dynamic-dispatch text at 2655-2681 (whose bytecode the caller
emits), the method call inside `Parse_Case` at 8536, and `Parse_Actual`'s method text.  The rest were
probed, and TWO were live:

    r := {a = 1, b = 2}     printed 00    (expected 12)   RECORD aggregate
    a := {1, 2, 3}          printed 000   (expected 123)  numeric ARRAY aggregate

**Both compiled, ran, and left their target untouched.**  That is the worst shape this project has a
rule against, and neither was visible in the corpus because no fixture uses an aggregate - which is
exactly why the sweep was worth a turn and the Files bisect was not.  Both now REFUSE, and both are
pinned in `tests/bytecode_gaps.sh` as `blocked` so the entries fail when the real fix lands: the
field and element stores whose offsets and kinds the type descriptor already carries.

**And the sweep produced a rule, which is the more durable result.**  The third candidate in that
review, XYplane's `Open`/`Dot` in REGION A (the builtin's own body, 7455/7464), also emits no
bytecode - and it is the same class, in the *other* half of the intrinsic dispatch, reachable by a
user module named `XYplane` exactly as `filesintr.ob2` reaches Files.  So:

    Before flipping a builtin to Scoped => True, audit its region-A arms.
    Region B is wired per member; region A is hand-written per arm and can be silent.

That is why `Files` was not a mystery and is not a cluster of six: some of its region-A arms emit
(the FStat/Delete pair 3cn read) and the question 3co posed - why one `New` works and the other does
not - is the next entry's business, not this one's.

### 3cr. The region-A AUDIT — four silent arms, and the Math flip is BLOCKED (not silent)

Gate 46 came back green on all seven suites, which clears the debt 3cq left open.  Then the audit,
because 3cq's *rule* was worth checking before acting on it - and checking it was right.

**The audit**: every arm keyed on `To_String (Mod_Name) = "..."` (the intrinsic dispatch), classified
by whether its body makes an EMITTING call (`O2c_Ir_Lower.` / `Call_Native` / `Bc_*`) or REFUSES
(`Wrong_Construct`) or does neither.  34 sites, 12 of them the Ada-side foreign declarations rather
than arms.

    region A (the expression dispatcher, 7262-7548):  Convert REFUSES, Env REFUSES, Args REFUSES,
                                                      XYplane REFUSES, In REFUSES, Files EMITS x2
    the older cluster (3147-3481):                    Math SILENT, Args SILENT, Input SILENT,
                                                      In SILENT, MathL REFUSES, XYplane REFUSES,
                                                      Reals REFUSES, Files EMITS x2

**Two corrections to 3cq, both mine.**  First, "region A is hand-written per arm and can be silent"
is simply false: it emits or refuses, every arm.  Second, the XYplane arm I had called a silent gap
is a *deliberate refusal* (7416, with the comment "Refused in bytecode mode rather than silently
emitting nothing") - my scan had classified it EMITS because the `emits` regex matched
`O2c_BC.Bytecode_Mode`, the guard itself.  A classifier that counts a guard as an emission is worse
than none; the rerun tests for an emitting *call*.

**What IS silent, and why it matters**: four arms in the older cluster - Math's and MathL's
transcendentals (Power, Exp, Ln, Log, Sin, Cos, Tan, ArcSin, ArcCos, ArcTan, ArcTan2), Args.ArgCount,
Input's InAvail/InReadCh/InTime, and In's InChar/InInt/InLong/InReal.  Each is reachable exactly as
`filesintr.ob2` reaches Files - a module NAMED after the builtin calling the intrinsic BARE - and a
flipped builtin's own body does the same thing.  So the audit answers the question it was run to
answer: **flipping Math today would produce a silently wrong body**, because Math's own source
computes with Ln/Sin/Cos and there is no bytecode path for them anywhere.  Refused now, with four
pinned reproducers whose messages each name their own arm, which is stronger evidence than the
suite's ok/blocked - it shows each probe reached the site it was written for.

**So the Math flip is BLOCKED, not pending**: the transcendentals need natives and VM arms
(append-only ids) before the flip is anything but a wrong answer.  That is a feature, not a bug
hunt - and finding it before the flip rather than after is the whole reason to audit first.

### 3cs. The disassembler, and a blocker that is now one measurement wide

3co asked for a byte comparison of `New` between the builtin and user-library images and 3cp found
no instrument for it: the image carries no name map.  So the instrument was built -
`tools/bc_disasm.py`, whose opcode table is parsed out of `docs/obc-image.md` rather than copied, so
it cannot drift from the spec.  104 opcodes, procedure table and bodies, operands decoded.

**What it showed, and it is all negative - which is worth as much:**

    Files.New   (builtin image):  LOAD_L 3, DROP, ALLOC_NEW 1, STORE_L 3, ...  identical in shape
    Lib2.New    (user-library):   LOAD_L 3, DROP, ALLOC_NEW 21, STORE_L 3, ...  to Files.New
    Files.Old   (builtin image):  ... LOAD_L 0, CALL_NATIVE (26, 1), STORE_FLD_I 72 ...

The native ids are RIGHT, on both paths, against the VM's own table: `Max_Natives = 5`, so id =
entry + 4, and entry 5 `o2c_fdel` = 9, entry 6 `o2c_frename` = 10, entry 22 `o2c_fstat` = 26, 23
`o2c_fread` = 27, 24 `o2c_fwrite` = 28, 25 `o2c_fclose` = 29.  The compiler's comments ("Native id 9
(o2c_fdel)", "Native id 10 (o2c_frename)") and the builtin path's emission (`FStat` -> 26) both agree
with the table.  I called this "found it" mid-measurement and it was not found; the ids check out.

**And that leaves exactly one difference between the two `New`s:**

    Files.New allocates ALLOC_NEW 1        Lib2.New allocates ALLOC_NEW 21

Everything else is the same sequence.  So the remaining blocker is one question, and it is one
measurement wide: **is descriptor 1 in that image actually `FileDesc`** - 64 chars plus a longint, 72
bytes, field `size` at offset 72 - **or is it something else the image declared first?**  If it is
not, `new (f)` allocates the wrong size, the loop's writes land outside the object, and every
Files symptom follows: the garbage name the host filesystem saw, and `Length` reading 0 because the
two fields overlap instead of sitting 72 bytes apart.  Listing the TYPES descriptors with their
sizes and name refs settles it, and that is the next command, not the next turn's design.

### 3ct. ROOT CAUSE — an array-valued FIELD has no correct lowering, and Files is built on one

3cs left one question: is descriptor 1 the `FileDesc`.  It is, and the answer resolves the cluster.

**The descriptor** (TYPES is 24 bytes, one descriptor, in the flipped-Files image):

    kind=3 (RECORD)  flags=0  size=80  name_ref=0   no field metadata   +16 has a 1

`FileDesc` is `name: A64; size: longint` = 64 + 8 = 72, but the size is **80** - and the emitted
store is `STORE_FLD_I 72`, i.e. `size` sits at 8 + 64.  So the fixed array field carries an **8-byte
length word in front of its 64 characters**.  That is the layout; the question is who disagrees.

**The natives do.**  `o2c_fstat`/`fread`/`fwrite`/`fclose` are in `obc_vm.adb` 1528-1585 and they read
the name with `Name_At (Args (0))` - bytes from the address given, from offset **0**, to a NUL, "as
every string here is".  The Oakwood contract assumes the characters start at the address passed.

**And the compiler cannot produce that address for a field.**  Two probes:

    Out.String (fp^.name)   ->  vm: malformed code        (the verifier rejects the image)
    Show (fp^.name)         ->  'fp' is not an array variable   (refused)

So an array-valued field has no correct lowering: the value path REFUSES, and the `Out.String`
intrinsic emits an image that will not load.  Both are loud, which is the rule working.

**Files is built on exactly that construct, through the intrinsic arms** - `Read`, `Write`,
`WriteString` and `Close` all pass `r.f^.name` to a native:

    r.res := FRead (r.f^.name, r.pos, r.cur);      r.res := FClose (r.f^.name)

The intrinsic arms accept any expression, so they do not refuse - and there the push is silently
wrong, which is why the flipped image RAN and wrote a file with a garbage name instead of failing.

**That is the whole mystery, and it explains every symptom the last six entries measured.**  `New`
is fine and identical to `Lib2.New` (3co/3cs) - it only does INDEXED writes, which are fine.  The
garbage name on the host filesystem came from `FWrite (r.f^.name, ...)`, which opened the file at a
garbage address: the name was never wrong, the ADDRESS was.  `Length` read 0 because nothing was
ever written through a correct name.  And the reason a builtin `New` and a user `New` behave
differently is that the user one is never reached with an array-valued field: `Show (fp^.name)` is
refused, so no user module can even express the construct - only a builtin's own body can, through
an intrinsic arm, which is the one path that does not check.

**So the Files fix is a feature, and a small one**: lower an array-valued field to the ADDRESS of
its characters (the natives' contract, offset 0 of the field's data, not of the field's storage),
in the intrinsic arms and the value path alike.  Then `FRead`/`FWrite`/`FClose` get a real address,
and the Files bodies become correct - they are already correct in every other respect.

### 3cu. The lowering is located, and the fix is a missing ARGUMENT

3ct said the fix is "lower an array-valued field to the address of its characters".  The code that
does that already exists - and the reason a field is wrong is visible without running anything.

**The address arithmetic lives in `O2c_Ir_Lower.Addr_Global`, and both indexed paths already call it
with three arguments:**

    the `[` branch, scalar element    (2142):  Addr_Global (Base_Name,
                                                 (if Is_Ptr or Base_On_Stack then 0 else Total_Slots (Base_UT)),
                                                 Nested)
    the `[` branch, user-typed row    (2180):  the same, to make the two agree after they diverged

`Nested` is the accumulated field offset, and its comment says why the second argument is
conditional: a POINTER's `Total_Slots` is zero, so a field reached through a pointer must be given
its offset explicitly - "the diagnostic blamed the array's length while the length was fine and the
address was a globals slot that does not exist".

**The value path calls the same primitive with TWO arguments** (2298, at the end of
`Parse_Rec_Ptr_Chain`, under `if VK = V_Arr and then UTypes (UT).Elem = T_Char`):

    Addr_Global (Base_Name, Total_Slots (Base_UT))          --  no `Nested`

So a field's characters are addressed as if the field began at the object's base.  That is the
missing argument, and it is the whole of 3ct's root cause.

**And the layout question that looked like it might be the bug is answered, and is not a bug.**  The
array field's characters start at the field's own offset; the 8-byte word that made `FileDesc` 80
bytes instead of 72 sits *after* the 64 characters (the length word at 64, `size` at 72), which is
exactly why `Field_Offset (name)` is 0 and why the natives' `Name_At` - which reads from the address
given, offset 0, to a NUL - is consistent with the indexed access `f^.name[i]`.  The two agree.  The
value path is the only party disagreeing.

**The remaining blocker is one read and one edit**: `Parse_Factor`'s handling of an array-char
designator, to see why `Out.String (fp^.name)` produced `vm: malformed code` when 2298 should have
pushed an address - either the factor discards a value the chain pushed (a depth mismatch the
verifier caught) or the chain's push is skipped and the factor never compensates.  Then 2298 takes
its third argument like its indexed siblings already do, and `fldv.ob2` / `fldv2.ob2` (kept in
/tmp, reproduced in 3ct) become the fixtures: `Out.String (fp^.name)` should print ABC, and
`Show (fp^.name)` should stop being refused.

### 3cv. 3cu was INCOMPLETE — the missing `Nested` is real but is not this bug

3cu concluded the fix was 2298 taking its third argument.  The edit was made, mirrored exactly from
the indexed sibling at 2142 - and it changed nothing, so it was REVERTED rather than landed.

**Two probes, and the second is the one that decided it:**

    fldv.ob2   `name: A64` as the FIRST field   (so Nested is 0 either way)
    fldv3.ob2  `pad: integer; name: A64`        (so Nested is 8 and the edit must matter)

Both fail identically.  With `Nested` supplied, a field that is NOT at offset 0 still fails - so the
failure cannot be the missing offset, and 3cu's "one read and one edit" was wrong about the edit.

**And the failure was not what I had been reading.**  `vm: malformed code` was the SECOND line; the
first is

    vm: internal error in phase 3: CONSTRAINT_ERROR (obc_vm.adb:2067 range check failed)

i.e. a NATIVE indexing `Args (0)` on an argument list that is too short, at RUNTIME.  The image
PASSES verification - the error comes after, from the interpreter's own `Call_Native`.  So for "an
array field used as a string value" the verifier's static model and the actual pushes disagree, and
it is loud: an internal error, then malformed code.  Every `tail -1`/`tail -2` in this session hid
that line, which is a reading habit worth naming - the diagnosis turned on `head`, not `tail`.

**What that leaves, stated as narrowly as the evidence allows:**

    - `Out.String (fp^.name)`       fails at runtime, field offset irrelevant
    - `Show (fp^.name)`             still refused by Parse_Actual (2418), untouched by all of this
    - the module-level array case   not re-measured this round, and NOT claimed either way

The next instrument is already in hand and has a known gap: `tools/bc_disasm.py` stops at opcode
`0x39` (the comparison group is a RANGE row in the spec's table, which the extractor does not parse),
so it breaks before reaching the CALL_NATIVE in `fldv.obc` and cannot show the extra or missing
push.  Fixing that gap is a few lines, and it is what turns this from deduction into a diff.

### 3cw. The spec had DRIFTED, and the disassembler was the thing that noticed

3cv named the instrument gap: `tools/bc_disasm.py` stopped at opcode `0x39`.  Fixing it found
something better than the fix.

**The first cause was mine.**  The spec's tables are space-ALIGNED, and my extractor required exactly
one space after the mnemonic's closing backtick - so the whole arithmetic and comparison group
(0x30-0x5F) was silently dropped and the tool "stopped at the first ILT".  Then my first repair
dropped the cell boundary instead (`(.*?)` with no trailing `|`), over-counting operands from the
stack-effect and notes cells and misaligning everything after; on the LIB image that showed
`LOAD_CONST / STR_EQ` where the truth was `LOAD_CONST / ILT`.  Two wrong decoders in a row, each
producing confident nonsense - which is exactly what the tool exists to prevent.  The tool now takes
widths from ONE cell (`[^|]*`), has a real CLI, and guards its main.

**The second cause was the repo's.**  With the alignment fixed the tool stopped at `0xEC` in a Files
body - an opcode `docs/obc-image.md` declares **reserved** (`0xE4-0xEF`, "fused guard+branch, inline
caches").  The VM implements it: `Op_Store_Idx_B = 16#EC#`, beside `Op_Load_Idx_B` (0xEB),
`Op_Copy_Str` (0xED), `Op_Str_Cmp` (0xEE), and the threading band `YIELD`/`CALL_INDIRECT`/`SPAWN`/
`JOIN`/`MUTEX_LOCK`/`MUTEX_UNLOCK`/`THREAD_ID` (0xE4-0xEA).  The compiler EMITS them.  The page that
the project treats as normative for the container had drifted from the implementation, and nothing
noticed until a tool built *from that page* refused to read a body the compiler had just written.

**They are all operand-free** - every verifier arm does `PC := PC + 1`, no inline operands - which is
how eleven opcodes fit between `DESC_OF` and the 0xF0 escape.  That is now in the spec, with the
stack effects.  One trap worth recording there: `SPAWN`'s declaration comment says "the procedure id
is an OPERAND", but its verifier arm accounts pops-and-pushes as net zero, which is only possible if
the id is POPPED from the stack.  The arm is the truth; the comment is not.

**And the disassembler immediately earned its keep on the original question.**  `fldv.obc`'s body now
decodes end to end:

    178: LOAD_G        [1]        the pointer's value = the object's address
    183: CALL_NATIVE   [1, 1]
    187: CALL_NATIVE   [2, 0]
    191: HALT

which looks RIGHT - one address on the stack, one argument.  So the runtime CONSTRAINT_ERROR 3cv
reported is NOT a missing push in the body, and the next measurement is to identify the call the VM
actually made: the raise locates at `obc_vm.adb:2067`, inside `when 0` (`Args (1)` of a two-argument
native), and this body contains no id-0 call at all.  Either the operand ORDER is `(id, argc)` rather
than `(argc, id)` - `agg.obc` emits `[0,2]` then `[2,0]` and runs, which is consistent with either
reading and is why the ambiguity went unnoticed - or the failing call is in a procedure the body
calls.  One measurement, and the tool can now print every procedure in the image.

### 3cx. Narrowed to one construct, and it is the one the corpus never tests

3cw left an ambiguity about CALL_NATIVE's operand order and a constraint error to explain.  Both are
settled, and the answer is smaller than the question.

**The order is `(id, argc)`, and the VM's own decode says so** (obc_vm.adb:1059-1072):

    Idx   := Natural (Code (PC + 1)) + Natural (Code (PC + 2)) * 256;   --  u16
    NArgs := Natural (Code (PC + 3));                                   --  u8

and it validates `Idx < Native_Count and then NArgs = Native_Pops (Idx)` - so a wrong arity is
`Bad_Native`, never a constraint error.  The table agrees with the emission: `0 => 2, 1 => 1, 2 => 0,
3 => 2, 4 => 1`, i.e. `Out.Int` 2, `Out.String` 1, `Out.Ln` 0.  The ambiguity that misled 3cw came
from reading `agg.obc`'s `[0,2]`/`[2,0]` as (id, argc) when it is (argc, id) - a reminder that a
two-element operand pair is only unambiguous once the decoder is checked against the interpreter.

**Then three probes, and they cut the problem down to one construct:**

    Out.String ("ABC")            ->  ABC      (a literal: Resolve_Str, the 3cg path)
    Out.String (a)                ->  ABC      (a module-level array)
    Out.Ln                        ->  fine      (so the failure is not the Ln that follows)
    Out.String (fp^.name)         ->  CONSTRAINT_ERROR at obc_vm.adb:2067

and the corpus prints arrays in `arrparam.ob2`, `charout.ob2`, `inlinearr.ob2` and `strconst.ob2`,
all passing - through a parameter, a local, and a global.  **No fixture anywhere prints an
array-valued FIELD**, which is why this survived: the construct is untested, and the disassembly of
its body looks right (one address pushed, `CALL_NATIVE [1, 1]`), which is why it survived a reading
too.

**So the remaining question is one line of runtime evidence away**, and it should be obtained by
instrument rather than by reading: a temporary trace in `Call_Native` printing `Idx`, `NArgs` and
`Args (0)` when the `when 0` arm is entered - the raise locates at 2067, in `Out.Int`'s two-argument
arm (`Args (1)`), while this body contains no `Out.Int` call at all.  Either the failing call is in a
procedure the body calls and the tool has not been pointed at, or the raise's line is being read
against the wrong arm; a printed `Idx` settles both in one run, and `tools/bc_disasm.py IMAGE 1 2 3
...` can now print every procedure in the image to say which.

### 3cy. THE ANSWER — a field array takes the string native; a module array takes Out.Char

3cx said the remaining question was one line of runtime evidence and named the instrument.  The
instrument produced it on the first run.  A temporary trace in the interpreter, just before
`Call_Native`, printing the id, the arity and the first argument:

    Out.String (fp^.name)   ->  TRACE native 1 argc 1 a0= 94344714588232
    Out.String (a)          ->  TRACE native 4 argc 1 a0= 65      (then 66, 67 - one per character)

So the two cases are not the same lowering at all:

    a MODULE-LEVEL array  ->  per-character Out.Char (native 4), the character as the VALUE   WORKS
    an ARRAY-VALUED FIELD ->  the string/pool native (native 1) with the OBJECT'S ADDRESS     dies

and native 1 is the one the LITERAL path reaches through `Resolve_Str` (3cg), i.e. the one whose
argument is a resolved pool address.  Handing it a heap address is the bug, and it is the last
thread of 3ct: the `D_Str` branch's ad-hoc "push the whole array as a string" is not how this
compiler lowers an array, and only a builtin's own body could ever reach it - which is why Files.Read
and Write passed a wrong address to FRead/FWrite while every user-visible path was correct.

**A second correction, and it matters for the shape of the fix.**  `Arg_Block` is
`array (0 .. Max_Native_Args - 1) of U64` - FIXED size - so `Args (0)` and `Args (1)` can never be
out of range.  3cx's reading of the constraint error as "an argument list that is too short" was
wrong: with a fixed array the stale `Args (1)` is simply whatever the last two-argument call left
there, and the range check that fires is a CONVERSION (`Natural` of a value whose high bit is set)
inside the native's own body.  That is what makes the failure reproducible and not a stack underflow:
the native is entered correctly with argc 1 and then interprets its argument as a pool index.

**So the fix is to lower an array-valued field the way this compiler already lowers a module-level
array** - the working path - rather than to invent a third lowering for it, and `fldv.ob2` /
`onlystr.ob2` / `globstr.ob2` are the fixtures, two of which already pass and are the reference.
That is a code change for a fresh session with the evidence in hand, not a guess, and it is the last
step between here and flipping Files.

### 3cz. The mechanism, and the fix is the THIRD instance of one mistake

3cy's trace said a field array reaches the pool-string native while a module array takes the
per-character loop.  The reason is three lines of recognition.

**`Out.String`'s argument is classified by looking its TEXT up as a symbol** (9340):

    if O2c_BC.Bytecode_Mode and then Find (To_String (A.Text)) > 0 then
       ASym := Find (...);  Is_Open := Syms (ASym).Open_Arr;  AU := Syms (ASym).UT;
       N := (if Is_Open then 0 else UTypes (AU).Arr_Len);
       ...
       if Is_Open or else (AU > 0 and then UTypes (AU).Elem = T_Char) then
          --  the per-character loop, ending in Str_Looped := True

A named variable is found; an ARRAY OF parameter is found; a FIELD'S Ada text (`fp.all.name`) is
not a symbol at all, so `Find` returns 0, the loop is skipped, and the member dispatch below emits
`Call_Native (1, 1)` - the pool-string native - with whatever the designator left on the stack.

**And the comment there records that this exact mistake has already been made once:**

    "Recognising only the first is why Out.String (s) inside a procedure fell through to the
     pool-string native and died as 'operand-stack underflow' - a message about the stack for a
     problem with a string."

So the field case is the THIRD instance of "recognise the shapes by name, and a shape that is not a
name silently falls through".  Global, then open parameter, now field - each found by a program
dying somewhere far from the cause.  That is the durable finding of this whole Files hunt: the
recognition is by TEXT where it should be by TYPE.

**The fix, precisely.**  The loop is already written to be independent of where the array lives: it
derives the base itself, and its first act is `Op_Discard` - "The chain pushed the array's address;
this loop derives its own, so drop that one".  For a field that push IS the right base (the chain's
`D_Str` branch pushes the field's own address), so the fix is to KEEP it instead of discarding it:
store it into the loop's temp local and load the base from there, exactly as the two existing cases
load it from a global or from a parameter slot.  The bound is the field's static length, which the
designator knows and `A` does not - so the front end has to carry it through, and that is the whole
of the change.  `onlystr.ob2` and `globstr.ob2` (failing and passing today) are the test pair.

### 3da. The fix's design, settled — three edits, and one distinction that matters

3cz left the shape; this is the design, ready to write.

**One carrier field.** `Expr_Rec` has `CStr : Boolean := False; -- whole ARRAY OF CHAR variable
value` but no array TYPE, so the call site cannot know a field's static length.  Add
`Arr_UT : Natural := 0` beside it, set by the chain's `D_Str` branch - which is the one place that
already has `UT`, the array's type, in hand - and carried through the `Desig` -> `Expr_Rec`
conversion like the other fields.

**One guard.** The loop at 9340 is entered on `Find (A.Text) > 0`; extend it so a non-symbol actual
with `A.Arr_UT /= 0` enters too, with `AU := (if A.Arr_UT /= 0 then A.Arr_UT else Syms (ASym).UT)`
and `Is_Open`/`N`/`P_Sl` derived from that rather than from `Syms (ASym)` - which is out of range for
the field case and would itself be the next crash.

**One store.** The loop's first act is `Op_Discard` ("The chain pushed the array's address; this
loop derives its own, so drop that one").  For a field, that push IS the base, so the field case
must STORE it into a local and load the base from there instead of discarding it.

**And the distinction that would make a naive version wrong**: the stack's address is the right base
for a field, but NOT for an ARRAY OF parameter - a parameter's own first slot holds the caller's
address, which is why that case does `Load_Local (P_Sl)` rather than using what the stack already
had.  So the store-instead-of-discard is for the field case only; the two existing derivations must
stay.  A version that used the pushed address for all three would fix `onlystr.ob2` and break
`arrparam.ob2`, which is exactly the trade this backend refuses.

That is the last step between here and flipping Files: three localized edits inside one block, with
`onlystr.ob2` (must start passing), `globstr.ob2` (must keep passing) and `arrparam.ob2` (must keep
passing) as the net.

### 3db. The fix was written, tested, and REVERTED — the last blocker is a gap in the IR

3da's design was implemented and run against its own net.  Four iterations, all reverted; the tree
never carried a broken path and the corpus stayed green throughout (`run_bc: PASS` after every
build).  What survived is worth more than the attempt.

**What the iterations established, in order:**

    1. carrier fields + guard + store, plain-designator site missed   -> unchanged (no path entered)
    2. + the plain-designator site (4360)                             -> 7 fixtures STORAGE_ERROR
    3. discriminator `D.Base_On_Stack`                                -> corpus green, field still dies
    4. discriminator `Is_Ptr or else Base_On_Stack` (the indexed rule) -> path ENTERED (new failure mode)
    5. store with no Src1                                             -> O2c_Ir: no such value

**Two of those are real knowledge.**  First, the recognition point matters: the plain-designator
site is shared with module-level arrays, so setting the carrier there without a discriminator turns a
globals run into a field and breaks seven fixtures - `Is_Ptr or else Base_On_Stack` is the same
condition the indexed sibling uses (2142), and with it the field case reaches the new path while
everything else is untouched.  Second, and this is the blocker: **the IR cannot express "store the
operand already on the stack into a frame local."**  `Src1 => No_Value` raises `O2c_Ir: no such
value`, and a *temp* is defined as having the stack as its home, so `Store_Value` deliberately emits
nothing for one.  The store quad wants a `Value_Id`; the value that needs storing does not have one.
That is a hole in the IR's vocabulary - not a mistake in this fix - and it is the last thing between
here and a working field-array lowering.

**So the next attempt starts from two options, both named:**

    (a) the chain emits the field's address into a frame local as well as pushing it - a store it can
        express, because `Addr_Global` gives it a VALUE - at the cost of one dead store per field use;
    (b) give the IR the missing primitive, which is what its own reserved `Op_Load`/`Op_Store` pair
        looks like it was left for.

The verified pieces are worth keeping in the retry: the `Expr_Rec`/`Desig` carrier fields, the guard
extended to a non-symbol actual, the `Is_Ptr or else Base_On_Stack` discriminator, and the third
local pair (`o2c_str_b` in both the frame and the IR).  Every one of them was built and compiled
clean; only the final store is missing.

### 3dc. FIXED — the IR got the primitive, and the Files blocker fell

3db ended with two options and the user chose (b).  Both bugs that had been masking each other are
now fixed, and the metric moved past Files for the first time.

**The IR primitive.**  Appended to the op set (append-only, at the end, after `Op_For_Next`):

    Op_Store_Local_Pop);          --  local slot Imm_1 := the stack top

with a helper mirroring `Discard`, and an `Emit_Quad` arm that calls `O2c_BC.Store_Local (Q.Imm_1)` -
STORE_L takes its value off the operand stack, which is the one thing the front end cannot name.
`Emit_Quad` has no `others` arm *by design* ("adding an Op to the IR without deciding how it lowers
is a compile error HERE"), so the op could not land without its lowering, and the selftest now counts
it.

**The front-end fix**, on top of 3db's verified pieces: the `Expr_Rec`/`Desig` carrier,
`Arr_UT := (if Is_Ptr or else Base_On_Stack then UT else 0)` in the chain's `D_Str` branch, the guard
extended to a non-symbol actual, `Store_Local_Pop` instead of the discard, and the loop's base loaded
back from that local.

**And the second bug, which the first had been hiding.**  With the crash gone, `arrfield.ob2` printed
an EMPTY line - and the differential said it plainly: "the Ada side agrees with the golden, the VM
does not".  The cause was 3cu's missing `Nested`: the field's offset was never added, so a field not
at offset 0 read its neighbour (`pad`, an integer 0, i.e. a NUL) and the loop stopped at once.  **3cu
was right and 3cv was wrong** - the crash that made the offset look irrelevant came from the
pool-native fall-through, so two bugs were masking each other, and only fixing one made the other
visible.

**A reading error of mine, worth recording twice over.**  I checked `fldv3` by running it and printing
line 2, saw a blank line, and called it a pass - when line 2 is blank *because line 1 is the string*.
The same habit hid the runtime error in 3cv ("malformed code" is the second line).  Twice in this
hunt the evidence was in line 1 and I read line 2; the differential caught what I did not.

**The measurement, with a probe flip that then came back out:**

    Files.WriteString end to end          out.txt  b'abc'      (was: a garbage name, b'(((')
    samples/hello.ob2 refusal            Math.ln is not yet supported

So Files is no longer the compile blocker - the metric has moved off it after twenty sessions - and
its WRITE path is verified correct.  The flip stays OUT regardless: Files' read/seek surface is not
yet verified, and this backend does not ship a library whose remaining half is unknown.  `Math.ln`
is the next gap, and 3cr already established what it needs: natives and VM arms for the
transcendentals, hand-rolled for a guest runtime with no elementary functions.

Verified: run_bc PASS, bytecode_gaps PASS, differential PASS, all five field/array probes print ABC,
and `out.txt` holds `abc`.

### 3dd. Files' read surface — one bug fixed, and the next one named exactly

3dc left Files' read/seek side unverified, which is why the flip stayed out.  This measures it.

**What works**: `Old` (FStat -> `Length` = 5), `Pos` (5 after five reads), `Seek`, and the write path.

**One real bug, found and fixed.**  `Files.Read`'s `FRead` argument list disassembled to

    55: LOAD_L 0; 58: LOAD_L 0; 61: LOAD_FLD_P 0     ; r.f
    64: LOAD_L 0; 67: LOAD_FLD_I 8                   ; r.pos
    70: LOAD_ADDR_G 5                                ; the address of a GLOBAL named "r"

- `Addr_Global` was inventing a module-level global for a **var parameter**, and `r.cur` is a field
of one.  So the native read into storage nobody had written while every write-path access happened to
avoid the case.  The value path now goes through `Bc_Field_Base`, one procedure that knows the three
places a base can live - on the stack (a pointer), in a frame slot (a by-ref formal), or in the
globals - shared by the string-value path and the two indexed ones, because three copies is how this
went wrong three times.  The disassembly now shows `LOAD_L 0; LOAD_CONST; IADD`, i.e. `r + cur`'s
offset.

**And the next one, named by the same disassembly.**  `Read`'s last two instructions are

    128: LOAD_IDX_B          ; r.cur[0]
    129: STORE_L  [1]        ; ch := ...

`ch` is a **`var` scalar parameter** (`Read (var r: Rider; var ch: char)`), so that store must go
THROUGH the parameter's address; `STORE_L` writes the slot that holds the address instead, and the
caller's variable is never written at all - which is why the probe printed a character it had never
received.  This is not a Files bug: it is every assignment to a `var` scalar formal, in any program,
and it is why `eof`/`pos`/`res` (fields, not formals) all behaved.

So the flip stays out, for a reason that is now one instruction wide.

### 3de. The `var` scalar store — site found, plan complete, not started

3dd named the blocker from `Read`'s disassembly (`STORE_L [1]` for a `var` scalar formal) and
located the general defect.  This turn found the one site that emits it and settled the whole plan;
the edit itself wants a fresh session, because it is four layers and every program passes through it.

**The site** - the statement dispatcher's plain scalar assignment:

    9869:  else
    9870:     declare V : Expr_Rec := Parse_Expr;      --  the value goes on the stack here
    ...
    9886:        Bc_Store (Ada_Id (Head (1 .. H_Len)));  --  and this is STORE_L/STORE_G

`Bc_Store` (350) chooses local-vs-global from `Local_Slot`, and a `var` formal IS a frame name - which
is exactly why it picks `STORE_L`, writing the slot that HOLDS the address.  The other three
`Bc_Store` sites are `Assign_Pointer` (2785), `NEW` (7790) and a procedure value (9176); none of them
is the scalar case.

**The plan, with the operands the spec already provides:**

    LOAD_ADDR_L (0x15)   "VAR params, arrays"     -> the address, from the slot
    STORE_IDX_B / _I     via Store_Idx (1 | 8)    -> [base, idx, value]
    LOAD_IND_I (0x17)    the read side, same shape

so the front end must push the base and the index BEFORE the value is parsed (Store_Idx consumes
[base, idx, v] in that order), and `By_Ref` is already on the symbol (`Syms (Idx).By_Ref`, as
`Bc_Field_Base` uses).

**Plumbing to append, all of it append-only:** `Load_Addr_L` on `O2c_BC` (procedure, `Byte_Of =>
16#15#`, u16 operand like `Load_L`), an `Op_Load_Addr_L` on the IR plus its `Emit_Quad` arm - which
the missing `others` arm forces, by design - and a `Load_Addr_L` helper on `O2c_Ir_Lower`.
`Store_Idx`/`Load_Idx` already exist and are what the indexed paths use.

**And the read side is the same bug**, which is why `Files.Pos` (a field) worked while `ch` (a
formal) did not: `LOAD_L` of a by-ref scalar yields the ADDRESS, so a read of one is wrong too.

**The test is already written**: `fres.ob2` in /tmp must print `c=[h]` instead of `c=[ ]`, and
`fall.ob2` must print `hello`.  A fixture belongs beside `arrfield.ob2` when it does - one that
assigns to a `var` scalar formal and shows the caller's variable changed.

### 3df. The by-ref scalar is a THREE-part fix, and the third part is a missing VM opcode

3de's plan was implemented - the site, the store, the plumbing - and it answered the question by
failing in a new way, three times over.  The change was reverted; the tree never carried a path that
turns a wrong-but-running case into a crash.

**Attempt 1: the plumbing did not compile.**  `Byte_Of`'s new arm resolved to the *procedure* I had
declared rather than to an enum literal, because I added the procedure without adding a member to
`O2c_BC`'s `Op` enum - the same enum-literal-versus-subprogram trap 3cg hit (`Resolve_Str`).  The
enum is ONE enum, ending at `Str_Addr);`; the fix was to append `Load_Addr_L` there too.

**Attempt 2: the VM does not implement the opcode.**  With that fixed the image loaded and stopped at

    vm: opcode not implemented in this slice at code offset 2497

`LOAD_ADDR_L` (0x15) is the FIRST row of the spec's address group ("VAR params, arrays") and this VM
does not implement it - a second spec/VM drift, after 3cw's threading band.  That is a useful fact on
its own: the spec has promised this op all along and nothing emitted it, so nothing noticed.

**Attempt 3: the caller passes a VALUE.**  Reverting to `Load_Local` as the base - on the reasoning
that a by-ref formal's slot holds the caller's address, which is true for the Rider parameter `r` -
gave STORAGE_ERROR, i.e. a wild address.  The conclusion is the opposite of the assumption: for a
scalar, the CALLER is not passing an address at all.  `Parse_Actual` hands over the value, the slot
holds the value, and `STORE_L` writes it - which is exactly why the original code lost the update
*quietly* instead of crashing.

**So the fix has three parts, and only the third is written:**

    1. the VM implements LOAD_ADDR_L - the address of a frame slot's variable
    2. Parse_Actual passes an ADDRESS for a by-ref scalar actual (it currently passes the value),
       which is what makes a var scalar parameter mean anything at all
    3. the callee's store goes through that address (Load_Local as the base, Push_Int (0), the
       value, Store_Idx (1 | 8)) - which is what I wrote twice today and reverted twice

Part 3 alone is what turns Files.Read's silent loss into a crash, which is why it is not in the tree.
Run the three together, and `fres.ob2` prints `c=[h]` and `fall.ob2` prints `hello`.

### 3dg. Why LOAD_ADDR_L was never implemented — and the by-ref scalar is a DESIGN fork

3df found that the VM does not implement `LOAD_ADDR_L` and that the caller passes a value.  This is
the reason, and it is a good one - not an oversight.

**Frame slots are reallocated.**  `Push_Frame` grows the frame arrays by allocating a bigger block and
copying:

    New_Slots : constant Natural_Array_Access := new Natural_Array'(0 .. Cap - 1 => 0);
    ...
    New_Slots (0 .. Old - 1) := Frame_Slots.all;
    Frame_Slots := New_Slots;

so the address of a frame slot is only valid until the next deeper call - which means `LOAD_ADDR_L`
("the address of a frame slot's variable") has nowhere safe to point for a LOCAL.  A module-level
variable's address is fine (the globals block is not reallocated), which is exactly the case
`Files.Read (r, c)` is: both `r` and the caller's `c` are module-level in any realistic program, and
`LOAD_ADDR_G` already exists.

**So the by-ref scalar is a three-way design fork, and it is the user's to make:**

    (a) GLOBALS-ONLY   by-ref scalar actuals work when the caller's variable is module-level (push
                       LOAD_ADDR_G, no VM change, and it unblocks Files); a LOCAL actual is REFUSED
                       loudly rather than silently not written back.
    (b) STABLE SLOTS   give frame slots a stable home so LOAD_ADDR_L can exist - the correct fix,
                       by-ref scalars everywhere, at the cost of reworking the frame model.
    (c) BOXED SCALARS  the caller boxes its own scalar in storage it owns and copies back, so no VM
                       opcode is needed and locals work too, at the cost of per-call (or pooled)
                       allocation.

Whichever is chosen, the callee side (3df part 3) goes with it: `Load_Local` as the base,
`Push_Int (0)`, the value, `Store_Idx (1 | 8)`.

### 3dh. Stable slots: the design is right, the edit is not one pass, and the VM is back as it was

The user chose (b), the correct fix: make frame slot storage stable so `LOAD_ADDR_L` can exist.  The
design is settled and verified; the edit was attempted and REVERTED, because the file fights back in a
way worth recording.

**The design, from the code rather than from a guess.**  `Locals` is its own array, separate from the
operand stack, and exactly ONE place reallocates it (Push_Frame, 2219-2228, doubling a `U64_Array` and
copying).  So the fix is local: replace that array with a CHUNKED store - 4096-word chunks, allocated
once, never freed, never moved - plus `Get_Local`/`Set_Local`/`Addr_Of_Local`, `Ensure_Locals` where
the old code grew, and then `LOAD_ADDR_L` (0x15) with its two verifier/interpreter arms.  The table of
chunk pointers may still be replaced, which costs nothing, because no address points into it.

**Why the edit is not one pass.**  `grep 'type Context is record'` finds MORE THAN ONE context, and
`Locals` appears as a field in more than one of them; the constructions at 3011 and 3672 are separate
from the one at 300.  My anchors matched the first occurrence, edits landed in the wrong record, and
the build said so:

    obc_vm.adb:2168:49: error: no selector "Chunks" for type "Context" defined at line 300
    obc_vm.adb:3011:26: error: no value supplied for component "Locals"

Half a refactor of the VM's core is worse than none, so the file was restored from the copy taken
before the attempt and the tree is green again (`run_vm` PASS, `run_bc` PASS).

**What the next attempt needs to do first**: enumerate every `Context`/`Locals` site before editing -
`grep -n 'type Context is record\|Locals  *:\|Locals =>\|Locals (\|C.Locals' vm/obc_vm.adb` - and
patch by LINE RANGE rather than by text, since the text repeats.  Then the chunked store, then
`LOAD_ADDR_L`, then 3df's parts 2 and 3 (the caller passes an address; the callee stores through it),
and `fres.ob2` prints `c=[h]` with `fall.ob2` printing `hello`.

### 3di. The chunked store: the SITE LIST is the deliverable

A second attempt at 3dh's design, reverted for the same reason (a blind patch over a file whose
identifiers repeat), and this time the enumeration is written down so no attempt has to rediscover it.

**Every site, by line, from `grep -n 'type Context is record|Locals *:|Locals =>|Locals (|C.Locals|
Locals.all|Locals :=' vm/obc_vm.adb`:**

    61    Max_VM_Locals (1024)          becomes unused - leave; it is a constant, not a ceiling
    300   type Context is record         unchanged (insert the chunk types+helpers AFTER its
                                        `end record;`, since they take a Context)
    303   Locals : U64_Array_Access      REPLACE with Chunks : Locals_Chunks_Access := null
    2122  comment                       unchanged
    2166  comment                       mentions Locals (Frame_Base...) - worth updating
    2168  Locals renames Ctx.Locals     REPLACE (there is no array to rename)
    2182  Locals_Used renames Pool_Used unchanged - a COUNT, not storage
    2191  Base := Locals_Used           unchanged
    2219-2228  the growth block         REPLACE with Ensure_Locals (Ctx, Base + Frame_Slots - 1)
    2232  Locals (Base+K) := Pop        -> Set_Local
    2238  Locals_Used := ...            unchanged
    2335  Mark_Word (C.Locals (K))      -> Mark_Word (Get_Local (C, K))   the GC root scan
    2482  Locals_Used := Frame_Slots(0) unchanged
    2684  Push (Locals (Addr))          -> Push (Get_Local (Ctx, Addr))
    2689  Locals (Addr) := Pop          -> Set_Local
    2731  Locals_Used := ...            unchanged
    2745  Locals_Used := ...            unchanged
    3434-3436  FOR slots, written      -> Set_Local x3
    3476-3478  FOR slots, read         -> Get_Local x3
    3483-3484  the FOR step            -> Set_Local / Get_Local     <- MISSED on the first attempt
    3011-3013  a Context construction  -> Chunks => null,
    3674  the other construction       -> Chunks => null,

**Two of those are why the attempts failed**: 3483/3484 (the FOR step) were not in my first patch at
all, and there are TWO `Context` constructions (3011 in the thread-spawn path, 3674 in `Run_Context`),
so a text anchor for `Locals =>` is ambiguous.  A third failure was arithmetic: inserting a
multi-line block shifts every later line, and I shifted by the block's LINE count instead of by the
ONE element it is in the list.

**So the next attempt's method matters more than its patch**: enumerate first (the list above), edit
bottom-up, shift by elements and not lines, assert the content of every line touched - and prefer the
editor tool that shows the lines and refuses an ambiguous edit over a blind text substitution.

### 3dj. Five attempts at the chunked store, five reverts, and the instrument was the problem

The design is settled (3dh) and the site list is complete (3di).  Five scripted attempts to apply it
failed, each for a different reason and every one of them mine:

    1. ambiguous text anchors - the edits landed in the wrong Context record
    2. shifted line numbers after an insert, because `L.insert` with a multi-line STRING adds one
       ELEMENT, and I shifted by the block's line count
    3. line numbers guessed from a `sed` window instead of taken from a grep
    4. an enumeration grep whose pattern (`Locals =>`) did not match `Locals      =>` - so a site was
       missing from the list I was patching from
    5. `find` by substring hitting a longer line (`if Locals (Base + Limit + 1) = 1 then` matched
       inside `More := (if Locals (Base + Limit + 1) = 1 then V <= Lim`), then an exact-strip rule
       applied to a line whose strip is the WHOLE line (`Locals      : U64_Array_Access renames
       Ctx.Locals;`), which of course does not equal `renames Ctx.Locals;`

The VM was never left half-changed: each attempt aborted before writing, or was restored from a copy
taken first, and the tree is green (`run_vm` PASS, `run_bc` PASS, `git diff` empty for obc_vm.adb).

**The conclusion is about the INSTRUMENT, not the design.**  A 3000-line Ada file where `Locals`
appears as a field, a renames, a local renames, an assignment target, three array forms and two
Context constructions is not something to patch by scripted text substitution - not by me, and not
by a script that has to keep re-deriving uniqueness.  It wants the editor tool that shows the lines
it is changing and refuses an ambiguous match, one site per edit, with the build run once at the end
(the refactor cannot be built half-applied: removing the field breaks every site at once).

**What is now reusable, and committed**: `docs/chunked-locals.txt` holds the exact helper block -
the chunk types, `Ensure_Locals`, `Get_Local`, `Set_Local`, `Addr_Of_Local` - and the strips of every
site to change, so the next attempt starts from a written patch rather than from a description of
one.  Then `LOAD_ADDR_L`, then 3df's parts 2 and 3, and `fres.ob2` prints `c=[h]`.

### 3dk. LANDED — stable locals, and LOAD_ADDR_L implemented at last

The user chose (b) in 3dg: make the locals pool non-moving so `LOAD_ADDR_L` can exist.  After five
failed scripted attempts (3dj) it is in, via the editor tool one site at a time - and it works.

**What the VM has now.**  The `Locals` array is gone; `Context` holds a chunked pool:

    Locals_Chunk_Shift/Len, Locals_Chunk(s)(_Access)   --  4096-word chunks, heap
    Ensure_Locals (C, Up_To)                            --  materialise a range, zeroed
    Get_Local / Set_Local / Addr_Of_Local               --  and the address, now stable

Twenty-odd sites went from `Locals (i)` to `Get_Local (Ctx, i)`; `Push_Frame` grew an array on every
deeper call and now only materialises chunks, which is the whole point: a chunk is allocated once and
never freed or moved, so an address taken in one call is still valid in the next.  `LOAD_ADDR_L`
(0x15, "VAR params, arrays" in the spec since the beginning) is now implemented - the constant, the
verifier arm, and the interpreter arm that pushes `Addr_Of_Local` - which is the first time anything
has emitted it.

**One real bug found by the suites, and it was the interesting kind.**  With the chunks in place
`run_bc` failed 21 fixtures: the OLD array was allocated for every slot up front, so frame 0 - the
module body - could read a slot without any `Push_Frame`.  Chunks are materialised on demand, and
nothing materialised frame 0's, so the very first `LOAD_L` dereferenced a null chunk.  `Execute`'s
prologue now calls `Ensure_Locals (Ctx, Max_VM_Locals - 1)` - one chunk's worth, which is also what
gives the otherwise-unused constant a use.

**And a compile-time lesson worth keeping**: the aggregate `new Locals_Chunks (0 .. Cap - 1 => null)`
needs its TYPE MARK - `Locals_Chunks'(...)` - exactly as the neighbouring `new Natural_Array'(...)`
does.  Without it: `missing ","`.

Verified: `make vm-host` with zero warnings, `run_vm` PASS, `run_bc` PASS, `run_stress` PASS.

**What remains is parts 2 and 3 of 3df**: `Parse_Actual` must pass an ADDRESS for a by-ref scalar
actual (it passes the value today), and the callee's store must go through it (`Load_Local` as the
base, `Push_Int (0)`, the value, `Store_Idx (1 | 8)`).  Then `fres.ob2` prints `c=[h]` and `fall.ob2`
prints `hello` - and Files' read surface is verified.

### 3dl. THE FILES BLOCKER IS GONE — by-ref scalars work, and Files is verified end to end

Parts 2 and 3 of 3df landed on top of 3dk's stable slots, and with them the last thing standing
between the metric and Files.

**What was wrong, in one sentence**: a `VAR` SCALAR formal's slot was given the caller's VALUE, and the
callee's store wrote that slot - so the caller's variable never changed, and nothing said so.  Two
halves, both now in:

    the CALLER (Parse_Actual)   a by-ref scalar actual pushes the caller's ADDRESS -
                                Load_Local for a formal passed on, Load_Addr_L for a frame local
                                (which the chunked pool made possible), Addr_Global for a module
                                variable; the value parse stays for the type check and is Discarded
    the CALLEE                  a read goes through it (Load_Local, Push_Int 0, Load_Idx) and so
                                does a store (the same shape, Store_Idx) - both the INDEXED access
                                with index 0, so no new dereference opcode was needed in either
                                direction, and the VM's missing LOAD_IND_I never came up

**And the verification is the whole surface, not a slice:**

    varparam.ob2   a user program: g := 40, Bump (g), BumpTwice (g)  ->  43   (new fixture)
    fres.ob2       Files: res=0 c=[h] eof-clear
    fall.ob2       Files: len5, "hello" read back through Read, pos5, Seek(1)+Read -> 'e'
    on disk        t.txt and z.txt, each b'hello'

`fres`'s `c=[h]` is the exact expectation written down in 3df two turns before anything worked, and
`Read`, `Pos`, `Seek`, `Length` and `Old` all agree with it.

**So the Files flip is IN**, on evidence: with it, `samples/hello.ob2` refuses at `Math.ln` - the
metric has moved off Files after twenty-odd sessions, and it moved because a library was verified
rather than because a gap was stepped over.  `Math.ln` is the next gap, and 3cr already established
what it needs: natives and VM arms for the transcendentals, hand-rolled for a guest runtime with no
elementary functions.

**One wart, recorded rather than hidden**: `fall.ob2` prints BASE-WRONG, and that is the PROBE's
fault - it compares `Files.Base (r)` before any `Set`/`Open` has put `f` in the rider.  `Base` itself
is fine (`Set` sets the field).  Worth fixing in the probe, not in the library.

### 3dm. Math: 3cr's premise was WRONG — the guest has the elementary functions

The metric is at `Math.ln`, so the transcendentals are next.  Before writing any of them, the guest
runtime was checked - and 3cr's conclusion, reached from a grep that looked for "Numerics" rather than
for the file's NAME, was wrong:

    userspace/gnat-rts/gnat/a-nlelfu.ads      Ada.Numerics.Long_Elementary_Functions

It IS there.  So this is ONE implementation for both platforms, exactly like `VM_IO.Read_File`, and
nothing needed hand-rolling.  3cr would have had me write `ln`, `sin` and `cos` twice.

**What is in**: `vm/vm_math.ads/.adb` (the eleven functions, `Ada.Numerics.Long_Elementary_Functions`
renamed to `Elem`, with the domain behaviour left to Ada - a raise is reported rather than a wrong
answer) and the natives in `obc_vm.adb`:

    entries 26..36 -> ids 30..40   power exp ln log sin cos tan arcsin arccos arctan arctan2
    Max_Foreign 32 -> 64           with the justification the project's rule asks for: the FFI
                                   surface is a closed, enumerable set the table IS the list of
    Native_Pops/Native_Pushes      the arities, and all eleven push a result
    one dispatch arm               Max_Natives + 25 .. + 35, each case R64_To_U64 (VM_Math.X
                                   (To_R64 (Args (k)))) - REAL and LONGREAL share the slot (M4e),
                                   so Math and MathL are the same code with a different name

`with VM_Math;` and a missing `with Ada.Numerics.Long_Elementary_Functions;` in the new body were the
only two build errors, both caught immediately.

Verified: `make vm-host` clean (0 warnings), `run_vm` PASS, `run_bc` PASS.

**What remains, and it is the smaller half**: the COMPILER arms.  The qualified path refuses every
Math member at the generic MARKER_EXPR_REFUSAL (3956), so the model to copy is `XYplane.IsDot`
(3949-3979): an allowlist condition plus the emit - `Bc_Push_Arg (Arg_R (K))` per argument and
`Call_Native (id, N_A)`.  The CONSTANT path (3985-3995) needs `Math.e` and `Math.pi` too, because
`hello.ob2` line 439 is `Math.ln (Math.e)` and the ARGUMENT is evaluated first; `O2c_Ir.Const_Real`
exists for that, and a `Push_Real` helper on `O2c_Ir_Lower` mirroring `Push_Int` is what it lacks.
Then the metric moves past `Math.ln`.

### 3dn. The Math arms are in, the metric is past Math, and two gaps closed on the way

3dm wired the natives; this wires the compiler, and the metric moved out of Math altogether.

**The compiler arms.**  A member map (`Math_Native (Mod, Member) -> id 30..40`, 0 for "not ours"),
`Math_Arity` for the three two-argument ones, and an emit block modelled on `XYplane.IsDot`: push each
argument, `Call_Native (id, N_A)`, result REAL - the same code for Math and MathL, as the natives are.
The allowlist condition at 3949 says which members may pass.

**Two gaps closed that nothing had noticed, both found by the feature rather than by reading:**

    V_CONST_REAL had NO LOWERING       Const_Real existed from the start and this is its first
                                       consumer; Push_Value raised
                                       "value kind V_CONST_REAL has no lowering yet" - the closed
                                       op set naming its own hole.  Push_Value now calls
                                       O2c_BC.Push_Real, which interns the bits and emits LOAD_CONST_R.
    a real LITERAL was loaded by NAME  Bc_Push_Arg's comment warns that Bc_Load is wrong for a
                                       literal - "it would look up a global called 1" - and for
                                       reals it was TRUE: Math.ln (2.0) reached Ada as a domain error
                                       because the argument was a global called "2.0".  Real
                                       literals now push their own value, read from their own text.

**The measurement:**

    Math.ln (2.0)                       0.693          exactly right
    tests/bc/mathln.ob2                 0.693 1.000 3.000 0.785   (arithmetic, not a recording)

and `samples/hello.ob2` now refuses at `Reals.Convert` - PAST every Math and MathL call it makes,
including the two-argument `MathL.power`.  Verified: `run_bc` PASS with the new fixture.

**One thing left open, and it is named rather than hidden**: `Math.pi` and `Math.e` work as a BARE
expression but double-count as an ARGUMENT - a probe doing `Out.Real (Math.pi, 0)` fails verification
with a depth violation, because the module's own emission pushes the value AND the argument machinery
expects to push it itself.  The arm for the constant path is therefore reverted, the fixture uses the
literal instead, and 3dn's follow-up is to find where the argument machinery expects to own that push
(the same question `XYplane.IsDot` would face if its result were ever passed as an argument).

### 3do. `Reals` is the next flip, and the flip found a NESTED PROCEDURE with no proc id

The metric is at `Reals.Convert`, whose refusal says "is an FFI primitive and is not yet supported".
It is NOT an FFI primitive: the embedded source is ordinary Oberon - `Convert` is a dozen lines of
real arithmetic with two NESTED procedures, `Put` and `Digit`, and no intrinsic anywhere.  The
refusal is the generic one for an unflipped builtin, so the lever is the same as Strings, Texts and
Files: `Compile_Builtin (Oak_Reals_Src, Scoped => True)`.

**Flipping it found a real gap, immediately and precisely:**

    o2c error: bytecode backend: call to 'Put' resolved to symbol 13 named 'Put'
               (kind S_PROC, params 1) with no procedure id

A NESTED procedure has no bytecode procedure id, so any call to one cannot be lowered.  That is the
whole of it - the message names the symbol, its kind and its parameter count - and it is a gap that
only a body with nested procedures could reach, which is what a builtin's own source is.  The flip is
reverted (it does not compile), the tree is green, and this is the next step: find where `Bc_Proc` is
assigned and why a nested declaration does not get one.  `Nested_Depth` exists in the front end
(M32 parses them), so the parsing is not the part that is missing.

**A note on method, since it keeps being the thing that matters**: every one of the last four steps
was found by TURNING SOMETHING ON and reading what it said, not by reading the code and predicting.
The transpose - "an FFI primitive" - was itself wrong for the same reason.

### 3dp. The nested-procedure blocker, located in one condition — and why the fix is not small

3do's error had an exact shape, and the assignment site is a single place (6394):

    if O2c_BC.Bytecode_Mode and then not O2c_BC.Proc_Open then
       ...
       Syms (N_Sym).Bc_Proc := O2c_BC.Begin_Proc (N_Par + N_Open, ...);
    end if;

The id is assigned ONLY when no procedure is open - which is true for a top-level one and false for a
NESTED one, since a nested declaration is parsed while its enclosing procedure is open.  So
`Bc_Proc` stays 0, and the call site reports it by name, kind and parameter count.  That is the whole
mechanism.

**Why the fix is a feature and not a condition to widen.**  Handing a nested procedure an id is the
easy half: `Begin_Proc` closes the procedure that is open, so emitting a nested body separately means
saving and resuming the outer one's state.  The hard half is the one that matters here: `Reals`'s
`Put` and `Digit` read and write the ENCLOSING procedure's locals (`str`, `n`, `v`, `d`, `s`, `k`), so
a separately-emitted nested body needs up-level addressing - static links, or inlining - and neither
is a small change to this IR, whose frame model is one flat run of slots per procedure.

**So `Reals` is where the next real piece of work is, and it is now bounded**: nested procedures with
up-level access.  Everything else about the module is ordinary code this backend already compiles -
real arithmetic, `CHR`, `len`, an open-array formal, `var` out-parameters (which is 3dl's fix, and
`Convert (x, str)` is exactly its shape).

### 3dq. Nested procedures: the design is settled, and the load-bearing fact is one refusal

3dp located the missing id; this settles how to get it.  The decisive fact is in the emitter:

    function Begin_Proc ... is
       if Cur_Proc /= 0 then
          raise Wrong_Construct with "bytecode backend: a procedure is already open";

ONE open procedure, no stack, and `Procs (Cur_Proc).Buf_Off := Length (Code)` - so a body is a
contiguous run of the single code buffer, and a nested body cannot be emitted inside its enclosing
one: the loader takes each procedure's extent as `Buf_Off .. the next one's`, so bytes in between
would be EXECUTED by the enclosing procedure.  That, and not the id, is the real work.

**The design, in four pieces, three of which use what already exists:**

    the static link    an ORDINARY slot: the caller passes `LOAD_ADDR_L (0)` - the address of its own
                       frame - and the callee reads it like any local.  An up-level access is
                       `Load_Local (link slot)`, `Push_Int (outer slot)`, `Load_Idx (8)`.  NO NEW
                       VM OPCODES: stable slot addresses are what made a static link expressible at
                       all, so 3dk's chunked pool pays for itself twice.
    the ordering       a nested body must be emitted BEFORE its enclosing one, and Oberon already
                       puts nested declarations ahead of the enclosing `begin`.  So the fix is to
                       DEFER the enclosing `Begin_Proc` from its declaration to its `begin`.
    the ids            `Begin_Proc` both allocates the id and starts the body; splitting those two -
                       reserve at the declaration, open at the `begin` - is what lets a nested body
                       be emitted first while its parent is already declared and callable.
    the level          a symbol needs the nesting depth it was declared at, and a use needs the
                       difference: 0 = this frame, 1 = up one (the link), >1 = REFUSE loudly.  The
                       front end already has `Nested_Depth`; what it lacks is the field on the symbol.

**And the limit stated up front**: one level up is what `Reals` needs (`Put` and `Digit` reach
`Convert`'s locals), and deeper nesting should REFUSE rather than be approximated - which is this
backend's rule everywhere else.  Recursion in a nested procedure wants a real id at its declaration,
so it is the one case the deferred-open must be careful with.

### 3dr. Step one of nesting is in; step two found the re-entry trap it has to respect

3dq's design, implemented in verified pieces.  The emitter half is IN and green:

    Reserve_Proc (NParams, NResults)   the id, with no body opened
    Open_Proc (Id)                     the body, opened where the code really starts
    Begin_Proc                         exactly those two calls, behaviour unchanged

`run_bc` and `run_vm` both PASS with it, so nothing regressed - which is what the two-halves split
was for.  It is also the piece that makes Buf_Off a LATE assignment, and that is the whole mechanism:
a nested body opens the buffer before its enclosing one, and the enclosing one is re-pointed when its
own begin arrives.

**Step two - always reserve the id, open the body at the `begin` - broke 143 fixtures, and the reason
is worth more than the change.**  The front end's own comment says it: "The front end may reach a
procedure declaration more than once for one declaration, and Begin_Proc must run once: this is how it
tells" - and `not Proc_Open` was that detector.  Deferring the open to the `begin` means the SECOND
pass sees no procedure open, reserves a SECOND id, and every later call resolves to the wrong one.

So the re-entry guard must move with the open, and it cannot be `Proc_Open` any more.  The symbol is
overwritten before the id is taken, so the flag has to be captured above that - a small, exact piece
of work, and the next thing to do.  The revert is clean (`git checkout compiler/o2c_compiler.adb`,
`run_bc` PASS) and the emitter half is committed.

### 3ds. Nesting step 2 needs a MEASUREMENT, not a third guess

Two attempts at "reserve the id at the declaration, open the body at the begin", and both broke the
same 143 fixtures - which is worth reading carefully, because the identical count means at least one
of them changed nothing.

**Attempt 1** removed the `not Proc_Open` guard, on the reasoning that the front end's own comment
("may reach a procedure declaration more than once ... this is how it tells") makes it the re-entry
detector.  **Attempt 2** kept that reasoning and carried the flag across the re-parse in a new
`Saved_Bc_Proc`, captured before the symbol is rebuilt.  **Neither moved the number**, and then a
third hypothesis - that `Open_Proc` resetting `Next_Frame` wipes the parameter slots interned during
the header, so the reset belongs in `Reserve_Proc` - moved it not at all either.

**So the cause is not among the three things I reasoned about, and the next step is to find out which
they are rather than to think of a fourth.**  The instrument this session keeps proving is the cheap
one: print, at the declaration and at the begin, the procedure's name and the id `Reserve_Proc`
returned, and the `Next_Frame`/`Local_Count` either side.  That says in one run whether a declaration
is reached twice, whether an id is reserved twice, and where the frame goes wrong - all three of which
I have now guessed at and none of which I have seen.

Every reverted attempt was clean (`git checkout compiler/`, build 0 warnings, `run_bc` PASS,
`run_vm` PASS) and the committed state is 3dr's emitter split, which is verified and green.

### 3dt. The trace answered the question, and the answer is a change of plan

3ds said the next step was to measure rather than guess a fourth time.  The trace took two lines:

    TRACE decl Length id= 0 locals= 0 open=FALSE
    o2c error: bytecode backend: a local needs an open procedure

which said, immediately, that the FIRST thing to break is not the id but the FRAME: the front end
interns a declaration's parameter slots while parsing its header, and `Local` refuses when nothing is
open.  Splitting the frame owner from the body owner - `Frame_Proc` set at the declaration, `Cur_Proc`
at the begin - fixed exactly that, and the trace moved on:

    TRACE begin Length id= 0 locals= 2 open=FALSE

So the parameters are interned correctly now, and the id is 0 at the begin.  Chasing that produced the
finding that matters, and it is about the front end's SHAPE rather than any one line:

**A procedure declaration is parsed TWICE.**  The first pass opens the procedure; the second emits the
body into it.  That is what `not Proc_Open` was really detecting - not a duplicate, but the second
half of one declaration - and it is why the id must live across the two passes, and why the first
pass's open must still be in force when the second pass runs.  Deferring the open to the `begin`
attacks that structure head-on, which is why three variations on it all broke the same 143 fixtures
while each fixed a different piece of what the trace showed.

**So the plan changes**: leave `Begin_Proc` where it is, and give a NESTED procedure the ordering it
needs some other way - the likeliest being to emit a nested body into the same buffer position but
with the enclosing body's bytes placed after it, or to emit nested bodies in a separate pass over the
declaration text.  That is a design question to settle deliberately, not by patching the open.

The trace itself is the win here: two lines replaced three failed attempts, and the second line
reframed the problem.  Nothing is committed from this attempt - `git checkout compiler/`, build 0
warnings, `run_bc` PASS, `run_vm` PASS - and the committed state is still 3dr's emitter split.

## 4. Method — what worked, and what did not

**Measure; do not infer.** Every wrong turn this session came from an inference
where a measurement was available, and every correction came from reading or
running. Nine probes were wrong before the code was.

**When a probe reports an error, suspect the probe first.** The failures fell
into three flavours, all the same mistake in different clothes:

    searched for a DECLARATION, not a use        (twice)
    assumed a call has PARENTHESES               (once)
    wrong name / wrong syntax / hidden output    (six times)

**Read how a thing is USED, not how it is declared or named.** This fixed
`Convert`'s names, `FDel`'s existence and `Delete`'s meaning. It also settled
whether `In` needed a platform seam (it does — `O2c_In_Load` calls
`Aegir_User.CLI.Get_Line`) and whether `XYplane` did (it does not — the Ada
backend keeps a shadow plane in the program).

**Put the diagnostic where the failure is and let the program report.** Three
rounds of reasoning about `Args.Get` were worth less than one line inside the
compiler, which printed `get=TRUE n3=TRUE` and moved the search to the emission
body.

**When a value looks like evidence, check that the code which would produce it
ran.** `r` reading `-1` looked like a working out-of-range path; the native was
never running and `-1` was uninitialised memory.

**Verify the artefact, not the report.** A scripted edit printed its success
message while changing nothing; `git status` was clean. After any scripted edit,
`grep` for a marker and check `git diff` **before** building.

**Let the compiler catch syntax.** A reserved word (`At`) and a dangling
`elsif` were each one build cycle, not worth reasoning about in advance.

## 5. Traps specific to this repo

- **`tools/bin/o2c_bc_host` links the compiler sources.** After changing any
  `compiler/*.adb` you MUST `rm -f tools/bin/o2c_bc_host && make tools-host`,
  or you will debug a stale binary. `make build` alone is not enough.
  `tools/bin/o2c_tokscan` links the lexer and is the coverage check's oracle -
  it is built by the same `make tools-host`, and a stale one would report
  coverage for a lexer that no longer exists.
- **The `VM_Platform` seam is three files per platform**, not two: the spec, the
  body, and the probe in `vm/compat-aegir/aegir_interface.adb`. Missing the
  Aegir *body* passes all three host suites and only `run_m1` notices.
- **`make -j` is forbidden** — concurrent gprlib corrupts `libaegir_user.a`.
- **Always `timeout`** around tests and the VM; a wedge otherwise spins forever.
- **Kill QEMU with `pkill -f "qemu-system-riscv6[4]"`** — the bracket class
  stops the pattern matching the invoking shell's own command line.
- **`/tmp` is not persistent between sessions** — recreate probe sources.
- **Run the suites from the repo root**; some paths are relative.
- **Ada reserved words that have bitten:** `at`, `yield`, `Entry`, `Body`.
  Identifiers may not end with `_`.
- **Append-only:** opcodes, syscall numbers, ABI handles, foreign native ids.
  New natives go at the end of the foreign table; `labs` is id 5.
- **A test that reports nothing is not a passing test.** A probe that fails to
  create its fixture can pass vacuously — write the fixture immediately before
  the check, as `tests/bytecode_gaps.sh` does for the file operations.

## 6. Files worth knowing

    docs/bytecode-gaps.md      the checklist; section A is generated
    tests/bytecode_gaps.sh     the executable half — asserts the working set
    tests/coverage.sh          every lexer token kind is exercised, or a recorded gap
    tests/differential.sh      both backends vs the golden, three ways — the gate
    tests/ada_host/            the host console shim that lets the Ada side RUN
    tests/run_bc.sh            fixtures in tests/bc/ (.ob2 + .out golden)
    tests/run_m1.sh            the guest build and the Ada-vs-VM diff
    compiler/o2c_compiler.adb  ~11k lines; the FFI call sites are near the end
    compiler/o2c_lexer.ads     the token kinds coverage is measured against
    vm/obc_vm.adb              the VM; natives are in the native dispatch
    vm/vm_platform.ads         the seam spec
    vm/compat-host|aegir/      the two seam bodies
    tools/o2c_bc_host.adb      the host bytecode front end; libs as extra args
    tools/o2c_ada_host.adb     the host Ada-text front end; prints the units
    tools/o2c_tokscan.adb      lexes a corpus and reports the kinds it finds

## 7. One thing to decide early — DECIDED

The differential (3c) is the standing answer to "stop surprising me", but it
only covers what the corpus exercises. **Ask whether the fixtures should be
written per *construct* (3b) or per *feature*.** Per-construct is what makes
coverage checkable mechanically against the lexer; per-feature is what the
previous 64 fixtures are. The answer probably changes how 3b is done, so decide
it before writing fixtures.

**Decided: per CONSTRUCT, mechanised against the lexer's `Tok_*` list.** The
`or`/`not` work settled it. Both were invisible precisely because no fixture
exercised the *token*: the corpus had 64 fixtures covering plenty of features
and still never evaluated a unary operator. A feature-level list cannot be
checked mechanically, and an uncheckable list is what let a silent wrong image
survive. Two caveats to carry into the work, both measured above: the
mechanical grep needs a per-token fixture **in `tests/bc`** (a hit in `samples`
does not count — nothing runs it), and a hit only says *look here*, so each new
fixture must assert the construct's **value**, not merely that it compiles.
