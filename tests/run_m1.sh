#!/bin/sh
# o2c M1 regression: the full dogfood pipeline.
#
#   1. build o2c.elf (o2c runs under Aegir)
#   2. boot a test-mode initrd staging Tests/O2c; o2c reads the demo
#      module sources from the initrd (Tests/O2cLib/*.ob2), compiles
#      them as separate modules and prints each generated Ada unit
#      between markers; rebuild them all on the host
#   3. boot again with O2C_BYTECODE=1: o2c compiles hello.ob2 TO
#      BYTECODE in the guest and runs it in its embedded VM; assert
#      the full demo output, including the cross-module tail
#
# Requires AEGIR_ROOT (the aegir checkout; no default).
set -eu

: "${AEGIR_ROOT:?AEGIR_ROOT must point at the aegir checkout}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK="${TMPDIR:-/tmp}/o2c-m1"
QEMU_LOG="$WORK/boot.log"
RUNTIME_LOG="$WORK/boot_runtime.log"
#  Boot windows in seconds, per boot.  Boot 1 (the Ada capture) stays at the
#  original 280 and does NOT request the bytecode hello pass: the aegir
#  Makefile stages HelloBc.mrk only for the bytecode boot, so in boot 1 o2c
#  finds no marker and skips the pass whose 94 console lines would tear the
#  capture.  Boot 2 requests it (O2C_BYTECODE=1: the marker, the VM and its
#  manifest entry) and therefore carries three full compiler passes - hence
#  the wider window - and its log is the one the bytecode assertions read.
RUN_MIN=${RUN_MIN:-280}
RUN_MIN_BC=${RUN_MIN_BC:-460}

rm -rf "$WORK"; mkdir -p "$WORK"

cleanup() {
   local rc=$?
   pkill -f 'qemu-system-riscv6[4]' 2>/dev/null || true
   #  The work directory (and with it both boot logs) is removed on exit, so
   #  a failing run leaves nothing to diagnose.  Keep the last boot log and
   #  the filtered runtime log under /tmp instead.
   if [ -s "$QEMU_LOG" ]; then
      cp -f "$QEMU_LOG" /tmp/run_m1_boot.log 2>/dev/null || true
   fi
   if [ -s "$RUNTIME_LOG" ]; then
      cp -f "$RUNTIME_LOG" /tmp/run_m1_runtime.log 2>/dev/null || true
   fi
   return $rc
}
trap cleanup EXIT INT TERM

boot_once() {  # $1 = extra make vars, $2 = marker
   rm -f "$QEMU_LOG"
   ( cd "$AEGIR_ROOT" && make run INITRD_MODE=min \
        O2C_ROOT="$ROOT" $1 QEMU_ARGS='-nographic -display none' \
        >"$QEMU_LOG" 2>&1 ) &
   local mp=$!
   local waited=0
   local window="${3:-$RUN_MIN}"
   while [ "$waited" -lt "$window" ]; do
      sleep 5; waited=$((waited+5))
      grep -aq -- "$2" "$QEMU_LOG" && return 0
      kill -0 "$mp" 2>/dev/null || break
   done
   echo "run_m1: marker '$2' not seen in $window s (tail below)" >&2
   tail -5 "$QEMU_LOG" >&2 || true
   return 1
}

echo "run_m1: building o2c.elf"
#  build the Ada backend and the Aegir VM.  o2c embeds the VM, so the guest
#  run needs no separate VM program staged any more (see o2c's
#  crate/o2c.gpr); vm-aegir is built to keep that target honest.  The build
#  status is checked: a silent failure here used to surface much later as an
#  inexplicable boot assertion.
if ! make -C "$ROOT" build vm-aegir AEGIR_ROOT="$AEGIR_ROOT" >/dev/null; then
   echo "run_m1: build failed" >&2
   make -C "$ROOT" build vm-aegir AEGIR_ROOT="$AEGIR_ROOT" 2>&1 | tail -15 >&2
   exit 1
fi

echo "run_m1: boot 1/2 - o2c compiles the demo modules (retry on torn capture)"
ATT=0
while [ "$ATT" -lt 6 ]; do
   ATT=$((ATT+1))
   echo "run_m1:   attempt $ATT"
   boot_once "" '--- ada end ---'
   python3 - "$QEMU_LOG" "$WORK" <<'PY'
