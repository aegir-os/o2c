module QRecVar;
(*  A whole assignment to or from an exported RECORD VARIABLE (M20f) emitted
    no bytecode either - the qualified-name site had the same gap as the
    plain-name one.  30 + 25 = 55; 88 + 11 = 99. *)
import Out, QRecL;
var a: QRecL.Point;
begin
  a.x := 30;
  a.y := 25;
  QRecL.origin := a;
  Out.Int(QRecL.origin.x + QRecL.origin.y, 0);
  Out.Ln;
  QRecL.origin.x := 88;
  QRecL.origin.y := 11;
  a.x := 0;
  a.y := 0;
  a := QRecL.origin;
  Out.Int(a.x + a.y, 0);
  Out.Ln
end QRecVar.
