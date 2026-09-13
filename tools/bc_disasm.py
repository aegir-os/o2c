#!/usr/bin/env python3
"""Disassemble an .obc image's procedure bodies.

Built because 3co-3cu needed to compare two compiled bodies - `Files.New` in a builtin image
against `Lib2.New` in a user-library image - and the image carries no name map (sections 3/4/5/6
only, no EXPORT and no DEBUG), so there was no way to ask it which procedure was which.  Every
conclusion 3co-3cu reached was checked against this tool's output rather than inferred.

The opcode table is read from docs/obc-image.md rather than copied, so this cannot drift from the
spec: the spec's tables are the table.  Two traps in parsing them, both hit while building this:

  * the tables are space-ALIGNED, so the mnemonic cell is padded.  Requiring a single space after
    the closing backtick silently dropped the whole arithmetic and comparison group (0x30-0x5F),
    and the tool then stopped at the first ILT in a body;
  * the cell after the mnemonic is the OPERANDS when the table has an operand column (the typed
    opcodes) and the STACK EFFECT when it does not (arithmetic, comparisons, sets).  Taking widths
    from that one cell - `[^|]*` - is right in both cases; taking them from the rest of the line
    over-counts and misaligns every instruction after it.

Usage:  python3 tools/bc_disasm.py IMAGE.obc [PROC_INDEX ...]
        1-based procedure indices.  With none, the table is listed and the procedures shaped like
        one open formal and one result are disassembled - which is what Files.New and Files.Old
        are.  The module body's offset is printed either way (`entry`), since a program's own code
        is usually what is wanted and is not in the procedure candidates.
"""
import re
import struct
import sys

WIDTHS = {'u8': 1, 'u16': 2, 'u32': 4, 'i32': 4}
_rows = re.findall(r'^\|\s*(0x[0-9A-Fa-f]{2})\s*\|\s*`([A-Z0-9_]+)`\s*\|([^|]*)',
                   open('docs/obc-image.md', encoding='utf-8').read(), re.M)
OPS = {int(hx, 16): (nm, [WIDTHS[w] for w in re.findall(r'\b(u8|u16|u32|i32)\b', operands)])
       for hx, nm, operands in _rows}
assert len(OPS) > 110, "the spec's opcode table did not parse"


def sections(data):
    count = struct.unpack_from('<H', data, 12)[0]
    table = struct.unpack_from('<Q', data, 0x10)[0]
    out = {}
    for i in range(count):
        at = table + i * 24
        sid, _flags = struct.unpack_from('<II', data, at)
        off, size = struct.unpack_from('<QQ', data, at + 8)
        out[sid] = data[off:off + size]
    return out


def procs(code):
    """(code_off, frame_slots, n_params, n_results) per procedure, 1-based."""
    n = struct.unpack_from('<I', code, 0)[0]
    out = []
    for i in range(n):
        at = 4 + i * 24
        out.append((struct.unpack_from('<I', code, at)[0],
                    struct.unpack_from('<I', code, at + 4)[0],
                    struct.unpack_from('<H', code, at + 8)[0],
                    struct.unpack_from('<H', code, at + 10)[0]))
    return out


def body(code, table, index):
    starts = sorted(t[0] for t in table)
    low = table[index - 1][0]
    highs = [s for s in starts if s > low]
    return code[low:(highs[0] if highs else len(code))]


def disassemble(code, table, index):
    off, frame, npar, nres = table[index - 1]
    chunk = body(code, table, index)
    print("  proc %d: code_off=%d len=%d frame=%d params=%d results=%d"
          % (index, off, len(chunk), frame, npar, nres))
    pc = 0
    while pc < len(chunk):
        op = chunk[pc]
        if op not in OPS:
            print("   %5d: %02x  [?] - not in the spec's table" % (pc, op))
            return
        name, widths = OPS[op]
        start = pc
        pc += 1
        args = []
        for width in widths:
            args.append(int.from_bytes(chunk[pc:pc + width], 'little'))
            pc += width
        print("   %5d: %-16s %s" % (start, name, args if args else ''))


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    data = open(argv[0], 'rb').read()
    code = sections(data)[6]
    table = procs(code)
    want = [int(a) for a in argv[1:]]
    print("opcodes from the spec: %d   procedures: %d" % (len(OPS), len(table)))
    print("entry (module body) at code offset %d"
          % struct.unpack_from('<Q', data, 0x38)[0])
    if not want:
        for i, (off, frame, npar, nres) in enumerate(table, 1):
            if (npar, nres) == (2, 1):
                want.append(i)
    for i in want:
        disassemble(code, table, i)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
