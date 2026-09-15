module QNames;
(*  A qualified type name - Lib.T - in every type-reference position.  A VAR
    of one had M20's branch; the formal, the POINTER TO target and the
    ARRAY OF element each refused "unknown type". *)
import Out, Texts;
type WP = pointer to Texts.Writer;
type WArr = array 2 of Texts.Writer;
var ws: WArr;
    p: WP;
    w: Texts.Writer;
procedure Put(var w: Texts.Writer; s: array of char);
begin
  Texts.OpenWriter(w);
  Texts.WriteString(w, s);
  Texts.WriteLn(w)
end Put;
begin
  new(p);
  Put(w, "one");
  Put(w, "two")
end QNames.
