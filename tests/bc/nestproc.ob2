module NestProc;
(*  A NESTED procedure, closing over its enclosing procedure's local.

    Bump reads and writes Outer's `n`, which is not in Bump's own frame - so this
    needs the static link: the caller passes its frame address and the access goes
    through it.  Before the link exists, such a name fell back to a module global,
    which is a wrong answer rather than a refusal. *)
import Out;
var g: integer;
procedure Outer;
var n: integer;
  procedure Bump;
  begin
    n := n + 1
  end Bump;
begin
  n := 40;
  Bump;
  Bump;
  g := n
end Outer;
begin
  Outer;
  Out.Int (g, 0); Out.Ln
end NestProc.
