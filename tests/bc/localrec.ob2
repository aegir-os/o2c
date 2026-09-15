module LocalRec;
(*  A LOCAL record as a VAR record actual: the frame address goes where
    the global case puts a global address (recactual.ob2 covers that one).
    The callee's write must land in the CALLER's frame slot - 0 before,
    41 after, read back by the caller itself. *)
import Out;
type Rec = record a: integer end;
procedure Q(var r: Rec);
begin
  r.a := 41
end Q;
procedure W;
var x: Rec;
begin
  x.a := 0;
  Q(x);
  if x.a = 41 then Out.String ("write-ok") else Out.String ("write-bad") end;
  Out.Ln
end W;
begin
  W
end LocalRec.
