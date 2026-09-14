module EnvSet;
(*  Env.Set with STRING LITERAL arguments.  The arm demanded declared ARRAY OF
    CHAR variables for both arguments, so a literal refused; the question is the
    one Convert.ToInt answered by materializing the literal into a compiler-made
    global and taking THAT address.  Here it is asked twice in one call, which
    is why the materialized global must be per-occurrence and not per-line. *)
import Out, Env;
begin
  Env.Set ("O2CENV", "hello-env");
  Out.Int (8401, 0); Out.Ln
end EnvSet.
