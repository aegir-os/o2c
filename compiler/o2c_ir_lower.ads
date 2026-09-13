--  Lowering: IR quads -> the bytecode emitter, in ONE place.
--
--  This is where the calling convention, the base-derivation arithmetic and the
--  stack discipline live, instead of being duplicated per branch in the parser.
--  It sits between the two so that neither knows the other: the front end
--  builds quads, this walks them, and O2c_BC receives the calls.
with O2c_Bc;
with O2c_Ir;

package O2c_Ir_Lower is

   --  Derive the BASE ADDRESS of a designator chain and leave it on the
   --  emitter's stack.
   --
   --  This arithmetic was written three times in the parser - once for a scalar
   --  element, once for a user-typed element, and once more inside Total_Slots -
   --  and the copies disagreed: one used a POINTER's Total_Slots, which is zero,
   --  so `ptr^.a[i]` refused with "an array needs a non-zero length", and another
   --  sized a record field as one slot, so a field aliased the array before it.
   --  One rule, one place: callers pass what the type model knows.
   --
   --  Global_Slots = 0 means the address is ALREADY on the stack (a pointer
   --  base, or an object already walked to); otherwise it is the object's whole
   --  run, at the slot the chain has walked to, with Nested as a byte offset.
   procedure Push_Base (Global_Slots : Natural;
                        Nested : Natural;
                        Base_Name : String);

   --  Map an IR label onto the EMITTER's label namespace.
   --
   --  The compiler allocates emitter labels with its own counter, and the emitter
   --  has only Mark and Jump - no allocator - so label ids are a compiler-side
   --  namespace.  Using an IR id directly would collide with the labels the
   --  parser already allocated, and a colliding jump target is a silent wrong
   --  answer, not a refusal.  So the front end, which owns the counter, hands the
   --  pair over here before any quad naming that label is lowered.
   procedure Reserve_Label (Ir_Label : O2c_Ir.Label_Id; Bc_Label : Natural);

   --  The width choice, in ONE place, so it can be tested directly: an
   --  instruction COUNT cannot tell Add from Radd, but this mapping can.
   function Bc_Op (Op : O2c_Ir.Op; C : O2c_Ir.Type_Class) return O2c_Bc.Op;

   --  Emit the bytecode for one quad.  Called INSIDE an open emitter procedure
   --  (O2c_BC.Proc_Open must hold), because that is what the emitter's stores
   --  and loads address.
   procedure Emit_Quad (Q : O2c_Ir.Quad_Info);

   --  How many quads this pass has lowered, so a caller can tell that the IR
   --  path ran rather than the inline one - the "did the edit actually happen"
   --  question, answered by a number instead of by assumption.
   function Lowered return Natural;

end O2c_Ir_Lower;
