#!/usr/bin/env python3
"""Disassemble an .obc image's procedure bodies.

Built because 3co-3cr needed to compare two compiled bodies - `Files.New` in a builtin image
against `Lib2.New` in a user-library image - and the image carries no name map (sections 3/4/5/6
only, no EXPORT and no DEBUG), so there was no way to ask it which procedure was which.

The opcode table is read from docs/obc-image.md rather than copied, so this cannot drift from the
spec: the spec's table is the table.

Usage:  python3 tools/bc_disasm.py IMAGE.obc [PROC_INDEX ...]
        (no indices: list the procedure table and disassemble each candidate that has an open
         formal and a result, i.e. the shape Files.New and Files.Old have)
"""
import io
import re, struct, sys
#  Build the opcode table from the spec itself, so the tool cannot drift from it.
rows = re.findall(r'^\| (0x[0-9A-Fa-f]{2}) \| `([A-Z0-9_]+)` \| (.*?) \|', open('docs/obc-image.md',encoding='utf-8').read(), re.M)
OPS = {}
for hx, nm, operands in rows:
    widths = [w for w in re.findall(r'\b(u8|u16|u32|i32)\b', operands)]
    OPS[int(hx,16)] = (nm, [{'u8':1,'u16':2,'u32':4,'i32':4}[w] for w in widths])
print("opcodes from the spec: %d" % len(OPS))

def code_payload(d):
    sc = struct.unpack_from('<H', d, 12)[0]; stab = struct.unpack_from('<Q', d, 0x10)[0]
    for i in range(sc):
        o = stab + i*24
        sid, _ = struct.unpack_from('<II', d, o); off, sz = struct.unpack_from('<QQ', d, o+8)
        if sid == 6: return d[off:off+sz]
    raise SystemExit("no CODE section")

def procs(pay):
    n = struct.unpack_from('<I', pay, 0)[0]
    out = []
    for i in range(n):
        r = 4 + i*24
        co, fs, np = struct.unpack_from('<II H', pay, r)[0], struct.unpack_from('<I', pay, r+4)[0], struct.unpack_from('<H', pay, r+8)[0]
        nr = struct.unpack_from('<H', pay, r+10)[0]
        out.append((co, fs, np, nr))
    return out

def body(pay, ps, i):
    lo = ps[i][0]
    hi = min([ps[k][0] for k in range(len(ps)) if ps[k][0] > lo] or [len(pay)])
    return pay[lo:hi]

def dis(pay, ps, i, limit=60):
    code = body(pay, ps, i); print("  proc %d: code_off=%d len=%d frame=%d params=%d results=%d"
          % (i+1, ps[i][0], len(code), ps[i][1], ps[i][2], ps[i][3]))
    pc = 0; shown = 0
    while pc < len(code) and shown < limit:
        op = code[pc]; nm, ws = OPS.get(op, ('?', []))
        if nm == '?': print("   %5d: %02x  [?]" % (pc, op)); return
        pc += 1; args = []
        for w in ws:
            v = int.from_bytes(code[pc:pc+w], 'little'); args.append(v); pc += w
        print("   %5d: %-14s %s" % (pc-1, nm, args if args else ''))
        shown += 1

for name, path in (('FILES(image with Files flipped)','/tmp/fn3.obc'), ('LIB(the Lib2 image)','/tmp/xm2.obc')):
    pay = code_payload(open(path,'rb').read()); ps = procs(pay)
    print("== %s: %d procs" % (name, len(ps)))
    for i,(co,fs,np,nr) in enumerate(ps):
        if (np,nr)==(2,1) and fs==4:
            print("  candidate: proc %d" % (i+1)); dis(pay, ps, i, 26)
