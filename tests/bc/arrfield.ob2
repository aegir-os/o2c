module ArrField;
(*  An ARRAY-VALUED FIELD used as a value - what `Out.String (p^.s)` and, in the Oakwood library,
    Files.Read/Write/WriteString/Close all need.

    Before 3dc this fell through to the pool-string native and died at run time with a constraint
    error, because the recognition looked the argument's TEXT up as a symbol and a field's Ada text
    is not one.  The field here is deliberately NOT at offset 0, so the address has to carry the
    field's own offset and not merely the object's base. *)
import Out;
type A8 = array 8 of char;
type Rec = record pad: integer; s: A8 end;
type Pt = pointer to Rec;
var p: Pt; i: integer;
begin
  new(p);
  p^.pad := 0;
  i := 0;
  while i < 8 do
    if i < 3 then p^.s[i] := CHR(65 + i) else p^.s[i] := CHR(0) end;
    i := i + 1
  end;
  Out.String (p^.s); Out.Ln
end ArrField.
