module LRealP;
(*  Out.LongReal prints SIX decimals (O2c_Put_LReal's shape); Out.Real
    prints three.  The bytecode side used to share native 3 for both, so
    the demo's MathL lines read 8.000 where the Ada backend prints
    8.000000 - visible only when the guest ran the demo both ways.
    Native 48 (o2c_putlreal) is the LONGREAL print; native 3 stays REAL. *)
import Out, MathL;
var lre: longreal; r: real;
begin
  lre := MathL.ln(MathL.e);
  Out.LongReal(lre, 0); Out.Ln;
  Out.LongReal(MathL.power(2.0D0, 3.0D0), 0); Out.Ln;
  Out.LongReal(MathL.pi, 0); Out.Ln;
  r := 2.5;
  Out.Real(r, 0); Out.Ln;
  lre := 2.5D0;
  lre := lre * 2.0D0 + 0.5D0;
  Out.LongReal(lre, 0); Out.Ln
end LRealP.
