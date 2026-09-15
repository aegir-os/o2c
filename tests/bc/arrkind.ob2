module ArrKind;
import Out;
type A3 = array 3 of integer;
type R = record v: real; a: A3 end;
var s: array 3 of set;
    lr: array 2 of longreal;
    n: array 2 of longint;
    r: R;
begin
  s[1] := {2, 4};
  if 2 in s[1] then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  if 3 in s[1] then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  lr[1] := 1.5;
  if lr[1] > 1 then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  n[1] := 3000000000;
  if n[1] = 3000000000 then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  r.v := 2.5;
  r.a[2] := 7;
  Out.Int(r.a[2], 0);
  Out.Ln;
  if r.v > 2 then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln
end ArrKind.
