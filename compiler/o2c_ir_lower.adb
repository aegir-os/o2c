with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with O2c_Bc;
with O2c_Ir; use O2c_Ir;

package body O2c_Ir_Lower is

   N_Lowered : Natural := 0;
   N_Args    : Natural := 0;   --  Op_Arg run since the last call

   Max_Ir_Labels : constant := 4096;
   Label_Map : array (1 .. Max_Ir_Labels) of Natural := (others => 0);

   function Lowered return Natural is
   begin
      return N_Lowered;
   end Lowered;

   function Bc_Op (Op : O2c_Ir.Op; C : O2c_Ir.Type_Class) return O2c_Bc.Op is
   begin
      --  Real has its own family for arithmetic AND comparison; bytes only have
      --  the element loads, so anything else at Tc_Byte is a front-end error
      --  rather than something to guess at.
      case C is
         when O2c_Ir.Tc_Real =>
            case Op is
               when O2c_Ir.Op_Add => return O2c_Bc.Radd;
               when O2c_Ir.Op_Sub => return O2c_Bc.Rsub;
               when O2c_Ir.Op_Mul => return O2c_Bc.Rmul;
               when O2c_Ir.Op_Div => return O2c_Bc.Rdiv;
               when O2c_Ir.Op_Neg => return O2c_Bc.Rneg;
               when O2c_Ir.Op_Eq => return O2c_Bc.Req;
               when O2c_Ir.Op_Ne => return O2c_Bc.Rne;
               when O2c_Ir.Op_Lt => return O2c_Bc.Rlt;
               when O2c_Ir.Op_Le => return O2c_Bc.Rle;
               when O2c_Ir.Op_Gt => return O2c_Bc.Rgt;
               when O2c_Ir.Op_Ge => return O2c_Bc.Rge;
               when others =>
                  raise Program_Error with "O2c_Ir_Lower: no real form of "
                    & O2c_Ir.Op'Image (Op);
            end case;
         when O2c_Ir.Tc_Word =>
            case Op is
               when O2c_Ir.Op_Add => return O2c_Bc.Add;
               when O2c_Ir.Op_Sub => return O2c_Bc.Sub;
               when O2c_Ir.Op_Mul => return O2c_Bc.Mul;
               when O2c_Ir.Op_Div => return O2c_Bc.IDiv;
               when O2c_Ir.Op_Mod => return O2c_Bc.IMod;
               when O2c_Ir.Op_Neg => return O2c_Bc.Neg;
               when O2c_Ir.Op_Eq => return O2c_Bc.Eq;
               when O2c_Ir.Op_Ne => return O2c_Bc.Ne;
               when O2c_Ir.Op_Lt => return O2c_Bc.Lt;
               when O2c_Ir.Op_Le => return O2c_Bc.Le;
               when O2c_Ir.Op_Gt => return O2c_Bc.Gt;
               when O2c_Ir.Op_Ge => return O2c_Bc.Ge;
               --  BOOLEAN and/or.  A boolean IS a word here, so these belong in
               --  the width table - and a SET's and/or does NOT, which is why the
               --  SET family is its own ops: both operands are Tc_Word either
               --  way, and only the op can say which was meant.
               when O2c_Ir.Op_And => return O2c_Bc.Band;
               when O2c_Ir.Op_Or  => return O2c_Bc.Bor;
               when others =>
                  raise Program_Error with "O2c_Ir_Lower: no word form of "
                    & O2c_Ir.Op'Image (Op);
            end case;
         when O2c_Ir.Tc_Byte =>
            raise Program_Error with "O2c_Ir_Lower: "
              & O2c_Ir.Op'Image (Op) & " has no byte form";
      end case;
   end Bc_Op;

   function Bc_Load_Idx (Elem_Bytes : Natural) return O2c_Bc.Op is
   begin
      if Elem_Bytes = 1 then
         return O2c_Bc.Load_Idx_B;
      elsif Elem_Bytes = 8 then
         return O2c_Bc.Load_Idx_I;
      else
         raise Program_Error with
           "O2c_Ir_Lower: no indexed load of" & Elem_Bytes'Image & " bytes";
      end if;
   end Bc_Load_Idx;

   function Bc_Store_Idx (Elem_Bytes : Natural) return O2c_Bc.Op is
   begin
      if Elem_Bytes = 1 then
         return O2c_Bc.Store_Idx_B;
      elsif Elem_Bytes = 8 then
         return O2c_Bc.Store_Idx_I;
      else
         raise Program_Error with
           "O2c_Ir_Lower: no indexed store of" & Elem_Bytes'Image & " bytes";
      end if;
   end Bc_Store_Idx;

   procedure Load_Idx (Elem_Bytes : Natural) is
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Load_Idx, Imm_1 => Elem_Bytes);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Load_Idx;

   procedure Store_Idx (Elem_Bytes : Natural) is
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Store_Idx, Imm_1 => Elem_Bytes);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Store_Idx;

   function Fld_Kind_Of (Tag : Natural) return Fld_Kind is
   begin
      --  The quad carries the kind as an ordinal, so an ordinal that is not one
      --  of the three is a front-end bug and says so here rather than picking an
      --  opcode by accident: the three kinds are all one instruction, so a wrong
      --  choice would be invisible in every count.
      case Tag is
         when 0 => return Fld_Int;
         when 1 => return Fld_Ptr;
         when 2 => return Fld_Real;
         when others =>
            raise Program_Error with
              "O2c_Ir_Lower: no such field kind:" & Tag'Image;
      end case;
   end Fld_Kind_Of;

   function Bc_Fld (K : Fld_Kind; Store : Boolean) return O2c_Bc.Op is
   begin
      if Store then
         case K is
            when Fld_Int  => return O2c_Bc.Store_Fld_I;
            when Fld_Ptr  => return O2c_Bc.Store_Fld_P;
            when Fld_Real => return O2c_Bc.Store_Fld_R;
         end case;
      else
         case K is
            when Fld_Int  => return O2c_Bc.Load_Fld_I;
            when Fld_Ptr  => return O2c_Bc.Load_Fld_P;
            when Fld_Real => return O2c_Bc.Load_Fld_R;
         end case;
      end if;
   end Bc_Fld;

   procedure Load_Fld (Off : Natural; K : Fld_Kind) is
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Load_Fld, Imm_1 => Off,
                   Imm_2 => Fld_Kind'Pos (K));
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Load_Fld;

   procedure Store_Fld (Off : Natural; K : Fld_Kind) is
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Store_Fld, Imm_1 => Off,
                   Imm_2 => Fld_Kind'Pos (K));
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Store_Fld;

   function Bc_Set (Op : O2c_Ir.Op) return O2c_Bc.Op is
   begin
      case Op is
         when O2c_Ir.Op_Set_Union     => return O2c_Bc.Set_Union;
         when O2c_Ir.Op_Set_Intersect => return O2c_Bc.Set_Intersect;
         when O2c_Ir.Op_Set_Diff      => return O2c_Bc.Set_Diff;
         when O2c_Ir.Op_Set_Symdiff   => return O2c_Bc.Set_Symdiff;
         when O2c_Ir.Op_Set_In        => return O2c_Bc.Set_In;
         when O2c_Ir.Op_Set_Single    => return O2c_Bc.Set_Single;
         when others =>
            raise Program_Error with "O2c_Ir_Lower: " & O2c_Ir.Op'Image (Op)
              & " is not a SET operator";
      end case;
   end Bc_Set;

   procedure Apply (O : O2c_Ir.Op) is
   begin
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      O2c_Ir.Emit (O);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Apply;

   procedure Bin_Op (O : O2c_Ir.Op;
                     Class : O2c_Ir.Type_Class := O2c_Ir.Tc_Word) is
      L : Value_Id;
   begin
      --  NOT inside a procedure is a real case, and it is not a bug: a
      --  CONSTANT declaration's expression is parsed and folded BEFORE any
      --  procedure is open, and its arithmetic never needs to be emitted at all
      --  - every use site pushes the folded value.  A quad cannot hold it in any
      --  case, because a quad's operands live in a frame.  The old direct
      --  emission DID fire here and appended dead bytes ahead of the first
      --  procedure's code, which is why this guard is a fix and not a
      --  workaround: the IR says "where there is no frame, there is no quad",
      --  and says it here instead of three frames down as a failed
      --  procedure-open check.
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      --  Src1 declares the LEFT operand - already on the stack, pushed by the
      --  sub-expression the parser had just read - and its only payload is the
      --  WIDTH.  That is the whole reason a temp is minted: a class lives on a
      --  value, an operand pushed without a value id has none, and the lowering
      --  must not guess Add from Radd (the choice 3bg put in Bc_Op's table
      --  precisely so it happens in ONE place).
      L := O2c_Ir.New_Temp (Typ => 0, Class => Class);
      O2c_Ir.Emit (O, Src1 => L);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Bin_Op;

   procedure Push_Int (V : Integer) is
      C : Value_Id;
   begin
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      C := O2c_Ir.Const_Int (Long_Integer (V), Typ => 1);
      O2c_Ir.Emit (O2c_Ir.Op_Copy, Src1 => C);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Push_Int;

   procedure Dup is
   begin
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Dup);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Dup;

   procedure Trap (Kind : Natural) is
   begin
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Trap, Imm_1 => Kind);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Trap;

   procedure Discard is
   begin
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Discard);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Discard;

   procedure Mark (L : O2c_Ir.Label_Id) is
   begin
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      --  The label is a VALUE in the quad (Dst), which is how the lowering
      --  resolves it back to the emitter's number through the reservation
      --  above - the same shape the print loop's Op_Label already uses.
      O2c_Ir.Emit (O2c_Ir.Op_Label, Dst => O2c_Ir.Label_Value (L));
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Mark;

   procedure Jump (L : O2c_Ir.Label_Id) is
   begin
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Jump, Src1 => O2c_Ir.Label_Value (L));
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Jump;

   procedure Jump_False (L : O2c_Ir.Label_Id) is
   begin
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Jump_False, Src1 => O2c_Ir.Label_Value (L));
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Jump_False;

   procedure Jump_True (L : O2c_Ir.Label_Id) is
   begin
      if not O2c_BC.Bytecode_Mode or else not O2c_BC.Proc_Open then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Jump_True, Src1 => O2c_Ir.Label_Value (L));
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Jump_True;

   procedure Load_Local (Slot : Natural) is
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      O2c_Ir.Emit (O2c_Ir.Op_Load_Local, Imm_1 => Slot);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Load_Local;

   procedure Store_Local (Slot : Natural) is
      T : Value_Id;
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      --  The value is the operand stack: a temp names it, and Push_Value emits
      --  nothing for one.  That is the front end's shape for every assignment -
      --  it pushes as it parses - so this is what keeps the emitted image the
      --  same while making the store a real quad with a real source.
      T := O2c_Ir.New_Temp (Typ => 0);
      O2c_Ir.Emit (O2c_Ir.Op_Store_Local, Src1 => T, Imm_1 => Slot);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Store_Local;

   procedure Load_Global (Name : String) is
      V : Value_Id;
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      V := O2c_Ir.New_Global (Name, Typ => 0);
      O2c_Ir.Emit (O2c_Ir.Op_Copy, Src1 => V);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Load_Global;

   procedure Store_Global (Name : String) is
      T : Value_Id;
      V : Value_Id;
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      T := O2c_Ir.New_Temp (Typ => 0);
      V := O2c_Ir.New_Global (Name, Typ => 0);
      O2c_Ir.Emit (O2c_Ir.Op_Copy, Dst => V, Src1 => T);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Store_Global;

   procedure Addr_Global (Name : String; Slots : Natural;
                          Nested : Natural := 0) is
      V : Value_Id;
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      V := O2c_Ir.New_Global (Name, Typ => 0, Slots => Slots);
      O2c_Ir.Emit (O2c_Ir.Op_Addr_Global, Src1 => V, Imm_1 => Nested);
      O2c_Ir_Lower.Emit_Quad
        (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (O2c_Ir.Quad_Count)));
   end Addr_Global;

   procedure Call_Native (Id : Natural; Arity : Natural) is
      First : Natural;
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      for K in 1 .. Arity loop
         pragma Unreferenced (K);
         O2c_Ir.Emit (O2c_Ir.Op_Arg);
      end loop;
      --  Quad ids are 1-based and Quad_Count is the LAST one emitted, so the
      --  first argument is Quad_Count - Arity + 1.  One less than this lowers
      --  the previous call - which fails loudly ("native N takes 0 arguments
      --  but M were pushed") rather than silently, but it is still wrong.
      First := O2c_Ir.Quad_Count - Arity + 1;
      O2c_Ir.Emit (O2c_Ir.Op_Call_Native, Imm_1 => Id, Imm_2 => Arity);
      --  the arguments, then the call
      for K in 0 .. Arity loop
         O2c_Ir_Lower.Emit_Quad
           (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (First + K)));
      end loop;
   end Call_Native;

   procedure Call_Proc (Proc_Id : Natural; Arity : Natural) is
      First : Natural;
   begin
      if not O2c_BC.Bytecode_Mode then
         return;
      end if;
      for K in 1 .. Arity loop
         pragma Unreferenced (K);
         O2c_Ir.Emit (O2c_Ir.Op_Arg);
      end loop;
      --  Quad ids are 1-based and Quad_Count is the LAST one emitted, so with
      --  Arity = 0 this is Quad_Count + 1 and the loop below lowers the call
      --  alone - the parameterless case, the common one in a statement part.
      First := O2c_Ir.Quad_Count - Arity + 1;
      O2c_Ir.Emit (O2c_Ir.Op_Call, Imm_1 => Proc_Id, Imm_2 => Arity);
      --  the arguments, then the call
      for K in 0 .. Arity loop
         O2c_Ir_Lower.Emit_Quad
           (O2c_Ir.Quad_At (O2c_Ir.Quad_Id (First + K)));
      end loop;
   end Call_Proc;

   procedure Reserve_Label (Ir_Label : O2c_Ir.Label_Id; Bc_Label : Natural) is
   begin
      if Natural (Ir_Label) = 0 or else Natural (Ir_Label) > Max_Ir_Labels then
         raise Program_Error with "O2c_Ir_Lower: no such IR label";
      end if;
      Label_Map (Natural (Ir_Label)) := Bc_Label;
   end Reserve_Label;

   function Bc_Label_Of (V : Value_Id) return Natural is
      I : constant Value_Info := Value_At (V);
   begin
      if I.Kind /= V_Label then
         raise Program_Error with
           "O2c_Ir_Lower: a jump needs a label value";
      end if;
      if Natural (I.Int) = 0 or else Natural (I.Int) > Max_Ir_Labels
        or else Label_Map (Natural (I.Int)) = 0
      then
         raise Program_Error with
           "O2c_Ir_Lower: label was never reserved with the emitter";
      end if;
      return Label_Map (Natural (I.Int));
   end Bc_Label_Of;

   function Local_Slot_Of (V : Value_Id) return Integer is
   begin
      return O2c_BC.Local_Slot (To_String (Value_At (V).Name));
   end Local_Slot_Of;

   procedure Push_Value (V : Value_Id) is
      I : constant Value_Info := Value_At (V);
      S : Integer;
   begin
      --  Only the two kinds M2 needs.  Every other kind names itself in the
      --  failure rather than falling through to a wrong image.
      if I.Kind = V_Const_Int then
         O2c_BC.Push_Int (Integer (I.Int));
      elsif I.Kind = V_Local then
         S := Local_Slot_Of (V);
         if S < 0 then
            raise Program_Error with "O2c_Ir_Lower: local is not in the "
              & "frame: " & To_String (I.Name);
         end if;
         O2c_BC.Load_Local (Natural (S));
      elsif I.Kind = V_Temp then
         --  The mirror of Store_Value's V_Temp case, and the reason a store can
         --  be a quad with a source rather than an op with a hole in it: a
         --  temp's home IS the operand stack, so its producer left the value
         --  there and there is NOTHING to emit here.  The emitter's depth model
         --  still checks the consumer, so a temp that nothing produced underflows
         --  loudly rather than storing nothing.
         null;
      elsif I.Kind = V_Global then
         O2c_BC.Load (O2c_BC.Global (To_String (I.Name)));
      else
         raise Program_Error with "O2c_Ir_Lower: value kind "
           & Value_Kind'Image (I.Kind) & " has no lowering yet";
      end if;
   end Push_Value;

   procedure Store_Value (V : Value_Id) is
      I : constant Value_Info := Value_At (V);
      S : Integer;
   begin
      if I.Kind = V_Temp then
         --  A temp's home IS the operand stack: its producer leaves the value
         --  there and the next quad that consumes it takes it off.  So there is
         --  nothing to emit here, and emitting a store would be an extra
         --  instruction the hand-written code did not have.  (M2 had no temps,
         --  which is why this was absent until the print loop's conditions
         --  needed it.)
         null;
      elsif I.Kind = V_Local then
         S := Local_Slot_Of (V);
         if S < 0 then
            raise Program_Error with "O2c_Ir_Lower: local is not in the "
              & "frame: " & To_String (I.Name);
         end if;
         O2c_BC.Store_Local (Natural (S));
      elsif I.Kind = V_Global then
         O2c_BC.Store (O2c_BC.Global (To_String (I.Name)));
      else
         raise Program_Error with "O2c_Ir_Lower: cannot store into a "
           & Value_Kind'Image (I.Kind);
      end if;
   end Store_Value;

   procedure Push_Base (Global_Slots : Natural;
                        Nested : Natural;
                        Base_Name : String) is
   begin
      if Global_Slots /= 0 then
         --  The variable's whole run, at the slot the chain has walked to:
         --  offsets are byte counts and the run is slots, and every offset
         --  here is a multiple of eight.
         O2c_BC.Load_Addr_G
           (O2c_BC.Global_Array (Base_Name, Global_Slots) + Nested / 8);
      elsif Nested > 0 then
         --  Already the object's address; step into it.
         O2c_BC.Push_Int (Nested);
         O2c_BC.Bin (O2c_BC.Add);
      end if;
   end Push_Base;

   procedure Emit_Quad (Q : O2c_Ir.Quad_Info) is
   begin
      if not O2c_BC.Bytecode_Mode then
         raise Program_Error with
           "O2c_Ir_Lower: the emitter is not in bytecode mode";
      end if;
      if not O2c_BC.Proc_Open then
         raise Program_Error with
           "O2c_Ir_Lower: no emitter procedure is open";
      end if;

      --  NO `others` ARM, on purpose: adding an Op to the IR without deciding
      --  how it lowers is a compile error HERE rather than a silently empty
      --  image.  That property is the whole reason the op set is closed.
      case Q.Op is
         when Op_Copy =>
            --  A Dst only when the value is to LAND somewhere: with no Dst this
            --  is the push an expression needs, which is how the front end reads
            --  a variable's value into the operand stack.
            Push_Value (Q.Src1);
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Nop =>
            null;

         when Op_Arg =>
            --  One argument has ALREADY been pushed, in order, by the front end
            --  as it parsed it - so this does NOT push again.  (M4a pushed, and
            --  that is wrong: it would double the operand, the same bug the
            --  qualified call path had in 3u.)  The op exists so the arity is
            --  DECLARED and can be checked against the call, instead of being
            --  left to the verifier or to luck.  Src1 carries the value for
            --  readers and for the arity's sake, not to be emitted.
            N_Args := N_Args + 1;

         when Op_Call_Native =>
            --  A native call: id and arity are immediates, and the arity must
            --  match the Op_Arg run that precedes it.  A mismatch is a bug in
            --  the front end, and the alternative to catching it here is an
            --  image that fails verification later - or, worse, one that does
            --  not.
            if N_Args /= Q.Imm_2 then
               --  Reset BEFORE raising: the run counter is state, and leaving
               --  it dirty would mis-attribute the arguments of the NEXT call.
               --  The self-test found this, because it lowers a mismatched call
               --  and then a valid one.
               declare
                  Pushed : constant Natural := N_Args;
               begin
                  N_Args := 0;      --  clean state, even on the failure path
                  raise Program_Error with "O2c_Ir_Lower: native"
                    & Natural'Image (Q.Imm_1) & " takes"
                    & Natural'Image (Q.Imm_2) & " arguments but"
                    & Natural'Image (Pushed) & " were pushed";
               end;
            end if;
            N_Args := 0;
            O2c_BC.Native_Call (Q.Imm_1, Q.Imm_2);

         when Op_Load_Local =>
            O2c_BC.Load_Local (Q.Imm_1);
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Store_Local =>
            Push_Value (Q.Src1);
            O2c_BC.Store_Local (Q.Imm_1);

         when Op_Load_Idx =>
            --  Src1 and Src2 are ALREADY on the stack - the designator chain
            --  pushed the base and the index as it parsed them, exactly as the
            --  front end pushes an Op_Arg's argument.  So this does not push
            --  them again.  The rule, made explicit because the self-test caught
            --  this arm breaking it: a STORE materialises its source (Op_Copy
            --  pushes), a designator-shaped op takes its operands from the
            --  stack.
            --  The SIZE -> opcode choice is Bc_Load_Idx's, not this arm's, so
            --  it can be tested directly: Load_Idx_B and Load_Idx_I are one
            --  instruction each, and a count cannot tell them apart.
            O2c_BC.Bin (Bc_Load_Idx (Q.Imm_1));
            --  A Dst only when the caller wants the element somewhere other
            --  than the operand stack.  A subscript INSIDE AN EXPRESSION leaves
            --  it there, exactly as the hand-written sites did, and a temp's
            --  home is the stack, so naming one adds no instruction either.
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Store_Idx =>
            --  The store half of the same pair.  [base, index, value] are
            --  ALREADY on the stack: the designator chain pushed the first two
            --  and the front end the value, because a store's value is parsed
            --  after its designator.  So nothing is pushed here, and there is no
            --  Dst to store - the store CONSUMES the value.
            O2c_BC.Bin (Bc_Store_Idx (Q.Imm_1));

         when Op_Load_Fld =>
            --  The offset-carrying form of an indexed access: the record's
            --  ADDRESS is already on the operand stack, so the operand rule is
            --  Op_Arg's - declare, do not push.  Imm_1 is the offset the front
            --  end computed, Imm_2 the kind that picks the opcode, and a Dst
            --  only when the value is not consumed where it lands.
            O2c_BC.Field (Bc_Fld (Fld_Kind_Of (Q.Imm_2), False), Q.Imm_1);
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Store_Fld =>
            --  And the store half: [address, value] are both on the stack, so
            --  there is nothing to push and no Dst - the store consumes the
            --  value, exactly as the hand-written sites did.
            O2c_BC.Field (Bc_Fld (Fld_Kind_Of (Q.Imm_2), True), Q.Imm_1);

         when Op_Dup =>
            O2c_BC.Dup_Top;

         when Op_Trap =>
            --  The kind byte is an immediate because a bare Trap would
            --  desynchronise the VM, which reads it.
            O2c_BC.Trap (Q.Imm_1);

         when Op_Discard =>
            O2c_BC.Discard;

         when Op_Label =>
            O2c_BC.Mark (Bc_Label_Of (Q.Dst));

         when Op_Jump =>
            O2c_BC.Jump (O2c_BC.Jmp, Bc_Label_Of (Q.Src1));

         when Op_Jump_True =>
            --  JNZ: jump when the top is NOT zero - the mirror of the arm
            --  below, and settled the same way, from the VM's opcode table.
            O2c_BC.Jump (O2c_BC.Jnz, Bc_Label_Of (Q.Src1));

         when Op_Jump_False =>
            --  Jz, not Jnz: the VM's Jnz jumps when the top is NOT zero, so
            --  "jump when false" is the zero case.  Getting this backwards
            --  produces a program that runs and is wrong, which is why the
            --  polarity is settled from the VM's opcode table rather than from
            --  the name.  The condition is already on the stack - Op_Arg's rule
            --  applies to it too: these ops DECLARE their operands.
            O2c_BC.Jump (O2c_BC.Jz, Bc_Label_Of (Q.Src1));

         when Op_Add | Op_Sub | Op_Mul | Op_Div | Op_Mod
            | Op_Neg | Op_Eq | Op_Ne | Op_Lt | Op_Le | Op_Gt | Op_Ge =>
            --  The WIDTH comes from the OPERAND, not the destination: a
            --  comparison's destination is a boolean word while its operands may
            --  be reals, and the op family follows the operands.
            O2c_BC.Bin
              (Bc_Op (Q.Op, Value_At (Q.Src1).Class));
            --  A Dst only when the result is to LAND somewhere.  With none it
            --  stays on the operand stack, which is the shape every EXPRESSION
            --  has - and this arm never saw one until Bin_Op sent it, because
            --  its only users were the print loop's conditions, all of which
            --  store their result.  Store_Value (No_Value) is what that
            --  assumption cost: an "O2c_Ir: no such value" from a value id of
            --  zero, two frames away from the operator that omitted it.
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Call =>
            --  A call into a procedure in THIS image.  Same arity contract as
            --  the native form above, and deliberately the same shape: the
            --  Op_Arg run that precedes must match Imm_2, and the counter is
            --  reset BEFORE raising so one bad call cannot mis-attribute the
            --  next one's arguments.
            if N_Args /= Q.Imm_2 then
               declare
                  Pushed : constant Natural := N_Args;
               begin
                  N_Args := 0;      --  clean state, even on the failure path
                  raise Program_Error with "O2c_Ir_Lower: procedure"
                    & Natural'Image (Q.Imm_1) & " takes"
                    & Natural'Image (Q.Imm_2) & " arguments but"
                    & Natural'Image (Pushed) & " were pushed";
               end;
            end if;
            N_Args := 0;
            O2c_BC.Call_Proc (Q.Imm_1);
            --  The RESULT, when the caller wants it in a frame slot or a
            --  global.  CALL has already left it on the operand stack, and a
            --  temp's home IS that stack (Store_Value), so a call whose result
            --  feeds the surrounding expression declares no Dst and adds no
            --  instruction here - which is what the hand-written sites did.
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Addr_Global =>
            --  The base of a global object.  The lowering's whole job for this
            --  op is to hand Push_Base the three facts the front end knows -
            --  which is the payoff of M3a putting that arithmetic in ONE place:
            --  there is no second copy here to drift from it.  Slots = 0 and
            --  Nested = 0 emit nothing, because then the address is already on
            --  the stack.
            Push_Base (Value_At (Q.Src1).Slots, Q.Imm_1,
                       To_String (Value_At (Q.Src1).Name));
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Not =>
            --  `not b` in this VM IS `b = 0`: a BOOLEAN is 0/1 (which is why
            --  Op_Btest is a no-op), so no new opcode is needed and §3a chose
            --  this deliberately.  Push_Int is +1 and Bin is -1, so the pair is
            --  depth-neutral.  Kept explicit rather than folded into Bc_Op: two
            --  instructions CAN be checked by a count, unlike a width choice, and
            --  a table entry saying Op_Not -> Eq would read as a mistake.
            O2c_BC.Push_Int (0);
            O2c_BC.Bin (O2c_BC.Eq);
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_And | Op_Or =>
            --  BOOLEAN and/or, where the width is not a question: a boolean is a
            --  word in this VM.
            O2c_BC.Bin (Bc_Op (Q.Op, O2c_Ir.Tc_Word));
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Set_Union | Op_Set_Intersect | Op_Set_Diff
            | Op_Set_Symdiff | Op_Set_In =>
            --  A binary SET operator: both operands are already on the stack, and
            --  the opcode comes from Bc_Set's table rather than from a width.
            O2c_BC.Bin (Bc_Set (Q.Op));
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Set_Single =>
            --  The only UNARY one: it takes an element off the stack and leaves
            --  the singleton set, which is net zero, so the emitter's Un models
            --  it exactly as the hand-written site did.
            O2c_BC.Un (Bc_Set (O2c_Ir.Op_Set_Single));
            if Q.Dst /= No_Value then
               Store_Value (Q.Dst);
            end if;

         when Op_Load | Op_Store
            | Op_Addr_Local | Op_Return
            | Op_Halt =>
            --  Each arrives with the construct that needs it, and until then
            --  says so loudly and says WHICH op - the next stage reads this
            --  message rather than guessing where to start.
            raise Program_Error with "O2c_Ir_Lower: " & Op'Image (Q.Op)
              & " has no lowering yet";
      end case;

      N_Lowered := N_Lowered + 1;
   end Emit_Quad;

end O2c_Ir_Lower;
