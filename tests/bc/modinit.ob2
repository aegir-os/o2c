module ModInit;
(*  Prints MInitL.ready - 42 only if the library's module body was called
    before this one, and only if that body returned to its caller instead
    of falling through into the next procedure. *)
import Out, MInitL;
begin
  Out.Int (MInitL.ready, 0);
  Out.Ln
end ModInit.
