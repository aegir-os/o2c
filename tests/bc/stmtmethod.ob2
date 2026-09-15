module StmtMethod;
import Out;
type Shape = record x: integer end;
type Circle = record (Shape) r: integer end;
type P = pointer to Shape;
type PC = pointer to Circle;
type R2 = record v: integer end;
var s: P;
    c: PC;
    w: R2;

procedure (var h: Shape) Bump(n: integer);
begin
  h.x := h.x + n
end Bump;

procedure (var k: Circle) Bump(n: integer);
begin
  k.x := k.x + 10 * n
end Bump;

procedure (var h: R2) Twice;
begin
  h.v := h.v * 2
end Twice;

procedure (var h: Shape) GetX: integer;
begin
  return h.x
end GetX;

procedure (var h: R2) Get: integer;
begin
  return h.v
end Get;

begin
  NEW(s);
  NEW(c);
  s.x := 1;
  c.x := 1;
  s.Bump(1);
  Out.Int(s.x, 0); Out.Ln;
  c.Bump(1);
  Out.Int(c.x, 0); Out.Ln;
  s := c;
  s.Bump(1);
  Out.Int(c.x, 0); Out.Ln;
  (*  GetX is NOT overridden: the impl was compiled against Shape's layout,
      and a Circle object must still place x where Shape puts it.  The old
      own-fields-first layout read r here. *)
  c.r := 99;
  Out.Int(s.GetX(), 0); Out.Ln;
  w.v := 4;
  w.Twice;
  Out.Int(w.Get(), 0); Out.Ln
end StmtMethod.
