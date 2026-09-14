module PtrL;
(*  PtrFun's library: the Geom.Next shape - a POINTER-valued function. *)
type Node* = pointer to NodeDesc;
type NodeDesc* = record v*: integer; next*: Node end;
procedure Next*(l: Node): Node;
begin
  return l^.next
end Next;
end PtrL.
