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
      pragma Unreferenced (Sl, P);

      Before := O2c_BC.Insns;
      O2c_Ir_Lower.Emit_Quad
        ((Op => Op_Copy, Dst => Lx, Src1 => C5, Src2 => No_Value, others => <>));
      Check (O2c_BC.Insns = Before + 2, "x := 5 lowers to two instructions");
      Check (O2c_Ir_Lower.Lowered = 1, "the lowerer counted that quad");

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
         V1, V2 : Value_Id;
      begin
         L1 := O2c_Ir.New_Label;
         L2 := O2c_Ir.New_Label;
         V1 := O2c_Ir.Label_Value (L1);
         V2 := O2c_Ir.Label_Value (L2);
         O2c_Ir_Lower.Reserve_Label (L1, 101);
         O2c_Ir_Lower.Reserve_Label (L2, 102);

         O2c_Ir_Lower.Emit_Quad ((Op => Op_Label, Dst => V1, others => <>));
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad ((Op => Op_Jump, Src1 => V2, others => <>));
         Check (O2c_BC.Insns = Before + 1, "a jump is one instruction");

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

         O2c_BC.Push_Int (7);
         Before := O2c_BC.Insns;
         O2c_Ir_Lower.Emit_Quad
           ((Op => Op_Store_Local, Src1 => C5, Imm_1 => Sl, others => <>));
         Check (O2c_BC.Insns = Before + 2,
                "a pushed value and a local store are two instructions (got"
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
