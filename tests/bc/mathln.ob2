module MathLn;
(*  The Math transcendentals, which 3cr found the module's own body calling with
    nothing able to answer them.

    One native group covers both Math and MathL, and every argument - including
    the module's e and pi - now reaches the image: a REAL constant is a pool entry
    (LOAD_CONST_R), which is what Const_Real had been unable to do since it was
    written.  The expected line is arithmetic, not a recording:
    ln 2 = 0.693, sin (pi/2) = 1.000, log (8, 2) = 3.000, arctan2 (1, 1) = 0.785.

    Math.pi and Math.e are NOT used here: as an ARGUMENT they double-count (the
    module's own emission pushes the value and the argument machinery expects to
    push it itself), which is 3dn's follow-up.  The literal is the same number. *)
import Out, Math;
begin
  Out.Real (Math.ln (2.0), 0); Out.Char (" ");
  Out.Real (Math.sin (1.5707963267948966), 0); Out.Char (" ");
  Out.Real (Math.log (8.0, 2.0), 0); Out.Char (" ");
  Out.Real (Math.arctan2 (1.0, 1.0), 0);
  Out.Ln
end MathLn.
