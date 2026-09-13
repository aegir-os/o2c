module LitArg;
(*  A STRING LITERAL as an ARRAY OF CHAR actual.  The caller pushed the
    literal's ADDRESS and NOT the length that an ARRAY OF formal carries, so the
    callee's length slot held whatever the next actual left there - and the VM's
    verifier rejected the whole image: "operand-stack depth violation ... depth
    -1" (3ce).  A variable actual always passed both, which is why no fixture
    had ever caught it. *)
import Out;
var t: array 8 of char;
procedure Put(a: array of char): integer;
begin
  return len(a)
end Put;
begin
  t := "abc";
  Out.Int(Put("xyz"), 0); Out.Ln;
  Out.Int(Put(t), 0); Out.Ln
end LitArg.
