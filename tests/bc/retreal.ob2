module RetReal;
import Out;
var r: real;
    d: longreal;
procedure One: real;
begin
  return 1
end One;
procedure Two: longreal;
begin
  return 2
end Two;
procedure Half: real;
begin
  return 0.5
end Half;
procedure FromInt(n: integer): real;
begin
  return n
end FromInt;
begin
  r := One;
  Out.Real(r, 0);
  Out.Ln;
  d := Two;
  Out.LongReal(d, 0);
  Out.Ln;
  r := Half;
  Out.Real(r, 0);
  Out.Ln;
  r := FromInt(3);
  Out.Real(r, 0);
  Out.Ln
end RetReal.
