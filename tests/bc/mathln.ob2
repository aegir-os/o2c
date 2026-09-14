module MathLn;
(*  The Math transcendentals, which 3cr found the module's own body calling with
    nothing able to answer them.

    One native group covers both Math and MathL, and every argument reaches the
    image exactly once: Parse_Actual pushes it and the native path pushes NOTHING
    of its own - re-pushing through Bc_Push_Arg sent every literal twice (one
    copy leaked for the rest of the run) and Math.pi/Math.e as a minted-zero
    global.  The expected line is arithmetic, not a recording:
    ln 2 = 0.693, sin (pi/2) = 1.000, log (8, 2) = 3.000, arctan2 (1, 1) = 0.785. *)
import Out, Math;
begin
  Out.Real (Math.ln (2.0), 0); Out.Char (" ");
  Out.Real (Math.sin (Math.pi / 2.0), 0); Out.Char (" ");
  Out.Real (Math.log (8.0, 2.0), 0); Out.Char (" ");
  Out.Real (Math.arctan2 (1.0, 1.0), 0);
  Out.Ln
end MathLn.
