module UserCall;
(*  The three imported call sites in one program: a statement call with
    arguments, a parameterless statement call, and a call in an EXPRESSION.
    7 then Bump is 8, and Add(0) reads the library's own state back out. *)
import Out, ULib;
begin
  ULib.Set(7);
  ULib.Bump;
  Out.Int(ULib.Add(0), 0);
  Out.Ln
end UserCall.
