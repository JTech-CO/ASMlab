"""Minimal read-only ELF64-LE inspection for trusted local build artifacts.
Development tool only; not an ASMlab runtime dependency.
"""
from __future__ import annotations
from pathlib import Path
import struct

class ELF64:
    def __init__(self, path: Path):
        self.data = path.read_bytes()
        h = struct.unpack_from('<16sHHIQQQIHHHHHH', self.data)
        if h[0][:6] != b'\x7fELF\x02\x01':
            raise ValueError('Expected ELF64 little-endian')
        self.type, self.machine = h[1], h[2]
        self.sections = []
        for i in range(h[12]):
            s = struct.unpack_from('<IIQQQQIIQQ', self.data, h[6] + i*h[11])
            self.sections.append(dict(zip(['nameoff','type','flags','addr','offset','size',
                                           'link','info','align','entsize'], s)))
        names = self.section_data(self.sections[h[13]])
        for s in self.sections:
            s['name'] = names[s['nameoff']:].split(b'\0',1)[0].decode()
        self.by_name = {s['name']: s for s in self.sections}
        self.symbols = {}
        tab = self.by_name.get('.symtab')
        if tab:
            strings = self.section_data(self.sections[tab['link']])
            for pos in range(tab['offset'], tab['offset']+tab['size'], tab['entsize']):
                n, info, other, section, value, size = struct.unpack_from('<IBBHQQ', self.data, pos)
                name = strings[n:].split(b'\0',1)[0].decode()
                if name and section and section < len(self.sections):
                    self.symbols[name] = (value, size, section)
    def section_data(self, section):
        return self.data[section['offset']:section['offset']+section['size']]
    def bytes_at_symbol(self, name: str, size: int) -> bytes:
        address, _, index = self.symbols[name]
        sec = self.sections[index]
        offset = sec['offset'] + address - sec['addr']
        if sec['type'] == 8 or offset < sec['offset'] or offset+size > sec['offset']+sec['size']:
            raise ValueError('Symbol range is not file-backed: '+name)
        return self.data[offset:offset+size]
