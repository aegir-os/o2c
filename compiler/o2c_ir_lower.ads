--  Lowering: IR quads -> the bytecode emitter, in ONE place.
--
--  This is where the calling convention, the base-derivation arithmetic and the
--  stack discipline live, instead of being duplicated per branch in the parser.
--  It sits between the two so that neither knows the other: the front end
--  builds quads, this walks them, and O2c_BC receives the calls.
with O2c_Ir;

package O2c_Ir_Lower is

   --  Emit the bytecode for one quad.  Called INSIDE an open emitter procedure
   --  (O2c_BC.Proc_Open must hold), because that is what the emitter's stores
   --  and loads address.
   procedure Emit_Quad (Q : O2c_Ir.Quad_Info);

   --  How many quads this pass has lowered, so a caller can tell that the IR
   --  path ran rather than the inline one - the "did the edit actually happen"
   --  question, answered by a number instead of by assumption.
   function Lowered return Natural;

end O2c_Ir_Lower;