import sys
log, work = sys.argv[1], sys.argv[2]
txt = open(log, errors="replace").read()
buf = {}
cur = None
for line in txt.splitlines():
    if line.startswith("--- unit ") and line.endswith(" ---"):
        cur = line[len("--- unit "):-len(" ---")]
        buf.setdefault(cur, [])
    elif line == "--- unit end ---":
        cur = None
    elif line.startswith("O2C|") and cur is not None:
        buf[cur].append(line[4:])
for name, lines in buf.items():
    open(work + "/" + name, "w").write("\n".join(lines) + "\n")
PY
   if [ ! -s "$WORK/hello.adb" ] || [ ! -s "$WORK/math.ads" ] \
      || [ ! -s "$WORK/math.adb" ] \
      || ! grep -q 'procedure Hello' "$WORK/hello.adb" \
      || ! grep -q 'package Math is' "$WORK/math.ads"; then
      echo "run_m1: capture torn (units missing/incomplete); retrying" >&2
      continue
   fi
   cp "$ROOT/tests/hello.gpr" "$WORK/"
   if ( cd "$AEGIR_ROOT/userspace/echo" && alr exec -- gprbuild -q -p \
        -P "$WORK/hello.gpr" -aP "$AEGIR_ROOT/userspace/rts" \
        -XAEGIR_ROOT="$AEGIR_ROOT" >/dev/null ); then
      break
   else
      echo "run_m1: host build of emitted Ada failed (torn capture); retrying" >&2
   fi
done
if [ "$ATT" -ge 6 ]; then
   echo "run_m1: emitted-Ada capture/build failed after 6 attempts" >&2
   exit 1
fi

echo "run_m1: boot 2/2 - o2c compiles hello.ob2 TO BYTECODE in the guest"
echo "  and runs it in the embedded VM; assert the demo output incl. shared"
echo "  O2c_Types exports (406) and the Files module reading the staged"
echo "  Tests/O2cLib/Sample.txt (M40)"
#  No O2C_HELLO_ELF: the Ada-compiled demo used to run here as program 41,
#  but it does the same BD0: delete/create/rename sequence the bytecode run
#  does, and two concurrent instances race on those files.  The bytecode
#  run prints the same 94 lines, so every assertion below is unchanged -
#  only the producer changed.  Boot 1 still builds the emitted Ada on the
#  host, which is the Ada backend's remaining gate.
#  The boot marker is the run's completion line, not '406': a bare number
#  also appears inside the O2C| source capture, and matching it there would
#  return before the run even produced it.
boot_once "O2C_BYTECODE=1" 'o2c bytecode: hello vm ' "$RUN_MIN_BC"

#  o2c's own order is: the VmGreet pass and its publish line, THEN the hello
#  bytecode pass, whose in-guest run prints every demo marker this script
#  asserts.  boot_once returns on '406', which lands in the MIDDLE of that
#  run - and the publish line is already behind us - so before reading the
#  log, wait for the run's own completion line.  It comes after the demo's
#  last marker; anything earlier would let the assertions read a log the
#  demo was still writing.
for _ in $(seq 1 36); do
   grep -aq 'o2c bytecode: hello vm ' "$QEMU_LOG" && break
   sleep 5
done
#  The boot-1 source capture also contains every string/number literal the
#  demo uses, so the demo assertions below must look at the runtime console
#  only - never at the O2C| capture lines.
grep -av '^O2C|' "$QEMU_LOG" > "$RUNTIME_LOG" || true

#  The '406' line was the boot marker while the demo was a separate program;
#  with the marker moved to the run's completion line it needs its own
#  assertion.  Anchored: '406' is also a substring of the m8406 marker.
if ! grep -aq '^406$' "$RUNTIME_LOG"; then
   echo "run_m1: the demo's shared O2c_Types export line (406) not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi

#  Temporary (M53): the demo's BD0 sequence is bracketed with m8401..m8407 so
#  a stall names the op it stalled in; assert the whole sequence for now.
if ! grep -aq 'm8407' "$RUNTIME_LOG"; then
   echo "run_m1: the demo's BD0 sequence did not complete (last marker below)" >&2
   grep -ao 'm84[0-9][0-9]' "$RUNTIME_LOG" | tail -1 >&2
   exit 1
