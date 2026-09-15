module Setl;
import Out;
var s: set; b: boolean;
    i: integer;
begin
  s := {1..5};
  i := 3;
  b := (i in s) & ~(6 in s);
  if b then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  s := {1, 3};
  b := 3 in s;
  if b then Out.Int(42, 0) else Out.Int(0, 0) end;
  Out.Ln;
  b := 2 in s;
  if b then Out.Int(0, 0) else Out.Int(7, 0) end;
  Out.Ln
end Setl.
