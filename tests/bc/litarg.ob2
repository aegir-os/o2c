module LitArg;
(*  A STRING LITERAL as an ARRAY OF CHAR actual - both halves of it.  The
    caller used to push the literal's pool WORD (an offset into the CONST
    payload) and not the length an ARRAY OF formal carries, so the callee's
    length slot held whatever the next actual left there (the VM rejected the
    image: "depth -1", 3ce) - and once that was fixed, the callee dereferenced
    the OFFSET and the VM walked off into memory as a SIGSEGV inside the
    interpreter (3cg).  A literal actual must therefore be resolved to its
    characters' ADDRESS and have its length pushed with it; a variable actual
    always passed both, which is why no fixture had ever caught either half. *)
import Out;
var t: array 8 of char;
procedure Put(a: array of char): integer;
begin
  return len(a)
end Put;
procedure Get(a: array of char): char;
begin
  return a[0]
end Get;
begin
  t := "abc";
  Out.Int(Put("xyz"), 0); Out.Ln;      (* 3 - the literal's own length *)
  Out.Int(Put(t), 0); Out.Ln;          (* 8 - the array's                *)
  Out.Char(Get("Qrs")); Out.Ln;        (* Q - the literal DEREFERENCED   *)
  Out.Char(Get(t)); Out.Ln             (* a                              *)
end LitArg.
