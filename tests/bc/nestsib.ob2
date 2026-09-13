module NestSib;
(*  A NESTED procedure calling its SIBLING: Put and Ten are both nested in Outer, so
    a call from Ten to Put must pass OUTER's frame as the static link - not Ten's
    own.  It used to pass Ten's, so Put wrote its update through the wrong frame and
    Outer's variable never changed: a silent 32 where 42 is right.  The same shape
    is Reals' Digit calling Put, which is what crashed the VM. *)
import Out;
var g: integer;
procedure Outer;
var n: integer;
  procedure Put (k: integer);
  begin
    n := n + k
  end Put;
  procedure Ten;
  begin
    Put (10)
  end Ten;
begin
  n := 32;
  Ten;
  g := n
end Outer;
begin
  Outer; Out.Int (g, 0); Out.Ln
end NestSib.
