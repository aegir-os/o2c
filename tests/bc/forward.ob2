module Forward;
(*  An ARRAY OF formal is two slots (address, length) in its OWN frame, so a
    nested procedure that forwards it, reads it as a string, or hands it to
    an FFI primitive reaches both through the static-link chain. *)
import Out;
var arr: array 3 of integer;
procedure Sink(a: array of integer);
begin
  Out.Int(a[1], 0); Out.Ln
end Sink;
procedure Show(s: array of char);
begin
  Out.String(s); Out.Ln
end Show;
procedure Outer(a: array of integer; s: array of char);
  procedure Inner;
  begin
    Sink(a);
    Show(s);
    Out.String(s); Out.Ln
  end Inner;
begin
  Inner
end Outer;
begin
  arr[1] := 42;
  Outer(arr, "hi")
end Forward.
