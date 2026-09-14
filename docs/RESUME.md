# RESUME — starting point for the next session

Written at the end of a long session on the bytecode backend's FFI surface,
then corrected and extended by the three sessions that followed it - the unary
operators, construct coverage, and descending FOR.
Read this first; the details live in `docs/bytecode-gaps.md`.

    HEAD            find it with:  git log --oneline -1
    commits         443
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

### 3du. Measured: 97 declarations, each ONCE — so 3dt's two-pass reading was wrong, and
the guard skips far more than nested procedures

3dt concluded from a comment that a procedure declaration is parsed twice and rested a plan on it.
Before building on that, the claim was measured - a counter at the declaration site and a full run
over one fixture.  The measurement says:

    97 declarations, every one reached exactly ONCE
    existing_id = 0 for all 97          (so nothing stale is being reused)
    69 of the 97 see open=TRUE          (so the not-Proc_Open guard skips 69 of them)

**So the two-pass reading is wrong** - that is the third of my inferences about this front end that a
measurement has overturned, and it is the reason the plan is now grounded rather than reasoned.

**And the third line is the finding.**  The declarations that see `open=TRUE` are not only the nested
ones.  They start at `Math`'s first exported member:

    TRACE decl#  1 Length open=FALSE
    ...
    TRACE decl# 27 power open=TRUE      --  Math's FIRST top-level member
    TRACE decl# 28 exp open=TRUE
    ...
    TRACE decl# 96 Bump open=FALSE      --  the fixture's own, declared last

`power` is a top-level member of a builtin module, and something is already open when it is declared -
so the guard `not Proc_Open` withholds an id from it.  That is much wider than "nested procedures":
ANY declaration reached while something is open is skipped, and inside a builtin, whose module is
compiled as one unit ahead of the user's own, that is most of them.

**So the next probe is one line, and it is not the id**: print `Proc_Open` when each MODULE starts and
ends.  Something is open across Math's declarations that should not be - the likeliest candidate is a
preceding module's body frame outliving its `End_Body` (which the emitter's own comment says used to
leak), and the trace above is the first evidence pointing at it.  Until that is known, every
explanation of the 143 fixtures is a guess - and this turn is the argument for not making one.

The instrument is reverted, the tree is green (`run_bc` PASS), and the committed state is unchanged.

### 3dv. FIXED — the module frame leak: a guard that skipped the close for unflipped builtins

The trace in 3du pointed at the module boundary and the code named itself.  `Emit_Module` begins:

    --  A module must START with no frame open.  The previous module's body frame is
    --  still open at this point ..., and leaving it open makes this module's first
    --  procedure skip its id - see O2c_BC.End_Body.
    if O2c_BC.Bytecode_Mode then
       O2c_BC.End_Body;
    end if;

The close was guarded by `Bytecode_Mode`.  An UNFLIPPED builtin compiles with that false - the mode
is the flip (`Compile_Builtin (Src, Scoped)` sets it) - so the module BEFORE such a builtin leaves its
body frame open, and every later module's declarations see `Proc_Open` true.  The guard at the
declaration (`not Proc_Open`, which is what withholds the id) then skips them.

**Why it survived twenty sessions**: the modules after a leak are unflipped too, and an unflipped
module needs no ids - its members refuse anyway.  It only bites when a LATER module is flipped, and
`Reals` is the first one that ever was.  The trace showed it exactly: `Wait` (Files' last member,
Files being the unflipped module before Math) is the last declaration with `open=FALSE`, and Math's
`power` is the first with `open=TRUE`.

**The fix** is to close unconditionally, which is safe because the emitter's `End_Body` is a no-op
when no body is open.  `run_bc` PASS - no regression - and the top-level members of a flipped builtin
now get their ids.

**And `Reals` still refuses, at exactly the place it should:** `call to 'Put' ... with no procedure
id`.  `Put` and `Digit` are NESTED, and nested declarations are skipped by that same guard for the
right reason - they are reached while their enclosing procedure is open.  So the leak is fixed and the
nested case remains, now cleanly separated from it.

**What that leaves validated for the nested work**: 3dr's emitter split (committed, green), the
`Frame_Proc` split measured as necessary in 3dt (parameters are interned at the declaration, so the
frame must start there while the body starts at the begin), and 3dq's static link, which needs no new
VM opcodes because slot addresses are stable since 3dk.  The remaining question is only the ORDER of
the code buffer.

### 3dw. Nesting works: 143 failures down to ONE — and the recipe is now exact

3dv fixed the leak; that removed the thing masking everything else, and the nested-procedure work
then went from impossible to nearly done in three measured steps.  The change is REVERTED (the one
remaining failure makes the suite red, and this repo does not land red) but it is written down here
in full, because the next attempt should be mechanical rather than exploratory.

**The recipe, three pieces, every one of them measured rather than reasoned:**

    the frame/body split    `Frame_Proc` (the frame owner, set at the declaration, where the header
                            interns parameters) separate from `Cur_Proc` (the body owner, set at the
                            begin).  `Local`/`Local_Slot`/the locals table key on `Frame_Proc`.
    the id, carried         `Open_Proc (Decl_Bc_Proc)` - and NOT `Syms (N_Sym).Bc_Proc`: the local
                            declarations between header and body move `N_Sym` (`:= Param_Base` drops
                            them), so reading the symbol at the begin gives 0 and Open_Proc dies on
                            an index check.  That single fact was behind every 143-failure attempt.
    `Next_Frame` untouched  `Open_Proc` must NOT reset it: it belongs to the frame Reserve_Proc
                            started.  Resetting gave the body's locals the parameters' slot numbers,
                            which is the "local slot out of range" that 23 fixtures then showed.

**And what it produced, measured at each step:**

    144 failures  ->  the frame split + the id carried + no Next_Frame reset  ->  2
    2             ->  End_Proc tolerates a declaration with no body (an EXTERN stub reserves a frame
                      and opens none), and Return_Void only when a body was opened  ->  1

**The one left is a negative test**: `threadmutex_bad.ob2` (a local mutex in `Worker`) now compiles,
where it must be refused by the check at 9479, `O2c_BC.Local_Slot (Ada_Id (Arg)) >= 0`.  Reading has
not explained it - `m` is a local of `Worker`, and at its statements `Frame_Proc` is `Worker`'s - so
the next step is the same instrument that produced all of the above: print `Local_Slot ("m")` at that
check, and `Frame_Proc` when `m` was interned.

And `Reals`, with the flip, gets past the nested id entirely and fails at `LEN of an unknown
parameter` - the UP-LEVEL access itself, which is 3dq's static link: the next piece, now reachable
rather than hypothetical.

### 3dx. The mutex check: two measured facts that do not fit — next probe, not next guess

3dw's recipe reproduces exactly (144 -> 1 with the three pieces and the two small fixes), and the one
remaining failure was instrumented.  It printed, for `threadmutex_bad.ob2`:

    TRACE intern m frame_proc= 30 next_frame= 0      --  m interned into Worker's frame, slot 0
    TRACE mutex arg=m slot=-1 nlocals= 0             --  and the check finds neither

Two facts, and they do not fit.  `m` IS a local of `Worker`, interned with `Frame_Proc = 30` and
`Next_Frame` incremented to 1.  At `Threads.Lock (m)` inside `Worker`'s statements, `Local_Slot`
returns -1 and `Local_Count` - which returns `Next_Frame`, not `N_Locals` - returns 0.

Checked before writing any of this down: `Open_Proc` no longer resets `Next_Frame` (the patch is in),
and the only `Next_Frame := 0` left are the startup reset and `Reserve_Proc`'s own.  The module body's
`Begin_Body` runs after the declared procedures are closed, so it cannot be the one that reset it
mid-body.  So the reset is somewhere reading has not found, and the next step is one more print -
`Frame_Proc` and `Cur_Proc` at that same check, which needs them exposed for the trace.

**What is settled and does not need re-deriving**: the three-piece recipe (frame/body split; the id
carried in `Decl_Bc_Proc`; `Next_Frame` not reset at the body) plus `End_Proc` tolerating a
declaration with no body and `Return_Void` only for a real one takes 144 failures to 1.  That is
written down in 3dw and reproduced twice.

The instrument and the recipe are reverted; the tree is green (`run_bc` PASS, `run_vm` PASS) and the
committed state is 3dv's leak fix.

### 3dy. The mutex check: the local is ALREADY in the table — so the next probe is the table

3dx left two facts that did not fit.  Sequencing the emitter's own steps answered it, and the answer
inverts what I had assumed.  With traces in `Reserve_Proc`, `Open_Proc`, `End_Proc` and after `Local`'s
interning, the fixture prints:

    T reserve  id= 30 frame= 0  next= 0
    T openproc id= 30 frame= 30 next= 0
    TRACE mutex arg=m frame_owner= 30 body_owner= 30 next_frame= 0

There is NO `T internal m` line anywhere.  `Local ("m")` therefore took its LOOKUP path - it found an
entry whose `Proc` is already 30 - so `m` was put in the locals table BEFORE the declaration's own
interning, and the declaration's call then found it and did not increment `Next_Frame`.  That is why
the count is 0 and the slot is stale: not a reset, and not a missing intern, but an intern that already
happened.

