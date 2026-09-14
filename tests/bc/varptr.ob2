module VarPtr;
(*  A VAR POINTER formal is passed as the caller's ADDRESS, like any by-ref
    scalar: Push must write head back through it.  Passing the value instead
    compiled, ran, and lost the assignment - head stayed NIL and head^.v
    faulted.  After three pushes head holds 3; Last walks to the 1. *)
import Out;
type Node = pointer to NRec;
type NRec = record v: integer; next: Node end;
var head: Node; tail: Node;

procedure Push(var l: Node; x: integer);
  var n: Node;
begin
  new(n); n^.v := x; n^.next := l; l := n
end Push;

procedure Last(l: Node): Node;
  var r: Node;
begin
  r := l;
  while r^.next # NIL do r := r^.next end;
  return r
end Last;

begin
  head := NIL;
  Push(head, 1); Push(head, 2); Push(head, 3);
  Out.Int(head^.v, 0); Out.Ln;
  tail := Last(head);
  Out.Int(tail^.v, 0); Out.Ln
end VarPtr.
