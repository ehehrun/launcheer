#!/usr/bin/env python3
"""Locate and verify Dock's local Launchpad preference initializer without loading it."""

import argparse
import bisect
import hashlib
from pathlib import Path
import re
import struct
import subprocess
import sys
import uuid


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique(values, description):
    require(len(values) == 1, f"Expected one {description}, found {len(values)}")
    return values[0]


def inspect(binary):
    data = binary.read_bytes()
    magic, count = struct.unpack_from(">II", data)
    require(magic == 0xCAFEBABE, "Expected a universal Mach-O Dock")
    slices = [struct.unpack_from(">iiIII", data, 8 + 20 * i) for i in range(count)]
    architecture = unique(
        [item for item in slices if item[0] == 0x0100000C and item[1] & 0xFFFFFF == 2],
        "arm64e slice",
    )
    slice_offset = architecture[2]
    header = struct.unpack_from("<IiiIIIII", data, slice_offset)
    require(header[0] == 0xFEEDFACF, "Expected a 64-bit arm64e Mach-O")
    position = slice_offset + 32
    bases, identities = [], []
    for _ in range(header[4]):
        command, size = struct.unpack_from("<II", data, position)
        if command == 0x19:
            segment = struct.unpack_from("<II16sQQQQiiII", data, position)
            if segment[2].rstrip(b"\0") == b"__TEXT":
                bases.append(segment[3])
        elif command == 0x1B:
            identities.append(uuid.UUID(bytes=data[position + 8:position + 24]))
        position += size
    base = unique(bases, "__TEXT segment")
    identity = unique(identities, "LC_UUID")

    def dyld(option):
        return subprocess.check_output(
            ["xcrun", "dyld_info", "-arch", "arm64e", option, str(binary)],
            text=True, stderr=subprocess.PIPE,
        )

    starts = [int(value, 16) for value in re.findall(
        r"^\s+(0x[0-9A-F]+)\s", dyld("-function_starts"), re.MULTILINE
    )]
    instructions = {}
    for line in dyld("-disassemble").splitlines():
        match = re.match(r"^(0x[0-9A-F]+)\s+(.*)", line)
        if match:
            instructions[int(match[1], 16)] = match[2].strip()

    def body(address):
        index = bisect.bisect_left(starts, address)
        require(index < len(starts) - 1 and starts[index] == address,
                f"No bounded function at {address:#x}")
        return [(offset, instructions[offset]) for offset in range(address, starts[index + 1], 4)]

    def calls(lines):
        return [match[1].strip('"') for _, line in lines
                if (match := re.match(r"(?:bl|b)\s+(\S+)", line))]

    init = int(unique(re.findall(
        r"^\s+(0x[0-9A-F]+)\s+-\[Springboard init\]$", dyld("-objc"), re.MULTILINE
    ), "Springboard.init implementation"), 16)
    init_body = body(init)
    candidates = []
    for site, line in init_body:
        match = re.match(r"bl\s+(0x[0-9a-f]+)$", line)
        if match and calls(body(int(match[1], 16))) == ["_dispatch_once"]:
            candidates.append((site, int(match[1], 16)))
    call_site, wrapper = unique(candidates, "local dispatch_once wrapper in Springboard.init")
    require(any(site < call_site and line == "retab" for site, line in init_body),
            "Preference wrapper is not in Springboard.init's cold path")
    require(any(re.match(rf"b\.\w+\s+{call_site:#x}$", line) for _, line in init_body),
            "Cold preference path has no conditional entry")
    require(re.match(r"b\s+0x[0-9a-f]+$", instructions[call_site + 4]),
            "Cold preference path does not return to initialization")

    wrapper_body = body(wrapper)

    def materialized_address(register):
        matches = []
        for index, (_, line) in enumerate(wrapper_body[:-1]):
            page = re.match(rf"adrp\s+{register},\s+-?\d+\s+; (0x[0-9a-f]+)$", line)
            addition = re.match(rf"add\s+{register}, {register}, #(0x[0-9a-f]+)$",
                                wrapper_body[index + 1][1])
            if page and addition:
                matches.append(int(page[1], 16) + int(addition[1], 16))
        return unique(matches, f"locally assigned {register} address")

    materialized_address("x0")  # dispatch_once token; the wrapper consumes no incoming arguments.
    block = materialized_address("x1")
    expected_wrapper = [
        r"pacibsp", r"stp\s+x29, x30, \[sp, #-0x10\]!", r"mov\s+x29, sp",
        r"adrp\s+x0,.*", r"add\s+x0, x0, #0x[0-9a-f]+",
        r"adrp\s+x1,.*", r"add\s+x1, x1, #0x[0-9a-f]+",
        r"bl\s+_dispatch_once", r"ldp\s+x29, x30, \[sp\], #0x10", r"retab",
    ]
    require(len(wrapper_body) == len(expected_wrapper)
            and all(re.fullmatch(pattern, line) for (_, line), pattern
                    in zip(wrapper_body, expected_wrapper)),
            "Preference wrapper has additional behavior or arguments")
    fixups = dyld("-fixups")
    require(any(f"{block:#x}".lower() in line.lower() and "__NSConcreteGlobalBlock" in line
                for line in fixups.splitlines()), "Preference callback is not a global block")
    callback = int(unique(re.findall(
        rf"^\s*\S+\s+\S+\s+0x{block + 16:X}\s+(?:auth-)?rebase\s+(0x[0-9A-F]+)",
        fixups, re.MULTILINE,
    ), "global block invoke fixup"), 16)
    callback_body = body(callback)
    preference_keys = re.findall(r'; @"([^"\n]+)"', "\n".join(line for _, line in callback_body))
    expected = ["eyecandy-show-borders", "springboard-reverse-scroll-gesture",
                "springboard-columns", "springboard-rows"]
    require(preference_keys == expected, f"Unexpected initializer preferences: {preference_keys}")
    callback_text = "\n".join(line for _, line in callback_body)
    for key, default in zip(expected, [0, 1, 7, 5]):
        require(re.search(rf'@"{re.escape(key)}".*?\bmov\s+w1, #0x{default:x}\b.*?\bbl\s+0x',
                          callback_text, re.DOTALL), f"Unexpected default for {key}")

    allowed_calls = {"_CFPreferencesCopyAppValue", "_objc_opt_class", "_objc_opt_isKindOfClass",
                     "_objc_retainAutoreleasedReturnValue", "_objc_autoreleaseReturnValue",
                     "_objc_release", "_objc_msgSend$boolValue", "_objc_msgSend$intValue",
                     "_objc_msgSend$objectForKeyedSubscript:"}
    pending, visited, read_domain = [callback], set(), False
    while pending:
        address = pending.pop()
        if address in visited:
            continue
        visited.add(address)
        function = body(address)
        read_domain |= any('; @"com.apple.dock"' in line for _, line in function)
        require(not any(re.match(r"(?:blr\w*|br|braa\w*|brab\w*)\s", line) for _, line in function),
                f"Indirect call in preference initializer at {address:#x}")
        function_addresses = {site for site, _ in function}
        for target in calls(function):
            if target.startswith("0x"):
                target_address = int(target, 16)
                if target_address not in function_addresses:
                    pending.append(target_address)
            else:
                require(target in allowed_calls, f"Initializer calls unsupported API {target}")
    require(read_domain, "Preference initializer does not read the com.apple.dock domain")
    return identity, wrapper - base, hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dock", type=Path,
                        default=Path("/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"))
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("NativeDockBuild.h"))
    args = parser.parse_args()
    identity, offset, digest = inspect(args.dock)
    uuid_bytes = ", ".join(f"0x{byte:02x}" for byte in identity.bytes)
    args.output.write_text(
        "// Generated by inspect_dock.py from the verified local arm64e Dock.\n"
        "#pragma once\n\n"
        f'#define NATIVE_DOCK_UUID_STRING "{identity}"\n'
        f"#define NATIVE_DOCK_UUID {{ {uuid_bytes} }}\n"
        f"#define NATIVE_DOCK_PREFS_WRAPPER_OFFSET 0x{offset:x}ULL\n"
        f'#define NATIVE_DOCK_SHA256 "{digest}"\n'
    )
    print(f"Verified arm64e Dock {identity}; wrote {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, struct.error, subprocess.CalledProcessError) as error:
        print(f"Incompatible Dock: {error}", file=sys.stderr)
        sys.exit(1)
