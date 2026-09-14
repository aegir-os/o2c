module EmptySet;
(*  The empty SET literal pushed NOTHING in bytecode mode - every element
    path pushed, the empty case had no elements - so `s := {}` left the
    by-ref store one operand short (Input.Mouse's `keys := {}` stored
    through a slot that was never a set).  The empty mask IS the value. *)
import Out;
var g: set;
procedure Clear(var s: set);
begin
  s := {}
end Clear;
begin
  g := {1, 3, 5};
  Clear(g);
  if g = {} then Out.Int(1, 0) else Out.Int(0, 0) end;
  Out.Ln
end EmptySet.
