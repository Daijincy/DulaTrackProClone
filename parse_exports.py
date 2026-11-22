import struct, subprocess

d = open("extracted/Payload/DTPAIiPad.app/DTPAIiPad", "rb").read()
ncmds = struct.unpack("<I", d[16:20])[0]
off = 32
trie_off = trie_size = None
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack("<II", d[off:off+8])
    if cmd == 0x80000033:  # LC_DYLD_EXPORTS_TRIE
        trie_off, trie_size = struct.unpack("<II", d[off+8:off+16])
    if cmd == 0x80000022:  # LC_DYLD_INFO_ONLY
        _, _, _, _, eo, es = struct.unpack("<IIIIII", d[off+8:off+32])
        if trie_off is None:
            trie_off, trie_size = eo, es
    off += cmdsize

print("trie", trie_off, trie_size)

def uleb(b, i):
    r = 0; s = 0
    while True:
        x = b[i]; i += 1
        r |= (x & 0x7f) << s
        if not x & 0x80:
            return r, i
        s += 7

names = []
def walk(node_off, prefix):
    i = node_off
    tsize, i = uleb(d, i)
    if tsize:
        flags, i = uleb(d, i)
        if flags & 0x08:  # EXPORT_SYMBOL_FLAGS_REEXPORT
            _, i = uleb(d, i)
            j = d.find(b"\x00", i); i = j + 1
        else:
            _, i = uleb(d, i)          # address
            if flags & 0x10:           # STUB_AND_RESOLVER
                _, i = uleb(d, i)      # resolver
        names.append(prefix)
    nchild = d[i]; i += 1
    for _ in range(nchild):
        j = d.find(b"\x00", i)
        edge = d[i:j].decode("utf-8", "ignore")
        i = j + 1
        child_off, i = uleb(d, i)
        walk(trie_off + child_off, prefix + edge)

end = trie_off + trie_size
walk(0, "")
app = [n for n in names if "_$s" in n or n.startswith("_$s")]
print("total exports", len(names), "swift", len(app))
open("recovered/exports_swift_raw.txt", "w").write("\n".join(app))
if app:
    p = subprocess.run(["swift", "demangle"], input="\n".join(app), text=True, capture_output=True)
    open("recovered/exports_swift_demangled.txt", "w").write(p.stdout)
    print("demangled", len(p.stdout.splitlines()))
