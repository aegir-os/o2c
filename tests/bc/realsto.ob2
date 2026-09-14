module RealsTo;
(*  Reals.ConvertTo - the RParse direction.  The builtin RParse branch set
    an Ada-only R.Text and emitted NO opcode in bytecode mode, so the
    enclosing store took the string's ADDRESS as the REAL and every
    ConvertTo answered 0 (hello.ob2's first wrong value).  Id 47
    (o2c_strtoreal) parses the string: a plain value, a negative, and an
    exponent. *)
import Out, Reals;
var r: real;
begin
  Reals.ConvertTo (r, "3.25");
  Out.Real (r, 3);
  Out.Ln;
  Reals.ConvertTo (r, "-1.5");
  Out.Real (r, 3);
  Out.Ln;
  Reals.ConvertTo (r, "2E3");
  Out.Real (r, 3);
  Out.Ln
end RealsTo.
