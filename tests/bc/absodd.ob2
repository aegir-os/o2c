module AbsOdd;
import Out;
var i: integer;
    n: longint;
    r: real;
begin
  i := -7;
  Out.Int(ABS(i), 0); Out.Ln;
  i := 9;
  Out.Int(ABS(i), 0); Out.Ln;
  i := 0;
  Out.Int(ABS(i), 0); Out.Ln;
  n := -4000000;
  if ABS(n) = 4000000 then Out.String("long-ok") else Out.String("long-bad") end;
  Out.Ln;
  r := -2.5;
  Out.Real(ABS(r), 0); Out.Ln
end AbsOdd.
