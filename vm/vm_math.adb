with Ada.Numerics.Long_Elementary_Functions;

--  See the spec: one body for both platforms, because the guest runtime ships
--  Ada.Numerics.Long_Elementary_Functions too.
package body VM_Math is

   package Elem renames Ada.Numerics.Long_Elementary_Functions;

   function Power (X : Long_Float; Y : Long_Float) return Long_Float is
     (Elem."**" (X, Y));

   function Exp (X : Long_Float) return Long_Float is
     (Elem.Exp (X));

   function Ln (X : Long_Float) return Long_Float is
     (Elem.Log (X));

   function Log (X : Long_Float; Base : Long_Float) return Long_Float is
     (Elem.Log (X) / Elem.Log (Base));

   function Sin (X : Long_Float) return Long_Float is
     (Elem.Sin (X));

   function Cos (X : Long_Float) return Long_Float is
     (Elem.Cos (X));

   function Tan (X : Long_Float) return Long_Float is
     (Elem.Tan (X));

   function ArcSin (X : Long_Float) return Long_Float is
     (Elem.Arcsin (X));

   function ArcCos (X : Long_Float) return Long_Float is
     (Elem.Arccos (X));

   function ArcTan (X : Long_Float) return Long_Float is
     (Elem.Arctan (X));

   function ArcTan2 (Y : Long_Float; X : Long_Float) return Long_Float is
     (Elem.Arctan (Y, X));

end VM_Math;
