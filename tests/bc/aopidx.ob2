module AopIdx;
(*  An indexed READ of an ARRAY OF parameter from a NESTED procedure.  The array's
    address lives in the ENCLOSING frame, so the base comes through the static link.
    This site used to convert Local_Slot's -1 straight to Natural, so the compiler
    died on a range check rather than working or refusing - and only the nested case
    reached it, which is why every existing fixture was silent.  Found by the
    fixture-first sweep for Reals, on its first run. *)
import Out;
var buf: array 8 of char; g: integer;
procedure Fill (var s: array of char);
  procedure One;
  begin
    g := ORD (s[0])
  end One;
begin
  s[0] := CHR(65);
  One
end Fill;
begin
  Fill (buf); Out.Int (g, 0); Out.Ln
end AopIdx.
