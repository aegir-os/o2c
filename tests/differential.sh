#!/bin/bash
#  The differential: run the corpus through BOTH backends and compare.
#
#  Why this exists.  run_bc already compares the VM against a golden file, and
#  that is enough to catch a VM that regresses - but not a golden that was
#  WRONG TO BEGIN WITH.  A golden produced by running the VM cannot
#  disagree with the VM, so for any construct where the VM is wrong and the
#  golden came from it, run_bc passes and always will.  That is the hole this
#  closes: the Ada backend is a second, INDEPENDENT oracle, and the only way to
#  ask whether a golden is right is to make something else agree with it.
#
#  Why it is a HOST SWEEP, against the note in RESUME (3c) that it would have
#  to run in the guest.  The Ada side's output is Ada source, and that source's
#  whole runtime dependency across the corpus is Aegir_User.Console - three
#  subprograms, because the builtin modules are emitted as pure Ada and Out is
#  inlined into Console calls.  tests/ada_host/ supplies them on the host, so
#  no QEMU, no cross-compile, no initrd.  (Measured, not assumed: see the note
#  in tests/ada_host/aegir_user-console.ads.)
#
#  THE THREE-WAY COMPARISON is the point, and it is why a two-way diff of the
#  backends would be worse:
#
#     golden   the expectation, checked in
#     ada      what the Ada backend's own output does when run
#     vm       what the bytecode backend's image does when run
#
#     ada == golden, vm != golden   ->  THE VM IS WRONG      (a bytecode bug)
#     vm  == golden, ada != golden  ->  THE GOLDEN IS SUSPECT (or an Ada gap)
#     all three differ              ->  look; possibly a front-end bug
#     all three agree               ->  the golden is corroborated
#
#  Which is what distinguishes "the VM is wrong" from "both differ from the
#  golden" - the distinction RESUME flags as the thing to get right.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/alrrt}"
export TMPDIR="${TMPDIR:-/tmp}"

ADA_HOST="$ROOT/tools/bin/o2c_ada_host"
BC_HOST="$ROOT/tools/bin/o2c_bc_host"
VM="$ROOT/vm/bin/vm_main"

#  The host toolchain for building the Ada side.  The same one make tools-host
#  uses: this is a plain native Ada build with no Aegir runtime.
GNAT_BIN="$(dirname "$(command -v gnatmake 2>/dev/null || echo /nonexistent)")"
if [ ! -x "$GNAT_BIN/gnatmake" ]; then
   GNAT_BIN="$(ls -d "$HOME"/.local/share/alire/toolchains/gnat_native_*/bin 2>/dev/null | head -1)"
fi
GPR_BIN="$(ls -d "$HOME"/.local/share/alire/toolchains/gprbuild_*/bin 2>/dev/null | head -1)"
GPRBUILD="${GPR_BIN:+$GPR_BIN/}gprbuild"

#  Fail loudly rather than reporting every fixture as an Ada-side limit: with no
#  toolchain the Ada side cannot be built at all, and "all 59 recorded" would
#  look like a result instead of a broken instrument.
if [ ! -x "$GNAT_BIN/gnatmake" ] || ! command -v "$GPRBUILD" >/dev/null 2>&1; then
   echo "differential: no native GNAT/gprbuild found" >&2
   echo "differential: looked on PATH and under" \
        "\$HOME/.local/share/alire/toolchains; set VM_GNAT_BIN/VM_GPR_BIN" >&2
   exit 1
fi

fails=0
note() { echo "diff: $*"; }
bad()  { echo "diff: FAIL: $*" >&2; fails=$((fails + 1)); }

if [ ! -x "$ADA_HOST" ] || [ ! -x "$BC_HOST" ] || [ ! -x "$VM" ]; then
   ( cd "$ROOT" && make tools-host vm-host \
       AEGIR_ROOT="${AEGIR_ROOT:-}" >"$WORK/build.log" 2>&1 ) \
     || { tail -20 "$WORK/build.log" >&2; exit 1; }
fi

