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

   --  The ELEMENT SIZE choice for an indexed access, in one place and testable
   --  for the same reason Bc_Op is: Load_Idx_B and Load_Idx_I are each ONE
   --  instruction, so an instruction count cannot tell them apart and only the
   --  mapping can.  A size the emitter has no op for raises here rather than
   --  being guessed at.
   function Bc_Load_Idx (Elem_Bytes : Natural) return O2c_Bc.Op;
   function Bc_Store_Idx (Elem_Bytes : Natural) return O2c_Bc.Op;

   --  One indexed element access, the whole site in one line: the designator
   --  chain has ALREADY pushed the base and the index - and, for a store, the
   --  value as well - so these DECLARE the size and emit the op, like Op_Arg
   --  declaring an argument it does not push.  A no-op outside bytecode mode.
   procedure Load_Idx (Elem_Bytes : Natural);
   procedure Store_Idx (Elem_Bytes : Natural);

   --  WHICH KIND of field - the fact that decides between the emitter's six
   --  field ops.  It is the front end's to state: it knows the field's type,
   --  and the lowering sees only an offset.
   type Fld_Kind is (Fld_Int, Fld_Ptr, Fld_Real);

   --  The kind -> opcode table, for Bc_Op's reason: all six field ops are ONE
   --  instruction each, so an instruction count cannot check the choice - only
   --  the table can.  `Store` selects the store half.
   function Bc_Fld (K : Fld_Kind; Store : Boolean) return O2c_Bc.Op;

   --  One field access: the record's ADDRESS is already on the operand stack,
   --  the OFFSET was computed by the front end, and a store's value is on the
   --  stack too (parsed after its designator).  No-ops outside bytecode mode.
   procedure Load_Fld (Off : Natural; K : Fld_Kind);
   procedure Store_Fld (Off : Natural; K : Fld_Kind);

   --  The BASE of a global object - an array run, a record, or a scalar - as an
   --  ADDRESS on the operand stack.  `Slots` is the object's whole run and
   --  `Nested` a byte offset the chain has already walked to, and **Slots = 0
   --  means the address is ALREADY on the stack**: that is how a pointer base
   --  and an object already stepped into are expressed, and it is why this op
   --  can legitimately emit no instruction at all.
   --
   --  The arithmetic itself is Push_Base's and stays there - M3a gave it one
   --  home, and this op is how a QUAD reaches it.  A no-op outside bytecode
   --  mode.  One IR value (a V_Global carrying the name and the run) is minted
   --  per call, so it is the values table that grows, not the emitter's.
   procedure Addr_Global (Name : String; Slots : Natural;
                          Nested : Natural := 0);

   --  The VALUE of a variable, and the STORE of one.  Four helpers because the
   --  parser picks between a frame local and a module variable at each use, and
   --  it must not get that wrong (its own comment: reading a zeroed global
   --  where a parameter was meant is silent).  `Slot >= 0` in the caller decides
   --  local-versus-global, which is the caller's fact.
   --
   --  A LOAD leaves the value on the operand stack - that is what an expression
   --  wants, and it is why Op_Load_Local's and Op_Copy's Dst are optional.  A
   --  STORE consumes the value the front end has already pushed: it is expressed
   --  as a source that IS the stack (a temp), not as an op with no source, so
   --  the model keeps meaning what it says.  All four no-op outside bytecode
   --  mode.
   procedure Load_Local  (Slot : Natural);
   procedure Store_Local (Slot : Natural);
   procedure Load_Global (Name : String);
   procedure Store_Global (Name : String);

   --  The SET operators -> the emitter's, one entry each.  This is the table
   --  that made them their own quads: `and`/`or` on BOOLEANS emit Band/Bor while
   --  on SETS they emit Set_Intersect/Set_Union, and both operands are Tc_Word,
   --  so the choice cannot be a width - it has to be the op.  All six are one
   --  instruction each, so the self-test checks the TABLE, as it does for
   --  Bc_Op, Bc_Load_Idx and Bc_Fld.
   function Bc_Set (Op : O2c_Ir.Op) return O2c_Bc.Op;

   --  An OPERATOR whose operands are already on the operand stack - the left one
   --  pushed when it was parsed, then the right.  Binary or unary: the lowering
   --  knows which each op is, so a site does not have to.  A no-op outside
   --  bytecode mode.
   procedure Apply (O : O2c_Ir.Op);

   --  A BINARY operator whose OPCODE depends on the width - arithmetic and
   --  comparison.  Same contract as Apply (the operands are already on the
   --  operand stack), plus the one fact a quad cannot otherwise carry: the
   --  CLASS.  A class lives on a VALUE and these operands were pushed without
   --  one, so the helper declares the left operand as a temp that carries the
   --  width - which is what lets the lowering call Bc_Op, the single place that
   --  decides Add from Radd (3bg), instead of guessing.
   --
   --  Apply is NOT this helper with a defaulted class: the SET and BOOLEAN
   --  families take their opcode from tables that already fix it, so a class
   --  argument there would be read by nobody - and a parameter nobody reads is
   --  how a wrong call goes unnoticed.
   procedure Bin_Op (O : O2c_Ir.Op; Class : O2c_Ir.Type_Class
                                          := O2c_Ir.Tc_Word);

   --  A LABEL, and the four ways to reach one.  The front end used to allocate
   --  the EMITTER's label ids itself and hand them to O2c_BC.Mark/Jump; the IR
   --  owns that namespace now, so a site names a label it got from here and
   --  never sees the emitter's numbering.  This is the print loop's proven
   --  Reserve_Label mechanism, with the ids no longer spelled out at each site.
   --
   --  Jump_False is Jz (jump when the top IS zero) and Jump_True is Jnz, and
   --  the polarity is settled from the VM's table (3be) rather than from the
   --  names - getting it backwards produces a program that runs and is wrong.
   --  All four no-op outside bytecode mode.
   --
   --  ALLOCATION is not here: the emitter has no label allocator (its namespace
   --  belongs to its caller), so the front end's own counter allocates the id
   --  and RESERVES it here with Reserve_Label.  One counter, one mapping.
   --  A CONSTANT as a push: `Op_Copy` with a constant source and no Dst IS the
   --  push an expression wants (Push_Value emits it), so a site states the
   --  value and nothing else.  The same helper covers an index bound, a literal
   --  operand and a length, which is what the statement sites kept spelling out.
   procedure Push_Int (V : Integer);
   procedure Push_Str (Text : String);

   --  Duplicate the top of the operand stack.  Needed before a bounds compare,
   --  which must not consume the index it is about to use, and by CASE's label
   --  matching.
   procedure Dup;

   --  TRAP with its kind byte (spec: 0 = index out of range).
   procedure Trap (Kind : Natural);

   --  Drop the top of the operand stack.  CASE keeps its selector there for the
   --  whole statement and drops it once at the end.
   procedure Discard;

   --  A UNARY operator whose opcode depends on the width - the sign, and the
   --  only one the parser emits.  Bin_Op's mirror, and the class is the same
   --  kind of fact: the operand is already on the stack, so its width has to
   --  travel on a value the quad names.
   procedure Un_Op (O : O2c_Ir.Op; Class : O2c_Ir.Type_Class);

   --  FOR.  The two opcodes take their target as an OPERAND (a fixup), so these
   --  are shaped differently from the Jump helpers: everything the opcode needs
   --  is an argument.  `L` is the else-target for For_Enter and the body's start
   --  for For_Next, and the lowering resolves it through the reservation like
   --  any other label.  from and to are on the operand stack for For_Enter.
   procedure For_Enter (Slot : Natural; Step : Integer; Limit_Slot : Natural;
                        L : O2c_Ir.Label_Id);
   procedure For_Next (Slot : Natural; Step : Integer; Limit_Slot : Natural;
                       L : O2c_Ir.Label_Id);

   procedure Mark (L : O2c_Ir.Label_Id);
   procedure Jump (L : O2c_Ir.Label_Id);
   procedure Jump_False (L : O2c_Ir.Label_Id);
   procedure Jump_True (L : O2c_Ir.Label_Id);

   --  CONTRACT: a local named in a quad must already have been declared to the
   --  emitter with `O2c_BC.Local` - the lowering resolves the name through the
   --  emitter's table and refuses by name when it is absent.

   --  One native call: `Arity` declared arguments, the call itself, and the
   --  lowering of exactly those quads.  The arguments were pushed by the front
   --  end as it parsed them, which is what Op_Arg declares.
   --
   --  This exists so a migration is one line - and so the DYNAMIC call sites,
   --  whose id and arity are computed at compile time, do not have to repeat
   --  their expression to get the right number of Op_Arg quads.  It is a no-op
   --  outside bytecode mode.
   procedure Call_Native (Id : Natural; Arity : Natural);

   --  One call into a procedure IN THIS IMAGE - the other half of the same
   --  convention, and the half that was still written per-branch in the parser:
   --  five call sites each worked out for themselves which id to use, what was
   --  already on the stack, and whether the callee had a body at all.  Two of
   --  them also had to decide foreign-versus-body inline.
   --
   --  Same contract as Call_Native: `Arity` declared arguments whose values the
   --  front end has ALREADY pushed, the call itself, and the lowering of
   --  exactly those quads.  The id is the callee's bytecode procedure id, which
   --  is why this cannot be folded into Call_Native: nothing here is native.
   --
   --  The RESULT is left on the operand stack, where CALL puts it.  A caller
   --  that wants it in a frame slot or a global passes a Dst to the quad; one
   --  whose result feeds the surrounding expression declares none, exactly as
   --  the hand-written sites did.
   --
   --  A no-op outside bytecode mode.
   procedure Call_Proc (Proc_Id : Natural; Arity : Natural);

   --  Emit the bytecode for one quad.  Called INSIDE an open emitter procedure
   --  (O2c_BC.Proc_Open must hold), because that is what the emitter's stores
   --  and loads address.
   procedure Emit_Quad (Q : O2c_Ir.Quad_Info);

   --  How many quads this pass has lowered, so a caller can tell that the IR
   --  path ran rather than the inline one - the "did the edit actually happen"
   --  question, answered by a number instead of by assumption.
   function Lowered return Natural;

end O2c_Ir_Lower;
