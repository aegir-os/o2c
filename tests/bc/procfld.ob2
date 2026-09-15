module ProcFld;
(*  A PROCEDURE-typed record field is a procedure id in a word: stored from
    a bare name, copied value-to-value, and called through with ().  It is
    one slot to the layout, so nested records place it like any other word
    field, and the GC scans it as a word (200 allocations ran clean in the
    probe). *)
import Out;
type Proc = procedure;
type Inner = record f: Proc end;
type Outer = record n: integer; inner: Inner end;
var r1, r2: Inner;
    o: Outer;
    g: Proc;
procedure One;
begin
  Out.Int(1, 0)
end One;
procedure Two;
begin
  Out.Int(2, 0)
end Two;
begin
  r1.f := One;
  r1.f();
  g := Two;
  r2.f := g;
  r2.f();
  r2.f := r1.f;
  r2.f();
  o.inner.f := Two;
  o.inner.f();
  Out.Ln
end ProcFld.
