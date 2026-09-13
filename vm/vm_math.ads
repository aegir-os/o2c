--  The transcendentals the Oakwood Math and MathL modules stand on.
--
--  ONE implementation serves both platforms, for the same reason VM_IO's is one:
--  Ada.Numerics.Long_Elementary_Functions is available on the host AND in the
--  Aegir runtime (userspace/gnat-rts/gnat/a-nlelfu.ads), so 3cr's assumption
--  that the guest would need a hand-rolled ln/sin/cos was wrong - checked before
--  writing any of them, which is the only reason it was not written twice.
--
--  Long_Float throughout: the VM's REAL and LONGREAL share one 64-bit slot (M4e),
--  so Math and MathL differ in nothing here.  Domain errors follow the Ada
--  functions, which raise Constraint_Error - the natives are called from the
--  interpreter, which reports a raise as an error rather than as a wrong answer.
package VM_Math is

   function Power (X : Long_Float; Y : Long_Float) return Long_Float;
   function Exp (X : Long_Float) return Long_Float;
   function Ln (X : Long_Float) return Long_Float;
   --  Log (X, Base) is Ln X / Ln Base, which is what the Oberon module means.
   function Log (X : Long_Float; Base : Long_Float) return Long_Float;
   function Sin (X : Long_Float) return Long_Float;
   function Cos (X : Long_Float) return Long_Float;
   function Tan (X : Long_Float) return Long_Float;
   function ArcSin (X : Long_Float) return Long_Float;
   function ArcCos (X : Long_Float) return Long_Float;
   function ArcTan (X : Long_Float) return Long_Float;
   --  ArcTan2 (Y, X) - the two-argument arctangent Oberon's Math.arctan2 is.
   function ArcTan2 (Y : Long_Float; X : Long_Float) return Long_Float;

end VM_Math;
