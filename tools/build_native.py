#!/usr/bin/env python3
"""Development-only NASM build with per-profile provenance. Never uses a bridge.
No C/C++ source is compiled by this script. GCC/cc is only the linker driver.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execute(argv: list[str], *, capture: bool = False) -> str:
    if not capture:
        print('+ ' + shlex.join(argv), flush=True)
    r = subprocess.run(argv, cwd=ROOT, text=True, capture_output=capture, check=True)
    return r.stdout.strip() if capture else ''


def tool(spec: str) -> list[str]:
    parts = shlex.split(spec)
    if not parts or not shutil.which(parts[0]):
        raise RuntimeError(f'Required tool not found: {spec}. Install NASM, GCC and binutils. '
                           'No automatic GAS fallback is provided.')
    return parts


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile', choices=['debug', 'release'], required=True)
    p.add_argument('--nasm', default=os.environ.get('NASM', 'nasm'))
    p.add_argument('--cc', default=os.environ.get('CC', 'cc'))
    a = p.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise RuntimeError('v0.1.1 native build requires Linux x86-64. ARM/Pi/Windows native is not implemented.')
    version = (ROOT / 'VERSION').read_text().strip()
    outdir = ROOT / 'build' / a.profile
    outdir.mkdir(parents=True, exist_ok=True)
    (ROOT / 'bin').mkdir(exist_ok=True)
    binary = Path('bin/asmlab' if a.profile == 'release' else 'bin/asmlab-debug')
    metadata = ROOT / (str(binary) + '.build.json')
    # Remove stale executable and provenance BEFORE building. Failure cannot leave
    # an older binary appearing to be the result of the failed build.
    (ROOT / binary).unlink(missing_ok=True)
    metadata.unlink(missing_ok=True)
    nasm, cc = tool(a.nasm), tool(a.cc)
    nasm_version = execute(nasm + ['-v'], capture=True)
    if not nasm_version.startswith('NASM version '):
        raise RuntimeError(f'Not a recognized NASM executable: {nasm_version!r}')
    obj = Path('build') / a.profile / 'asmlab.o'
    listing = Path('build') / a.profile / 'asmlab.lst'
    linkmap = Path('build') / a.profile / 'asmlab.map'
    # Default NASM warnings promoted to errors. Do not enable optional relocation
    # diagnostics (-Wall): cross-section ELF relocations are intentional here.
    flags = ['-f', 'elf64', '-w+error']
    flags += ['-O0', '-g', '-F', 'dwarf'] if a.profile == 'debug' else ['-Ox']
    assemble = nasm + flags + ['-I./', '-l', str(listing), '-o', str(obj), 'src/asmlab.asm']
    link = cc + ['-no-pie', '-Wl,-z,noexecstack,-z,relro,-z,now,--build-id=sha1',
                 '-Wl,-Map,' + str(linkmap), '-o', str(binary), str(obj)]
    execute(assemble)
    execute(link)
    paths = sorted(list(ROOT.glob('src/*.asm')) + list(ROOT.glob('include/*.inc'))
                   + [ROOT / 'Makefile', ROOT / 'VERSION', Path(__file__).resolve()])
    source_hashes = {str(f.relative_to(ROOT)): digest(f) for f in paths}
    ld_name = execute(cc + ['-print-prog-name=ld'], capture=True)
    ld_path = shutil.which(ld_name) or ld_name
    report = {
        'schema_version': 1, 'project': 'ASMlab', 'version': version,
        'profile': a.profile, 'build_kind': 'nasm-native',
        'built_at_utc': datetime.now(timezone.utc).isoformat(),
        'host': {'system': platform.system(), 'machine': platform.machine(),
                 'kernel': platform.release(), 'libc': list(platform.libc_ver())},
        'assembler': {'command': nasm, 'version': nasm_version,
                      'sha256': digest(Path(shutil.which(nasm[0])).resolve())},
        'linker_driver': {'command': cc, 'version': execute(cc + ['--version'], capture=True).splitlines()[0]},
        'linker': {'path': ld_path, 'version': execute([ld_path, '--version'], capture=True).splitlines()[0]},
        'commands': [assemble, link], 'project_object': str(obj),
        'object_sha256': digest(ROOT / obj), 'binary': str(binary),
        'binary_sha256': digest(ROOT / binary), 'link_map': str(linkmap),
        'link_map_sha256': digest(ROOT / linkmap),
        'source_sha256': source_hashes,
        'runtime_level': 'Level 2; libc/CRT retained; not L3-Core',
        'test_status': 'not asserted by the build; run make test',
    }
    metadata.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    origins = ['ASMlab ' + version + ' - NASM native build records',
               'Build success is not test success. See evidence/native/ for delivered tests.',
               'This is Level 2: libc and CRT are retained.',
               'Release: bin/asmlab + bin/asmlab.build.json',
               'Debug: bin/asmlab-debug + bin/asmlab-debug.build.json',
               'Each sidecar records inputs, tool versions, commands and binary SHA256.',
               'Missing binary/sidecar or a hash mismatch means that profile is not verified.']
    origin_tmp = ROOT / 'bin' / ('.origin.' + a.profile + '.tmp')
    origin_tmp.write_text('\n'.join(origins) + '\n')
    origin_tmp.replace(ROOT / 'bin/BUILD_ORIGIN.txt')
    print(f'Built {binary} ({a.profile}, NASM); SHA256 {report["binary_sha256"]}')
    return 0

if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as e:
        print('Native build failed: ' + str(e), file=sys.stderr)
        raise SystemExit(1)
