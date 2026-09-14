module InputUse;
(*  Oakwood Input, called from a user program - the shape that needed a general
    answer: `Input.Available` has NO parentheses, and a bare qualified call had no
    branch, so it fell to MARKER_BARE_REFUSAL.

    Bare names are idiomatic Oberon - a builtin's own body is written in them
    throughout - so the marker now resolves the member instead of refusing it: a
    procedure whose code is in the image is an ordinary call, with the module's
    own WITH arranged for the Ada side.

    With no input, Available is In_C_Len - In_C_Pos + 1 = 0 (the +1 is the
    terminator when there IS content), and Read past the end is Character'Val (0)
    - both what the Ada helper returns. *)
import Out, Input;
var a: integer; c: char;
begin
  a := Input.Available;
  Input.Read (c);
  Out.Int (a, 0); Out.Int (ORD (c), 0); Out.Ln
end InputUse.