fi
if ! grep -aq 'O2c files demo ok' "$RUNTIME_LOG"; then
   echo "run_m1: Files read demo output not seen in boot 2 (tail below)" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq 'O2cW!' "$RUNTIME_LOG"; then
   echo "run_m1: Files write demo (BD0: roundtrip) output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq 'res-ok' "$RUNTIME_LOG"; then
   echo "run_m1: Files res/Close/Rename demo output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq 'in-eof' "$RUNTIME_LOG"; then
   echo "run_m1: In module demo output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq '2.50000E+00' "$RUNTIME_LOG" || ! grep -aq 'term-ok' "$RUNTIME_LOG"; then
   echo "run_m1: Reals/Term demo output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq '8.000000' "$RUNTIME_LOG" || ! grep -aq '3.141593' "$RUNTIME_LOG"; then
   echo "run_m1: LONGREAL/MathL demo output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq '8000' "$RUNTIME_LOG" || ! grep -aq '8001' "$RUNTIME_LOG" \
   || ! grep -aq '8002' "$RUNTIME_LOG" || ! grep -aq '8003' "$RUNTIME_LOG"; then
   echo "run_m1: Input module demo output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq '8100' "$RUNTIME_LOG" || ! grep -aq '8103' "$RUNTIME_LOG" \
   || ! grep -aq '8105' "$RUNTIME_LOG"; then
   echo "run_m1: XYplane module demo output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq '8210' "$RUNTIME_LOG" \
   || ! grep -aqE '^(8211|8212)$' "$RUNTIME_LOG" \
   || ! grep -aq 'err-ok' "$RUNTIME_LOG"; then
   echo "run_m1: Args/Err demo output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq 'hello-env' "$RUNTIME_LOG" || ! grep -aq '8300' "$RUNTIME_LOG"; then
   echo "run_m1: Env demo output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi
if ! grep -aq '8310' "$RUNTIME_LOG" || ! grep -aq '8315' "$RUNTIME_LOG" \
   || ! grep -aq '8320' "$RUNTIME_LOG" || ! grep -aq -- '-123' "$RUNTIME_LOG"; then
   echo "run_m1: Convert demo output not seen" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi

#  M53: the VM ran an image inside the guest.  The fixture's output line is
#  unique on purpose, so it cannot be confused with the Ada backend's own
#  markers - seeing it proves the Aegir build of the VM loaded, verified and
#  executed a .obc image under Aegir.
#  Both tokens are written by a *single* console write (a Put_Line), which
#  matters because o2c and the demo run concurrently: 'vm elf ok ' and '55'
#  come from separate Out.String/Out.Int calls, so a racing writer can land
#  between them and split that line.  Asserting the single-write token, plus
#  o2c's own status line, is the fragment-tolerant form (see AGENTS.md on
#  merged console lines).
#  Both halves of the in-guest bytecode story: o2c compiles a program and
#  executes the image in-process, writes it to BD0:, and the standalone VM
#  (program 42) runs that copy.  The sequencing that makes it deterministic
#  is the launcher's: the aegir Manifest carries `await BD0:README.TXT`
#  between System/Bfs and the programs that need the volume, so init holds
#  the manifest until the mount is real - hence asserting that the timeout
#  line is ABSENT as well (its presence means the sequencing failed).
if grep -aq 'init: await' "$RUNTIME_LOG"; then
   echo "run_m1: the launcher's await timed out (sequencing failed)" >&2
   grep -a 'init: await' "$RUNTIME_LOG" >&2
   exit 1
fi
#  The standalone half WORKS (a boot shows o2c build the image at line 770 and
#  program 42 running it at 774), but it is not asserted here yet: running the
#  bytecode pass first puts o2c's output and the VM's success inside boot 1's
#  capture window, and the extra concurrent console traffic tears the capture
#  more often than the six retries tolerate.  That is harness fragility, and a
#  flaky assertion is worse than none - so boot 1 should stop carrying this
#  work (see the note in the o2c README) before the assertion comes back.
#  Three producers, three tokens: the standalone VM ran the published slice
#  ('vm elf ok'), o2c ran the slice in-process ('vm ok'), and o2c compiled
#  hello.ob2 to bytecode and ran THAT in-process ('hello vm ok') - the full
#  demo, compiled and executed inside the guest.
if ! grep -aq 'vm elf ok' "$RUNTIME_LOG" \
   || ! grep -aq 'o2c bytecode: vm ok' "$RUNTIME_LOG" \
   || ! grep -aq 'o2c bytecode: hello vm ok' "$RUNTIME_LOG"; then
   echo "run_m1: the guest did not compile and run bytecode" >&2
   tail -30 "$RUNTIME_LOG" >&2
   exit 1
fi

echo "run_m1: PASS"
