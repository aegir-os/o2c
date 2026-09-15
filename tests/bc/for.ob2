module Forl;
import Out;
var i: integer;
procedure P;
var k: integer;
begin
  for k := 1 to 3 do Out.Int(k, 0) end;
  Out.Ln
end P;
begin
  P;
  for i := 1 to 3 do
    Out.Int(i, 0); Out.Ln
  end;
  Out.Ln
end Forl.
