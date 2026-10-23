"""Read the supported architectures from thin or universal 64-bit Mach-O bytes."""
from pathlib import Path
import struct
import sys

CPU_NAMES = {0x01000007: "x86_64", 0x0100000C: "arm64"}
THIN = {b"\xcf\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xcf": ">"}
FAT = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
       b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}


def architectures(data: bytes) -> frozenset[str]:
    if len(data) < 8:
        raise ValueError("Truncated Mach-O header")
    magic = data[:4]
    if magic in THIN:
        cpu = struct.unpack_from(THIN[magic] + "I", data, 4)[0]
        if cpu not in CPU_NAMES:
            raise ValueError("Unsupported Mach-O CPU type")
        return frozenset((CPU_NAMES[cpu],))
    if magic not in FAT:
        raise ValueError("Not a supported 64-bit Mach-O")
    endian, wide = FAT[magic]
    count = struct.unpack_from(endian + "I", data, 4)[0]
    entry_size = 32 if wide else 20
    table_end = 8 + count * entry_size
    if not 1 <= count <= 16 or table_end > len(data):
        raise ValueError("Invalid universal Mach-O architecture table")
    names, ranges = set(), []
    for index in range(count):
        entry = 8 + index * entry_size
        cpu = struct.unpack_from(endian + "I", data, entry)[0]
        offset, size = struct.unpack_from(endian + ("QQ" if wide else "II"), data, entry + 8)
        if cpu not in CPU_NAMES or CPU_NAMES[cpu] in names:
            raise ValueError("Unsupported or repeated universal Mach-O CPU type")
        if offset < table_end or size < 8 or offset + size > len(data):
            raise ValueError("Universal Mach-O slice is outside the archive")
        if any(offset < end and offset + size > start for start, end in ranges):
            raise ValueError("Overlapping universal Mach-O slices")
        slice_arch = architectures(data[offset:offset + size])
        if slice_arch != frozenset((CPU_NAMES[cpu],)):
            raise ValueError("Universal Mach-O slice CPU differs from its header")
        names.add(CPU_NAMES[cpu])
        ranges.append((offset, offset + size))
    return frozenset(names)


def label(names: frozenset[str]) -> str:
    return "universal" if names == frozenset(("arm64", "x86_64")) else next(iter(names))


if __name__ == "__main__":
    print(label(architectures(Path(sys.argv[1]).read_bytes())))
