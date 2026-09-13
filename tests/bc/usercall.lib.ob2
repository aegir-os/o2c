module ULib;
(*  A USER library: its bodies are compiled into the SAME image as the main
    module, so calling one is an ordinary CALL with a procedure id - not a
    native.  Nothing in the host corpus imported a user library before this
    fixture, which is why the three imported call sites were unexercised. *)
var store*: integer;
procedure Set*(v: integer);
begin
  store := v
end Set;
procedure Bump*;
begin
  store := store + 1
end Bump;
procedure Add*(v: integer): integer;
begin
  return store + v
end Add;
end ULib.
