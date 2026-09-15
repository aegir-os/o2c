--  vm: run an .obc image (M53).
--
--  The first argument names the image; anything after it is the interpreted
--  program's own argument list, which VM_Platform.Arg_Get exposes as Arg N.
--
--  With NO argument the image is a default, because a program spawned from
--  System/Manifest gets no arguments: that is how the in-guest test runs
--  the VM, on the image o2c itself wrote to BD0: in the same boot.  The
--  default is only RUN when the boot staged the wait marker
--  (VM_Platform.Wait_For_Default) - everywhere else no compiler is coming,
--  and polling for the default image looks like a hang, so the VM prints
--  its usage instead.
with Ada.Command_Line;
with Ada.Text_IO;
with OBC_VM;
with VM_Platform;

procedure VM_Main is
   use Ada.Command_Line;
   use type OBC_VM.Status;

   Default_Image : constant String := "BD0:VmGreet.obc";
   --  A path the user typed gets a short grace for create/rename races
   --  (5 s in VM_IO's 100 ms steps), not the manifest's wait: a typo must
   --  fail, not poll.
   Arg_Attempts  : constant Natural := 50;

   procedure Run_Image (Path : String; Attempts : Natural) is
      Full : constant String := VM_Platform.Resolve_Path (Path);
      St   : OBC_VM.Status;
   begin
      --  On STDERR: the VM's stdout is the interpreted program's output and
      --  nothing else, so anything of the VM's own (this line, diagnostics)
      --  goes to the diagnostics stream.  Still one write, so a concurrent
      --  writer cannot split it.
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "vm: running " & Full);
      St := OBC_VM.Run (Full, Attempts);
      if St = OBC_VM.Ok then
         VM_Platform.Exit_With (True);
      else
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "vm: " & OBC_VM.Image (St));
         VM_Platform.Exit_With (False);
      end if;
   end Run_Image;

begin
   VM_Platform.Init;
   OBC_VM.Set_Quantum (VM_Platform.Quantum_Override);
   if Argument_Count >= 1 then
      Run_Image (Argument (1), Arg_Attempts);
   elsif VM_Platform.Wait_For_Default then
      Run_Image (Default_Image, 0);
   else
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "usage: o2_vm <image.obc> [program args ...]");
      VM_Platform.Exit_With (False);
   end if;
end VM_Main;
