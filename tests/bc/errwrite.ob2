module ErrWrite;
(*  Err.Write and Err.WriteLn: the diagnostics channel.  Write's argument is a
    real ADDRESS (the compiler passes it through Addr_Str_Actual), not a pool
    offset, so a literal works exactly as a variable does.  The output goes to
    the VM's stderr, which is the same channel its own notes use. *)
import Out, Err;
begin
  Err.Write ("err-ok");
  Err.WriteLn;
  Err.WriteLn;
  Out.Int (8501, 0); Out.Ln
end ErrWrite.