#  Fixtures are the ones with a golden: the *_bad files are refusal tests with
#  nothing to run, and comparing output against nothing is not a differential.
fixtures() { ls "$ROOT"/tests/bc/*.out | sed 's#.*/##;s#\.out$##' | sort; }

#  The Ada unit the compiler generates for a fixture takes its name from the
#  MODULE, not from the file: set.ob2 says `module Setl`, so the main unit is
#  setl.adb and the binary is `setl`.  Assuming the file's name built nothing
#  for set / ifelsif / real / repeat, and gprbuild said only "not a source of
#  project".
module_of() {  # $1 = fixture source
   sed -n 's/^[[:space:]]*[Mm][Oo][Dd][Uu][Ll][Ee][[:space:]]\{1,\}\([A-Za-z0-9_]*\).*/\1/p' \
      "$1" | head -1 | tr 'A-Z' 'a-z'
}

#  Split the Ada-text capture into one file per unit, in Dst.
split_units() {  # $1 = capture, $2 = dest dir
   python3 - "$1" "$2" <<'PY'
import sys, os
cap, dst = sys.argv[1], sys.argv[2]
cur, buf, seen = None, [], False
for line in open(cap, errors="replace"):
    line = line.rstrip("\n")
    #  The END marker must be tested FIRST: "--- unit end ---" also starts with
    #  "--- unit ", so the obvious order treats every end marker as the start of
    #  a unit named "end ---" and then no unit is ever closed or written.  Every
    #  Ada build failed with "not a source of project" before this was noticed,
    #  which is its own lesson about trusting a tally that said PASS.
    if line == "--- unit end ---" and cur is not None:
        with open(os.path.join(dst, cur), "w") as fh:
            fh.write("\n".join(buf) + "\n")
        cur = None
    elif line.startswith("--- unit ") and line.endswith(" ---"):
        cur = line[len("--- unit "):-len(" ---")]
        buf = []
        seen = True
    elif cur is not None:
        buf.append(line)
sys.exit(0 if seen else 1)
PY
}

note "=== the corpus, three ways ==="
agree=0; ada_refused=0; ada_broken=0; vm_wrong=0; golden_suspect=0; split=0
: > "$WORK/report.txt"
: > "$WORK/seen.txt"

#  ---- the Ada backend's own limitations, RECORDED ------------------------
#  Every one of these is the ADA side failing, not the VM: it refuses the
#  construct, or emits Ada that will not compile.  The Ada backend is the
#  oracle here, and it is an imperfect one - it is also the backend being
#  retired, so these are recorded rather than fixed.
#
#  Recording them makes the check a GATE rather than a report: a fixture that
#  is not on this list and is not corroborated FAILS, so a new disagreement
#  cannot appear quietly, and an entry that stops applying FAILS too, so the
#  list cannot outlive its cause.
#
#  <fixture> <TAB> <CODE> <TAB> why.  CODE is the classification the run must
#  produce for that fixture.
cat > "$WORK/recorded.txt" <<'EOB'
gcloop	ADA_REFUSED	refuses: "type mismatch assigning cur.next" (pointer designator)
localprocv	ADA_REFUSED	refuses: procedure values as variables
proccall	ADA_REFUSED	refuses: procedure values as variables
threadid	ADA_REFUSED	refuses: "Threads needs the bytecode backend"
threadjoin	ADA_REFUSED	refuses: procedure values as variables
threadmutex	ADA_REFUSED	refuses: "Threads needs the bytecode backend"
threadname	ADA_REFUSED	refuses: "Threads needs the bytecode backend"
threadstart	ADA_REFUSED	refuses: procedure values as variables
threadstress	ADA_REFUSED	refuses: "Threads needs the bytecode backend"
threadyield	ADA_REFUSED	refuses: "Threads needs the bytecode backend"
inputuse	ADA_BROKEN	the ADa side emits the builtin Input, whose body
argsuse	ADA_BROKEN	the Ada side emits the builtin Args, whose body
envset	ADA_BROKEN	the Ada side emits the builtin Env, whose body
plane	ADA_BROKEN	the Ada side emits the builtin XYplane, whose body
errwrite	GOLDEN_SUSPECT	the Ada side builds and runs this one (its Err
#  calls the same Aegir_User.CLI unit - the identical environment limit as
#  inputuse above, and the same reason it is not a defect: the Ada backend is
#  being removed.  The fixture stays because run_bc exercises what mattered -
#  a qualified READ of an exported variable, which used to emit Ada text and
#  no bytecode at all.
#  calls Aegir_User.CLI - a GUEST unit the host differential build does not
#  have.  A reasoned environment limit, not a defect: the Ada backend is being
#  removed, which is why the bytecode backend exists.
#  envset is the same again, one module further on: the Ada side emits the
#  builtin Env (o2c_envset/o2c_envget), which reaches Aegir_User.CLI for the
#  same reason.
#  plane is the same class: the Ada side emits the builtin XYplane, whose
#  helpers reach Aegir_User.CLI, a guest unit the host build does not have.
#  The fixture still earns its place: run_bc exercises the VM's Dot mode
#  (draw writes 1, erase writes 0 - it used to write 1 always, and an
#  erased dot still read back as drawn).
#  errwrite is a DIFFERENT class - GOLDEN_SUSPECT, not ADA_BROKEN - and the
#  distinction is informative: the Ada side builds and runs it, because its Err
#  helper does NOT reach Aegir_User.CLI the way Env's does.  It still disagrees
#  with the golden, so all three outputs differ.  The golden here is the
#  program's STDOUT (8501); Err writes to stderr, so whether the comparison
#  should carry stderr too is an open question about the suite, not about Err.  The fixture stays because run_bc exercises what mattered - a
#  string LITERAL passed where the arm demanded a declared variable, twice in
#  one call, which used to refuse outright.
#  The fixture stays because
#  run_bc exercises the shape that mattered here - a parameterless qualified
#  call - and that is the backend under development.
#  CASE is the cause of the three "conflicts with a declaration" entries, and
#  it is worth naming because it is a category, not three coincidences: ADA
#  identifiers are case-INSENSITIVE and Oberon's are not, so a module with
#  `type P = pointer to R` and `var p: P` is fine in Oberon and a collision in
#  the emitted Ada.  Every fixture whose types and variables differ only in
#  case trips it.  Not fixed: it needs a per-scope rename table threaded through
#  the Ada emitter, and the Ada backend is the one being retired.
gcscalar	ADA_BROKEN	emits Ada that will not compile: "p" conflicts with a declaration
recmix	ADA_BROKEN	emits Ada that will not compile: "r" conflicts with a declaration
recreal	ADA_BROKEN	emits Ada that will not compile: "r" conflicts with a declaration
list	ADA_BROKEN	emits Ada that will not compile: reference to the current instance of a type
newloop	ADA_BROKEN	emits Ada that will not compile: reference to the current instance of a type
nested	ADA_BROKEN	emits Ada that will not compile: a component used before the record ends
realarr	ADA_BROKEN	emits Ada that will not compile: expected type Boolean
#  newdesig's subject is the BYTECODE side: NEW of a pointer field designator
#  (h.p, and q^.next for the self-referential spelling).  The Ada side takes
#  h.p but refuses q^.next with "NEW needs a POINTER value" - the chain's
#  Ada-mode leaf sends a self-referential field to D_Scalar, which the NEW
#  statement does not read.  list/newloop's self-referential category, one
#  statement earlier in the walk.
newdesig	ADA_REFUSED	refuses: "NEW needs a POINTER value" for the self-referential q^.next (bytecode side is the subject)
#  arrkind is realarr's category, three element types wider: the Ada side
#  knows only O2c_Int_Arr and O2c_Bool_Arr as anonymous-array bases, so an
#  ARRAY OF SET / LONGREAL / LONGINT (like realarr's REAL) is emitted as an
#  array of Boolean and GNAT rejects it.  The bytecode side - the fixture's
#  subject - holds all three by value.
arrkind	ADA_BROKEN	emits Ada that will not compile: anonymous arrays of SET/LONGREAL/LONGINT map to O2c_Bool_Arr (realarr's category)
#  filesintr is the one fixture that is deliberately bytecode-only.  Its module
#  is NAMED Files, because that is what makes the file intrinsics reachable at
#  all - and the Ada path then emits calls to O2c_FDel/O2c_FStat/... whose BODIES
#  are emitted only into the builtin Files module, never into a user module that
#  merely carries the name.  So the Ada output references helpers it does not
#  define.  The fixture's subject is the four natives, which the VM side verifies
#  by effect (the byte read back is the byte written); there is nothing here for
#  the Ada side to corroborate except this limitation.
filesintr	ADA_BROKEN	emits Ada that will not compile: a user module named Files gets the intrinsics without the helpers the builtin's own body carries
#  usercall imports a USER library, and the Ada host front end takes no library
#  argument at all (o2c_ada_host passes N_Libs => 0), so the Ada side refuses
#  the import itself (M19) - the fixture's subject is the three imported CALL
#  sites, which the VM side compiles, runs and checks by output.
usercall	ADA_REFUSED	takes no library argument on the Ada side (N_Libs => 0), so the Ada text backend refuses the import of a user module
#  ptrfun and qrecvar are the same shape as usercall - each imports its own
#  .lib.ob2 library - so the Ada side refuses the import for the same reason.
#  ptrfun's subject is a POINTER-valued function across a module boundary;
#  qrecvar's is a whole assignment to and from an exported RECORD VARIABLE.
#  Both are VM-side subjects, checked by output.
ptrfun	ADA_REFUSED	takes no library argument on the Ada side (N_Libs => 0), so the Ada text backend refuses the import of a user module
qrecvar	ADA_REFUSED	takes no library argument on the Ada side (N_Libs => 0), so the Ada text backend refuses the import of a user module
#  modinit is the same shape again - it imports its own .lib.ob2 library, and
#  its subject is VM-side: a library's module body must be CALLED before the
#  main body's statements, and must RETURN rather than fall through.
modinit	ADA_REFUSED	takes no library argument on the Ada side (N_Libs => 0), so the Ada text backend refuses the import of a user module
#  recactual passes a record to a procedure and writes through it - the fixture
#  for 3cj, and its subject is the VM side (the callee has to resolve a record
#  formal's own slot).  The Ada side emits Ada that will not build: "w"
#  conflicts with a declaration, the same name-collision family as gcscalar,
#  recmix and recreal, and the Ada backend is being retired.
recactual	ADA_BROKEN	emits Ada that will not compile: a variable name collides with a declaration
withguard	GOLDEN_SUSPECT	the Ada side does not implement WITH's skip; the VM and the golden DO, and Oberon's WITH skips, so the Ada side is the odd one out
EOB

for name in $(fixtures); do
   src="$ROOT/tests/bc/$name.ob2"
   gold="$ROOT/tests/bc/$name.out"
   d="$WORK/$name"; mkdir -p "$d"
   mod="$(module_of "$src")"
   if [ -z "$mod" ]; then
      bad "$name: no 'module' line to take the unit name from"
      continue
   fi

   #  ---- the VM side, exactly as run_bc builds and runs it ---------------
   LIB=()
   if [ -f "$ROOT/tests/bc/$name.lib.ob2" ]; then
      LIB=("$ROOT/tests/bc/$name.lib.ob2")
   fi
   if ! timeout 120 "$BC_HOST" "$src" "$d/$name.obc" \
        ${LIB[@]+"${LIB[@]}"} >"$d/vm.compile" 2>&1; then
      bad "$name: the bytecode backend no longer compiles it"
      continue
   fi
   if ! timeout 60 "$VM" "$d/$name.obc" >"$d/vm.out" 2>"$d/vm.err"; then
      bad "$name: the VM failed to run it"
      continue
   fi

   #  ---- the Ada side: emit, build natively, run -------------------------
   if ! timeout 120 "$ADA_HOST" "$src" >"$d/ada.txt" 2>"$d/ada.log"; then
      ada_refused=$((ada_refused + 1))
      printf '%s\tADA_REFUSED\n' "$name" >> "$WORK/seen.txt"
      printf '%-14s ada REFUSED: %s\n' "$name" "$(tail -1 "$d/ada.log")" >> "$WORK/report.txt"
      continue
   fi
   if ! split_units "$d/ada.txt" "$d"; then
      ada_broken=$((ada_broken + 1))
      printf '%s\tADA_BROKEN\n' "$name" >> "$WORK/seen.txt"
      printf '%-14s ada CAPTURE TORN (no units)\n' "$name" >> "$WORK/report.txt"
      continue
   fi

   #  One gpr per fixture: the emitted units plus the host console shim.
   cat > "$d/diff.gpr" <<GPR
project Diff is
   for Source_Dirs use ("$d", "$ROOT/tests/ada_host");
   for Object_Dir use "obj";
   for Exec_Dir use "bin";
   for Main use ("$mod.adb");
   for Create_Missing_Dirs use "True";
   package Compiler is
      for Default_Switches ("Ada") use ("-gnaty0");
   end Compiler;
end Diff;
GPR
   if ! PATH="$GNAT_BIN:$GPR_BIN:$PATH" timeout 300 "$GPRBUILD" -q -p -P "$d/diff.gpr" \
        >"$d/ada.build" 2>&1; then
      ada_broken=$((ada_broken + 1))
      printf '%s\tADA_BROKEN\n' "$name" >> "$WORK/seen.txt"
      printf '%-14s ada WILL NOT BUILD: %s\n' "$name" \
         "$(grep -m1 -E 'error|not a source' "$d/ada.build" | cut -c1-110)" \
         >> "$WORK/report.txt"
      continue
   fi
   if ! timeout 60 "$d/bin/$mod" >"$d/ada.out" 2>"$d/ada.run"; then
      ada_broken=$((ada_broken + 1))
      printf '%s\tADA_BROKEN\n' "$name" >> "$WORK/seen.txt"
      printf '%-14s ada RAISED at run time: %s\n' "$name" \
         "$(tail -1 "$d/ada.run")" >> "$WORK/report.txt"
      continue
   fi

   #  ---- classify --------------------------------------------------------
   #  Every fixture that gets this far is recorded as CORROBORATED or as one of
   #  the three DISAGREEMENTS; the Ada-side refusals and build failures above
   #  are recorded where they happen.  seen.txt is the record the tail checks
   #  the recorded list against.
   a_eq_g=no; v_eq_g=no; a_eq_v=no
   cmp -s "$d/ada.out" "$gold" && a_eq_g=yes
   cmp -s "$d/vm.out"  "$gold" && v_eq_g=yes
   cmp -s "$d/ada.out" "$d/vm.out" && a_eq_v=yes

   if [ "$a_eq_g" = yes ] && [ "$v_eq_g" = yes ]; then
      agree=$((agree + 1))
      printf '%s\tCORROBORATED\n' "$name" >> "$WORK/seen.txt"
   elif [ "$a_eq_g" = yes ]; then
      vm_wrong=$((vm_wrong + 1))
      printf '%s\tVM_WRONG\n' "$name" >> "$WORK/seen.txt"
      printf '%-14s VM WRONG: the Ada side agrees with the golden, the VM does not\n' \
         "$name" >> "$WORK/report.txt"
   elif [ "$v_eq_g" = yes ]; then
      golden_suspect=$((golden_suspect + 1))
      printf '%s\tGOLDEN_SUSPECT\n' "$name" >> "$WORK/seen.txt"
      printf '%-14s GOLDEN SUSPECT: the VM agrees with the golden, the Ada side does not%s\n' \
         "$name" "$([ "$a_eq_v" = yes ] && echo ' - and the Ada side differs from the VM too, so exactly one of the three is wrong' || echo ' - and the Ada side differs from the VM as well, so all three disagree')" \
         >> "$WORK/report.txt"
   else
      split=$((split + 1))
      printf '%s\tALL_DIFFER\n' "$name" >> "$WORK/seen.txt"
      printf '%-14s ALL THREE DIFFER: %s\n' "$name" \
         "$([ "$a_eq_v" = yes ] && echo 'ada and vm agree with each other; the golden is the odd one out' || echo 'ada and vm differ from each other too')" \
         >> "$WORK/report.txt"
   fi
done

cat "$WORK/report.txt"
note
note "corroborated (ada and vm agree with the golden): $agree"
note "VM WRONG                          : $vm_wrong"
note "golden suspect                    : $golden_suspect"
note "all three differ                  : $split"
note "ada refused (its own gap)         : $ada_refused"
note "ada could not build or run        : $ada_broken"
note

#  ---- every outcome must be CORROBORATED or a recorded Ada-side limit -----
#  This is what makes it a gate.  Without it the check reports and exits 0 no
#  matter what it found, which is exactly how the coverage check's first
#  version said PASS while every Ada build was failing.
while IFS=$'\t' read -r nm cls; do
   [ -z "$nm" ] && continue
   rec="$(awk -F'\t' -v n="$nm" '$1==n {print $2}' "$WORK/recorded.txt")"
   if [ "$cls" = CORROBORATED ]; then
      if [ -n "$rec" ]; then
         bad "$nm is corroborated now, but is still recorded as $rec - remove it"
      fi
   elif [ "$cls" = VM_WRONG ]; then
      bad "$nm: THE VM IS WRONG - the Ada side agrees with the golden and the VM does not"
   elif [ -z "$rec" ]; then
      bad "$nm: $cls, and it is not a recorded Ada-side limit - look at it"
   elif [ "$rec" != "$cls" ]; then
      bad "$nm: is $cls now, but is recorded as $rec - the list needs updating"
   fi
done < "$WORK/seen.txt"

while IFS=$'\t' read -r nm cls rest; do
   #  The recorded list is a heredoc with commentary in it, so a '#' line is
   #  prose, not an entry.  Without this the comments are read as fixtures
   #  named "# CASE is the cause ..." and every one of them is reported as a
   #  stale entry - discovered when the list gained its first comment.
   case "$nm" in '' | '#'*) continue ;; esac
   grep -q "^$nm	" "$WORK/seen.txt" || \
      bad "$nm is recorded as $cls but no longer behaves that way - remove the entry"
done < "$WORK/recorded.txt"

note
if [ "$fails" -eq 0 ]; then
   note "PASS ($agree fixtures corroborated by both backends; every other outcome"
   note "      is a recorded, reasoned Ada-side limit)"
   exit 0
fi
note "FAIL: $fails"
exit 1
