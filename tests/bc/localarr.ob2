module LocalArr;
(*  A LOCAL array as an ARRAY OF actual: the frame address and the static
    length go where the global case puts a global address - the same two
    slots the forwarding case already hands on.  The callee also WRITES
    through it, which proves the address is the caller's frame and not a
    copy: "hi" becomes "Ji" only if both names denote the same bytes. *)
import Out;
procedure Show(s: array of char);
begin
  Out.String(s)
end Show;
procedure Bump(var s: array of char);
begin
  s[0] := "J"
end Bump;
procedure W;
var a: array 4 of char;
begin
  a := "hi";
  Show(a);
  Bump(a);
  Show(a)
end W;
begin
  W;
  Out.Ln
end LocalArr.
