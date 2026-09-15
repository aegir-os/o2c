module Nest9;
(*  Nine records deep: Total_Slots' recursion guard is a depth bound, not a
    nesting limit, and the scan's worry was unfounded - this compiled and
    ran the first time it was probed. *)
import Out;
type R1 = record v: integer end;
type R2 = record a: R1 end;
type R3 = record a: R2 end;
type R4 = record a: R3 end;
type R5 = record a: R4 end;
type R6 = record a: R5 end;
type R7 = record a: R6 end;
type R8 = record a: R7 end;
type R9 = record a: R8 end;
var r: R9;
begin
  r.a.a.a.a.a.a.a.a.v := 42;
  Out.Int(r.a.a.a.a.a.a.a.a.v, 0)
end Nest9.
