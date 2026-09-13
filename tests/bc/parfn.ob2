module Parfn;
(*  A parameterless FUNCTION, called without parentheses.  It is the one call
    shape with no fixture anywhere, because the `(): T` spelling is refused by
    the parser - and the expression path emitted NOTHING for it, so `n := P`
    stored whatever happened to be on the operand stack (3ca).  The Oakwood
    library bodies are full of this shape, which is how it was found. *)
import Out;
var n: integer;
procedure P: integer;
begin
  return 7
end P;
begin
  n := P;
  Out.Int(n, 0); Out.Ln;
  Out.Int(P + 1, 0); Out.Ln
end Parfn.
