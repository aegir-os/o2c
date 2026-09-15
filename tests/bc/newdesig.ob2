module NewDesig;
import Out;
type R = record n: integer end;
type P = pointer to R;
type H = record p: P end;
type Node = record v: integer; next: Node end;
type NP = pointer to Node;
var h: H;
    q: NP;
begin
  new(h.p);
  h.p^.n := 7;
  Out.Int(h.p^.n, 0);
  Out.Ln;
  new(q);
  new(q^.next);
  q^.v := 1;
  q^.next^.v := 2;
  Out.Int(q^.next^.v, 0);
  Out.Ln
end NewDesig.
