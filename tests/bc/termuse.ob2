module TermUse;
(*  Term, flipped like Reals before it.  Its procedures emit ANSI escape sequences,
    so the golden below is bytes - which is exactly what makes it worth pinning:
    the escapes are built from CHR and Out.Int inside REAL Oberon bodies, and the
    first thing the backend had to get right was compiling them. *)
import Out, Term;
begin
  Term.SetColor (2, 0);
  Out.String ("x"); Out.Ln
end TermUse.
