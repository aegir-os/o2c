module CmpSet;
import Out;
var a, b: set;
    p, q: boolean;
    r: real;
begin
  a := {1, 3}; b := {1, 2, 3};
  if a <= b then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if b <= a then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if b >= a then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if a >= b then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  p := true; q := false;
  if p = q then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if p # q then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  r := 2.5;
  if r > 2 then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if 4 <= r then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln
end CmpSet.
