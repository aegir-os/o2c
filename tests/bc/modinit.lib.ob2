module MInitL;
(*  ModInit's library: one whose MODULE BODY must run before the main
    module's.  The header's entry runs only the main body, so the compiler
    records every non-empty library body and has the main body CALL it
    first.  Two things were wrong here: nobody called the body (hello.ob2's
    Input.TimeUnit read as whatever the global happened to hold), and the
    body's procedure had no RET, so once called it fell through into the
    next procedure in the image. *)
var ready*: integer;
begin
  ready := 42
end MInitL.
