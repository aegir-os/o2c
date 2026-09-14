module ConvFFI;
(*  Two FFI emission bugs behind hello.ob2's last wrong values.  A
    module-global used as a FOR control variable is interned into the
    enclosing frame, but the ToInt arm resolved the same name by raw text
    and wrote the GLOBAL - the program read the frame slot and answered
    the loop's leftover.  And FromInt loaded its first argument with
    Bc_Load, so an EXPRESSION actual minted a zero global and the string
    came out "0".  Both arms now use the frame-aware Push_Var_Addr /
    Bc_Push_Arg, and their dead Parse_Actual pushes are dropped. *)
import Out, Convert;
var n, res, i: integer;
    s: array 16 of char;
begin
  for n := 4 to 5 do
    i := n
  end;
  Convert.ToInt ("8311", n, res);
  if (res = 0) & (n = 8311) then Out.Int (8310, 0) else Out.Int (8319, 0) end;
  Out.Ln;
  Convert.FromInt (0 - 123, s);
  Out.String (s);
  Out.Ln
end ConvFFI.
