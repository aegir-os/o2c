module ArgsUse;
import Out, Args;
var buf: array 8 of char; res: integer;
begin
  Args.Get (1, buf, res);
  Out.Int (Args.count, 0); Out.Int (res, 0); Out.Ln
end ArgsUse.
