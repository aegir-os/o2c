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
               when others =>
                  raise Program_Error with "O2c_Ir_Lower: no word form of "
                    & O2c_Ir.Op'Image (Op);
            end case;
         when O2c_Ir.Tc_Byte =>
            raise Program_Error with "O2c_Ir_Lower: "
              & O2c_Ir.Op'Image (Op) & " has no byte form";
      end case;
   end Bc_Op;

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
            Push_Value (Q.Src1);
            Store_Value (Q.Dst);

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
            Store_Value (Q.Dst);

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
            if Q.Imm_1 = 1 then
               --  Load_Idx_B is an op value, not a procedure: the emitter's
               --  Bin takes it, and [base, index] come off the stack.
               O2c_BC.Bin (O2c_BC.Load_Idx_B);
            else
               raise Program_Error with
                 "O2c_Ir_Lower: no indexed load of " & Q.Imm_1'Image
                 & " bytes";
            end if;
            Store_Value (Q.Dst);

         when Op_Discard =>
            O2c_BC.Discard;

         when Op_Label =>
            O2c_BC.Mark (Bc_Label_Of (Q.Dst));

         when Op_Jump =>
            O2c_BC.Jump (O2c_BC.Jmp, Bc_Label_Of (Q.Src1));

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
            Store_Value (Q.Dst);

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

         when Op_Not | Op_And | Op_Or | Op_Load | Op_Store
            | Op_Addr_Local | Op_Addr_Global | Op_Return
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
