#!/usr/bin/env python3
"""Regress universal slices and the matching signed-update hardware metadata."""
from pathlib import Path
import base64
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from macho import architectures, label

ROOT = Path(__file__).resolve().parent.parent


def thin(cpu):
    return bytes.fromhex("cffaedfe") + struct.pack("<I", cpu) + bytes(24)


def universal(wide=False, endian=">"):
    magic = bytes.fromhex("cafebabf" if wide else "cafebabe")
    if endian == "<":
        magic = magic[::-1]
    entry_format = endian + ("IIQQII" if wide else "IIIII")
    data = bytearray(0x220)
    data[:8] = magic + struct.pack(endian + "I", 2)
    for index, (cpu, offset) in enumerate(((0x0100000C, 0x100), (0x01000007, 0x200))):
        values = (cpu, 0, offset, 32, 8, 0) if wide else (cpu, 0, offset, 32, 8)
        entry = struct.pack(entry_format, *values)
        start = 8 + index * len(entry)
        data[start:start + len(entry)] = entry
        data[offset:offset + 32] = thin(cpu)
    return bytes(data)


class DistributionTests(unittest.TestCase):
    def test_supported_thin_and_universal_headers(self):
        self.assertEqual(architectures(thin(0x0100000C)), {"arm64"})
        self.assertEqual(architectures(thin(0x01000007)), {"x86_64"})
        for wide in (False, True):
            for endian in ("<", ">"):
                self.assertEqual(architectures(universal(wide, endian)), {"arm64", "x86_64"})
                self.assertEqual(label(architectures(universal(wide, endian))), "universal")

    def test_invalid_or_incomplete_architecture_tables_are_rejected(self):
        for data in (b"", b"not a Mach-O", thin(123), universal()[:100]):
            with self.assertRaises(ValueError):
                architectures(data)
        for offset, value in ((8, 0x01000007), (36, 0x100), (40, 0xFFFFFF)):
            data = bytearray(universal())
            struct.pack_into(">I", data, offset, value)
            with self.assertRaises(ValueError):
                architectures(bytes(data))

    def test_appcast_accepts_matching_hardware_and_rejects_wrong_restrictions(self):
        namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
        info = {"CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "20", "LSMinimumSystemVersion": "26.0"}
        with tempfile.TemporaryDirectory(prefix="keypin-distribution-") as directory:
            root = Path(directory)
            plist = root / "Info.plist"
            plist.write_bytes(plistlib.dumps(info))
            for binary, suffix, hardware, succeeds in (
                (universal(), "universal", "", True),
                (universal(), "universal", "arm64", False),
                (thin(0x0100000C), "arm64", "arm64", True),
                (thin(0x0100000C), "arm64", "", False),
                (thin(0x01000007), "x86_64", "", True),
                (thin(0x01000007), "x86_64", "arm64", False),
                (thin(0x0100000C), "universal", "arm64", False),
            ):
                archive = root / f"KeyPin-1.2.3-{suffix}.zip"
                with zipfile.ZipFile(archive, "w") as package:
                    package.writestr("KeyPin.app/Contents/MacOS/keypin", binary)
                restriction = f"<sparkle:hardwareRequirements>{hardware}</sparkle:hardwareRequirements>" if hardware else ""
                signature = base64.b64encode(bytes(64)).decode()
                feed = root / "appcast.xml"
                feed.write_text(f'<rss xmlns:sparkle="{namespace}"><channel><item><sparkle:version>20</sparkle:version><sparkle:shortVersionString>1.2.3</sparkle:shortVersionString><sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>{restriction}<enclosure url="https://github.com/mreasonyang/keypin/releases/download/v1.2.3/{archive.name}" length="{archive.stat().st_size}" sparkle:edSignature="{signature}" /></item></channel></rss>')
                result = subprocess.run([sys.executable, str(ROOT / "scripts/verify-appcast.py"), str(feed), str(archive), "v1.2.3", str(plist)], capture_output=True)
                self.assertEqual(result.returncode == 0, succeeds, (suffix, hardware))


if __name__ == "__main__":
    unittest.main()
