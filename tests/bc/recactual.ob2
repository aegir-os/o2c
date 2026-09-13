module RecActual;
(*  A record can now be passed to a procedure, and written through it.  This is
    the fixture the gap of 3ci could not be: the CALLEE's own designator chain
    resolved a record formal's name as a GLOBAL, so the store landed in a fresh
    zeroed run and the caller's record was untouched - first as a loud verifier
    rejection, then, once the caller pushed an address, as a SILENT wrong answer
    (1 instead of 7).  Bc_Base loads a by-reference formal's own slot now, which
    is the rule the ARRAY OF path always had. *)
import Out;
type W = record pos: integer; tag: integer end;
var w: W;
procedure Set(var x: W);
begin
  x.pos := 7
end Set;
procedure Show(var x: W);
begin
  Out.Int(x.pos, 0); Out.Ln
end Show;
begin
  w.pos := 1; w.tag := 2;
  Set(w);
  Show(w);
  Out.Int(w.tag, 0); Out.Ln     (* 2 - the field the callee never touched *)
end RecActual.
