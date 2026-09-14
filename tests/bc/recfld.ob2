module RecFld;
(*  A GLOBAL RECORD, assigned then field-read.  This is the shape that faults in
    hello.ob2: the emitted code does LOAD_G (the record's VALUE) where a field
    access needs its ADDRESS, so it reads the first word as a pointer and
    dereferences it.  7 + 35. *)
import Out;
type Pt = record x, y: integer end;
var p: Pt;
begin
  p.x := 7;
  p.y := 35;
  Out.Int (p.x + p.y, 0); Out.Ln
end RecFld.
