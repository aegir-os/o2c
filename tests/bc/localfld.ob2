module LocalFld;
(*  A LOCAL record's fields: Bc_Base refused them because "there is no
    load-address-of-local op" - true when written, false since 3dk's
    LOAD_ADDR_L.  Write and read back BY VALUE: 41 stored through the
    frame address must read 41 back. *)
import Out;
type R = record a, b: integer end;
procedure W;
var x: R;
begin
  x.a := 40;
  x.b := 1;
  if x.a + x.b = 41 then Out.String ("fld-ok") else Out.String ("fld-bad") end;
  Out.Ln
end W;
begin
  W
end LocalFld.
