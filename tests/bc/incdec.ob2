module IncDec;
import Out;
var x: integer;
    n: longint;

procedure Bump(var v: integer);
begin
  INC(v, 10);
  DEC(v, 3)
end Bump;

begin
  x := 3;
  INC(x);
  Out.Int(x, 0); Out.Ln;
  INC(x, 5);
  Out.Int(x, 0); Out.Ln;
  DEC(x);
  Out.Int(x, 0); Out.Ln;
  DEC(x, 2);
  Out.Int(x, 0); Out.Ln;
  Bump(x);
  Out.Int(x, 0); Out.Ln;
  n := 10;
  INC(n);
  INC(n, 4);
  DEC(n, 5);
  if n = 10 then Out.String("long-ok") else Out.String("long-bad") end;
  Out.Ln
end IncDec.
