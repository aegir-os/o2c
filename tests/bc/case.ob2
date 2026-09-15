module Cas;
import Out;
var i: integer;
begin
  i := 2;
  case i of
    1: Out.Int(11, 0)
  | 2: Out.Int(42, 0)
  | 3: Out.Int(33, 0)
  else Out.Int(0, 0)
  end;
  Out.Ln;
  i := -2;
  case i of
    -3, -2: Out.Int(1, 0)
  | 0: Out.Int(2, 0)
  | 1, 2, 3: Out.Int(3, 0)
  end;
  Out.Ln;
  case 9 of
    1: Out.Int(4, 0)
  end;
  Out.Int(5, 0);
  Out.Ln
end Cas.
