module StrLib;
(*  The builtin Strings module compiled from its OWN body rather than served by
    a VM native: Length, Pos and Cap all run, and hello.ob2's refusal now lands
    past the whole module, at Texts (3cg).  Three defects stood on that path and
    each is a fixture now: a parameterless function call emitted nothing (3cb),
    a string-literal actual passed a pool offset instead of an address (3cg),
    and a `var ARRAY OF` write emitted nothing at all (3cc). *)
import Out, Strings;
var s: array 16 of char; n: integer;
begin
  s := "hello world";
  Out.Int(Strings.Length(s), 0); Out.Ln;
  Out.Int(Strings.Pos("world", s), 0); Out.Ln;
  Out.Int(Strings.Pos("zzz", s), 0); Out.Ln;
  Strings.Cap(s);
  Out.String(s); Out.Ln
end StrLib.
