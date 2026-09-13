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
             "a global store lowers to two instructions");

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
      Before := O2c_BC.Insns;
      O2c_Ir_Lower.Emit_Quad ((Op => Op_Arg, Src1 => C5, others => <>));
      O2c_Ir_Lower.Emit_Quad ((Op => Op_Arg, Src1 => C5, others => <>));
      O2c_Ir_Lower.Emit_Quad
        ((Op => Op_Call_Native, Imm_1 => 1, Imm_2 => 2, others => <>));
      Check (O2c_BC.Insns = Before + 3,
             "two arguments and a native call lower to three instructions");

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
