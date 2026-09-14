module MathConst;
(*  A qualified CONST read (Math.e, Math.pi) emitted NOTHING in bytecode
    mode: in an expression the stack came up one short, and as a Math
    argument the re-push machinery loaded a minted-zero global instead -
    `Math.ln (Math.e)` raised a domain error.  The export now carries the
    literal's text and the read pushes the value: ln e = 1, sin (pi/2) = 1. *)
import Out, Math;
var r: real;
begin
  if Math.e > 2.7 then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln;
  r := Math.ln(Math.e);
  Out.Real(r, 0); Out.Ln;
  Out.Real(Math.sin(Math.pi / 2.0), 0); Out.Ln
end MathConst.
