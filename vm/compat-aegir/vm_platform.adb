--  Aegir body of VM_Platform: CLI.Init parses the args page (redirection
--  trailer, cwd) and CLI.Exit_With closes the redirects, so the VM's
--  output behaves like every other CLI program's.
with Ada.Text_IO;
with Aegir_User.CLI;
with Aegir_User.Files;
with Aegir_User.Syscalls;
with Aegir_Interface;
with Interfaces;

package body VM_Platform is

   --  The file server reports sizes, offsets and statuses as Unsigned_64, and
   --  these functions compare them.  The operators are not directly visible
   --  without this, and the three HOST suites never compile this file - only
   --  run_m1 does, which is how the omission was caught.
   use type Interfaces.Unsigned_64;

   procedure Init is
   begin
      Aegir_User.CLI.Init;
      --  Reached, not merely present: gprbuild builds only the units a main
      --  can reach, so a probe nothing calls is silently never compiled -
      --  which is how the first version of it passed while doing nothing.
      Aegir_Interface.Touch;
   end Init;

   function Resolve_Path (Path : String) return String is
   begin
      return Aegir_User.CLI.Resolve_Path (Path);
   end Resolve_Path;

   --  Guest wait for the image, in VM_IO's 100 ms steps.  Effectively
   --  "wait for it": the writer is o2c, a manifest sibling that compiles the
   --  whole 12-import demo before reaching its bytecode pass, and that takes
   --  minutes on this target - every finite guess here has been too small
   --  (10 s, 60 s, 300 s each expired first), and giving up early is
   --  indistinguishable from a missing image.  The wait is cheap: it polls
   --  and returns immediately once the image appears, and the boot itself
   --  bounds a process that would otherwise spin forever.
   function Max_Input_Attempts return Natural is
     (30000);
   --  50 min: longer than any boot

   function Image_Arg return String is
     (Aegir_User.CLI.Argument (1));
   --  CLI.Argument answers "" out of range, which is the no-argument case.

   --  Probe by OPENING, not Stat: Stat on the initrd volume has answered
   --  not-OK for a file that was staged, which is why o2c reads its own
   --  marker (HelloBc.mrk) instead of statting it.  Called once per run,
   --  so the unclosed handle is the one Get_Env already tolerates per call.
   function Wait_For_Default return Boolean is
      Size : Aegir_User.Files.U64;
   begin
      return Aegir_User.Files.Open
        ("RD0:Tests/O2cLib/VmWait.mrk", Size) = Aegir_User.Files.Status_Ok;
   end Wait_For_Default;

   --  The guest has an environment too: Aegir keeps variables as ENV:<Name>
   --  files, and M51's Env builtin reads and writes them through this very
   --  call.  So O2C_QUANTUM works here the same way it does on the host, and
   --  the guest test can be driven at a different quantum - which matters,
   --  because the guest is the only place the VM runs on the real target.
   function Quantum_Override return Natural is
      Raw : constant String := Aegir_User.CLI.Get_Env ("O2C_QUANTUM");
      N   : Natural := 0;
   begin
      --  Digits only, as on the host: a malformed value is ignored rather
      --  than guessed at, because a harness silently running at a quantum it
      --  did not ask for is worse than one that visibly did not take effect.
      if Raw'Length = 0 then
         return 0;
      end if;
      for C of Raw loop
         if C not in '0' .. '9' then
            return 0;
         end if;
      end loop;
      N := Natural'Value (Raw);
      return N;
   end Quantum_Override;

   procedure Delete_File (Path : String) is
      --  The file server's status is dropped on purpose: Oakwood's
      --  Files.Delete has no status to report, so surfacing one here would
      --  invent an API the dialect does not have.  A subsequent Stat is how a
      --  program finds out whether it worked.
      Status : constant Aegir_User.Files.U64 :=
        Aegir_User.Files.Delete (Path);
      pragma Unreferenced (Status);
   begin
      null;
   end Delete_File;

   procedure Rename_File (From, To : String) is
      Status : constant Aegir_User.Files.U64 :=
        Aegir_User.Files.Rename (From, To);
      pragma Unreferenced (Status);
   begin
      null;
   end Rename_File;

   --  Positioned file I/O.  Every one of these is the file server's own call,
   --  with its status mapped onto the dialect's convention (0 = success) and
   --  Stat onto its sentinel (-1 = no such file).  The Ada backend's emitted
   --  helpers do exactly this, and these mirror them so that both backends'
   --  Files behave the same in the guest.  Getting the AEGIR body of the seam
   --  wrong is the failure the three host suites cannot see: only run_m1
   --  builds this file.

   function Stat_File (Path : String) return Long_Integer is
      Sz : Aegir_User.Files.U64;
   begin
      Aegir_User.CLI.Init;
      if Aegir_User.Files.Stat (Path, Sz) /= Aegir_User.Files.Status_Ok then
         --  A bare volume root ("BD0:") is not a file, so Stat answers
         --  not-found for it even when the volume is mounted.  The Files
         --  module's Wait polls exactly that path, and the poll's
         --  400 x 2,000,000 spin is seconds for compiled code but minutes
         --  under the interpreter - the run looked hung at m8401.  The
         --  volume question has its own op: Volume_Info, the one the
         --  launcher's `await BD0:` uses.
         if Path'Length >= 2 and then Path (Path'Last) = ':' then
            declare
               Total, Free, Cluster : Aegir_User.Files.U64;
            begin
               if Aegir_User.Files.Volume_Info
                 (Path, Total, Free, Cluster) = Aegir_User.Files.Status_Ok
               then
                  return 0;
               end if;
            end;
         end if;
         return -1;
      end if;
      return Long_Integer (Sz);
   end Stat_File;

   function Read_File (Path : String; Offset : Long_Integer;
                       Buf : out String) return Integer is
      Ct : Aegir_User.Files.U64;
      St : Aegir_User.Files.U64;
      Lim : constant Aegir_User.Files.U64 :=
        Aegir_User.Files.U64 (Buf'Length);
   begin
      if Offset < 0 then
         return 1;
      end if;
      Aegir_User.CLI.Init;
      St := Aegir_User.Files.Read (Path, Aegir_User.Files.U64 (Offset),
                                   Buf'Address, Lim, Ct);
      if St /= Aegir_User.Files.Status_Ok then
         return Integer (St);
      end if;
      return 0;
   end Read_File;

   function Write_File (Path : String; Offset : Long_Integer;
                        Buf : String) return Integer is
      Ct : Aegir_User.Files.U64;
      St : Aegir_User.Files.U64;
      Lim : constant Aegir_User.Files.U64 :=
        Aegir_User.Files.U64 (Buf'Length);
   begin
      if Offset < 0 then
         return 1;
      end if;
      Aegir_User.CLI.Init;
      St := Aegir_User.Files.Write (Path, Aegir_User.Files.U64 (Offset),
                                    Buf'Address, Lim, Ct);
      if St /= Aegir_User.Files.Status_Ok then
         return Integer (St);
      end if;
      if Ct = 0 then
         return 1;
      end if;
      return 0;
   end Write_File;

   function Close_File (Path : String) return Integer is
      St : Aegir_User.Files.U64;
   begin
      Aegir_User.CLI.Init;
      St := Aegir_User.Files.Close (Path);
      if St /= Aegir_User.Files.Status_Ok then
         return Integer (St);
      end if;
      return 0;
   end Close_File;

   function Get_Env (Name : String) return String is
   begin
      return Aegir_User.CLI.Get_Env (Name);
   end Get_Env;

   procedure Set_Env (Name, Value : String) is
      Status : constant Aegir_User.CLI.U64 :=
        Aegir_User.CLI.Set_Env (Name, Value);
      pragma Unreferenced (Status);
   begin
      null;
   end Set_Env;

   function Arg_Get (N : Natural; Buf : out String) return Integer is
   begin
      --  Offset by one, the host's convention: the VM's own argument 1 is
      --  the image, so the interpreted program's Arg N is the CLI token
      --  N + 1.  (This used to be "no offset" because the manifest spawner
      --  could not pass an image at all; the CLI can.)
      if N < 1 or else N + 1 > Aegir_User.CLI.Arg_Count then
         return -1;
      end if;
      declare
         A : constant String := Aegir_User.CLI.Argument (Positive (N + 1));
         L : Natural := 0;
      begin
         for C of A loop
            exit when L = Buf'Last;
            L := L + 1;
            Buf (L) := C;
         end loop;
         return L;
      end;
   end Arg_Get;

   procedure Get_Line (S : out String; L : out Natural; E : out Boolean) is
   begin
      --  The same call the Ada backend's O2c_In_Load makes, so a program
      --  reading input behaves identically on both backends.
      Aegir_User.CLI.Get_Line (S, L, E);
   end Get_Line;

   procedure Put_Err (S : String) is
   begin
      Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, S);
   end Put_Err;

   procedure New_Line_Err is
   begin
      Ada.Text_IO.New_Line (Ada.Text_IO.Standard_Error);
   end New_Line_Err;

   function Arg_Count return Natural is
     (if Aegir_User.CLI.Arg_Count >= 1 then Aegir_User.CLI.Arg_Count - 1
      else 0);

   function Clock_Ms return Long_Integer is
      use type Aegir_User.Syscalls.U64;
      Sec, Ns : Aegir_User.Syscalls.U64;
   begin
      --  The Ada backend's generated O2c_In_Time body, called through the seam
      --  instead of inlined: same syscall, same units.
      Aegir_User.Syscalls.Read_Clock (Sec, Ns);
      return Long_Integer (Sec) * 1000 + Long_Integer (Ns / 1_000_000);
   end Clock_Ms;

   procedure Exit_With (Ok : Boolean) is
   begin
      if Ok then
         Aegir_User.CLI.Exit_With (Aegir_User.CLI.RC_Ok);
      else
         Aegir_User.CLI.Exit_With (Aegir_User.CLI.RC_Fail);
      end if;
   end Exit_With;

end VM_Platform;
