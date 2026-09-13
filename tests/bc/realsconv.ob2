module RealsConv;
(*  Reals, the first library module to be flipped since Files - and the one that
    found the sibling link.  Its Convert is the only procedure in the corpus with
    the shape that exposed it: a nested procedure CALLING ITS SIBLING (Digit calls
    Put), which needs the PARENT's frame as the static link, not the caller's own.
    Everything here is a consequence of that one line being wrong. *)
import Out, Reals;
var s: array 32 of char; r: real;
begin
  r := 1.0 / 3.0;
  Reals.Convert (r, s);
  Out.String (s); Out.Ln
end RealsConv.