**So the next probe is the table itself**: at the mutex check (and at the declaration), print
`N_Locals` and every entry's `Proc`/`Slot`/`Name`.  Two candidates are worth naming so the output can
rule between them - `O2c_BC.Local` being reached twice for one declaration (the second call finding the
first's entry), and the parameter interning path, which runs at the header and may register the names
that the `var` section then re-uses.  The trace above cannot distinguish them; the table can.

**Settled and unchanged**: the three-piece recipe from 3dw takes 144 failures to 1, reproduced twice,
and is saved as a script (`/tmp/nest_recipe.py`) so applying it is mechanical rather than retyped.

Instrument and recipe reverted; tree green (`run_bc` PASS) and the committed state is 3dv's leak fix.

### 3dz. The mutex failure is MY comparison, not a missing intern — isolated by running the clean tree

3dy concluded a pre-existing table entry was defeating the intern.  Running the SAME instrument on the
CLEAN tree (no recipe) separates the two possibilities in one line, and it is the recipe:

    clean tree:   S clean-slot m cur= 30 nloc= 92      and the check FIRES
                  o2c error: a mutex must be a module-level variable, not a local
    with recipe:  the table is 74 entries, no L INTERN for m, the check does not fire

So `m` IS interned on the clean tree, the check works, and the recipe breaks the interning - by making
`Local`'s lookup MATCH something it should not, so the real intern never happens.

**And the mechanism is now visible in the two counts**: entries are interned at the DECLARATION, which
on the clean tree is when `Begin_Proc` runs - so intern and use both see the same `Cur_Proc`.  The
recipe opens the body at the BEGIN instead, so a header-time intern sees `Cur_Proc = 0` while a
use-time lookup sees `Cur_Proc = 30`: the comparisons no longer agree, and the `Frame_Proc` change I
made to compensate shifts the mismatch rather than removing it (92 -> 74 entries is exactly that).

**So the next attempt's fix is specific**: the locals table's ownership field and BOTH comparisons must
agree on a single value that is the same at intern time and at use time.  `Frame_Proc` is that value in
principle - it is set at the declaration and lives until End_Proc - and the 92/74 difference says my
application of it was not uniform (one of the two loops still compared `Cur_Proc`).  That is a
one-place check rather than a redesign.

The instrument and the recipe are reverted; the tree is green (`run_bc` PASS) and the committed state is
3dv's leak fix.  The recipe script is /tmp/nest_recipe.py.

### 3ea. Both of 3dz's explanations are eliminated — the recipe LOSES internings

3dz named two suspects: one loop still comparing `Cur_Proc`, and a non-uniform ownership field.  Both
were checked in the recipe-applied file and both are false:

    761:  if Locals (I).Proc = Frame_Proc        --  Local's lookup
    771:  Locals (N_Locals) := (Proc => Frame_Proc,
    790:  if Locals (I).Proc = Frame_Proc        --  Local_Slot's lookup

All three agree, and there is no `Cur_Proc` left in a locals context.  So the comparisons are uniform
and my explanation was wrong - the fourth hypothesis about this front end that inspection has killed.

**What IS established, and it is a clean discriminator**: with the recipe the table holds 74 entries
and `m` is not among them; without it, 92 entries and `m` is.  The recipe therefore LOSES internings -
18 of them - and `m` is one.  The instrumented runs are the evidence:

    clean:        S clean-slot m cur= 30 nloc= 92      and the check fires
    with recipe:  S enter m frame= 30 nloc= 74         and it does not

**So the next probe is not a hypothesis at all**: run the *same* two instruments (`Local`'s enter/intern
and `Local_Slot`'s enter, which are written and were removed only to keep the tree clean) on the clean
tree and on the recipe tree, and DIFF the two logs.  The 92nd-vs-74th difference says the recipe
suppresses 18 `Local` calls; the diff says which, and each one is a call that reached the intern before
and does not now.  That is the whole remaining question, and it is a log comparison rather than a guess.

**Everything else about the recipe stands**: 3dw's three pieces take 144 failures to 1, reproduced
twice, and the script is /tmp/nest_recipe.py.  The two small fixes (End_Proc tolerating a bodyless
declaration, Return_Void only for a real body) are part of it.

Instrument and recipe reverted; tree green (`run_bc` PASS, `run_vm` PASS); committed state is 3dv's
leak fix.

### 3eb. LANDED — nested procedures get their ids, and run_bc/run_vm are GREEN

`Reals.Convert` needed nested procedures, and this is the whole chain, now in and passing.  Five
pieces, and the last one was found by the code's own comment:

    the frame/body split      Frame_Proc (set at the declaration) vs Cur_Proc (set at the begin).
                              Local/Local_Slot and the locals table key on Frame_Proc.
    the id carried            Open_Proc (Decl_Bc_Proc): the local declarations move N_Sym, so the
                              symbol cannot be read back at the begin.
    Next_Frame untouched      Open_Proc must not reset it; it belongs to the frame.
    End_Proc/Return_Void      a declaration with no begin (an EXTERN stub) reserves a frame and opens
                              no body, so End_Proc keys on the frame and Return_Void on the body.
    the interning GATE       a procedure's locals are interned during its HEADER, and that site was
                              gated on Proc_Open - which the deferred body makes false there.  It is
                              now gated on Frame_Open.  The comment at that site records the FIRST
                              time this exact mistake was made ("gated on In_Proc, which is set at the
                              body's BEGIN ... every local silently resolved to a global"); the
                              lesson repeated one level down, and the comment is why it was quick.

**The descent, all measured:** 144 failures with the first three pieces, 2 with End_Proc/Return_Void,
1 with... and 0 once the gate moved to the frame.  `run_bc` PASS, `run_vm` PASS.

**And the next piece is the up-level access, which is now the ONLY thing between `Reals` and a flip.**
With the flip, `Reals` gets past the nested ids entirely and stops at `LEN of an unknown parameter`:
`Put`/`Digit` reaching `Convert`'s `str`.  3dq's design applies unchanged - the static link is an
ordinary slot the caller passes, and an up-level access is `Load_Local (link)`, `Push_Int (outer slot)`,
`Load_Idx (8)`, all with NO new VM opcodes because slot addresses are stable (3dk).

**And it must REFUSE rather than resolve silently**: an up-level name that is not in this frame
currently falls back to a module global (`Local_Slot` = -1 -> `Load_Global`), which is a silent wrong
answer - the thing this backend exists to refuse.  So the level field from 3dq comes with the access:
a name whose declaration level is below this frame means the link, and anything deeper refuses.

### 3ec. The static link: the depth semantics measured, and why the piece is three changes

3eb made nested procedures compile.  The remaining piece for `Reals` is the static link, and the first
thing to establish is what `Nested_Depth` actually means at the point the design depends on - the
reserve, which is where the callee's frame size is decided.

    Nested_Depth := Nested_Depth + 1;   Decl_Procedure;   Nested_Depth := Nested_Depth - 1;

at 6687-6689, in the "a nested PROCEDURE declaration" arm.  So a TOP-LEVEL procedure is declared with
depth 0 and a NESTED one with depth 1 - which means the committed condition for the extra link slot,
`Nested_Depth > 1`, is off by one: `Put` and `Digit` are declared at depth 1 and get no link slot.
It should be `> 0`.

**And that one-line fix cannot land alone**, which is the point of this entry.  `Reserve_Proc (N_Par +
N_Open + 1, ...)` sets the CALLEE's parameter count, and `Push_Frame` pops exactly that many values -
so counting a link slot without the caller pushing one would mis-set every nested procedure's frame.
An unflipped `Reals` means the corpus compiles no nested procedures at all, so `run_bc` would stay
green and tell me nothing: the change is unverifiable in the current tree, and unverifiable changes do
not land here.

**So the piece is three changes together, and they are now specific:**

    the link slot       `> 0` at the reserve (6407), and the callee declaring it - `Local
                        ("o2c_link")` once, at its begin, after the parameters.  Both.
    the caller's push   a call to a nested procedure pushes its own frame address first:
                        `O2c_BC.Load_Addr_L (0)` is the caller's frame base, and it is stable (3dk),
                        which is what makes this a slot and not a new opcode.
    the access          a name whose slot is in the ENCLOSING frame - not this one - loads via
                        `Load_Local (link)`, `Push_Int (outer slot)`, `Load_Idx (8)`; stores are the
                        same shape with `Store_Idx`.  The emitter already has the table to answer
                        "which frame owns this name": `Local_Slot` searches with `Proc = Frame_Proc`,
                        so the enclosing owner is `Saved_Frame_Proc` - one level, and deeper REFUSES
                        rather than falling back to a module global, which is a silent wrong answer.

**Measured, for the next attempt**: with the flip, `Reals` stops at `LEN of an unknown parameter` -
one level up from `Put`, which is exactly the case above.

Tree green (`run_bc` PASS), committed state is 3eb's nested-procedure work.

### 3ed. The link: measured, and two facts from the disassembly that must be reconciled first

The three changes of 3ec were implemented, with a fixture written for exactly this (`nestproc.ob2`: a
nested `Bump` incrementing `Outer`'s `n`, expected 42).  The baseline first, and it is the bug in one
number: BEFORE any change the fixture compiles and prints **0** - `n` resolved to a fresh module
global, which is the silent wrong answer 3ec predicts.

With the changes it compiles and runs but dies on a wild address, and the disassembly says why.  Two
facts, both from `bc_disasm`:

    proc 31 = Outer:  nparams=1  frame=1        --  the link WAS counted
       0: LOAD_CONST [115]   ; n := 40
       5: STORE_L    [0]     ; at slot 0
       8: CALL       [3123]  ; Bump   --  and NO link was pushed
    proc 32 = the module body
       0: CALL       [3098]  ; Outer    --  likewise

So `Outer` - a TOP-LEVEL procedure with no parameters - is recorded with **nparams = 1**, meaning
`Nested_Depth > 0` was true at its RESERVE; and its frame has one slot, with `n` at slot 0, meaning the
link was NOT interned for it, i.e. the same condition was false a few lines later.  The two sites
disagree, and on a top-level procedure both should be false.

**And the parameterless call pushed no link at all**, which is why `Bump` ran with garbage in its link
slot: the `LOAD_ADDR_L` for the 4208 path did not appear in the image even though the patch matched its
text.  That is the second thing to reconcile - whether the emission landed on a path the fixture does
not take, or whether `Proc_Nested` answered false for a callee that was marked nested.

**So the next probe is a trace of `Nested_Depth` at those two sites** - the reserve and the link
interning - for a nested and a top-level procedure.  One run distinguishes "the value differs between
the two sites" from "the condition is right and the counting is not", and that is the same instrument
that has answered every question in this stretch.

Both the changes and the fixture are reverted (the fixture is kept at /tmp/nestproc.ob2, and it will go
into tests/bc/ the moment it prints 42 rather than 0).  Tree green, `run_bc` PASS, committed state is
3eb.

### 3ee. The depth trace: the condition is RIGHT, and 3ed's contradiction was a misreading

3ed asked for the depth at the reserve and left two facts to reconcile.  One trace answered it, and the
answer is that there was nothing to reconcile:

    D reserve Outer depth= 0 npar= 0      --  a top-level procedure
    D reserve Bump  depth= 1 npar= 0      --  a nested one

`Nested_Depth` is exactly what the design assumed: 0 at module level, 1 inside a top-level procedure.
So `Nested_Depth > 0` is the correct condition for "this declaration is nested, it needs a link", and
the pair of facts in 3ed - a top-level procedure with `nparams = 1` AND no link interned - cannot both
be about the same procedure.  They were: I read the procedure table by index and took the entry whose
BODY I recognised, but the bodies are emitted nested-first (that is the whole point of the deferred
open), so the index and the declaration order do not line up the way I assumed.

**That is the fifth wrong inference about this front end in this stretch, and the cheapest to correct**
- two printed numbers, no code change.  What it leaves is a much smaller problem: the depth condition,
the +1 parameter count and the link interning are all right, and the FAILURE is that the caller's
`LOAD_ADDR_L` did not appear in the image for `Bump;` (a parameterless call).  The patch matched its
text at the parameterless expression path, so the next probe is a print at that site: is it reached for
`Bump;` at all, and does `Proc_Nested` say true there.

Tree green, `run_bc` PASS; committed state is 3eb.  The fixture is at /tmp/nestproc.ob2 (expected 42,
currently 0) and goes into tests/bc/ when it passes.

### 3ef. The call traces fire only for Length — and the likely reason is a symbol dropped too early

3ee left one question: is the parameterless call site reached for `Bump;`, and what does `Proc_Nested`
say.  Instrumenting the two call sites answers the first half, and not in the way the question assumed:

    C withargs Length params= 1     (x4, and nothing else)

Four traces in the whole compile, all `Length` from inside a builtin's body.  The fixture's own calls -
`Outer;` and `Bump;` - never reach the call sites at all, so they are emitted somewhere else, or the
symbol they need is not there to be found.

**And the second reading is the one the code supports.**  `Decl_Procedure` ends with

    N_Sym := Param_Base;        --  drop parameters and locals

and a NESTED procedure's symbol is declared inside the enclosing one, i.e. ABOVE that mark - so it is
dropped, together with the parameters and locals, at the end of the enclosing procedure's declarations.
`Bump` is therefore invisible to `Outer`'s own body, where `Bump;` is written.  That would explain both
halves: the call sites for local procedures are never reached because the name does not resolve, and
something else emitted the `CALL` that the disassembly showed.

**The test is one print**: `Find ("Bump")` at the statement that calls it.  If it is 0, the fix is that
`Param_Base` must not drop a nested PROCEDURE symbol - a procedure is not a parameter or a local, and it
is visible for the whole enclosing scope, which is exactly what the nested-declaration syntax means.
That is a one-line change with a fixture already written to prove it.

**Where this leaves the piece**: the depth condition, the +1 parameter count and the link interning are
right (3ee); the caller's push needs a call site that is actually reached; and the reachability is now
the suspect rather than the emission.

Tree green, `run_bc` PASS; committed state is 3eb; the fixture is at /tmp/nestproc.ob2.

### 3eg. Both counts are RIGHT; the visibility fix is not local; the call targets are the next suspect

Three measurements, in the order they narrowed it.

**1. The reserve trace.  Both counts are correct:**

    R Outer depth= 0 cnt= 0
    R Bump  depth= 1 cnt= 1 NESTED

`Outer`, top level, is reserved with no link; `Bump`, nested, with one.  So the +1 convention and the
depth semantics are settled (with 3ee), and `3ed`'s "nparams = 1 for a top-level procedure" was indeed a
misreading of the procedure table - whose field order I also cannot take on trust, since it is my own
disassembler's reading of the doc.

**2. The visibility fix works, and is not local.**  `3ef` was confirmed exactly:

    P drop n    kind=S_VAR
    P drop Bump kind=S_PROC

so `N_Sym := Param_Base` does drop a nested procedure symbol.  Keeping those symbols (moving them down
over the parameters and locals) is a small change in the right direction, and it is NOT local: with it,
the compile produces **zero** call traces where it previously produced four.  A fix whose effect I cannot
characterise does not land, so it is reverted.  The evidence for the diagnosis stands; the repair needs
its own measurement of what else moves.

**3. The call targets are not procedure starts.**  With every call site instrumented, the fixture's own
calls never reach one - and the CALL operands in the image do not resolve to any procedure start (the
disassembler shows `-> ?` for all of them, including the module body's `CALL [3098]` to `Outer`).  Since
bodies are emitted nested-first and the call targets are patched at `Finish`, the offset table is the
next thing to read: a target that is not a start offset is consistent with a patch applied to a stale
offset, and that alone would produce the wild address.

**So the remaining questions are two, both about ids and offsets rather than about frames**: where the
fixture's statement call is emitted, and what the id -> offset patch table contains at `Finish`.  And the
lesson from three reverted attempts in a row is that a repair to this front end needs a measurement
first, not a diagnosis first - the diagnosis has been right four times (3ef included) and the repairs
have been local three times out of three only when they were aimed at a value that had been printed.

Tree green, `run_bc` PASS; committed state is 3eb; fixture at /tmp/nestproc.ob2 (expected 42, still 0).

### 3eh. ROOT CAUSE: `Decl_Bc_Proc` is one variable, and a nested declaration clobbers it

Reading the procedure table properly (by offset, not by the body I recognised) shows the whole failure in
four records:

    29  off=3098  body: n := n + 1        <- Bump
    30  off=3098  body: SAME as 29        <- and OutER's id points here
    31  off=3123  body: n := 40; Bump; Bump; g := n
    32  off=3150  body: CALL 3098 ...     <- the module asks for Outer at 3098

Two records at one offset, and `Outer`'s body emitted under `Bump`'s id.  The cause is one line of state:

    Decl_Bc_Proc : Natural := 0;    --  the id a body opens with at its BEGIN

It is a single variable, set at each declaration.  `Outer`'s declaration sets it to Outer's id; then
`Bump`, declared inside, sets it to Bump's; then `Outer`'s BEGIN opens the body with whatever is in it -
Bump's id.  So the enclosing body is emitted as the nested procedure, two records point at the nested
body, and every call to `Outer` - patched from the id at Finish - runs `Bump` instead, which reaches for
a static link that was never pushed.  That is the wild address, and it is one variable.

**Two corrections to earlier entries, both now measured:**

* `3eg`'s third finding is withdrawn.  The call targets ARE procedure starts; the `-> ?` was a bug in my
  own lookup (I keyed on `operand + 3`, the length of the CALL header).  The fixups are correct and
  `Finish` patches against a final `Buf_Off`.  The stale-offset hypothesis was wrong.
* `3ef`'s diagnosis was also wrong.  `P drop Bump kind=S_PROC` is real, but `N_Sym := Param_Base` runs at
  the END of `Decl_Procedure`, after the body - so the nested procedure is visible in the enclosing body
  all along, and `Bump;` resolved and emitted a call.  The visibility fix was not needed, and reverting
  it cost nothing.

The save/restore of `Decl_Bc_Proc` around the nested declaration was tried WITH the link changes.  It
turned the `STORAGE_ERROR` into a VM **depth violation** - the first diagnostic that names a stack rather
than an address, which is progress of exactly the kind worth having: a verifier error instead of a wild
pointer.  It did not land because it also introduced a compiler warning ("possible infinite recursion" at
the declaration site), and warnings do not land.  The next attempt should hoist the saved id out of the
`declare` block that provoked it - that is a three-line change with a known target.

**So the piece stands at**: depth semantics right, +1 parameter count right, link interning right, and the
id collision identified.  With the collision fixed plus the link push, the failure was already a verifier
depth violation rather than memory corruption - and a fixture at /tmp/nestproc.ob2 that prints 0 (want 42)
will say when it is done.

### 3ei. The id collision is FIXED - the image is correct - and one depth violation is left

The per-invocation local (a variable declared INSIDE `Decl_Procedure`, so each invocation keeps its own -
LIFO by construction) plus the link changes produce a **correct image** and no warnings.  Read off the
disassembly:

    Bump  @3098: LOAD_L[0] PUSH 0 LOAD_L[0] PUSH 0 LOAD_IDX_I PUSH 1 IADD STORE_IDX_I
                 n := n + 1, through the link: link at slot 0, outer slot 0, 8-byte element
    Outer @3123: LOAD_CONST 40; STORE_L 0; CALL 3098; CALL 3098; LOAD_L 0; STORE_G 1   npar=0
    module:      CALL 3123

That is the whole feature working on paper: the enclosing body is emitted under its OWN id with its own
frame, the module's call reaches the enclosing procedure, the enclosing body calls the nested one twice,
and the nested body reads and writes the enclosing local through the static link, 8-byte indexed, with
the link in the last argument slot where `Push_Frame`'s reverse pop puts it.

**Why it still does not land**: the VM now reports `operand-stack depth violation` instead of the wild
address.  That is the right kind of error - a verifier complaint instead of memory corruption - but it is
not yet fixed, so the change does not land.  The measurement that follows is a correct depth trace per
procedure: the one run in this session was worthless because the script's own table gave `LOAD_CONST` a
depth delta of 0 (it must be +1), so every number it printed after the first constant was wrong.  That is
the third instrument error in this stretch - after the `operand + 3` lookup and the procedure table read
by the wrong key - and it is the reason the rule is "measure, then repair", not "reason, then repair":
the instruments need checking as much as the code.

**Two smaller things the image shows**, to settle next: records 29 and 31 have the SAME offset 3098 with
different frames (0 and 1), so a record for the nested procedure looks duplicated - possibly the
provisional record `Reserve_Proc` writes and the one `End_Proc` fills in, or a second reserve.  It did not
affect the emitted code, and it should be understood before the depth violation is chased, since a
verifier walks records.

Tree green, `run_bc` PASS; committed state is 3eb; fixture at /tmp/nestproc.ob2 (still 0; want 42).

### 3ej. The "duplicate record" is a bodyless declaration - and the depth violation is what is left

3ei's second question is answered, and the answer is that there was no duplicate.  The emitter, traced at
reserve/open/end, is authoritative:

    E reserve id=29 npar=0 len=2326 frameproc=0
    E end     id=29 slots=0 len=2326          <- bodyless: length UNCHANGED, offset stays provisional
    E reserve id=30 npar=0 len=2326 frameproc=0     <- Outer
    E reserve id=31 npar=1 len=2326 frameproc=30    <- Bump, nested in 30
    E end     id=31 slots=1 len=2351               <- Bump's body: 2326 -> 2351
    E end     id=30 slots=1 len=2378               <- Outer's body: 2351 -> 2378
    E reserve id=32 npar=0 len=2378 frameproc=30    <- the module body

id 29 is declared and ended without a body, so its `Buf_Off` stays where `Reserve_Proc` provisionally put
it - the code length at that moment, 2326 - and 2326 is exactly where Bump's body begins.  Two records
with one offset, and no duplication.  Note also `frameproc=30` at id 31: the nested reserve correctly sees
Outer as the enclosing frame, which is what `Up_Level_Slot` searches.

**That is the fourth instrument error in this stretch**, and the same species as the third: reading a
table by offset without checking what the offsets are relative to.  The emitter print is what settled it,
in one run.

**What is left is the depth violation, and only that.**  With the image now correct - enclosing body under
its own id and frame, module call reaching it, nested call with its link, up-level access through the
link - the VM's verifier rejects one procedure's operand stack.  The next measurement is a depth trace with
a correct table (`LOAD_CONST` = +1, and the call's pop is the CALLEE's `NParams`, which the record now
carries correctly since the reserve and the end agree).

Tree green, `run_bc` PASS; committed state is 3eb; fixture at /tmp/nestproc.ob2 (still 0; want 42).

### 3ek. The VM named the instruction, and the grep named the bug: SIX call sites, two patched

3ej left one depth violation.  Rather than write a fourth depth script (three of the four instrument
errors in this stretch were hand-written tables), the VM's own checks were instrumented to report their
state.  The verifier's 20 `Bad_Stack` returns printed nothing; the interpreter's 26 printed:

    X badstack pc= 3131 sp= 0

That is exact.  3131 is `Outer`'s FIRST call to `Bump` - the disassembly puts `CALL 3098` at 3123 + 8 -
and SP = 0 says the operand stack is EMPTY at a call whose callee declares one parameter.  The link was
never pushed, which is precisely the symptom the earlier fixes were aimed at.

**And the reason is a count I never took.**  Grepping every `Call_Proc` site in the compiler:

    4171   the expression path WITH arguments      <- patched
    4208   the expression path, parameterless      <- patched
    3995   the library/handle path
    8037   the generic call emitter
    8352   the generic call emitter
    9949   the statement/generic path
    10132  "the EMPTY Op_Arg run: a parameterless call"   <- the shape `Bump;` has

Six sites, and the link push went into two of them.  `Bump;` is a bare-name statement, so it takes one of
the last four - and 10132's own comment already describes it as the parameterless call.  The fix is to
push the link at the site that is reached; the measurement that identifies it is the VM's `pc`, which is
what the interpreter instrument was added to give.

**This is the fifth instrument error corrected by printing, and the first time the instrument was the VM
itself rather than a script of mine** - which is why it was right the first time.  When the code under test
can report its own state, ask it.

Tree green, `run_bc` PASS; committed state is 3eb; fixture at /tmp/nestproc.ob2 (still 0; want 42).

### 3el. LANDED: nested procedures print 42.  The metric moved one step, and its next site is named

**Committed as `ee527b0`** - nested procedures work, with `tests/bc/nestproc.ob2` printing 42 where it
used to print 0, and all seven suites PASS (the fixture runs as a positive check).  The five pieces are
in 3ec-3ek; the one that mattered most was moving the link push into `O2c_Ir_Lower.Call_Proc`, the single
place all six front-end call sites pass through.

With `Reals` flipped on as a probe, the refusal advances from the MODULE (`Reals.Convert is an FFI
primitive and is not yet supported`) to a CONSTRUCT INSIDE IT:

    o2c error: bytecode backend: LEN of an unknown parameter

and that message has exactly one site, at the `LEN` emission: an ARRAY-OF parameter whose name
`O2c_BC.Local_Slot` cannot find.  `Local_Slot` searches `Proc = Frame_Proc` - the CURRENT frame - so a
name one level up is not found, and the `LEN` path does not use the `Up_Level_Slot` machinery that
`Bc_Load` and `Bc_Store` now do.

**So the same up-level treatment is missing in a THIRD site**, and it is the same shape as the two that
landed: `LEN` of an open-array parameter that lives in the enclosing frame needs `Load_Local (link)`,
`Push_Int (outer slot + 1)`, `Load_Idx`.  That is the next step, and it is the reason the metric stops
where it does.

The probe is reverted (the rule stands: `Reals` goes in only with its own evidence), tree green,
`run_bc` PASS, 445 commits.

### 3em. The up-level treatment in two more sites - and Reals' whole backend chain clears

Both fallbacks left by 3el were the same species: a site that calls `O2c_BC.Local_Slot` directly, so a name
one level up is not found and the site refuses.  Given the same treatment as `Bc_Load`/`Bc_Store`:

* **`LEN` of an open-array parameter** - `Load_Local (link)`, `Push_Int (outer slot + 1)`, `Load_Idx (8)`:
  an array-of travels as two slots, so the LENGTH sits one above the address.
* **the base of an indexed access** to an array-of parameter - `Load_Local (link)`, `Push_Int (outer slot)`,
  `Load_Idx (8)`: that slot holds the array's ADDRESS.

Both only replace what was a RAISE, so nothing that compiled before changes behaviour; the gate says so
anyway (all seven suites PASS, and `nestproc` still prints 42).

**Measured with the `Reals` flip ON, the refusal advanced THREE times and then left the bytecode backend
entirely:**

    Reals.Convert is an FFI primitive and is not yet supported     <- before this work
    LEN of an unknown parameter                                    <- after the LEN site
    ARRAY OF parameter is not in the frame: str                    <- after both
    M3 statement expected at line 63                               <- a PARSER limitation

The last one is not a backend refusal at all, and the line number is the BUILTIN's, not the sample's -
this compiler is single-pass, so the module being compiled owns the line.  That is `Oak_Reals_Src`'s line
63, and with `Reals` ON the backend now compiles the whole module.

The flip is still REVERTED, because the builtin does not compile yet: what stands between `Reals` and
`Scoped => True` is an M3-era statement-parser limitation, not the bytecode backend.  That is a different
subsystem and a separate step.  Tree green, `run_bc` PASS; committed state carries the two fixes.

### 3en. The last barrier before Reals, minimised: a NUMBER on the LEFT of a binary minus

3em left a parser message at `Oak_Reals_Src` line 63.  Asking the parser to report the token it choked on
- the instrument that has been right every time this stretch - gives it in one run:

    S stmt-expected kind=TOK_MINUS text='-'

so the statement dispatcher is looking at a MINUS where a new statement should begin: the assignment
consumed `e := 0` and stopped, leaving `- e`.  And the builtin's line 63 is exactly

    e := 0 - e

which reduces it to a shape, not a module.  Minimised:

    x := 0 - x;   ->  M3 statement expected at line 6, token TOK_MINUS
    x := x - 0;   ->  compiles and links (4216 bytes)

**So the parser mishandles a numeric LITERAL on the LEFT of a binary minus.**  That is a pre-existing bug
in the expression parser, unrelated to the bytecode backend, and the corpus has never caught it because
none of its modules writes a number on the left of a minus - which is why `Reals` is the first thing to
trip it.  The two-operand swap above is the whole diagnostic.

Everything in the bytecode backend for `Reals` is now cleared (3em).  This parser shape is the ONE thing
between `Reals` and `Scoped => True`, and it is the smallest possible target: one expression-parser site,
with a six-line reproduction at /tmp/minus_repro.ob2 that will become a fixture the moment it passes.

The probe is reverted (it was instrumentation) and the flip with it; tree green, `run_bc` PASS, 447
commits.

### 3eo. FIXED: an M2 fast path that never checked the literal was the whole RHS

3en reduced the last barrier before `Reals` to one shape; this is the cause and the fix.

The shape was sharper than the minus: **a number on the LEFT of an arithmetic operator**, in an assignment
to an integer.  `x := 0 - x`, `0 + x`, `0 * x`, `0 div x` all failed; `b := 0 = x` and `b := 0 < x` were
fine.  That asymmetry is the whole clue, and it pointed straight at the statement dispatcher:

    if O2c_BC.Bytecode_Mode
      and then Cur.Kind = Lex.Tok_Number      --  the RHS IS a literal
      and then Cur.Len <= 9
      and then Syms (Idx).UT = 0
      and then Syms (Idx).Typ = T_Int          --  ...and the target is an INTEGER
    then

a deliberately narrow M2 fast path for `x := <short integer literal>`.  It tests that the right-hand side
IS a literal but never that the literal is the WHOLE right-hand side - and this parser has no lookahead,
so it cannot check: it consumed the literal, left the operator, and the dispatcher reported "M3 statement
expected" AT THE OPERATOR.  `Typ = T_Int` is exactly why the boolean comparisons survived.

**Removed rather than narrowed**, because there is no way to narrow it without lookahead, and the general
path below already parses the literal as an expression and stores it - correct for every shape, including
the bare `x := 41` the fast path was written for.  Measured after: the reproduction prints **-5**, the bare
form prints **41**, `nestproc` still prints **42**, and all seven suites PASS with a new fixture
`tests/bc/minus2.ob2` pinning the shape.

The lesson is now its fourth instance: the diagnostic that worked was the one that asked the code to state
a fact - here the offending TOKEN - rather than one that modelled it.  "M3 statement expected at line 63"
named nothing; `kind=TOK_MINUS text='-'` named the bug, and the four-way operator test above turned it
into a guard to read.

### 3ep. The metric has LEFT the bytecode backend: the next refusal is an M19 import rule

With `Reals` flipped on AND the parser fix in place, `hello.ob2` compiles past every earlier barrier and
stops here:

    o2c error: M19 imports: only Out, plus library modules provided earlier (found 'Geom')

That is an M19-era IMPORT rule - a module may import `Out` and whatever was registered before it - and it is
not a bytecode-backend refusal at all.  `samples/hello.ob2` imports `Geom`, so the sample needs `Geom`
compiled before it; the compound invocation passes all three precisely so the later ones can import the
earlier ones.

**So the goal's metric has now advanced five times in this stretch - and has left the subsystem the work
was aimed at:**

    Reals.Convert is an FFI primitive and is not yet supported   <- where 3ec started
    LEN of an unknown parameter                                  <- 3em
    ARRAY OF parameter is not in the frame: str                   <- 3em
    M3 statement expected at line 63                              <- 3em (a PARSER limit)
    M19 imports: ... (found 'Geom')                               <- now (a MODULE-STORY limit)

For `Reals` specifically: the bytecode backend is CLEAR and the parser is CLEAR.  What stands between it
and `Scoped => True` is an import/registration story, and that is a different question from this stretch's.

The `Reals` flip is reverted again - not because it fails, but because its evidence would be the suites,
and the honest state is "advances past the backend, stops at an M19 import rule", which is a statement
about the corpus rather than about `Reals`.  Tree green, `run_bc` PASS, 449 commits.

### 3eq. The M19 rule is not about order, and the samples are a system that must each register

Two probes settled what 3ep left open.

  1. `geom.ob2` ALONE fails on its own source, not on imports:
         o2c error: exported VARIABLE 'origin': its RECORD type must be exported (M20f)
  2. `hello.ob2` WITH `geom.ob2` supplied moves on from `Geom` to the NEXT import:
         o2c error: M19 imports: only Out, plus library modules provided earlier (found 'Geo')

So the M19 rule is NOT order-dependent and is not about `Geom` at all: passing `geom.ob2` registered the
name `Geom` successfully - even though that module's own compile failed on M20f - and the rule then
complained about the next name on the line.  And `hello.ob2`'s import list is long:

    import Out, Geom, Geo, Math, MathL, Strings, Texts, Files, In, ...

**The samples are a SYSTEM**: each one imports the others, so `hello.ob2` cannot compile until the modules
it names have registered, and `geom.ob2` does not register cleanly because of M20f - a rule about an
exported variable whose record type is not exported, in the sample's own source.

**Where this leaves the goal**: the bytecode backend clears `Reals` and clears `hello.ob2`'s own code.  What
the metric now reports is the state of the SAMPLE CORPUS - M19 registration and M20f export rules - which is
a property of the test material, not of the backend.  The next step for the metric is therefore to make the
samples register in dependency order, and the first concrete blocker in that chain is the sample's own M20f:
an exported record-typed variable whose type is not exported.

Committed state, tree green, run_bc PASS, 450 commits.

### 3er. The last silent wrong answer in the nested-procedure feature is now a refusal

`Up_Level_Slot` searches exactly one frame - `Saved_Frame_Proc`, the single enclosing frame the static link
reaches.  A name that is TWO levels up was therefore not found, and not found meant it fell through to a
module global of the same name: a fresh, zeroed variable.  That is precisely the silent wrong answer this
stretch opened with (3ec: `nestproc` printing 0), surviving one level higher - and nothing covered it.

**Detecting it soundly needs the scope chain, which the emitter did not keep.**  `Reserve_Proc` saves only
one enclosing frame, so a grandparent is not visible through that variable - but it IS visible through the
record: every procedure now records the procedure that encloses it,

    Parent : Natural := 0;    --  the enclosing procedure, 0 at module level

set at reserve from `Saved_Frame_Proc`, which at that moment IS the enclosing procedure.  So the chain is
recoverable: start at `Frame_Proc`, step past the ONE enclosing frame the link covers, then walk parents -
and if the name is in any of them, it is more than one level up and the callers refuse.

Both fall-through sites now do (`Bc_Load` and `Bc_Store`; the LEN and indexed-base sites already raised):

    o2c error: bytecode backend: 'x' is more than one level up, which is not supported yet

**Measured both ways**: one level up still prints **42** (`nestproc`), two levels up is refused by name, and
the gate is 7/7 PASS with a new negative check in `run_bc.sh` that generates the three-level module and
asserts the refusal ('negative: a name two levels up refused').

*Implementing* deeper access is separate, and now well-defined: the link of the enclosing frame is itself
in the enclosing frame, so a two-level access is `Load_Local (link)`, index the PARENT's link slot,
`Load_Idx`, then the final index - a link walk.  Not done here; refused by name until it is.

### 3es. Reals does NOT land: the metric advanced, and its bytecode is broken

The flip was tried, measured, and reverted.  Two results, both useful.

**1. The metric advanced again.** With `Reals` on, the compound command moves past it:

    o2c error: bytecode backend: Term.SetColor is an FFI primitive and is not yet supported

so the backend now clears `Reals` AND reaches the next library module.  That is the sixth advance of this
metric in this stretch and it is a real gain in coverage.

**2. But `Reals`'s own code is broken at runtime**, so flipping it would land a feature that does not work -
and no suite would notice, because nothing exercises `Reals`.  That is exactly the blindness the standing
rule forbids.  Minimal reproduction (8 lines, /tmp/rr.ob2):

    module RR;  import Out, Reals;
    var s: array 32 of char; r: real;
    begin  r := 1.0;  Reals.Convert (r, s);  Out.String (s);  Out.Ln  end RR.

    -> vm: internal error in phase 3: STORAGE_ERROR (stack overflow or erroneous memory access)

**Bisected, so the next probe starts ahead.**  Not the caller's real arithmetic, not strings, not nested
procedures with parameters:

    r := 1.0; Reals.Convert (r, s)        CRASH
    r := 1.0 / 3.0; Reals.Convert (r, s)  CRASH
    s[0] := "a"; ... Out.String (s)       prints "aa"
    r := 1.0 / 3.0; Out.Ln                runs
    nested procedure WITH a parameter     prints 42

So the fault is INSIDE `Convert`'s own body - 115 lines with a nested `Digit`, a nested `Put(ci)`, a
`for ... to len(str) - 1`, `str[i] := CHR(0)`, and `e := 0 - e` (the shape 3eo fixed).  The next step is to
narrow it within that body rather than around it; the LEN and indexed-store sites are the ones it exercises
that no fixture does.

Tree green (flip reverted), `run_bc` PASS, 452 commits.

### 3et. Fixture-first paid off at once: the sweep found TWO compiler crashes, not a runtime bug

The plan was to write the smallest program for each shape `Reals.Convert` uses and let the crash name
itself.  It did, on the first run - and the fault was not in the routine at all:

    A4: COMPILE -> raised CONSTRAINT_ERROR : o2c_compiler.adb:4634 range check failed
    A7: COMPILE -> raised CONSTRAINT_ERROR : o2c_compiler.adb:4634 range check failed

Both are an INDEXED READ of an ARRAY OF parameter from a NESTED procedure.  The cause is one expression,
in two places:

    Natural (O2c_BC.Local_Slot (Ada_Id (Nm)))

`Local_Slot` returns -1 for a name that is not in this frame - which is exactly what "one level up" means -
and converting -1 to `Natural` raises.  So the compiler CRASHED on a range check instead of working or
refusing.  A5, the same read NOT nested, ran fine: `Local_Slot` finds it, and that is why every existing
fixture was silent about this.

Two sites, both now given the same up-level treatment the load and store paths already had:
* 4634 - the BASE of the indexed read: through the link, `Load_Local (link)`, `Push_Int (Up)`, `Load_Idx (8)`.
* 4685 - the BOUNDS CHECK's length slot: an array-of travels two slots, so the LENGTH is `Up + 1` from the
  enclosing frame, loaded through the link the same way.

**The grep mattered more than the fixes**: searching for the CONVERSION PATTERN found both sites at once,
where fixing one crash at a time would have surfaced the second only on a re-run.  Fixture `tests/bc/aopidx.ob2`
pins the shape (prints 65); the sweep of seven shapes is clean;

    A1 s[0] := CHR(65) in a nested proc        65
    A2 len(s) in a nested proc                  8
    A3 while i < len(s) in the enclosing       66
    A4/A5 indexed read (nested / not)           0   (legit: neither stores)
    A6 for i := 1 to len(s)-1 do s[i] := ...   67
    A7 g := s[0] in a nested proc               1

Gate 7/7 PASS.

**Still open**: `Reals`'s own RUNTIME `STORAGE_ERROR` (3es).  None of the seven swept shapes reproduces it,
so it is elsewhere in `Convert` - the remaining constructs it uses that no fixture does are a `for` whose
body calls a NESTED procedure, and the `e := 0 - e` / digit-emission sequence.  That is the next sweep.

### 3eu. THE SIBLING LINK: Reals works.  A nested call passed the wrong frame.

The sweep was aimed at `Reals`'s runtime crash and found a silent wrong answer instead:

    B3 - a nested proc calling its SIBLING:
      Put and Ten are both nested in Outer; Ten calls Put, which writes Outer's n.
      Printed 32 where 42 is right.

**The cause was in the link push, and it is a one-line distinction.** `O2c_Ir_Lower.Call_Proc` pushed
`Load_Addr_L (0)` - the CALLER's own frame - as the callee's static link.  That is correct only when the
callee is nested DIRECTLY in the caller.  For a SIBLING - two procedures nested in the same parent - the
link must be the PARENT's frame, which for the caller is its OWN link slot.  Pushing the caller's frame
instead made the callee read and write through the wrong frame: a silent 32, and a wild address in the one
place the corpus has this shape - `Reals`' `Digit` calling `Put`.

The fix is a query the emitter is the right layer for, because it holds the parent chain:

    Link_For_Callee (Callee) = Own_Frame  -> Load_Addr_L (0)      nested directly in the caller
                              = slot >= 0 -> Load_Local (slot)    a SIBLING: the caller's link
                              = No_Link   -> refuse               two levels out

**`Reals` now works**: `Reals.Convert (1.0 / 3.0, s)` prints `3.33333E-01`.  The runtime crash of 3es WAS
this bug, and the fixture-first sweep is what found it - not by reproducing the crash, but by pinning the
shape behind it and noticing the ANSWER was wrong.

**A trap worth recording**: the first attempt at the fix used 0 to mean "the caller's own frame", and it
silently did nothing, because slot 0 is exactly where a PARAMETERLESS nested procedure's link lives.  0 was
a valid slot and a marker at once.  Fixture `tests/bc/nestsib.ob2` (42) pins the shape; `nestproc` 42,
`aopidx` 65, `minus2` -5, and the seven-shape sweep are all clean; gate 7/7 PASS.

**Still blocking the `Reals` FLIP** is bug 2 from this step: with `Reals` on, a module-level global is
refused as "'g' is more than one level up" - a FALSE POSITIVE in `Too_Deep_Up_Level`, triggered by the
extra builtins that run before the module.  `Reset` DOES clear `N_Locals`, so the "never cleared" mechanism
inferred last step was wrong; the real one is not yet known.  The instrument is ready and written down:
print the MATCHED frame, `Frame_Proc` and the walk's start at the raise (needs `with Ada.Text_IO;` in
o2c_bc.adb).  That is the next measurement, and it is the last thing between this work and flipping Reals.

### 3ev. Reals WORKS; the flip is blocked by a cross-module false positive, and the epoch fix was wrong

**`Reals` works, and this time it is not a probe.** With the sibling-link fix in:

    Reals.Convert (1.0 / 3.0, s)  ->  3.33333E-01

and the metric advances to the next module: `Term.SetColor is an FFI primitive and is not yet supported`.
So the backend clears `Reals`, `Reals` runs, and the only thing between it and `Scoped => True` is the bug
below.

**The false positive, measured.** Instrumenting the raise gave the mechanism in one run:

    F matched frame 30 name='g' frame_proc=40 fp_parent=37 np_used=40 n_locals=124

In a module with FOUR procedures, `N_Procs_Used` is 40 and `N_Locals` is 124: the emitter's tables span a
whole compiler RUN, not a module.  So the `Parent` walk from the live frame wanders into a BUILTIN's records
and matches its own local named `g` - and a module-level global is refused as "more than one level up".

**The obvious fix is wrong, and the gate said so in one run.**  Adding a per-module `Epoch` (bumped in
`Begin_Body`, required by the three searches) fixed `B3` - and broke `aopidx`, my own fixture:

    run_bc: FAIL: aopidx.ob2 did not compile: 'g' is more than one level up
    differential rc=1   run_stress rc=1

Because `Begin_Body` fires at the module BODY, which comes AFTER the declaration pass - so every procedure's
frames, interned during declarations, carry the PREVIOUS epoch.  The change traded one false positive for
another, and reverting cost nothing: the state at 454 is green and all four fixtures print correctly.

**The next attempt has a better shape**: bound the walk by the module's PROC-ID RANGE (the first id reserved
in this module .. `N_Procs_Used`), which needs no new state and cannot go stale - an earlier module's id is
simply outside it.  An epoch would work too, but it must be set at the DECLARATION boundary, not at the body.

Tree green, `run_bc` PASS, 455 commits, four fixtures (nestproc 42, aopidx 65, minus2 -5, nestsib 42).

### 3ew. LANDED: Reals is flipped.  The blocker was frame state leaking across modules

The proc-id-range bound planned in 3ev turned out to be unnecessary once the mechanism was read
correctly.  The instrument had said `Parent(37) != 0` for a MODULE-LEVEL procedure - and a module-level
procedure's parent must be 0.  So `Frame_Proc` was not 0 when that procedure was reserved: the frame state
LEAKS from one module to the next, and the next module's first procedure records a parent that belongs to a
previous module.  From there the walk wanders, and eventually matches a builtin's local named `g`.

The fix needs no new state, because the compiler already marks the boundary: `End_Body` is called at every
module boundary, so that is where the chain is cut -

    Frame_Proc := 0;  Saved_Frame_Proc := 0;  Link_Of := -1;  Next_Frame := 0;

A module-level procedure's parent is then 0, the walk stops at the module level, and it cannot leave the
module at all.  (An epoch or an id range would work too; cutting the chain where the compiler already says
"module over" is simply the smallest true statement of the same thing.)

**Reals is flipped and the gate is 7/7 PASS with it ON**, so this is a real capability now, not a probe:

    Reals.Convert (1.0 / 3.0, s)  ->  3.33333E-01

Fixture `tests/bc/realsconv.ob2` pins it.  The metric reaches `Term.SetColor is an FFI primitive and is not
yet supported` - six advances from where this stretch began, and no longer inside the bytecode backend.

Five fixtures now cover what this work found: nestproc 42, aopidx 65, minus2 -5, nestsib 42, realsconv
3.33333E-01.

### 3ex. Term flipped too - and the chain is a repeatable shape now

`Term` is compilable Oberon after all: `Oak_Term_Src` has real bodies (`SetColor` is `Bracket`, `Ch`,
`Out.Int`), it was simply left at `Scoped => False`, and `samples/hello.ob2:460` is the line that needed it.
Flipping it compiled and advanced the metric a SEVENTH time:

    o2c error: bytecode backend: Input.Read is an FFI primitive and is not yet supported

**And it is exercised**, not flipped blind: `tests/bc/termuse.ob2` calls `Term.SetColor (2, 0)` and the
golden is the bytes it must emit -

    1b 5b 33 32 6d  1b 5b 34 30 6d  78 0a
    ESC [ 3 2 m      ESC [ 4 0 m      x \n

which is fg=2 as green and bg=0 as black, built from `CHR` and `Out.Int` inside Oberon bodies.  Gate 7/7
PASS, with the fixture reported as "termuse.ob2 compiles, runs, and prints the golden".

**The remaining work has a shape now.** Each module still in the chain is one of two things, and the
measurement that tells them apart is a single grep:

* a compilable builtin left at `Scoped => False` - flip it, probe, build a fixture, gate, land (`Reals`
  3ew, `Term` here);
* a native wrapper whose body is `EXTERN` - that needs a VM native, appended at the end of the foreign
  table, which is a different job.

`Input` (`Oak_Input_Src`, `Scoped => False`) is next and is the same shape as `Term` until the probe says
otherwise.

### 3ey. Term switches to 256-colour, and the terminal gets a written target

A design question that had never been discussed: what the Aegir terminal should handle for escape codes.
Measured before answering - `userspace/terminal/terminal.adb` (1279 lines) handles NO escape sequences, and
`Term` emits a small output-only ANSI set - and the decision is now written down in the AEGIR tree, at
`docs/terminal-emulation.md`: target VT100/xterm, with the sequences `Term` emits as the guaranteed core,
everything outside the set DEFINED (ignored and counted) rather than undefined, and the Term <-> Terminal
integration left as a later unit with the CSI parser specified as a pure function over a byte stream.

Colour follows from it: **256 now**, so `Term.SetColor` emits `ESC[38;5;<fg>mESC[48;5;<bg>m` instead of the
old single-digit `ESC[3<fg>m`, with values outside 0..255 clamped.

**The differential suite earned its place.**  The first version clamped by assigning to the PARAMETERS -
legal in Oberon, where they are copies, and impossible in the Ada the compiler also emits, where they are
`in`:

    diff: FAIL: termuse: ADA_BROKEN, and it is not a recorded Ada-side limit - look at it
    run_m1: host build of emitted Ada failed

So the clamp moved into locals (`f := fg; if f > 255 then f := 255 end; ...`), and the bytes are unchanged.
That is a real hazard for anything written in the Oberon builtins: the same source goes to two backends and
only one of them forbids writing to a parameter.

Gate 7/7 PASS; `tests/bc/termuse.out` now carries the 256-colour bytes.

### 3ez. Input is NOT a flip - it is the boundary to the runtime, and the seam already exists

`Input` was the next module in the chain and looked like `Reals` and `Term`.  It is not, and two measurements
say so before any code.

**It IS compilable Oberon** - `Oak_Input_Src` is 26 lines with real bodies - **but those bodies reference
three names nothing in them declares**:

    procedure Available*: integer;   begin   return InAvail   end Available;
    procedure Read*(var ch: char);   begin   ch := InReadCh   end Read;
    procedure Time*: longint;        begin   return InTime    end Time;

They come from `Aegir_User.Console` - the Ada side `with`s it - so they are the RUNTIME'S input and clock
services, and the bytecode backend has no equivalent.  Flipping it proves the point: the metric advances
(`Input's InAvail/InReadCh/InTime is not yet supported`) and `run_bc` goes to **FAIL (150)**, because nearly
everything imports Input.

**And the refusal is deliberate, with the author's reasoning in the comment**: this arm appends Ada text and
makes no bytecode call, so a flipped builtin's body would compile, run, and quietly do nothing.  That is the
same silent-wrong-answer class as 3ec/3eh, already guarded.

**What the job actually is, measured:**

* the VM HAS an Aegir target (`make vm-aegir`, `vm/vm_aegir.gpr`, `compat-aegir/`) - so binding the console
  is feasible rather than blocked;
* `VM_Platform` is the established seam: **spec shared, body per platform** (host: files, env, args,
  `Get_Line`, exit; aegir: the same through `Aegir_Interface` + CLI).  Console input already has a home
  there, and `InAvail`/`InReadCh`/`InTime` belong beside `Get_Line`;
* the compiler has an M48 FFI arm immediately below the refusal - so the emission side has a pattern to
  follow, and the new ids are append-only like every other table.

So the unit is four pieces, none of them a survey: three services in the `VM_Platform` seam (host and aegir
bodies), three natives appended to the VM's foreign table, the compiler's arm changed from refuse to emit,
then flip / fixture / gate.  Next run executes it; nothing is landed here beyond the measurement and the
revert.

### 3fa. Input, piece 1: the seam's clock - and the Ada helpers read at last

The three names were traced to their Ada implementation, which is GENERATED into the emitted program
rather than living in a package - so reading them defines the job exactly:

    O2c_In_Cload   loops Aegir_User.CLI.Get_Line into a 4096-byte buffer, appending LF each round
    O2c_In_Avail   Cload; return In_C_Len - In_C_Pos + 1        (buffered chars plus the terminator)
    O2c_In_ReadCh  Cload; past the end returns Character'Val (0), else take one and advance
    O2c_In_Time    Aegir_User.Syscalls.Read_Clock (Sec, Ns); return Sec * 1000 + Ns / 1_000_000

**Two consequences, and they make the unit smaller than it looked:**

* the INPUT side needs no new seam function at all.  `Available`/`Read` are LINE-BUFFERED - their Ada
  helper loops on `Get_Line` - so the seam's existing `Get_Line` is the only primitive they need, and the
  buffer belongs in the VM where both platforms share it;
* the CLOCK needs exactly one, and its semantics are fixed by the Ada body: milliseconds since the epoch
  the guest's syscall counts from.

**Landed: `VM_Platform.Clock_Ms`** - spec plus both bodies, host from `Ada.Calendar` against the same 1970
epoch, aegir from `Aegir_User.Syscalls.Read_Clock` with the generated helper's own arithmetic.  **Staged**:
nothing calls it yet.  Verified by building BOTH targets, which is worth more than it looks - the aegir
build is the only thing that checks the guest body, and it confirms `Read_Clock` is the real API rather
than a name read out of generated text.

**Still to do, in order**: the VM's line buffer plus three natives (`in_avail`, `in_readch`, `in_time`,
appended); the compiler's arm changed from the 3602 refusal to emitting those natives in bytecode mode,
which is the M48 FFI pattern sitting immediately below it; then flip, fixture and gate.

### 3fb. Input, piece 2: the VM's three natives - and two traps in the VM's own tables

Landed: `o2c_in_avail` / `o2c_in_readch` / `o2c_in_time`, appended as ids 41..43 with `Pops => 0` (the surface
takes no arguments) and `Native_Pushes => True` (each returns one, or the pushed result reads as a stack
imbalance).  Their implementations mirror the Ada helpers exactly - the LF-joined buffer, the terminator in
the count, `Character'Val (0)` past the end, and milliseconds from the seam's clock.

**Two traps, both found by the compiler rather than by reasoning, and both worth recording.**

1. **The `Foreign` table is ENTRY-indexed, not id-indexed**: ids 30..40 are entries 26..36, so the entry for
   a new id is `id - Max_Natives`.  The new natives are entries **37..39**, while their ARM offsets are
   `Max_Natives + 36 .. +38` - two different numbers for the same three natives, in two tables that look
   alike.  The patch asserted on the wrong anchor, so nothing was written, which is the failure mode this
   habit exists for.
2. **The VM already had an input buffer, and it is the WRONG one.**  `In_Buf`/`In_Pos`/`In_Len` exist for the
   `In` module: they load ONCE, join lines with SPACES, and are walked as TOKENS.  `Input`'s primitives join
   with LF and walk CHARACTERS.  That is exactly why the Ada backend keeps `In_C_*` beside `In_*` rather
   than sharing, so the VM needs the same split - and mine are named `In_C_*` to say so.

**Verified**: both builds clean (`vm-host` and `vm-aegir`), and the FULL gate green - run_vm, run_bc,
bytecode_gaps, coverage, differential, run_m1, run_stress.  The natives are inert until the compiler emits
them, which is the honest caveat: the arm cannot be reached from source yet.

**Still to do**: the compiler's 3602 arm switched from refuse to emitting these three ids in bytecode mode
(the M48 FFI pattern below it); exercising the natives - `vm/fixture/` holds hand-written images
(`VmGreet.obc`), so they can be tested before the compiler can name them; then the flip, a fixture, and the
gate.

### 3fc. Input, piece 3: the arm is right, and there is a SECOND site - the bare-name call

The compiler arm was written as designed - the 3602 refusal replaced by three `Call_Native (41..43, 0)`
emissions, mirroring the Ada branch below it - and the flip turned on.  Two results, and the second is the
finding.

The metric moved: `Input's InAvail/InReadCh/InTime is not yet supported` became

    o2c error: 'InAvail' is not a declared procedure (line  5)

Line 5 of `Oak_Input_Src` is `return InAvail` - and that message has a single site, at 10042, in the
PARAMETERLESS-CALL dispatch:

    if Idx = 0 or else Syms (Idx).Kind /= S_Proc then
       raise O2c_Error with "'" & Head (1 .. H_Len) & "' is not a declared procedure (line " ...

So there are TWO places an FFI name is recognised, and the arm at 3602 is on the FACTOR path.  `return
InAvail` is a bare name with no parentheses, so it takes the parameterless-call path instead - the same path
the earlier session had to fix for USER procedures, and for the same reason: the corpus never wrote that
shape, so nothing exercised it.  `InAvail` is not a symbol, so `Idx = 0` and it refuses.

**Reverted, not landed** - `run_bc` was FAIL (150) while the flip was on without that second site, and a red
tree does not stand.  The measurement stands, though, and reading the site pins the rest of it:

* the raise is at 10015, and the code BELOW it is an argument-list parser - so this is reached from `return`,
  which treats its operand as a call, and the raise fires before that parser is ever entered.  The FFI names
  need the same recognition here, guarded by `Mod_Name = "Input"` and bytecode mode, exactly as the factor
  arm is;
* **and it must LEAVE A VALUE ON THE STACK**, because it is reached from `return InAvail` - the emission is
  `Call_Native (41..43, 0)`, which does that, but the raise has to be skipped rather than replaced, so the
  structure is an `if` that jumps past it rather than a `return`;
* it is worth noting WHY this shape was never exercised: it is the same bare-name call the earlier session
  found unwritten for user procedures.  The corpus has now met it twice from opposite directions - a builtin
  written in Oberon is the first source that WANTS it.

**And reading the factor arm again explains why it did not fire.**  That arm is inside the dispatch for
`Mod_Name`-QUALIFIED members - it recognises `Input.Available`, `Input.Read`, `Input.Time` as written by a
program that IMPORTS Input.  The builtin's own body never qualifies anything: its source is `return InAvail`,
a bare name.  So the arm was correct for callers and irrelevant for the body being compiled, and the
recognition has to exist in the BARE-NAME path as well - which is the same conclusion, reached from the
other side, and it is why two sites and not one.

The line number moved between readings (10042 then ~10016) because the first was taken with the flip and the
arm applied, before the revert: another reminder that a line number is only meaningful next to the revision
it was read from.

**One more measurement, and it changes the shape of the fix.**  `return` itself is handled inside
`Statement_Seq` (7513) and calls `Parse_Expr` for its operand - and the raise, at 10017, is in
`Statement_Seq` TOO.  So `Parse_Expr` returned WITHOUT consuming `InAvail`, and the statement loop then met
the bare name and tried to treat it as a statement.

That contradicts the note from earlier in this work that an unresolved name falls back to a module global -
here it is not falling back to anything.  Which means the bare-name fix may not be "add recognition at the
factor" at all, but "why does the factor decline a name that is not a symbol": the next measurement is a
print at the factor's identifier handling for an unresolved name, and the answer decides whether the fix is
one `if` or something structural.

Worth stating plainly: `Input` has now cost five measurements and no landed compiler change, and the
measurements have each removed a wrong theory rather than adding code.  The next step is that print.

Then flip / fixture / gate, and the fixture can be deterministic: with no stdin, `Available` is 1 (the
terminator) and `Read` gives `Character'Val (0)`, which is what the Ada helper returns.

### 3fd. Input, piece 3: the arm needs a Next - and the whole "second site" theory was wrong

The piece-3 arm was re-applied and failed identically to before, which is the useful result: the error did
not change, so the arm was not doing what its text said.

**The arm never consumed the identifier.**  The Ada branch immediately below it opens with `Next;` - the
name is captured and then the lexer is advanced - and my branch returned without it.  So the statement loop
received back an identifier it had already been given, and `return InAvail`'s own `Parse_Expr` produced a
value from the arm while the loop then met `InAvail` again as a STATEMENT.  Hence "not a declared procedure"
at line 5, both with the arm and without it: without it the refusal fired first, with it the refusal's
replacement did, and the same name was still sitting under the cursor.

**So the "second site" was never needed.**  The `Statement_Seq` raise at 10017 is not a second place that
must learn the FFI names - it is the first place, seeing a name that the factor arm failed to spend.  That
also explains why the earlier readings kept moving: they were readings of a bug in my own arm, not of two
dispatch paths.

The fix is three lines in the arm - capture the name into a local, `Next`, then dispatch on the local,
exactly as the Ada branch does - and it was not written because the second patch's assertion caught a
duplicated body and aborted before writing, leaving the tree in its red intermediate state.  Reverted to
green, `run_bc: PASS`, and the fix is recorded rather than applied under a spent budget.

### 3fe. LANDED: the arm with its Next, and Input flipped - the sixth module

The three-line fix went in as ONE replacement this time, and the whole picture changed:

* **`run_bc` PASSES with `Input` flipped** - down from 150 failures.  The builtin's body compiles now, which
  is what the refusal existed to prevent it from doing *silently*;
* the metric moves again, to a DIFFERENT arm: `Input.Available is not yet supported`.  That is the QUALIFIED
  form - a program writing `Input.Available` - and it is the other half of the same pair.  The arm just fixed
  serves the builtin's own body, which writes bare `InAvail`; the qualified arm (4091/4145) serves callers;
* **the full gate is green**: run_bc, run_vm, bytecode_gaps, coverage, differential, run_m1, run_stress.

So `Input` is module six, and the honest caveat is narrow: the flip makes the MODULE compile and its bare
names resolve, but no user program can call through it yet, because the qualified arm still refuses.  That is
a refusal rather than a wrong answer, which is the state this project's rules ask for.

**And the shape is not unique to Input.**  The refusal list shows `Args.ArgCount in a builtin's own body`
(3527) and `In's InChar/InInt/InLong/InReal` (3677) - two more builtins whose bodies call runtime services,
each with the same structure: a bare name inside the module, a qualified name outside it, and a refusal in
between.  Fixing Input's qualified arm and doing the same for those is one pattern applied three times,
which is a much better position than three separate investigations.

### 3ff. The qualified refusal is a MARKER, and the right fix is not to add Input to the FFI surface

Reading the arm at 4090 shows it is not a per-member decision at all:

    --  MARKER_EXPR_REFUSAL: default refusal, as on the statement paths.
    raise O2c_BC.Wrong_Construct with
      "bytecode backend: " & FNm & "." & MName & " is not yet supported";

It fires because the QUALIFIED dispatch is a hand-written FFI surface - it knows `XYplane.IsDot` and
`Math_Native` by name - and anything it does not recognise falls through to that marker.

**Which means the right fix is the opposite of adding three entries to it.**  `Input`'s procedures now EXIST
AS SYMBOLS, because the module compiles (3fe).  So a caller's `Input.Available` should be resolved the
ordinary way, like any other module's procedure - and one of the three makes that mandatory rather than
merely tidier:

    procedure Read*(var ch: char);

`Read` takes a VAR parameter.  An FFI native takes addresses, which is how Convert.ToInt manages its two
var formals - but `Read` does not need to be a native at all, because its own body is `ch := InReadCh`, and
that resolves through the bare-name arm fixed in 3fe.  Adding `Input.Read` to the FFI surface would duplicate
a body that already exists and is already compiled.

So the change is to let symbol resolution serve Input's members on the qualified path, not to extend the
surface.  That is a smaller change than the last three attempts at this file, and a different kind - worth
recording before anyone starts adding cases to a marker that exists to catch what is missing.

### 3fg. The qualified refusal is NOT Input-specific - it is the parameterless qualified call

3ff concluded the fix was "let symbol resolution serve Input's members".  Measuring where `"Input"` appears
on the qualified path corrects that: it appears in exactly three places, and none of them is a surface that
intercepts `Input.X` -

    3589   the bare-name arm (3fe), guarded by Mod_Name = "Input" - inside the module
    11067  Ada-text generation for the O2c_In_* helpers
    11463  the same, for the module body
    12947  Emits ("Input") - the module list

So nothing is intercepting `Input` by name, and `Reals.Convert (r, s)` proves qualified calls to a flipped
module already work.  The difference is the SHAPE:

    Reals.Convert (r, s)   has parentheses - works
    Input.Available        has NONE       - falls to the MARKER_EXPR_REFUSAL

**It is the parameterless qualified call**, which is the same gap the earlier session recorded for user
procedures - "a parameterless FUNCTION has had no fixture anywhere" - now met from the library side.  That
makes the remaining work a general parser improvement rather than three Input-specific arms, and it is worth
having found before writing them: the fix that was about to be written would have added cases to a marker for
a shape that the module list does not even mention.

The three builtins at 3527/3677/4091 stay on the list, but they are one shape - a bare name inside a builtin,
a qualified name outside it - and this entry says what the outside half actually needs: the parameterless
qualified call, handled once.

### 3fh. The parameterless qualified call: the site, and what the fix has to do in both backends

The path is the imported-module-member handler (3896):

    if Imported_Mod (FNm) then
       ... if T1.Kind = Tok_Dot then Next; Next; Expect (Tok_Ident); ...
           if Xs (XI).Kind = S_Const then ... R.Text := "Mod.Member"; return R;
           if Xs (XI).Kind = S_Var and then ... then ... R.Text := ...; return R;
           if Xs (XI).Kind = S_Var then  --  M20f: exported RECORD VARIABLE

It has a branch for a CONST, two for a VAR (plain and record), and the `S_Proc` handling below them assumes a
CALL WITH PARENTHESES.  A parameterless qualified call - `Input.Available` - therefore reaches none of them
and falls through to MARKER_EXPR_REFUSAL.  That is the whole gap, and it is one branch, at one place, for
every module rather than for Input.

**What the branch must do, in both backends**, and this is the part worth writing down before it is written:

* BYTECODE: the member is a CALL, so it takes the road a call takes - the procedure id and the arity - via
  `Call_Proc (id, 0)`, with `Params /= 0` refused because a member that takes arguments needs parentheses
  and reaching here means there are none.  The result stays on the stack, as every call's does.
* ADA: the same expression must ALSO produce its Ada text, `Mod.Member`, exactly as the CONST and VAR
  branches above do.  That text is valid Ada here - the builtin's own module IS emitted (11463), so
  `Input.Available` names the generated procedure, which in turn calls `O2c_In_Avail`.  This is the one
  branch where the two backends need different things from one place, which is why it is worth not guessing.

Not written: reading the existing `S_Proc` arm below (3975+) is the last step, so the new branch matches its
conventions rather than inventing its own - and the last three attempts at this file are the argument for
reading it first.

### 3fi. The parameterless qualified call WORKS - and two suites say what it still owes

The branch was written (in the imported-member path, before the record-variable case), it built first time
once it used the right field - `Xs (XI).Bc`, whose own comment gives the rule the branch then followed:

    The bytecode procedure id, when this procedure's code is IN the image.  Zero means "not compiled to
    bytecode", and that IS the signal a call site uses to choose between calling it and refusing.

**It works.**  `Input.Available` from a user module now compiles and runs, and prints 0 - which is the
CORRECT value, not a bug: `Available` is `In_C_Len - In_C_Pos + 1`, and with no input that is `0 - 1 + 1`.
The `+1` is the terminator when there is content.  `run_bc` passes with the new fixture.

**And two suites failed, each naming exactly what the branch still owes:**

* **differential: `inputuse: ADA_BROKEN`** - the emitted Ada contains `Input.Available`, and the Ada program
  does not `with Input`.  The branch produces the member's Ada text as the CONST and VAR branches above it
  do, which is right in principle - the builtin's own module IS emitted - but the WITH must be arranged too,
  and that is a separate mechanism (the emit list).
* **bytecode_gaps: `XYplane.Key is not compiled to bytecode`** - that suite pins the exact refusal text for
  gaps, and my new `Bc = 0` refusal replaced the message it expects for `XYplane.Key`.  The refusal is right;
  its WORDING is now a pinned interface.

Reverted, not landed: the committed state is green and the branch is preserved in this entry for the next
run.  Both remaining items are small and named - arrange the Ada `with`, and match or update the pinned
refusal text - and both were found by suites rather than by reasoning, which is the third time in this
stretch that the gate has been the thing that knew.

### 3fj. Both blockers measured - and one of them corrects 3fh

Two greps, and each of the two failures now has a named fix.

**1. `XYplane.Key` USED TO COMPILE.**  The suite's message is "XYplane no longer compiles", and its fixture
line is `if XYplane.Key = CHR(0) then i := 1 else i := 0 end;` - an ordinary parameterless qualified call.
So the shape was never missing a branch at all: the FFI surface below the imported-member path HANDLES it for
the modules it knows.  My branch, placed BEFORE that surface, shadowed `XYplane.Key` and refused it - so
`bytecode_gaps` was right and 3fh's "the `S_Proc` handling assumes parentheses" was too narrow a reading.

The correct place is therefore not "a new branch beside S_Const" but AT THE MARKER: the marker exists to
catch what nothing handled, so the fix is to try symbol resolution THERE, before raising.  That is what 3ff
meant by "let symbol resolution serve Input's members" - and it keeps every FFI entry ahead of it, which is
exactly what my shadowing branch got wrong.

**2. The Ada `with` has a mechanism already**: `Body_Withs` (203), added-to at 454-462, emitted at 11049, and
gated for builtins by `Emits (...)` (12810+).  A module using `Input.Available` must get `with Input;` the
same way - which is a call at the point the usage is recognised, not a new subsystem.

So the remaining change is: at the marker, resolve the member; if it is a procedure with a non-zero `Bc`,
emit the call AND arrange the `with`; otherwise raise exactly as now.  Two call sites, one condition, and
both are already-measured mechanisms rather than new ones.

### 3fk. At the marker now, and the one value still missing is the exported Bc

The branch went where 3fj said - at the marker, as an `elsif` ahead of the refusal - and the placement is
proved right by the suite that caught the last attempt:

    bytecode_gaps: PASS (all listed gaps still as recorded)

`XYplane.Key` is back, so every FFI entry keeps its priority and nothing is shadowed.  But the module still
refuses, which means one of the new branch's three conditions is false.  `XI` cannot be it (the code above
raises when the member is not exported), and `N_A` cannot be it (there are no arguments to count), so it is
the third:

    Xs (XI).Kind = S_Proc  and then  Xs (XI).Bc /= 0  and then  N_A = 0

**`Xs (XI).Bc` is 0 for `Input.Available`.**  The field is documented as exactly this signal - "Zero means
'not compiled to bytecode', and that IS the signal a call site uses to choose between calling it and
refusing" - so the signal is right and the value is wrong, which means the export never received the id.

Where it should come from is measured: the symbol export aggregate sets `Bc => Syms (PSym).Bc_Proc` (6752),
and the shared cataloguer that files it is at 606.  So one of two things is true, and the next command tells
which: either that aggregate is the METHOD export rather than the plain-procedure one, or the export runs
before the declaration's `Reserve_Proc` has set `Bc_Proc` on the symbol.

Reverted, not landed: an inert branch is not a landing, and the tree is green at 474.  The remaining
measurement is one grep for the plain-procedure export path - and it is the last thing between Input and
being usable from a program rather than merely compiling.

### 3fl. LANDED: the parameterless qualified call - Input is usable, and the marker was the place

The branch went in at MARKER_BARE_REFUSAL (the marker whose own comment already named `XYplane.Key`, a
parameterless qualified call the backend knows), resolving the member instead of refusing it:

    if Xs (XI).Kind = S_Proc and then Xs (XI).Bc /= 0 then
       Add_BW (Ada_Id (FNm));                      --  the Ada side's WITH
       O2c_Ir_Lower.Call_Proc (Xs (XI).Bc, 0);     --  the bytecode side's call
       R.Text := "Mod.Member";  R.Typ := ...;  R.Lit := False;  R.Folds := False;

and it works: a program calling `Input.Available` and `Input.Read` compiles and runs, printing `00` - which
is what the Ada helpers return with no input.

Three findings from getting here, each worth more than the patch:

* **no arity test is needed**: reaching the BARE marker means there were no parentheses, so a member with
  parameters cannot be here.  The first version tested `N_A = 0` and did not compile, because `N_A` does not
  exist on this path - the compiler said so in one line, which is the fastest correction of the session.
* **`Xs (XI).Bc` carries the id** - probed rather than assumed, after a wrong guess that the export had not
  received it: `E Input.Available psym= 2 sym_bc= 30 E.bc= 30`.  The signal is documented on the field and it
  is delivered.
* **there are TWO markers with the same text** (a query marker and the bare one), and patching the first left
  the behaviour unchanged - which is the third time a line number misled a reading.  Line numbers belong to a
  revision, and mine move under my own patches.

`run_bc` and `bytecode_gaps` pass, and `differential` passes again once the fixture is withdrawn.

**The blocker is resolved, and the fixture is in.**  `tests/differential.sh` has a recorded-limits list
(a heredoc of `name<TAB>CLASS<TAB>reason`), so `inputuse` went into it - with the reason, because the list is
read by people:

    inputuse  ADA_BROKEN  the Ada side emits the builtin Input, whose body calls Aegir_User.CLI - a GUEST
              unit the host differential build does not have.  A reasoned environment limit, not a defect:
              the Ada backend is being removed, which is why the bytecode backend exists.  The fixture stays
              because run_bc exercises the shape that mattered - a parameterless qualified call.

Gate green with it: diff PASS (66 fixtures corroborated by both backends), run_bc PASS, and the other five.

**`Input` is done.**  It taught more than the other five modules together, and the summary of what it taught
is short: a builtin's own body is written in BARE names, so the marker that refuses bare calls is the place
the backend's general answer belongs - and it took a probe rather than a reading to find, because the two
markers share their text and my line numbers move under my own patches.

### 3fm. Args: the same shape, and now a measured plan rather than an investigation

`Oak_Args_Src` is nine lines and calls two bare runtime names:

    module Args;
    var count*: integer;
    procedure Get*(n: integer; var arg: array of char; var res: integer);
    begin  ArgGet(n, arg, res)  end Get;
    begin  count := ArgCount  end Args.

Flipped, it refuses twice over and `run_bc` goes to FAIL (151) - the same signature as Input before its arms
were fixed - and the metric names the second one: `Args.ArgGet are not yet supported`.

**Both arms are now measured, so this is mechanical next time:**

* the `ARGCOUNT` arm EXISTS (mirroring Input's `InAvail` arm exactly: same guard, same refusal, same `Next`,
  same Ada text).  It needs the same treatment - in bytecode mode, emit instead of refusing.
* there is NO `ARGGET` arm.  That is the refusal in the metric, and it needs writing.
* `o2c_argget` ALREADY EXISTS in the VM (foreign id 13, Pops => 3), so `Get` needs no VM work at all - which
  is most of it.
* `o2c_argcount` does not exist.  One native to append, id 44.

So Args is Input's shape with one arm already present and one native already present: two arms and one native,
against Input's three arms and three natives.  Reverted rather than started, because the tree was red and a
five-part change is not something to begin under a spent budget - but the plan above is read off the code, not
guessed, and that is the difference the last five modules taught.

**Both remaining unknowns are now measured, and both come out easy:**

* **the argument count is available on BOTH platforms.**  The aegir `Arg_Get` guards with
  `N > Aegir_User.CLI.Arg_Count`, so the guest has the count directly; the host's `Arg_Get` already computes
  `Ada.Command_Line.Argument_Count - 1` because its own argument 1 is the image.  So `VM_Platform.Arg_Count`
  is two lines per body and no new concept - which was the one thing that could have made Args expensive.
* **`ArgGet`'s bytecode marshalling ALREADY EXISTS**: `O2c_Ir_Lower.Call_Native (13, 3)` at 8411, in another
  arms' shape, with the address convention the three arguments need.  So the `ARGGET` arm is a copy of a
  working arm, not a design.

So Args reduces to: the `Arg_Count` seam (2 + 2 lines), native 44 appended (Pops 0, Pushes true - id 44 is
entry 40), the `ARGCOUNT` arm switched from refuse to emit, the `ARGGET` arm copied from 8411, then flip /
fixture / gate.  Nothing in it is unmeasured now, which is the state worth reaching before writing rather
than after reverting.

**And it is smaller still: `Args.Get`'s bytecode path ALREADY EXISTS.**  The arm at ~8380 handles the
qualified `Args.Get (n, arg, res)` in full - it parses the three arguments, pushes the value argument (with
the literal-or-load distinction that `Bc_Load` alone gets wrong for `1`), pushes the buffer and the result
slot with `Addr_Global`, and calls `Call_Native (13, 3)`.  So a CALLER of Args.Get is already served.

What is missing is only the BARE `ArgGet` inside the builtin's own body - the same bare/qualified split as
Input, in the opposite order: here the qualified half is done and the bare half is not.  Its arguments are
the body's own parameters, and `arg`/`res` are by-ref, so their slots hold the ADDRESSES the native wants -
which means the bare arm is a small parse and three pushes, with the qualified arm beside it as the worked
example.  The 3-argument parse is the part not yet studied, and that is the next measurement.

`In` (3677, `InChar/InInt/InLong/InReal`) is the same family and should be measured the same way first - and
its four names suggest four arms and possibly a native, which the same kind of reading will settle.

### 3fn. Args: the VM side is in, the arms are in, and the bare arm still does not fire

Staged and verified: `VM_Platform.Arg_Count` (both bodies - the host from
`Ada.Command_Line.Argument_Count - 1`, the guest from `Aegir_User.CLI.Arg_Count`, which its own `Arg_Get`
already guards with), native 44 as foreign entry 40 with `Pops => 0` and a `True` in `Native_Pushes`, the
`ARGCOUNT` arm switched from refuse to emit, and a new bare `ARGGET` arm beside it.  Both VM targets build
clean with all of it.

With the flip on, though, the metric still reports

    bytecode backend: Args.ArgGet are not yet supported

which is the MARKER's wording (`FNm & "." & MName`), not the Args arm's own text ("Args.ArgCount in a
builtin's own body").  So the bare `ArgGet` does not travel through the arm I added beside `ARGCOUNT` - it
reaches the marker instead, which means the bare name is resolved somewhere else in the factor path than the
module arm.

**That is the third instance of the same trap in this file**: two refusals with overlapping text, and the
first one patched is not the one firing.  For Input the answer was a PROBE - printing the condition at the
marker - after two readings had failed.  The same probe is the next step here, at the marker, printing
`FNm`, `MName`, `XI` and `Xs (XI).Kind` when it declines: `ArgGet` is not an export, so `Find_X` should
return 0 and the question is which of the two paths sees it first.

The flip is reverted so the tree is green; the seam, the native and both arms stay, because they are additive
and both VM targets build with them - the same way `Clock_Ms` waited for its native.

### 3fo. Args: the REAL site was 7848, and the arms work - one push short in the emission

The metric's wording was the clue: `Args.ArgGet are not yet supported` - ARE, not IS.  Grepping for that string
found a FAMILY of per-module refusals at 7739-7946 (Convert, Env, Args, XYplane, In), each naming its members
in prose.  The `Args.ArgGet` arm is at 7848, and it is nothing like the `ARGCOUNT` arm I had patched: its Ada
path ALREADY parses all three arguments (`P1` integer, `P2` ARRAY OF CHAR, `P3` integer) and appends
`O2c_Arg_Get (p1, p2, p3)`.  So the bytecode fix was small - drop the raise, and emit beside the Ada append.

**And it works**: with the flip on, `run_bc` PASSES and the metric moves off Args entirely, to

    only INTEGER/CHAR/REAL comparisons are supported, and pointers compare only with NIL

a semantic rule further along the compilation.  So Args' compiler work is done; what follows is the next gap
the corpus meets.

**One push short.**  A fixture for Args - `Args.Get (1, buf, res)` then `Out.Int (Args.count, 0)` - compiles
and then the VM rejects it:

    operand-stack depth violation at code offset 6004: depth-1, limit 153, opcode 195

opcode 195 is the native call, and depth -1 says the three pushes before it did not all happen.  P1 is a
LOAD (or a literal push), and P2/P3 are the body's by-ref parameters, whose SLOT holds the address - which is
why they are `Load_Local (Local_Slot (...))` rather than `Bc_Load`.  One of those three is not pushing what the
emitter expects, and the next step is to disassemble the fixture's Args body and count: `tools/bc_disasm.py`
shows exactly what was emitted, which is how the sibling-link bug was found.

**An eighth refusal site, and the lesson stands**: three turns on this file, and each time the first site
patched was not the one firing.  The probe answered it here (no print appeared at either of the two markers,
which sent the grep to the third string), and the probe is now removed.  The `Args` arms and the native stay,
additive and verified, with the flip off - the same staging `Clock_Ms` went through.

### 3fp. The Args stack bug, disassembled - a bounds-check prefix with no check

`tools/bc_disasm.py` on the fixture's image shows it in one screen.  `proc 36` is `Args.Get` (npar=4: three
parameters plus the open array's length slot), and it contains TWO overlapping sequences:

    proc 36 (frame=4 npar=4)
       0 LOAD_L[0]  LOAD_L[1]  LOAD_L[3]  LOAD_CONST[119]  LOAD_IDX_I     <- stray
      15 LOAD_L[0]  LOAD_L[1]  LOAD_L[3]                                  <- the three loads
      24 CALL_NATIVE [13, 3]                                              <- pops 3
      28 RET_VOID

The first group is the PREFIX of an indexed-access bounds check - the shape that normally reads
`DUP, LOAD_CONST n, IGE, JNZ, TRAP, ...` and leaves exactly ONE value behind - with everything after
`LOAD_IDX_I` missing.  So an indexed access emitted its address-and-index part and then nothing, leaving the
operand stack deeper than the native call expects, which is precisely the `depth-1` the VM reported.

That is the whole of the bug: something in `Args.Get`'s body emits a bounds-check prefix and then stops.  The
body is `ArgGet (n, arg, res)`, and `arg` is an `ARRAY OF CHAR` PARAMETER - so the indexed-access path for an
open-array parameter is the suspect, and it is the same path whose up-level and by-ref variants took three
separate fixes earlier in this work.  The disassembly is the right instrument for it: it shows the emission,
not the intent.

Reverted so the tree is green; the Args arms and native stay staged.  The remaining work is this emission in
the open-array-parameter path, and it would affect any builtin indexing such a parameter.

### 3fq. Checked the instrument first - and the real bug is a qualified VARIABLE read

3fp read the disassembler's per-proc view and concluded an indexed access emitted a bounds-check prefix and
stopped.  Before chasing that, the decode was repeated FLAT over the whole code section, and the earlier
reading dissolved: the per-proc offsets are BASED (the table's `code_off` is `Code_Base + Buf_Off`), so
slicing by them misaligns - the same artifact class as the "two records share an offset" reading earlier in
this work.  Twice now, a tool of mine has reported a structure the code does not have.

Flat, at the offset the VM named:

    5989 DROP
    5990 CALL        [3819]        <- Args.Get
    5995 LOAD_CONST  [288]
    6000 CALL_NATIVE [0, 2]       <- Out.Int, with ONE argument pushed
    6004 LOAD_G      [4]          <- the offset the VM reported
    6009 LOAD_CONST  [289]
    6014 CALL_NATIVE [0, 2]
    6018 CALL_NATIVE [2, 0]
    6022 HALT

and immediately before the call: `LOAD_CONST 286, LOAD_ADDR_G 3, LOAD_ADDR_G 4, LOAD_G 4, DROP`.  The
`LOAD_G 4; DROP` pair is the tell.

**The program is `Out.Int (Args.count, 0)`.**  `Args.count` is a QUALIFIED EXPORTED VARIABLE, and its
imported-member branch produces the Ada text (`R.Text := "Args.count"`) and NO bytecode - exactly the shape
the refusal arms were guarding against, in a branch that never had a refusal because it looked like a read.
So the value is never pushed: one argument instead of two, hence `depth-1` at the native that wants both.

That also explains the stray `LOAD_G 4; DROP`: something emitted the load and then discarded it, where the
argument emission had already moved on.

**This is general, not Args-specific.**  Any qualified variable read - `Args.count`, `Env`'s values, any
exported `var` - takes that branch, and the branch is Ada-only.  It is the same defect class as the bare and
qualified call arms, in the one place nobody looked: a READ rather than a call.

Reverted, tree green; the Args arms and native stay staged.  The next step is that branch: emit the bytecode
load beside the Ada text, the way the call arms now emit beside their Ada text.

### 3fr. The read fix is one call - and the open question is the global's NAME

`Load_Global (Name)` is the right instrument and it is already safe on both paths: its first statement
returns unless `O2c_BC.Bytecode_Mode`, so the `S_Var` branch can call it unconditionally beside the Ada text,
exactly as the call arms emit beside theirs.  One call, no new machinery.

**What is NOT settled is the name, and the disassembly says why.**  The two sides disagree:

* the builtin's own `count` is stored to global slot 2 - proc 37 is exactly `CALL_NATIVE [44, 0];
  STORE_G [2]`, i.e. the module body doing `count := ArgCount` with native 44;
* the importer's read compiled to global slot 4, under the key `Args.count`.

Two slots, two globals: the builtin interned a global called `count` and the importer asked for one called
`Args.count`, so the read never sees the write.  `New_Global` keys by NAME, so the fix is to make the two
sides agree - and which side moves is one measurement, not a guess: what does the builtin's own declaration
intern, and does any existing qualified read in the corpus already work (which would show the convention).

That is the whole remaining question for Args, and it is small and concrete: one call plus the right key.
Everything else - the seam clock, the count native, both call arms - is landed and verified, with the flip
off so the tree stays green.

### 3fs. LANDED: Args - and the bug was a qualified READ, which is GENERAL

Both halves of the question answered by measurement, and both came out clean:

* a module-level var is interned UNQUALIFIED - `Store_Global (Ada_Id (V_Name (1 .. V_len)))`, so the
  declaring module's key for `count` is just `count`;
* the corpus already READS qualified library vars: `samples/hello.ob2:476` is `if Input.TimeUnit = 1000 ...`
  and `:508` is `Out.Int (8200 + Args.count, 0)`.  So `Args.count` is not exotic - the sample does exactly
  it, and that read was producing Ada text and no bytecode.

The fix is one call in the imported-member `S_Var` branch, using the bare member name to match the
declaration, with `Load_Global`'s own bytecode-mode guard making it safe on both paths.

**It works**: `Args.count` reads 0 and `res` reads -1 with no arguments, the fixture prints `0-1`, and the
whole gate is green - run_bc, run_vm, bytecode_gaps, coverage, differential, run_m1, run_stress.

**And the fix is general, not Args-specific.**  Any qualified read of an exported variable took that branch -
`Input.TimeUnit` included, in the very sample the metric is measured on.  The same turn closed a pinned gap:
`bytecode_gaps` had `Args.ArgCount, bare` recorded as blocked, and said so in as many words - "is ok, but this
list says blocked - the list needs updating".

Two notes for the future, both recorded rather than fixed:

* the global KEY is the bare member name, so two modules exporting the same spelling would share one global.
  Latent, not observed, and fixing it means changing both sides and every module's globals with them.
* `differential` records `argsuse` as an Ada-side limit with its reason, the same guest-RTS unit as
  `inputuse` - a limit that retires with the Ada backend.

### 3ft. In: the arms are right and the VALUES are missing - one probe away

Three arms written, mirroring the patterns that landed for Input and Args:

* the `INCHAR`/`ININT`/`INLONG`/`INREAL` bare family: refusal removed, `Call_Native (22..25, 0)` beside the Ada
  text.  All four natives already existed for the qualified path.
* `INOPEN`: `Call_Native (19, 0)` beside its `O2c_In_Reset` append.
* `INSTRING`/`INNAME`: `Call_Native (20 | 21, 1)` with the body's own by-ref ARRAY OF CHAR slot as the address
  - the Args.ArgGet shape.

With the flip on, `run_bc` PASSES (down from FAIL 152).  But `bytecode_gaps` - which has a probe of its own for
In - reports:

    In printed 'helloworld', expected helloworld42882.500

**The text is right and the numbers are absent**, so the values never appear: `In.Int` and `In.Real` produce
nothing.  Their bodies are `x := InInt()` and `x := InReal()` - an assignment to a BY-REF parameter whose
right-hand side is the native call.  That store takes `[base, index, value]`, with the base and index pushed
BEFORE the right-hand side is parsed, so the call's result must land between them and the STORE_IDX.  A native
call as the right-hand side of a by-ref store is therefore the suspect - the same family as the by-ref and
up-level work earlier, and the disassembler is the instrument that settles it: the In probe's body shows
whether the call sits before or after the store's base and index.

**The probe's own output sharpens it further, without any new instrumentation.**  The fixture is

    In.Open; In.String (s); Out.String (s);
    In.Name (n);  Out.String (n);
    In.Int (i);   Out.Int (i, 0);
    In.Char (c);  Out.Int (ORD (c), 0);
    In.Real (r);  Out.Real (r, 0)

and it printed `helloworld` - so String and Name WORK.  The three that produce nothing differ from them in
one place, and it is not the arm: `In.String`'s body is `InString (str)`, a PLAIN CALL, while `In.Int`'s is

    x := InInt()

an ASSIGNMENT whose right-hand side is the call.  `String`'s parameter is by-ref too, so by-ref passing is
not the difference - a call on the right of an assignment is.  That is the suspect, narrowed to one shape,
and it is the same shape a caller writes as `i := SomeFunction ()`.

Also worth recording: an unrelated `run_bc: host build failed` appeared in one background run and did not
reproduce on a re-run - the suites each build the host tool, and one of them raced.  Noted rather than chased;
if it recurs, that is the thing to look at.

Reverted, tree green: run_bc PASS and bytecode_gaps PASS.  What is left for In is the by-ref store with a call
on the right, measured the same way the last four defects were.

### 3fu. The suspect was wrong: the ASSIGNMENT emission is correct, the CALLEE returns 0

The suspicion from 3ft was a call on the right of an assignment.  It is testable without In at all, because
Reals is flipped and samples/hello.ob2 calls Reals.Expo:

    x := Reals.Expo (1.0);  Out.Real (x, 2)

compiles, runs, and prints 0.000 - the value is lost.  So the shape reproduces in a plain user module.

**But the disassembly says the assignment is innocent:**

    5964 LOAD_CONST_R [286]     push 1.0
    5969 CALL         [4856]    Reals.Expo
    5974 STORE_G      [3]       x := result
    5979 LOAD_G       [3]       load x
    5984 LOAD_CONST   [287]
    5989 CALL_NATIVE  [3, 2]    Out.Real

Argument pushed, call made, result stored, result reloaded - and no depth error, so the stack balanced.
The only way that prints 0.000 is that **Reals.Expo RETURNED 0.0**.  The bug is in the callee's return path,
not in the store that consumes it - and the same explanation covers In.Int, whose body is `x := InInt()` and
which also produced nothing.

That is the fifth time in this stretch that dumping the bytes has overturned a confident reading - and the
second time the overturned reading was my own from the previous turn.  The rule keeps earning its place: when
an expression produces a wrong value, look at what the producer emitted before suspecting the consumer.

**Next**: Reals.Expo's own body - a function returning 0. The suspects are its return path (RET against
RET_VOID), the native it calls, or the arithmetic in between - and the disassembler answers it the same way,
on the SAME fixture, with no flip needed: Reals is already in.

### 3fv. Both suspicions dead: the probe was wrong, twice

3ft suspected a call on the right of an assignment.  3fu disproved that from the disassembly and suspected the
callee's return instead.  Both are wrong, and two fixtures settle it:

    x := Twice (21);           -> 42   a LOCAL function on the right
    n := Reals.Expo (250.0);   -> 2    a QUALIFIED one, returning its own type

The second is the one that misled me.  `Reals.Expo*(x: real): integer` returns the DECIMAL EXPONENT, not
e^x - so `Expo (1.0)` is 0 and `Out.Real (x, 2)` printing 0.00 was the right answer to a meaningless
question.  The corpus agrees: hello.ob2 calls `Out.Int (Reals.Expo (250.0), 0)`, an INTEGER.  And the first
fixture shows the assignment shape works, so neither the store nor the call is at fault.

**That is the sixth probe of mine to be wrong in this stretch**, and the fourth in a row to be caught by
running the fixture rather than reading the code.  The rule that keeps being validated is narrower than "dump
the bytes": it is that a NEGATIVE result from a new fixture needs the same scrutiny as a positive one - three
times now, a failing fixture turned out to be a failing fixture rather than a failing compiler.

What survives is much narrower, and it is not the assignment or the call as such: `In.Int`'s body is
`x := InInt()`, where the right-hand side is a NATIVE call and `x` is a BY-REF parameter.  Both halves matter
- a native on the right of a by-ref store, which takes [base, index, value] with base and index pushed before
the right-hand side.  `Twice (21)` is a procedure call, not a native, so neither fixture above exercises it,
and it is reachable only inside a builtin - which is why In is where it shows.

The next probe writes exactly that shape into an ordinary function, with In flipped only to reach it - or
re-applies the three In arms and disassembles `In.Int`'s own body, which shows whether the native's result
lands between the store's base/index and its STORE_IDX.

### 3fw. The In failure is a CRASH the suite hides - and the emission is correct

Running the probe by hand, with its own input and its stderr shown, is what the suite never does:

    vm: running /tmp/int.obc
    hello                                    <- In.String works
    world                                    <- In.Name works
    vm: internal error in phase 3: STORAGE_ERROR (stack overflow or erroneous memory access)

**`bytecode_gaps` never showed this.**  It discards the probe's stderr and compares stdout, so a CRASH reads as
a wrong answer - the entry says "In printed 'helloworld', expected helloworld42882.500" when what actually
happened is that the VM died after two lines.  A suite that reports a wrong value for a crash sends the reader
looking at the values.

And the emission is CORRECT.  `In.Int`'s body is

    4068 LOAD_L       [0]       the by-ref slot - the caller's address
    4071 LOAD_CONST   [121]     the index, and pool[121] = 0
    4076 CALL_NATIVE  [23, 0]   InInt
    4080 STORE_IDX_I

which is exactly [base, index, value].  The address itself is what is bad, so the CALLER did not pass one:
`In.Int (i)` is a qualified call to a FLIPPED module, and `i` is a to-var parameter of it - so the passing
convention across that boundary is the suspect, not the body.  The export carries `By_Ref` (`E.P (I) := (...,
By_Ref => PRef (I), ...)`) and the caller is supposed to use it; whether it does is the next measurement.

Two things worth keeping:

* **a crash can masquerade as a wrong answer**.  `bytecode_gaps` compares stdout only; three suites now have
  had a failure whose true shape differed from its report.
* the last four turns have each ended with a corrected suspicion - three of them my own from the preceding
  turn.  What is holding up is the disassembler and the hand-run; what is not is reasoning about emissions
  from the code that was meant to produce them.

Reverted, tree green.  Next: the by-ref convention across a module boundary - what the caller pushes for a
flipped module's to-var parameter.

### 3fx. Reproduced without In, without a crash, and narrowed to `real`

The by-ref-across-a-boundary question is testable with no flip and no builtin, because Reals is already in.
Two fixtures, both run by hand with stderr shown - which is the habit 3fw established:

    Reals.ConvertTo (r, "3.25");   Out.Real (r, 2)      ->  0.000   WANT 3.25
    Args.Get (1, buf, n);          Out.Int (n, 0)       ->  -1      CORRECT

The second is the control, and it is a control that PASSES: `n` is a module-level global, so it starts at 0,
and printing -1 means the callee DID write through the caller's address.  So `Args.Get`'s to-var INTEGER
parameter works, and `Reals.ConvertTo`'s to-var REAL parameter does not.

**That narrows it to the scalar type.**  Both procedures take an `ARRAY OF CHAR` alongside the to-var
parameter, so the array is not the difference and neither is the boundary: the difference is INTEGER against
REAL.  The next probes are cheap and pin it exactly - a to-var LONGINT and a to-var CHAR would say whether it
is "real" alone or "anything but integer", and both need no flip either.

Note also what did NOT happen: **no crash**, unlike In's STORAGE_ERROR.  So these are two different faults
that the suite reported with the same line, which is the reason 3fw's point matters - the report and the fault
have not been the same thing for four turns now.

Reverted nothing: no compiler change was made for this, and the tree is green.  The probe fixtures are in /tmp
and will become tests when they pass.

### 3fy. Three more probes, all passing - and the residual is a to-var REAL across the boundary

Every local guess is now excluded by a fixture that PASSES:

    to-var REAL in one module                         ->  3.250
    to-var INTEGER control                            ->  7
    to-var REAL + ARRAY OF CHAR param + a literal     ->  1.500   (the ConvertTo shape exactly)

So the scalar type is not it, the array parameter is not it, the literal argument is not it, and two
parameters of mixed kinds are not it.  What is left is the only thing the passing fixtures do not have:

    Args.Get's      to-var INTEGER across the module boundary   ->  -1     WORKS
    ConvertTo's     to-var REAL    across the module boundary   ->  0.000  FAILS

Both are qualified calls to flipped modules with a by-ref parameter; they differ in the parameter's TYPE.  So
the suspect is now the by-ref convention for a REAL - the export's `Typ` and `By_Ref` together, or the size
the caller passes - and the measurement that separates them is a disassembly of the two CALL SITES, side by
side: one that works and one that does not, in the same image, from the same compiler.

That is what the last several turns have been converging on, and it is now a comparison of two known-good
compilations rather than a hunt.  Three probes this turn, all passing, is the pattern to note: the faults get
narrowed by fixtures that FAIL, but the shape of the fault gets narrowed by fixtures that PASS.

None of this needed a flip or a builtin, and no compiler change was made - the tree is green.

### 3fz. The two call sites side by side: identical in structure, so the fault is in the CALLEE

The comparison 3fy asked for, and it clears the caller completely:

    ConvertTo (FAILS):  LOAD_ADDR_G[3]  LOAD_G[3] DROP  LOAD_CONST[286]  LOAD_CONST[287]  CALL[4716]
    Args.Get  (WORKS):  LOAD_CONST[286] LOAD_ADDR_G[3] LOAD_CONST[287]  LOAD_ADDR_G[4] LOAD_G[4] DROP  CALL[3819]

Reading them:

* both push their arguments in the parameter order the declaration gives, an address for each to-var scalar
  and address-plus-length for each open array.  ConvertTo gets [addr(r), addr(literal), len(literal)] for
  `(var x: real; s: array of char)`; Args.Get gets [1, addr(buf), len(buf), addr(n)] for
  `(n: integer; var arg: array of char; var res: integer)`.  Both are right, and both balance against the
  callee's parameter count.
* **both contain the same stray `LOAD_G n; DROP` pair** - the by-ref actual, a wasted load and discard that
  nets zero.  It is in the working call too, so it is not the fault, but it is worth knowing it exists.
* they were compiled by the same compiler from the same run.

So the difference is not in the caller, which leaves the callee: `Reals.ConvertTo`'s own body, where `x := ...`
writes back through the slot the caller filled with an address.  `Args.Get`'s body writes back the same way
and works, so the two bodies are the next side-by-side - and one of them is a to-var REAL and the other a
to-var INTEGER, which is the last distinction standing.

This is the third consecutive turn where the answer came from putting two emissions side by side rather than
reading either one.  The instrument is cheap and the comparison is what carries the information.

Tree green, no compiler change.

### 3ga. ROOT CAUSE: ConvertTo's body stores an ADDRESS into the real

The two bodies side by side, and the difference is not subtle once the pool is read:

    Reals.ConvertTo   4716 LOAD_L[0]  LOAD_CONST[190]  LOAD_L[1]  STORE_IDX_I  RET_VOID
    Args.Get          3819 LOAD_L[0]  LOAD_L[1]  LOAD_L[3]  LOAD_CONST[119]  LOAD_IDX_I  ...

and pool[190] = 0, pool[119] = 0 - both indices are ZERO, which is what a by-ref access wants.  So
ConvertTo's first instruction group is

    *(slot0 + 0) := slot1

read literally: **store the contents of slot 1 through the address in slot 0**.  For
`ConvertTo (var x: real; s: array of char)` the slots are x's ADDRESS (0), s's ADDRESS (1) and s's LENGTH
(2) - so the body's first operation writes S'S ADDRESS INTO X.  A pointer-sized write into a real, at the
start of the procedure, before any parsing happens.

That is why `r` stays 0.000 and why nothing crashes: the write goes through x's address, which is valid, and
puts address bits in it.  `Out.Real` then prints whatever those bits mean - 0.000 here.

**And Args.Get has the same stray prefix but no store at the end of it**, which is exactly the difference
between the two: one body STORES the stray computation, the other leaves it on the stack where a later call
sweeps it up.  That also explains the `LOAD_G n; DROP` pair at the call sites - the same by-ref machinery,
there in a harmless form.

So the fault is in whatever emits that opening store for a body whose FIRST parameter is a to-var scalar
followed by an open array: it treats the array's address as a value to assign.  Two probes would pin it -
a local `procedure T (var v: real; s: array of char)` whose body does nothing but `v := 1.5` (already known
to work, so the difference is the BODY's shape) against `ConvertTo`'s actual body, which begins by assigning.

Six consecutive turns have ended by putting two emissions side by side.  It is now the method, not a trick.

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
