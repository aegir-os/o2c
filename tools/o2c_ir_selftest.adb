--  Self-test for O2c_Ir's builders.
--
--  M1a's evidence - "all seven suites green, 52 corroborated, unchanged" - is
--  the right evidence for a SEAM and not enough for a builder: a package that
--  compiles and does nothing observable would pass it while its builders were
--  wrong.  This tool builds a small quad stream and checks what came back, then
--  checks the two paths that must RAISE rather than truncate.
--
--  It is deliberately self-checking: no golden file, exit status 0 or 1, so it
--  can run inside the existing host-tool suite.
with O2c_Bc;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;

with O2c_Ir; use O2c_Ir;
with O2c_Ir_Lower;

use type O2c_Bc.Op;

procedure O2c_Ir_Selftest is

   Fails : Natural := 0;

   procedure Check (Ok : Boolean; What : String) is
   begin
      if not Ok then
         Fails := Fails + 1;
         Put_Line (Standard_Error, "IR SELFTEST FAIL: " & What);
      end if;
   end Check;

   C7, T, G, T2 : Value_Id;
   L1, L2       : Label_Id;
   LV           : Value_Id;
   Q            : Quad_Info;
   V            : Value_Info;
   Raised       : Boolean;

begin
   Init (Max_Values => 64, Max_Quads => 64, Max_Labels => 8);
   Begin_Proc;

   --  Build:  t := 7 ; *g := t ; L1: if t < 10 goto L2 ; return t ; L2: halt
   C7 := Const_Int (7);
   T  := New_Temp (Typ => 1);
   G  := New_Global ("g", Typ => 1);
   T2 := New_Temp (Typ => 1);
   Emit (Op_Copy, T, C7);
   Emit (Op_Store, G, T);
   L1 := New_Label;
   L2 := New_Label;
   LV := Label_Value (L1);
   Emit (Op_Label, Dst => LV);
   Emit (Op_Lt, T2, T, C7);
   Emit (Op_Jump_False, Src1 => Label_Value (L2), Src2 => T2);
   Emit (Op_Return, Src1 => T);
   Emit (Op_Label, Dst => Label_Value (L2));
   Emit (Op_Halt);

   Check (Quad_Count = 8, "eight quads emitted");

   --  The quad stream, in order and three-address
   Q := Quad_At (1);
   Check (Q.Op = Op_Copy and then Q.Dst = T and then Q.Src1 = C7
          and then Q.Src2 = No_Value, "quad 1 is t := 7");
   Q := Quad_At (2);
   Check (Q.Op = Op_Store and then Q.Dst = G and then Q.Src1 = T,
          "quad 2 stores t through g");
   Q := Quad_At (5);
   Check (Q.Op = Op_Jump_False and then Q.Src2 = T2
          and then Q.Src1 /= No_Value, "quad 5 jumps on a value to a label");
   Q := Quad_At (8);
   Check (Q.Op = Op_Halt, "quad 8 halts");

   --  Value records keep what the front end put in them
   V := Value_At (C7);
   Check (V.Kind = V_Const_Int and then V.Int = 7, "the integer constant is 7");
   V := Value_At (T);
   Check (V.Kind = V_Temp and then V.Slots = 1, "a temp is one slot");
   V := Value_At (G);
   Check (V.Kind = V_Global and then To_String (V.Name) = "g",
          "the global kept its name");
   V := Value_At (LV);
   Check (V.Kind = V_Label, "a label value is a label");

   --  Begin_Proc restarts values and labels but NOT the quad stream: a consumer
   --  walks one procedure's run after another.
   declare
      Quads_Before : constant Natural := Quad_Count;
   begin
      Begin_Proc;
      Check (Quad_Count = Quads_Before, "Begin_Proc keeps the quad stream");
      Check (New_Temp (Typ => 1) = Value_Id (1),
             "Begin_Proc restarts value numbering");
   end;

   Dump;

   --  ---- the lowering, against the REAL emitter -------------------------
   --  A quad the front end would build for `x := 5`: one of M2's construct.
   --  The instruction counts are pinned on purpose - the point of a self-test
   --  is to notice when the lowering changes, not to tolerate it.
   declare
      Lx, Lg, C5 : Value_Id;
      Tp : Value_Id;
      Lw : Natural;
      Sl, P, Before : Natural;
      Raised2 : Boolean := False;
   begin
      Init;                       --  a fresh IR and a fresh emitter run
      Begin_Proc;
      Lx := New_Local ("x", Typ => 1);
      Lg := New_Global ("g", Typ => 1);
      C5 := Const_Int (5);

      O2c_BC.Begin_Mode;
      P := O2c_BC.Begin_Proc (1, 0);
      --  AFTER Begin_Proc, not before: interning a local allocates a frame
      --  slot, so the emitter requires an open procedure - which is the
      --  contract the compiler must respect too, and the reason this self-test
      --  ran red before it ran green.
      Sl := O2c_BC.Local ("x");
      Tp := New_Temp (Typ => 1);
      pragma Unreferenced (Sl, P);

      Before := O2c_BC.Insns;
      O2c_Ir_Lower.Emit_Quad
        ((Op => Op_Copy, Dst => Lx, Src1 => C5, Src2 => No_Value, others => <>));
      Check (O2c_BC.Insns = Before + 2, "x := 5 lowers to two instructions");
      Check (O2c_Ir_Lower.Lowered = 1, "the lowerer counted that quad");

      --  The same copy with NO Dst, which is the shape every expression has:
      --  the value lands on the operand stack and the caller consumes it from
      --  there, so the push is the whole quad.
      Before := O2c_BC.Insns;
      O2c_Ir_Lower.Emit_Quad
        ((Op => Op_Copy, Src1 => C5, Src2 => No_Value, others => <>));
      Check (O2c_BC.Insns = Before + 1,
             "a copy with no Dst is one push (got"
               & Natural'Image (O2c_BC.Insns - Before) & ")");

      Before := O2c_BC.Insns;
      O2c_Ir_Lower.Emit_Quad
        ((Op => Op_Copy, Dst => Lg, Src1 => C5, Src2 => No_Value, others => <>));
      Check (O2c_BC.Insns = Before + 2,
             "a global store lowers to two instructions (got"
               & Natural'Image (O2c_BC.Insns - Before) & ")");

      begin
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Jump, Dst => No_Value, Src1 => No_Value,
             Src2 => No_Value, others => <>));
      exception
         when Program_Error =>
            Raised2 := True;
      end;
      Check (Raised2, "an op with no lowering raises rather than passing");

      --  A native call: an Op_Arg run, then the call, whose arity must match
      --  the run.  The count is pinned: two arguments push, the call is one.
      --  The arguments are the CALLER's to push (Op_Arg only counts them), so
      --  the test pushes them the way the front end does and then checks that
      --  the call itself is one instruction.
      Before := O2c_BC.Insns;
      O2c_BC.Push_Int (7);
      O2c_BC.Push_Int (9);
      O2c_Ir_Lower.Emit_Quad ((Op => Op_Arg, Src1 => C5, others => <>));
      O2c_Ir_Lower.Emit_Quad ((Op => Op_Arg, Src1 => C5, others => <>));
      O2c_Ir_Lower.Emit_Quad
        ((Op => Op_Call_Native, Imm_1 => 1, Imm_2 => 2, others => <>));
      Check (O2c_BC.Insns = Before + 3,
             "two pushed arguments and a native call are three instructions (got"
               & Natural'Image (O2c_BC.Insns - Before) & ")");
      Check (O2c_BC.Insns /= Before + 5,
             "Op_Arg does NOT push a second copy");

      Raised2 := False;
      begin
         O2c_Ir_Lower.Emit_Quad ((Op => Op_Arg, Src1 => C5, others => <>));
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Call_Native, Imm_1 => 1, Imm_2 => 2, others => <>));
      exception
         when Program_Error =>
            Raised2 := True;
      end;
      Check (Raised2, "a native call whose arity disagrees raises");

      --  And the EMPTY Op_Arg run, which is what Out.Ln is: a native with no
      --  arguments.  The arity check has two boundaries and this is the one
      --  the corpus exercises in every fixture.
      Before := O2c_BC.Insns;
      O2c_Ir_Lower.Emit_Quad
        ((Op => Op_Call_Native, Imm_1 => 2, Imm_2 => 0, others => <>));
      Check (O2c_BC.Insns = Before + 1,
             "a no-argument native lowers to one instruction (got"
               & Natural'Image (O2c_BC.Insns - Before) & ")");

      Raised2 := False;
      begin
         O2c_Ir_Lower.Emit_Quad ((Op => Op_Arg, Src1 => C5, others => <>));
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Call_Native, Imm_1 => 2, Imm_2 => 0, others => <>));
      exception
         when Program_Error =>
            Raised2 := True;
      end;
      Check (Raised2, "an argument pushed at a no-argument native raises");

      --  ---- control flow: a label, a jump, a conditional jump ------------
      --  The emitter's label namespace belongs to the CALLER (the compiler has
      --  its own counter and the emitter has no allocator), so the test reserves
      --  the mapping itself - that IS the contract.
      declare
         L1, L2 : O2c_Ir.Label_Id;
         L3, L4 : O2c_Ir.Label_Id;   --  fresh ones: Mark twice is an error
         V1, V2 : Value_Id;
      begin
         L1 := O2c_Ir.New_Label;
         L2 := O2c_Ir.New_Label;
         V1 := O2c_Ir.Label_Value (L1);
         V2 := O2c_Ir.Label_Value (L2);
         O2c_Ir_Lower.Reserve_Label (L1, 101);
         O2c_Ir_Lower.Reserve_Label (L2, 102);
         L3 := O2c_Ir.New_Label;
         L4 := O2c_Ir.New_Label;
         O2c_Ir_Lower.Reserve_Label (L3, 103);
         O2c_Ir_Lower.Reserve_Label (L4, 104);

         O2c_Ir_Lower.Emit_Quad ((Op => Op_Label, Dst => V1, others => <>));
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad ((Op => Op_Jump, Src1 => V2, others => <>));
         Check (O2c_BC.Insns = Before + 1, "a jump is one instruction");

         --  And the four HELPERS a statement site uses, so the front end never
         --  touches the emitter's namespace: Mark, Jump, Jump_False, Jump_True.
         --  Each is one instruction, and the True/False pair must reach the
         --  right POLARITY - which a count cannot see, so the check is on the
         --  VM's opcode table: Jnz jumps when the top is NOT zero, Jz when it is
         --  (settled in 3be, and getting it backwards runs and is wrong).
         O2c_BC.Push_Int (1);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Mark (L3);
         --  ZERO, not one: the emitter's Mark records the label's position and
         --  emits nothing.  A count of one here would have meant a byte of code
         --  where a label is - so the check states the 0 the emitter's own
         --  Mark does, rather than the 1 the name invites.
         Check (O2c_BC.Insns = Before, "a Mark emits nothing (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");
         Before := O2c_BC.Insns;
         O2c_BC.Push_Int (1);
         O2c_Ir_Lower.Jump (L4);
         Check (O2c_BC.Insns = Before + 2,
                "the Jump helper is one push plus one jump");
         Before := O2c_BC.Insns;
         O2c_BC.Push_Int (1);
         O2c_Ir_Lower.Jump_False (L4);
         O2c_Ir_Lower.Jump_True (L4);
         Check (O2c_BC.Insns = Before + 3,
                "and the conditional pair is two pushes and two jumps (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         --  The CONDITION is the caller's push, like Op_Arg's argument: these
         --  ops declare their operands rather than emitting them.  The
         --  emitter's own depth check is what enforces that - it refused with
         --  "operand-stack underflow" until this push was added, which is a
         --  loud failure rather than a silent wrong jump.
         Before := O2c_BC.Insns;
         O2c_BC.Push_Int (1);
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Jump_False, Src1 => V2, others => <>));
         Check (O2c_BC.Insns = Before + 2,
                "a pushed condition and a conditional jump are two instructions (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         --  an unreserved label is refused, rather than jumping somewhere
         Raised2 := False;
         declare
            L3 : constant O2c_Ir.Label_Id := O2c_Ir.New_Label;
         begin
            begin
               O2c_Ir_Lower.Emit_Quad
                 ((Op => Op_Jump, Src1 => O2c_Ir.Label_Value (L3),
                   others => <>));
            exception
               when Program_Error =>
                  Raised2 := True;
            end;
         end;
         Check (Raised2, "a jump to an unreserved label raises");
      end;

      --  ---- the width choice, checked DIRECTLY -----------------------------
      --  An instruction count cannot tell Add from Radd, so the mapping is
      --  tested where it lives rather than inferred from what got emitted.
      Check (O2c_Ir_Lower.Bc_Op (Op_Add, Tc_Word) = O2c_BC.Add,
             "add at word width is Add");
      Check (O2c_Ir_Lower.Bc_Op (Op_Add, Tc_Real) = O2c_BC.Radd,
             "add at real width is Radd");
      Check (O2c_Ir_Lower.Bc_Op (Op_Lt, Tc_Real) = O2c_BC.Rlt,
             "a comparison follows its OPERAND's width, not the boolean result");
      Raised2 := False;
      begin
         declare
            X : constant O2c_BC.Op := O2c_Ir_Lower.Bc_Op (Op_Add, Tc_Byte);
            pragma Unreferenced (X);
         begin
            null;
         end;
      exception
         when Program_Error =>
            Raised2 := True;
      end;
      Check (Raised2, "an op with no byte form raises rather than guessing");

      --  ---- the four ops added for the Out.String loop --------------------
      declare
         Sl : constant Natural := O2c_BC.Local ("ls");
         Lt : Value_Id;
         --  A local NAMED IN A QUAD must already be declared with O2c_BC.Local:
         --  Local_Slot_Of looks the name up in the emitter's own table, and
         --  rightly refuses - by name - when it is missing.  This is the front
         --  end's side of the contract.
         Lt_Sl : constant Natural := O2c_BC.Local ("lt");
         pragma Unreferenced (Lt_Sl);
      begin
         Lt := New_Local ("lt", Typ => 1);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Load_Local, Dst => Lt, Imm_1 => Sl, others => <>));
         Check (O2c_BC.Insns = Before + 2,
                "a local load and its store are two instructions (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         --  And the load with no Dst: one instruction, the push itself.
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Load_Local, Imm_1 => Sl, others => <>));
         Check (O2c_BC.Insns = Before + 1,
                "a local load with no Dst is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         O2c_BC.Push_Int (7);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Store_Local, Src1 => C5, Imm_1 => Sl, others => <>));
         Check (O2c_BC.Insns = Before + 2,
                "a pushed value and a local store are two instructions (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         --  The OTHER store shape, and the one the parser actually uses: the
         --  value is already on the stack, named by a TEMP whose home is the
         --  stack.  Push_Value emits nothing for a temp, so the store is ONE
         --  instruction - which is what makes the IR route identical to the
         --  hand-written site it replaces.
         O2c_BC.Push_Int (7);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Store_Local, Src1 => Tp, Imm_1 => Sl, others => <>));
         Check (O2c_BC.Insns = Before + 1,
                "a store whose source IS the stack is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         O2c_BC.Push_Int (0);
         O2c_BC.Push_Int (1);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Load_Idx, Dst => Lt, Src1 => C5, Src2 => C5,
             Imm_1 => 1, others => <>));
         Check (O2c_BC.Insns = Before + 2,
                "an indexed byte load and its store are two instructions (got"
                & Natural'Image (O2c_BC.Insns - Before) & ")");

         Raised2 := False;
         begin
            O2c_BC.Push_Int (0);
            O2c_BC.Push_Int (1);
            O2c_Ir_Lower.Emit_Quad
              ((Op => Op_Load_Idx, Dst => Lt, Src1 => C5, Src2 => C5,
                Imm_1 => 4, others => <>));
         exception
            when Program_Error => Raised2 := True;
         end;
         Check (Raised2, "an indexed load of four bytes raises");

         --  The SIZE -> opcode choice is a MAPPING, not a count: Load_Idx_B and
         --  Load_Idx_I are one instruction each, so a count cannot tell them
         --  apart and only the table can.  (3bg settled Add/Radd the same way.)
         Check (O2c_Ir_Lower.Bc_Load_Idx (1) = O2c_BC.Load_Idx_B
                and then O2c_Ir_Lower.Bc_Load_Idx (8) = O2c_BC.Load_Idx_I,
                "a byte element loads with Load_Idx_B, a word with Load_Idx_I");
         Check (O2c_Ir_Lower.Bc_Store_Idx (1) = O2c_BC.Store_Idx_B
                and then O2c_Ir_Lower.Bc_Store_Idx (8) = O2c_BC.Store_Idx_I,
                "a byte element stores with Store_Idx_B, a word with Store_Idx_I");

         --  A WORD element load with NO Dst: the element IS the result and the
         --  surrounding expression consumes it from the operand stack, which is
         --  the shape every expression-site subscript has - so the quad adds no
         --  store.
         O2c_BC.Push_Int (0);
         O2c_BC.Push_Int (1);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad ((Op => Op_Load_Idx, Imm_1 => 8, others => <>));
         Check (O2c_BC.Insns = Before + 1,
                "a word element load with no Dst is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         --  And the store half: [base, index, value] are on the stack, and the
         --  store itself is one instruction.
         O2c_BC.Push_Int (0);
         O2c_BC.Push_Int (1);
         O2c_BC.Push_Int (7);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad ((Op => Op_Store_Idx, Imm_1 => 8, others => <>));
         Check (O2c_BC.Insns = Before + 1,
                "an indexed word store is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         --  The field kind -> opcode table: six ops, one instruction each, so
         --  only the table can be checked - the argument Bc_Load_Idx already
         --  has.  The KIND is the front end's fact, the opcode is the table's.
         Check
           (O2c_Ir_Lower.Bc_Fld (O2c_Ir_Lower.Fld_Int, False)
              = O2c_BC.Load_Fld_I
            and then O2c_Ir_Lower.Bc_Fld (O2c_Ir_Lower.Fld_Ptr, False)
              = O2c_BC.Load_Fld_P
            and then O2c_Ir_Lower.Bc_Fld (O2c_Ir_Lower.Fld_Real, False)
              = O2c_BC.Load_Fld_R,
            "an integer, pointer and real field LOAD pick the I, P and R op");
         Check
           (O2c_Ir_Lower.Bc_Fld (O2c_Ir_Lower.Fld_Int, True)
              = O2c_BC.Store_Fld_I
            and then O2c_Ir_Lower.Bc_Fld (O2c_Ir_Lower.Fld_Ptr, True)
              = O2c_BC.Store_Fld_P
            and then O2c_Ir_Lower.Bc_Fld (O2c_Ir_Lower.Fld_Real, True)
              = O2c_BC.Store_Fld_R,
            "and the STORE half picks the matching three");

         --  A lowering check for each half: [address] for a load, and
         --  [address, value] for a store, are already on the stack.
         O2c_BC.Push_Int (0);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Load_Fld, Imm_1 => 8, Imm_2 => 0, others => <>));
         Check (O2c_BC.Insns = Before + 1,
                "a field load is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         O2c_BC.Push_Int (7);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Store_Fld, Imm_1 => 8, Imm_2 => 1, others => <>));
         Check (O2c_BC.Insns = Before + 1,
                "a field store is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         --  And an ordinal that is NOT one of the three is refused: the three
         --  kinds are one instruction each, so a quiet wrong choice would be
         --  invisible everywhere else.
         Raised2 := False;
         begin
            O2c_Ir_Lower.Emit_Quad
              ((Op => Op_Load_Fld, Imm_1 => 8, Imm_2 => 9, others => <>));
         exception
            when Program_Error => Raised2 := True;
         end;
         Check (Raised2, "a field kind that is not one of the three raises");

         --  The BASE of a global object, where the interesting case is the one
         --  that emits NOTHING: Slots = 0 means the address is already on the
         --  stack, which is how a pointer base and an already-walked chain are
         --  expressed.  Counting instructions is the right check here - unlike
         --  the opcode choices above, the three cases have DIFFERENT counts.
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Addr_Global ("garr", 4);
         Check (O2c_BC.Insns = Before + 1,
                "a global run's base is one address instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Addr_Global ("garr", 4);
         Check (O2c_BC.Insns = Before + 1,
                "and the SAME name is the same run (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Addr_Global ("", 0);
         Check (O2c_BC.Insns = Before,
                "Slots = 0 with no offset emits NOTHING");

         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Addr_Global ("", 0, 16);
         Check (O2c_BC.Insns = Before + 2,
                "Slots = 0 with an offset steps into the object (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         --  The SET table: six ops, one instruction each, so only the table can
         --  be checked - and it is the table that made these their OWN quads
         --  rather than a Tc_Set width, because a BOOLEAN and a SET are both
         --  words and only the op can say which was meant.
         Check (O2c_Ir_Lower.Bc_Set (Op_Set_Union) = O2c_BC.Set_Union
                and then O2c_Ir_Lower.Bc_Set (Op_Set_Intersect)
                  = O2c_BC.Set_Intersect
                and then O2c_Ir_Lower.Bc_Set (Op_Set_Diff) = O2c_BC.Set_Diff
                and then O2c_Ir_Lower.Bc_Set (Op_Set_Symdiff)
                  = O2c_BC.Set_Symdiff
                and then O2c_Ir_Lower.Bc_Set (Op_Set_In) = O2c_BC.Set_In
                and then O2c_Ir_Lower.Bc_Set (Op_Set_Single) = O2c_BC.Set_Single,
                "the six SET operators map to the six emitter ops");

         Raised2 := False;
         begin
            declare
               X : constant O2c_Bc.Op := O2c_Ir_Lower.Bc_Set (Op_Add);
            begin
               pragma Unreferenced (X);
            end;
         exception
            when Program_Error => Raised2 := True;
         end;
         Check (Raised2, "a non-SET op asked of the SET table raises");

         --  BOOLEAN and/or live in the WIDTH table, at the only width a boolean
         --  has - and at a width that has no such form they raise.
         Check (O2c_Ir_Lower.Bc_Op (Op_And, Tc_Word) = O2c_BC.Band
                and then O2c_Ir_Lower.Bc_Op (Op_Or, Tc_Word) = O2c_BC.Bor,
                "BOOLEAN and/or pick Band and Bor at word width");
         Raised2 := False;
         begin
            declare
               X : constant O2c_Bc.Op := O2c_Ir_Lower.Bc_Op (Op_And, Tc_Real);
            begin
               pragma Unreferenced (X);
            end;
         exception
            when Program_Error => Raised2 := True;
         end;
         Check (Raised2, "and at a width with no form raises");

         --  And the lowering of each, BY COUNT: `not` is the pair §3a chose
         --  (`b = 0`), so it is TWO instructions while every other operator here
         --  is one - which is exactly why Op_Not is written out rather than
         --  folded into a table whose entries are all one instruction.
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Apply (Op_Not);
         Check (O2c_BC.Insns = Before + 2,
                "not lowers to the two instructions of b = 0 (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         O2c_BC.Push_Int (1);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Apply (Op_Set_Union);
         Check (O2c_BC.Insns = Before + 1,
                "a SET union is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         O2c_BC.Push_Int (1);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Apply (Op_Set_Single);
         Check (O2c_BC.Insns = Before + 1,
                "a SET singleton is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         O2c_BC.Push_Int (1);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Apply (Op_And);
         Check (O2c_BC.Insns = Before + 1,
                "a BOOLEAN and is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         --  An ARITHMETIC operator, where the class has to reach the lowering.
         --  A count cannot see it - Add and Radd are one instruction each - so
         --  the check is on the QUAD: Bin_Op must declare the left operand as a
         --  value that CARRIES the class, because that is the only place the
         --  width can live for an operand that was pushed without a value id.
         --  And OUTSIDE a procedure an operator is a no-op rather than a
         --  failure, because that is exactly where a CONSTANT declaration's
         --  expression is parsed and folded: its arithmetic is never needed (the
         --  use sites push the folded value) and a quad could not hold it, since
         --  a quad's operands live in a frame.
         O2c_BC.End_Proc;
         Raised2 := False;
         begin
            O2c_BC.Push_Int (1);
            Before := O2c_BC.Insns;
            Lw := O2c_Ir_Lower.Lowered;
            O2c_Ir_Lower.Bin_Op (Op_Add);
            O2c_Ir_Lower.Apply (Op_Set_Union);
            Check (O2c_BC.Insns = Before
                   and then O2c_Ir_Lower.Lowered = Lw,
                   "an operator outside a procedure emits nothing and lowers "
                     & "nothing");
         exception
            when others => Raised2 := True;
         end;
         Check (not Raised2, "and it does not raise either (a folded constant's "
                  & "expression reaches it)");
         O2c_BC.Begin_Mode;
         declare
            Reopen : constant Natural := O2c_BC.Begin_Proc (1, 0);
            pragma Unreferenced (Reopen);
         begin
            null;
         end;

         O2c_BC.Push_Int (1);
         O2c_BC.Push_Int (2);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Bin_Op (Op_Sub, Tc_Real);
         Check (O2c_BC.Insns = Before + 1,
                "a real subtraction is one instruction (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");
         Check (Quad_At (Quad_Id (Quad_Count)).Op = Op_Sub
                and then Quad_At (Quad_Id (Quad_Count)).Src1 /= No_Value
                and then Value_At (Quad_At (Quad_Id (Quad_Count)).Src1).Class
                  = Tc_Real,
                "the operator quad carries the operand CLASS, which is what the "
                  & "lowering picks Rsub from");

         O2c_BC.Push_Int (1);
         O2c_BC.Push_Int (2);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Bin_Op (Op_Sub);
         Check (O2c_BC.Insns = Before + 1
                and then Value_At (Quad_At (Quad_Id (Quad_Count)).Src1).Class
                  = Tc_Word,
                "and with no class argument it is a WORD operator (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");

         O2c_BC.Push_Int (1);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad ((Op => Op_Discard, others => <>));
         Check (O2c_BC.Insns = Before + 1, "a discard is one instruction");
      end;

      --  and the same choice through the LOWERING, on a value whose class IS
      --  real - the first version of this check said "a real add" while the
      --  class still defaulted to word, so it was exercising the word path.
      declare
         Lr : Value_Id;
      begin
         Lr := New_Local ("r", Typ => 1, Class => Tc_Real);
         declare
            Sl : constant Natural := O2c_BC.Local ("r");
            pragma Unreferenced (Sl);
         begin
            null;
         end;
         O2c_BC.Push_Int (1);
         O2c_BC.Push_Int (2);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Add, Dst => Lr, Src1 => C5, Src2 => C5, others => <>));
         Check (O2c_BC.Insns = Before + 2,
                "an add and a store are two instructions (got"
                  & Natural'Image (O2c_BC.Insns - Before) & ")");
      end;

      O2c_BC.End_Proc;
      O2c_BC.Finish;
   end;

   --  ---- procedure calls: Op_Call, the convention in one place ------------
   --  A call into a procedure in THIS image, as opposed to a native.  The
   --  callees are declared FIRST and closed: the emitter refuses two open
   --  frames at once, and declaring them is what gives Call_Proc the params it
   --  pops and the results it pushes - the depth model the test is checking
   --  against.  The caller is opened last because Emit_Quad requires an open
   --  procedure.
   declare
      P2, P0   : Natural;
      Tq       : Value_Id;
      Bq       : Natural;
      Bq_L     : Natural;
      Qc       : Quad_Id;
      Raised2  : Boolean := False;
   begin
      Init;
      Begin_Proc;
      O2c_BC.Begin_Mode;
      P2 := O2c_BC.Begin_Proc (2, 1);
      O2c_BC.End_Proc;
      P0 := O2c_BC.Begin_Proc (0, 0);
      O2c_BC.End_Proc;
      declare
         Caller : constant Natural := O2c_BC.Begin_Proc (0, 0);
         pragma Unreferenced (Caller);
      begin
         null;
      end;

      Tq := New_Temp (Typ => 1);

      --  The helper the front end will call: it DECLARES the arguments, emits
      --  the call, and lowers exactly those quads.  The argument values were
      --  pushed by the caller first, the way the front end pushes them while
      --  parsing - so the helper's own contribution is the CALL, one
      --  instruction, and three lowered quads.
      O2c_BC.Push_Int (7);
      O2c_BC.Push_Int (9);
      Bq := O2c_BC.Insns;
      Bq_L := O2c_Ir_Lower.Lowered;
      O2c_Ir_Lower.Call_Proc (P2, 2);
      Check (O2c_BC.Insns = Bq + 1,
             "a procedure call is one instruction (got"
               & Natural'Image (O2c_BC.Insns - Bq) & ")");
      Check (O2c_Ir_Lower.Lowered = Bq_L + 3,
             "the helper lowered the two arguments and the call");

      --  And the QUAD STREAM is the contract: the arguments are declared, and
      --  the call carries the id and the arity the lowering checks.
      Qc := Quad_Id (Quad_Count);
      Check (Quad_At (Qc).Op = Op_Call
             and then Quad_At (Qc).Imm_1 = P2
             and then Quad_At (Qc).Imm_2 = 2,
             "the call quad carries the callee's id and its arity");
      Check (Quad_At (Qc - 2).Op = Op_Arg and then Quad_At (Qc - 1).Op = Op_Arg
             and then Quad_At (Qc - 2).Dst = No_Value,
             "the arguments are DECLARED by Op_Arg, not pushed again");

      --  A declared arity that disagrees with the call is a front-end bug, and
      --  it must say so with the numbers - the native form's contract, kept.
      Raised2 := False;
      begin
         O2c_BC.Push_Int (7);
         O2c_Ir_Lower.Emit_Quad ((Op => Op_Arg, Src1 => Tq, others => <>));
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Call, Imm_1 => P2, Imm_2 => 2, others => <>));
      exception
         when Program_Error => Raised2 := True;
      end;
      Check (Raised2, "a procedure call whose arity disagrees raises");
      O2c_BC.Discard;             --  the argument that call never consumed

      --  The EMPTY run: a parameterless call, which is the most common
      --  statement in the language and the corpus's own boundary.
      Bq := O2c_BC.Insns;
      O2c_Ir_Lower.Call_Proc (P0, 0);
      Check (O2c_BC.Insns = Bq + 1,
             "a parameterless procedure call is one instruction (got"
               & Natural'Image (O2c_BC.Insns - Bq) & ")");

      --  A result the caller wants in a frame slot: CALL left it on the stack,
      --  and a temp's home IS the stack, so naming one adds NO instruction -
      --  which is why an expression-position call can declare a Dst and still
      --  emit exactly what the hand-written path did.
      O2c_BC.Push_Int (1);
      O2c_BC.Push_Int (2);
      O2c_Ir_Lower.Emit_Quad ((Op => Op_Arg, Src1 => Tq, others => <>));
      O2c_Ir_Lower.Emit_Quad ((Op => Op_Arg, Src1 => Tq, others => <>));
      Bq := O2c_BC.Insns;
      O2c_Ir_Lower.Emit_Quad
        ((Op => Op_Call, Dst => Tq, Imm_1 => P2, Imm_2 => 2, others => <>));
      Check (O2c_BC.Insns = Bq + 1,
             "a call whose result goes to a temp adds no instruction (got"
               & Natural'Image (O2c_BC.Insns - Bq) & ")");

      --  And an id the emitter does not know is refused by name rather than
      --  emitted as a call to nothing.  The front end keeps its own guard for
      --  Bc_Proc = 0 (with a much better message); this is the layer below it.
      Raised2 := False;
      begin
         O2c_Ir_Lower.Call_Proc (999, 0);
      exception
         when O2c_BC.Wrong_Construct => Raised2 := True;
      end;
      Check (Raised2, "a call to a procedure the emitter never opened raises");

      O2c_BC.End_Proc;
      O2c_BC.Finish;
   end;

   --  The two paths that must RAISE: a capacity overrun is reported, never
   --  truncated (the project's rule for capacity tables), and an out-of-range
   --  id is refused rather than silently answered.
   Raised := False;
   begin
      Init (Max_Values => 2, Max_Quads => 2, Max_Labels => 2);
      Begin_Proc;
      declare
         A : constant Value_Id := New_Temp (Typ => 1);
         B : constant Value_Id := New_Temp (Typ => 1);
         C : constant Value_Id := New_Temp (Typ => 1);
      begin
         pragma Unreferenced (A, B, C);
         null;
      end;
   exception
      when Program_Error =>
         Raised := True;
   end;
   Check (Raised, "a value-capacity overrun raises");

   Raised := False;
   begin
      Init;
      declare
         X : constant Quad_Info := Quad_At (Quad_Id (1));
         pragma Unreferenced (X);
      begin
         null;
      end;
   exception
      when Program_Error =>
         Raised := True;
   end;
   Check (Raised, "reading a quad that was never emitted raises");

   Init;

   if Fails = 0 then
      Put_Line ("ir selftest: PASS");
   else
      Put_Line (Standard_Error, "ir selftest: FAIL ("
                & Natural'Image (Fails) & " checks)");
      Set_Exit_Status (Failure);
   end if;
end O2c_Ir_Selftest;
