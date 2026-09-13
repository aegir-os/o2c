module VarArr;
(*  Writes through a `var ARRAY OF` parameter - the fixture the corpus never
    had, because this statement built only the Ada text and emitted NOTHING, so
    the write disappeared silently (3cc).  Strings.Cap is exactly this shape,
    which is how it was found; `&` in the condition and CHAR arithmetic are
    along for the ride. *)
import Out;
var s: array 8 of char;
procedure Up(var a: array of char);
  var i: integer;
begin
  for i := 0 to len(a) - 1 do
    if (ORD(a[i]) >= 97) & (ORD(a[i]) <= 122) then
      a[i] := CHR(ORD(a[i]) - 32)
    end
  end
end Up;
begin
  s := "hello";
  Up(s);
  Out.String(s); Out.Ln
end VarArr.
