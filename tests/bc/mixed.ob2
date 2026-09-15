module Mixed;
import Out;
var r: real;
begin
  r := 2.0;
  Out.Real(r * 3, 0); Out.Ln;
  Out.Real(3 * r, 0); Out.Ln;
  Out.Real(r + 1, 0); Out.Ln;
  Out.Real(1 + r, 0); Out.Ln;
  Out.Real(r - 1, 0); Out.Ln;
  Out.Real(5 - r, 0); Out.Ln;
  Out.Real(r / 2, 0); Out.Ln;
  Out.Real(7 / r, 0); Out.Ln;
  Out.Real(r * 2.0, 0); Out.Ln
end Mixed.
