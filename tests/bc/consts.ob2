module Consts;
import Out;
const N = 2 * 3;
    XCh = "x";
    Yes = true;
var k: integer;
    c: char;
    b: boolean;
begin
  k := N;
  Out.Int(k, 0);
  Out.Ln;
  c := XCh;
  if c = "x" then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  b := Yes;
  if b then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln
end Consts.
