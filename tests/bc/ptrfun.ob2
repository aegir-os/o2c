module PtrFun;
(*  A POINTER-valued function across a module boundary: tx := Lib.Next(hx),
    then a field read through the result.  tx walks to the second cell, so
    the answer is the 60 stored there, not the 40 in the first. *)
import Out, PtrL;
var hx, tx: PtrL.Node;
begin
  new(hx);
  hx^.v := 60;
  hx^.next := nil;
  new(tx);
  tx^.v := 40;
  tx^.next := hx;
  hx := tx;
  tx := PtrL.Next(hx);
  Out.Int(tx^.v, 0);
  Out.Ln
end PtrFun.
