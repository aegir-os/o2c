module WholeCopy;
(*  Whole-record and whole-array assignment emitted NO bytecode at all - the
    statement compiled, ran, and copied nothing, so b kept its zeroes.  The
    copy is per-slot (the spec's COPY_BYTES is unimplemented); 19 + 23 = 42
    on both lines. *)
import Out;
type P = record x, y: integer end;
var a, b: P;
    c, d: array 3 of integer;
begin
  a.x := 19; a.y := 23;
  b := a;
  Out.Int(b.x + b.y, 0); Out.Ln;
  c[0] := 19; c[1] := 23; c[2] := 0;
  d := c;
  Out.Int(d[0] + d[1], 0); Out.Ln
end WholeCopy.
