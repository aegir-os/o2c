module ConvInt;
(*  Convert.ToInt with a STRING LITERAL first argument.  The arm used to demand a
    declared ARRAY OF CHAR variable and refuse `"8311"`, because it only had an
    Addr_Global to offer.  A literal needs no global: bytecode pushes one as an
    address through Push_Str, the same mechanism Out.String ("x") uses.  Values
    are hello.ob2's own: 8311 converts with status 0, "nope" fails with -1. *)
import Out, Convert;
var n, res: integer;
begin
  Convert.ToInt ("8311", n, res);
  if (res = 0) & (n = 8311) then Out.Int (8310, 0) else Out.Int (8319, 0) end;
  Out.Ln;
  Convert.ToInt ("nope", n, res);
  if res = -1 then Out.Int (8315, 0) else Out.Int (8316, 0) end;
  Out.Ln
end ConvInt.
