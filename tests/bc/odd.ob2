module Odd;
import Out;
var i: integer;
    n: longint;
begin
  i := 3;
  if ODD(i) then Out.Int(1, 0) else Out.Int(0, 0) end; Out.Ln;
  i := 4;
  if ODD(i) then Out.Int(1, 0) else Out.Int(0, 0) end; Out.Ln;
  i := 0;
  if ODD(i) then Out.Int(1, 0) else Out.Int(0, 0) end; Out.Ln;
  i := -3;
  if ODD(i) then Out.Int(1, 0) else Out.Int(0, 0) end; Out.Ln;
  i := -4;
  if ODD(i) then Out.Int(1, 0) else Out.Int(0, 0) end; Out.Ln;
  n := 4000001;
  if ODD(n) then Out.Int(1, 0) else Out.Int(0, 0) end; Out.Ln
end Odd.
