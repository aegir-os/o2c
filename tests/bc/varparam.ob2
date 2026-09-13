module VarParam;
(*  A VAR scalar parameter must reach its caller.

    The callee's slot holds the caller's ADDRESS and its store goes through it; the
    caller hands over where its variable lives, not its value.  Before this, the value
    was passed and the store wrote the callee's own slot - so the caller's variable
    silently never changed.  The global here is the common case; a frame local works
    too, which is what the chunked locals pool was for. *)
import Out;
var g: integer;
procedure Bump (var n: integer);
begin
  n := n + 1
end Bump;
procedure BumpTwice (var n: integer);
begin
  Bump (n); Bump (n)
end BumpTwice;
begin
  g := 40;
  Bump (g);
  BumpTwice (g);
  Out.Int (g, 0); Out.Ln
end VarParam.
