module StrLitCmp;
import Out;
const H = "hi";
var s: array 4 of char;
begin
  s := "hi";
  if s = "hi" then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if "hi" = s then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if s = H then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if s = "ho" then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if s < "hj" then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if "hz" > s then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if s >= "hi" then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if s >= "hz" then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln
end StrLitCmp.
