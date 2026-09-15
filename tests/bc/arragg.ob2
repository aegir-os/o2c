module ArrAgg;
(*  A numeric fixed-array aggregate { e1, e2, .. }: the same silence the
    record aggregate had, found by the same sweep (`a := {1, 2, 3}`
    printed 000).  Each element stores [base, index, value] exactly as an
    indexed assignment does - 8-byte slots for INTEGER, bytes for CHAR. *)
import Out;
type A3 = array 3 of integer;
type C2 = array 2 of char;
var a: A3;
    s: C2;
begin
  a := {1, 2, 3};
  if a[0] + a[1] + a[2] = 6 then Out.String ("int-ok") else Out.String ("int-bad") end;
  Out.Ln;
  s := {"h", "i"};
  if (s[0] = "h") & (s[1] = "i") then Out.String ("char-ok") else Out.String ("char-bad") end;
  Out.Ln
end ArrAgg.
