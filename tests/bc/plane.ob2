module PlaneT;
(*  XYplane.Dot's mode is the VALUE the dot gets (draw = 1, erase = 0):
    the VM native ignored it and always wrote 1, so an erased dot still
    read back as drawn (8102 where the Ada backend prints 8103). *)
import Out, XYplane;
begin
  XYplane.Open;
  XYplane.Dot(3, 4, XYplane.draw);
  if XYplane.IsDot(3, 4) then Out.Int(8100, 0) else Out.Int(8101, 0) end;
  Out.Ln;
  XYplane.Dot(3, 4, XYplane.erase);
  if XYplane.IsDot(3, 4) then Out.Int(8102, 0) else Out.Int(8103, 0) end;
  Out.Ln;
  XYplane.Clear;
  if XYplane.IsDot(3, 4) then Out.Int(8104, 0) else Out.Int(8105, 0) end;
  Out.Ln
end PlaneT.
