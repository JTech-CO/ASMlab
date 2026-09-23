#!/usr/bin/env python3
"""Build the independent no-libc smoke and development-only runtime fixtures."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from build_native import ROOT, digest, tool, execute

def foundation_inputs() -> list[Path]:
    return sorted([*ROOT.glob('src/rt/**/*.asm'),*ROOT.glob('src/platform/**/*.asm'),
                   *ROOT.glob('include/**/*.inc'),*ROOT.glob('tests/runtime/*.asm'),
                   ROOT/'VERSION', ROOT/'Makefile', ROOT/'tools/build_foundation.py',
                   ROOT/'tools/build_native.py'])

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--nasm',default=os.environ.get('NASM','nasm'))
    p.add_argument('--ld',default=os.environ.get('LD','ld'))
    p.add_argument('--cc',default=os.environ.get('CC','cc'))
    a=p.parse_args()
    targets=['bin/asmlab-runtime-smoke','bin/tests/runtime-primitives.so',
             'bin/tests/runtime-faults.so','bin/tests/decimal-adapter.so','bin/tests/decimal-native.so']
    meta=ROOT/'bin/runtime-foundation.build.json'
    for s in targets:
        (ROOT/s).parent.mkdir(parents=True,exist_ok=True);(ROOT/s).unlink(missing_ok=True)
    meta.unlink(missing_ok=True)
    try:
        if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
            raise RuntimeError('Foundation build requires Linux x86-64.')
        nasm,ld,cc=tool(a.nasm),tool(a.ld),tool(a.cc)
        nv=execute(nasm+['-v'],capture=True)
        if not nv.startswith('NASM version '):raise RuntimeError('Not NASM: '+nv)
        folder=Path('build/runtime');(ROOT/folder).mkdir(parents=True,exist_ok=True)
        sources={'primitives':'src/rt/primitives.asm','integer':'src/rt/integer.asm',
                 'fd_io':'src/rt/fd_io.asm','syscalls':'src/platform/linux/syscalls.asm',
                 'start':'src/platform/linux/start.asm','smoke':'tests/runtime/smoke.asm',
                 'probe':'tests/runtime/abi_probe.asm','fake_syscalls':'tests/runtime/fake_syscalls.asm',
                 'libc_io':'src/rt/adapters/libc_io.asm',
                 'biguint':'src/rt/biguint.asm','decimal_parse':'src/rt/decimal_parse.asm',
                 'decimal_format':'src/rt/decimal_format.asm'}
        objects={};commands=[]
        for name,source in sources.items():
            obj=folder/(name+'.o')
            cmd=nasm+['-f','elf64','-Ox','-w+error','-I./','-o',str(obj),source]
            execute(cmd);commands.append(cmd)
            objects[name]={'source':source,'path':str(obj),'sha256':digest(ROOT/obj)}
        groups=[['start','smoke','primitives','integer','fd_io','syscalls'],
                ['primitives','integer','fd_io','syscalls','probe'],
                ['primitives','integer','fd_io','fake_syscalls','probe'],['libc_io','probe'],['biguint','decimal_parse','decimal_format','probe']]
        results=[]
        for i,(target,group) in enumerate(zip(targets,groups)):
            mapfile=folder/('target-'+str(i)+'.map')
            objpaths=[objects[k]['path'] for k in group]
            if i==3:
                cmd=cc+['-shared','-Wl,-Bsymbolic,-z,noexecstack,-z,relro,-z,now,--no-undefined',
                        '-Wl,-Map,'+str(mapfile),'-o',target]+objpaths
            else:
                cmd=ld+['-m','elf_x86_64','-z','noexecstack','--build-id=sha1','--no-undefined','-Map',str(mapfile)]
                if i:cmd+=['-shared','-Bsymbolic']
                else:cmd+=['-e','_start']
                cmd+=['-o',target]+objpaths
            execute(cmd);commands.append(cmd)
            results.append({'path':target,'sha256':digest(ROOT/target),'objects':group,
                            'link_map':str(mapfile),'link_map_sha256':digest(ROOT/mapfile),
                            'kind':'no-libc-smoke' if i==0 else 'development-only-shared-fixture'})
        data={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),
              'build_kind':'nasm-native-foundation',
              'built_at_utc':datetime.now(timezone.utc).isoformat(),
              'host':{'system':platform.system(),'machine':platform.machine(),'kernel':platform.release()},
              'assembler':{'command':nasm,'version':nv,'sha256':digest(Path(shutil.which(nasm[0])).resolve())},
              'linker':{'command':ld,'version':execute(ld+['--version'],capture=True).splitlines()[0]},
              'commands':commands,'objects':objects,'targets':results,
              'source_sha256':{str(f.relative_to(ROOT)):digest(f) for f in foundation_inputs()},
              'limitations':['Smoke is not the full math program.','Shared fixtures are test-only; decimal adapter intentionally uses libc.',
                             'No test pass is asserted by this build.']}
        meta.write_text(json.dumps(data,indent=2)+'\n')
        print('Built standalone foundation and development fixtures.')
        return 0
    except BaseException:
        for s in targets:(ROOT/s).unlink(missing_ok=True)
        meta.unlink(missing_ok=True);raise
if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as e:
        print('Foundation build failed: '+str(e),file=sys.stderr);raise SystemExit(1)
