module TextsLib;
(*  The SECOND library compiled from its own body rather than served by natives.
    Texts' Write* family writes straight to Out in this subset, so the output is
    observable; Texts.Write's body also carries `t[0] := ch`, an indexed write
    into a LOCAL array, which nothing else in the corpus writes.  The two
    blockers on this path were 3ci/3cj (a record actual, which Texts.OpenWriter
    and every Write* call passes). *)
import Out, Texts;
var w: Texts.Writer;
begin
  Texts.OpenWriter(w);
  Texts.WriteString(w, "hi ");
  Texts.WriteInt(w, 42, 0);
  Texts.Write(w, "!");
  Texts.WriteLn(w);
  Texts.WriteReal(w, 1.5, 0);
  Texts.WriteLn(w)
end TextsLib.
