import struct, subprocess, sys

BIN = "extracted/Payload/DTPAIiPad.app/DTPAIiPad"
d = open(BIN, "rb").read()

assert d[:4] == b"\xcf\xfa\xed\xfe", "not 64-bit LE Mach-O"
ncmds = struct.unpack("<I", d[16:20])[0]
off = 32
symoff = nsyms = stroff = strsize = None
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack("<II", d[off:off+8])
    if cmd == 0x2:  # LC_SYMTAB
        symoff, nsyms, stroff, strsize = struct.unpack("<IIII", d[off+8:off+24])
    off += cmdsize

print("symtab:", symoff, nsyms, stroff, strsize, file=sys.stderr)

syms = []
for i in range(nsyms):
    p = symoff + i * 16
    strx, ntype, nsect, ndesc = struct.unpack("<IBBH", d[p:p+8])
    value = struct.unpack("<Q", d[p+8:p+16])[0]
    end = d.find(b"\x00", stroff + strx)
    name = d[stroff + strx:end].decode("utf-8", "ignore")
    if name:
        syms.append((name, ntype, value))

print("total symbols:", len(syms), file=sys.stderr)
open("recovered/symbols_raw.txt", "w").write("\n".join(f"{v:016x}\t{n}" for n, t, v in syms))

swift = [n for n, t, v in syms if n.lstrip("_").startswith("$s")]
objc = [n for n, t, v in syms if n.startswith("_OBJC_CLASS_$_") or n.startswith("_OBJC_METACLASS_$_")]
print("swift symbols:", len(swift), "objc classes:", len(objc), file=sys.stderr)

if swift:
    p = subprocess.run(["swift", "demangle"], input="\n".join(swift), text=True, capture_output=True)
    open("recovered/symbols_swift_demangled.txt", "w").write(p.stdout)
    print("demangled lines:", len(p.stdout.splitlines()), file=sys.stderr)

open("recovered/objc_classes.txt", "w").write("\n".join(sorted(set(objc))))
