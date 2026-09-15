module LongLit;
(*  An integer literal above INTEGER'Last is LONGINT.  The parser types a
    digit literal INTEGER, and in bytecode mode Integer'Value raised on
    3000000000 - a refusal the Ada backend never had, because a
    universal_integer literal in its text takes the TARGET's range.  The
    same shape with SMALL literals is longint.ob2; this one is the range. *)
import Out;
var n: longint;
begin
  n := 3000000000;
  if n = 3000000000 then Out.String ("assign-ok") else Out.String ("assign-bad") end;
  Out.Ln;
  if n > 2147483647 then Out.String ("gt-ok") else Out.String ("gt-bad") end;
  Out.Ln;
  n := n + 1;
  if n = 3000000001 then Out.String ("add-ok") else Out.String ("add-bad") end;
  Out.Ln;
  n := 0 - n;
  if n < 0 then Out.String ("neg-ok") else Out.String ("neg-bad") end;
  Out.Ln
end LongLit.
