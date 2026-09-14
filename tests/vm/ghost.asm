#  A procedure nothing calls, and the body prints 42 without it.
#
#  This is the CONTROL for the verifier's per-procedure walk: a legal
#  uncalled procedure is not an error, so the image must run - while its
#  two byte-patched derivatives (run_vm.sh's ghostbad and ghoststack) must
#  be rejected at LOAD, because verification visits every procedure now,
#  called or not.  Before the walk became per-procedure, the body - emitted
#  last - was all that was verified, and both derivatives RAN.
MAXSTACK 8
GLOBALS 0
POOL forty 42
POOL zero 0

#  PROC name frame_slots nparams nresults
PROC ghost 0 0 0
  NOP
  RET_VOID

ENTRY main
PROC main 0 0 0
  LOAD_CONST forty
  LOAD_CONST zero          # Out.Int takes (value, width)
  CALL_NATIVE 0 2          # Out.Int (x, width)
  CALL_NATIVE 2 0          # Out.Ln
  HALT
