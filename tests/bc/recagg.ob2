module RecAgg;
(*  A record aggregate: the 3cq sweep found it SILENT (`r := {a = 1,
    b = 2}` printed 00), and it has refused since.  The given fields store
    through Bc_Base at the offsets Field_Offset already computes, and the
    ones left out take Scalar_Init's defaults.  An extension type walks
    the parent chain, so y.a lives at the parent's offset. *)
import Out;
type Rec = record a, b, c: integer; r: real; f: boolean end;
type Ext = record (Rec) d: integer end;
var x: Rec;
    y: Ext;
begin
  x := {a = 40, b = 2, r = 1.5};
  if x.a + x.b = 42 then Out.String ("given-ok") else Out.String ("given-bad") end;
  Out.Ln;
  if x.c = 0 then Out.String ("default-ok") else Out.String ("default-bad") end;
  Out.Ln;
  if (x.r > 1.4) & (x.r < 1.6) then Out.String ("real-ok") else Out.String ("real-bad") end;
  Out.Ln;
  if ~x.f then Out.String ("bool-ok") else Out.String ("bool-bad") end;
  Out.Ln;
  y := {a = 1, d = 41};
  if y.a + y.d = 42 then Out.String ("ext-ok") else Out.String ("ext-bad") end;
  Out.Ln;
  if y.c = 0 then Out.String ("extdef-ok") else Out.String ("extdef-bad") end;
  Out.Ln
end RecAgg.
