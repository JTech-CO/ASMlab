#!/usr/bin/env python3
"""Development-only NASM build. Separately linked runtime boundary, no GAS fallback.
Production is linked directly by ld with no CRT/libc. cc is development-reference only.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]

APP_MODULES = [
 ('src/asmlab.asm','asmlab'), ('src/rt/primitives.asm','rt-primitives'),
 ('src/rt/integer.asm','rt-integer'), ('src/rt/biguint.asm','rt-biguint'),
 ('src/rt/decimal_parse.asm','rt-decimal-parse'), ('src/rt/decimal_format.asm','rt-decimal-format'),
 ('src/rt/fd_io.asm','rt-fd-io'), ('src/rt/adapters/app_io.asm','rt-app-io'),
 ('src/rt/console_format.asm','rt-console-format'),
 ('src/platform/linux/syscalls.asm','rt-syscalls'), ('src/platform/linux/app_start.asm','rt-app-start')]
REFERENCE_MODULES = [('src/asmlab.asm','asmlab'),
 ('dev/runtime/libc_primitives.asm','rt-primitives'), ('src/rt/adapters/libc_io.asm','rt-libc-io')]

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def build_inputs() -> list[Path]:
    """Record all project runtime sources, including the comparison adapter."""
    return sorted([*ROOT.glob('src/**/*.asm'), *ROOT.glob('include/**/*.inc'),
                   *ROOT.glob('dev/**/*.asm'), ROOT/'Makefile', ROOT/'VERSION',
                   ROOT/'tools/build_native.py'])

def execute(argv: list[str], *, capture: bool = False) -> str:
    if not capture:
        print('+ ' + shlex.join(argv), flush=True)
    r = subprocess.run(argv, cwd=ROOT, text=True, capture_output=capture, check=True)
    return r.stdout.strip() if capture else ''

def tool(spec: str) -> list[str]:
    parts = shlex.split(spec)
    if not parts or not shutil.which(parts[0]):
        raise RuntimeError(f'Required tool not found: {spec}. No automatic GAS fallback.')
    return parts

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile', choices=['debug','release'], required=True)
    p.add_argument('--backend', choices=['native','libc-reference'], default='native')
    p.add_argument('--nasm', default=os.environ.get('NASM','nasm'))
    p.add_argument('--ld', default=os.environ.get('LD','ld'))
    p.add_argument('--cc', default=os.environ.get('CC','cc'))
    a = p.parse_args()
    if a.backend == 'libc-reference' and a.profile != 'release':
        raise RuntimeError('The development reference uses release encoding only.')
    name = ('asmlab-libc-reference' if a.backend == 'libc-reference' else
            'asmlab-debug' if a.profile == 'debug' else 'asmlab')
    binary = Path('bin')/name
    metadata = ROOT/(str(binary)+'.build.json')
    (ROOT/'bin').mkdir(exist_ok=True)
    # Remove before tool lookup: failed builds must not appear to be old successes.
    (ROOT/binary).unlink(missing_ok=True); metadata.unlink(missing_ok=True)
    try:
        if platform.system() != 'Linux' or platform.machine() not in ('x86_64','amd64'):
            raise RuntimeError('Native build requires Linux x86-64; ARM/Pi/Windows is not implemented.')
        nasm = tool(a.nasm)
        linker = tool(a.cc) if a.backend == 'libc-reference' else tool(a.ld)
        nv = execute(nasm+['-v'],capture=True)
        if not nv.startswith('NASM version '):
            raise RuntimeError('Not a NASM executable: '+nv)
        version = (ROOT/'VERSION').read_text().strip()
        folder = Path('build')/('reference' if a.backend=='libc-reference' else a.profile)
        (ROOT/folder).mkdir(parents=True,exist_ok=True)
        modules = REFERENCE_MODULES if a.backend == 'libc-reference' else APP_MODULES
        flags = ['-f','elf64','-w+error'] + (['-O0','-g','-F','dwarf'] if a.profile=='debug' else ['-Ox'])
        if a.backend == 'libc-reference': flags += ['-DASMLAB_LIBC_REFERENCE=1']
        commands, objects = [], []
        for source, stem in modules:
            obj = folder/(stem+'.o'); listing = folder/(stem+'.lst')
            cmd = nasm+flags+['-I./','-l',str(listing),'-o',str(obj),source]
            execute(cmd); commands.append(cmd)
            objects.append({'source':source,'path':str(obj),'sha256':digest(ROOT/obj)})
        linkmap = folder/'asmlab.map'
        if a.backend == 'libc-reference':
            link = linker+['-no-pie','-Wl,-z,noexecstack,-z,relro,-z,now,--build-id=sha1',
                        '-Wl,-Map,'+str(linkmap),'-o',str(binary)]+[o['path'] for o in objects]
        else:
            link = linker+['-m','elf_x86_64','-static','--no-undefined','-z','noexecstack',
                         '--build-id=sha1','-e','_start','-Map',str(linkmap),'-o',str(binary)]+[o['path'] for o in objects]
        execute(link);commands.append(link)
        lp = shutil.which(linker[0]) or linker[0]
        report = {
            'schema_version':2,'project':'ASMlab','version':version,'profile':a.profile,
            'build_kind':'nasm-native','runtime_backend':a.backend,
            'built_at_utc':datetime.now(timezone.utc).isoformat(),
            'host':{'system':platform.system(),'machine':platform.machine(),
                    'kernel':platform.release(),'libc':list(platform.libc_ver())},
            'assembler':{'command':nasm,'version':nv,'sha256':digest(Path(shutil.which(nasm[0])).resolve())},
            'linker_driver':{'command':linker,'role':'cc reference only' if a.backend=='libc-reference' else 'direct ld'},
            'linker':{'path':lp,'version':execute([lp,'--version'],capture=True).splitlines()[0]},
            'commands':commands,'project_objects':objects,'binary':str(binary),
            'binary_sha256':digest(ROOT/binary),'link_map':str(linkmap),
            'link_map_sha256':digest(ROOT/linkmap),
            'source_sha256':{str(f.relative_to(ROOT)):digest(f) for f in build_inputs()},
            'runtime_level':'development-only libc reference' if a.backend=='libc-reference' else 'L3-Core; own entry, numeric conversion and I/O; no libc/CRT',
            'test_status':'not asserted by the build; run make test',
        }
        metadata.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
        if a.backend == 'native':
            temp = ROOT/'bin'/('.origin.'+a.profile+'.tmp')
            temp.write_text('ASMlab '+version+' - NASM native build\n'
                            'Default: NASM-only static ELF; own entry/runtime/decimal; no libc/CRT.\n'
                            'Build success is NOT test success. Run the full L3 gate.\n'
                            'Release/debug: bin/asmlab, bin/asmlab-debug; see *.build.json.\n'
                            'Reference: bin/asmlab-libc-reference is DEVELOPMENT ONLY.\n'
                            'Independent foundation smoke is NOT the full math application.\n')
            temp.replace(ROOT/'bin/BUILD_ORIGIN.txt')
        print(f'Built {binary}; SHA256 {report["binary_sha256"]}')
        return 0
    except BaseException:
        (ROOT/binary).unlink(missing_ok=True);metadata.unlink(missing_ok=True)
        raise
if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,RuntimeError,subprocess.CalledProcessError) as e:
        print('Native build failed: '+str(e),file=sys.stderr);raise SystemExit(1)
