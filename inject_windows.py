#!/usr/bin/env python3
"""
inject_windows.py - Inject dylib vào Mach-O binary (Windows compatible)
Không cần macOS, chạy được trên Windows

Usage:
    python inject_windows.py <FreeFireMAX_binary> <dylib_path> <dylib_name>

Example:
    python inject_windows.py "Payload/FreeFireMAX.app/FreeFireMAX" "FFAimbot.dylib" "FFAimbot.dylib"
"""

import struct
import sys
import os
import shutil

# Mach-O constants
MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
LC_LOAD_DYLIB = 0x0000000C
LC_LOAD_WEAK_DYLIB = 0x00000018
LC_ID_DYLIB = 0x0000000D

def align(x, a):
    return ((x) + (a) - 1) & ~((a) - 1)

def read_macho(path):
    with open(path, 'rb') as f:
        return bytearray(f.read())

def write_macho(path, data):
    with open(path, 'wb') as f:
        f.write(data)

def parse_macho(data):
    magic = struct.unpack_from('<I', data, 0)[0]
    if magic == MH_CIGAM_64:
        le = False
    elif magic == MH_MAGIC_64:
        le = True
    else:
        raise ValueError(f"Not a valid Mach-O 64 binary (magic: 0x{magic:08X})")
    
    # Parse header
    hdr_fmt = '<I' if le else '>I'
    hdr_size = 32  # 64-bit header
    
    cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from(
        '<IIIIIIII' if le else '>IIIIIIII', data, 4
    )
    
    return {
        'magic': magic,
        'cputype': cputype,
        'cpusubtype': cpusubtype,
        'filetype': filetype,
        'ncmds': ncmds,
        'sizeofcmds': sizeofcmds,
        'flags': flags,
        'little_endian': le,
        'header_size': hdr_size,
        'load_commands_start': hdr_size,
    }

def find_load_commands(data, hdr):
    offset = hdr['load_commands_start']
    le = hdr['little_endian']
    fmt = '<II' if le else '>II'
    
    cmds = []
    for i in range(hdr['ncmds']):
        cmd, cmdsize = struct.unpack_from(fmt, data, offset)
        cmds.append({
            'cmd': cmd,
            'cmdsize': cmdsize,
            'offset': offset,
        })
        offset += cmdsize
    return cmds

def inject_dylib(binary_path, dylib_name):
    """Inject LC_LOAD_DYLIB vào Mach-O binary"""
    
    print(f"[*] Reading: {binary_path}")
    data = read_macho(binary_path)
    hdr = parse_macho(data)
    
    if not hdr['little_ending']:
        # We need little endian for iOS
        print("[!] Converting endianness...")
    
    le = hdr['little_endian']
    fmt_cmd = '<II' if le else '>II'
    
    # Parse existing load commands
    cmds = find_load_commands(data, hdr)
    
    # Check if dylib already injected
    for cmd in cmds:
        if cmd['cmd'] == LC_LOAD_DYLIB or cmd['cmd'] == LC_LOAD_WEAK_DYLIB:
            # Read dylib name
            off = cmd['offset'] + 24  # offset of dylib name
            name = data[off:cmd['offset'] + cmd['cmdsize']]
            name_str = name.split(b'\x00')[0].decode('utf-8', errors='replace')
            if dylib_name in name_str:
                print(f"[!] Dylib already injected: {name_str}")
                return
    
    # Tạo LC_LOAD_DYLIB command mới
    dylib_path_bytes = f"@executable_path/Frameworks/{dylib_name}".encode('utf-8') + b'\x00'
    dylib_path_len = len(dylib_path_bytes)
    dylib_path_padded = dylib_path_len
    # Align to 4 bytes
    if dylib_path_padded % 4 != 0:
        dylib_path_padded += 4 - (dylib_path_padded % 4)
    
    cmdsize = 24 + dylib_path_padded  # dylib_command size
    
    # dylib_command structure:
    #   uint32_t cmd       (LC_LOAD_DYLIB = 0xC)
    #   uint32_t cmdsize   (total size of this command)
    #   uint32_t dylib_name_offset (offset from start, usually 24)
    #   uint32_t dylib_timestamp
    #   uint32_t dylib_current_version
    #   uint32_t dylib_compatibility_version
    #   char     name[cmdsize - 24]
    
    new_cmd = bytearray(cmdsize)
    struct.pack_into('<II', new_cmd, 0, LC_LOAD_DYLIB, cmdsize)
    struct.pack_into('<I', new_cmd, 8, 24)  # name offset
    struct.pack_into('<I', new_cmd, 12, 2)  # timestamp
    struct.pack_into('<I', new_cmd, 16, 0x10000)  # current version (1.0.0)
    struct.pack_into('<I', new_cmd, 20, 0x10000)  # compatibility version (1.0.0)
    new_cmd[24:24 + dylib_path_len] = dylib_path_bytes
    # Pad with zeros
    for i in range(dylib_path_len, dylib_path_padded):
        new_cmd[24 + i] = 0
    
    # Chèn load command mới vào cuối vùng load commands
    insert_offset = hdr['load_commands_start'] + hdr['sizeofcmds']
    
    # Mở rộng vùng load commands
    new_data = bytearray(len(data) + cmdsize)
    new_data[:insert_offset] = data[:insert_offset]
    new_data[insert_offset:insert_offset + cmdsize] = new_cmd
    new_data[insert_offset + cmdsize:] = data[insert_offset:]
    
    # Cập nhật header
    struct.pack_into('<I' if le else '>I', new_data, 16, hdr['ncmds'] + 1)  # ncmds++
    struct.pack_into('<I' if le else '>I', new_data, 20, hdr['sizeofcmds'] + cmdsize)  # sizeofcmds
    
    # Ghi lại
    write_macho(binary_path, new_data)
    print(f"[+] Injected {dylib_name} into {os.path.basename(binary_path)}")
    print(f"[+] New ncmds: {hdr['ncmds'] + 1}, sizeofcmds: {hdr['sizeofcmds'] + cmdsize}")

def main():
    if len(sys.argv) < 3:
        print("Usage: python inject_windows.py <binary_path> <dylib_name>")
        print("Example: python inject_windows.py Payload/FreeFireMAX.app/FreeFireMAX libsubstrate.dylib")
        sys.exit(1)
    
    binary = sys.argv[1]
    dylib = sys.argv[2]
    
    if not os.path.exists(binary):
        print(f"[!] Binary not found: {binary}")
        sys.exit(1)
    
    # Backup
    backup = binary + ".bak"
    if not os.path.exists(backup):
        shutil.copy2(binary, backup)
        print(f"[*] Backup created: {backup}")
    
    inject_dylib(binary, dylib)

if __name__ == '__main__':
    main()
