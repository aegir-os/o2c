module Deep;
import Out;
var g: integer;
    arr: array 4 of integer;

procedure A(a: array of integer);
  var x: integer;

  procedure Mark;
  begin
    x := x + 1000
  end Mark;

  procedure B;
    var y: integer;

    procedure C;
    begin
      x := x + 1;
      y := y + 10;
      g := g + 100;
      Mark;
      Out.Int(x + y + g, 0); Out.Ln;
      Out.Int(a[2], 0); Out.Ln;
      Out.Int(len(a), 0); Out.Ln
    end C;

  begin
    y := 1;
    C;
    Out.Int(y, 0); Out.Ln
  end B;

begin
  x := 5;
  B;
  Out.Int(x, 0); Out.Ln
end A;

begin
  g := 0;
  arr[2] := 42;
  A(arr);
  Out.Int(g, 0); Out.Ln
end Deep.
