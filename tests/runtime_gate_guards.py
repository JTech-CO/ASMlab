#!/usr/bin/env python3
"""Exercise Runtime Foundation fail-closed behavior in a disposable project copy."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report',type=Path,default=ROOT/'build/runtime-gate-guards.json')
    a=p.parse_args();checks=[]
    with tempfile.TemporaryDirectory(prefix='ASMlab runtime guard ') as td:
        r=Path(td)/'project relocated with spaces'
        shutil.copytree(ROOT,r,ignore=shutil.ignore_patterns('evidence','__pycache__','.git','*.lst','*.log','*.disassembly.txt'))
        def mark(name,ok):checks.append({'name':name,'passed':bool(ok)})
        def reset():
            for name in ['bin/asmlab-runtime-smoke','bin/tests/runtime-primitives.so',
                         'bin/runtime-foundation.build.json','bin/asmlab-libc-reference.build.json',
                         'src/rt/primitives.asm','build/runtime/integer.o']:
                shutil.copy2(ROOT/name,r/name)
        def gate():
            result=subprocess.run([sys.executable,'tools/runtime_gate.py','--report-dir','build/guards'],cwd=r,
                                  text=True,capture_output=True,timeout=90)
            return result,json.loads((r/'build/guards/runtime-summary.json').read_text())
        result,state=gate();mark('relocated_runtime_tree_verifies',result.returncode==0 and state['status']=='passed')
        for name in ['bin/asmlab-runtime-smoke','bin/tests/runtime-primitives.so','build/runtime/integer.o']:
            reset()
            with (r/name).open('ab') as f:f.write(b'tampered')
            result,state=gate()
            mark('reject_before_execution:'+name,result.returncode!=0 and state['status']=='failed' and not state['steps'])
        reset();path=r/'src/rt/primitives.asm';path.write_text(path.read_text()+'\n; changed after build\n')
        result,state=gate();mark('changed_nested_runtime_input_rejected',result.returncode!=0 and not state['steps'])
        reset();path=r/'bin/runtime-foundation.build.json';meta=json.loads(path.read_text());meta['source_sha256'].pop('src/rt/integer.asm');path.write_text(json.dumps(meta))
        result,state=gate();mark('incomplete_input_inventory_rejected',result.returncode!=0 and not state['steps'])
        reset();meta=json.loads(path.read_text());meta['targets'][0]['objects'].append('fake_syscalls');path.write_text(json.dumps(meta))
        result,state=gate();mark('fake_provider_cannot_be_declared_in_smoke',result.returncode!=0 and not state['steps'])
        reset();(r/'bin/asmlab-libc-reference.build.json').unlink()
        result,state=gate();mark('reference_provenance_required',result.returncode!=0 and not state['steps'])
        reset();result=subprocess.run([sys.executable,'tools/build_foundation.py','--nasm','/nonexistent/asmlab/nasm'],
                                      cwd=r,text=True,capture_output=True,timeout=20)
        gone=['bin/asmlab-runtime-smoke','bin/tests/runtime-primitives.so','bin/tests/runtime-faults.so',
              'bin/tests/decimal-adapter.so','bin/runtime-foundation.build.json']
        mark('missing_nasm_clears_all_stale_foundation_outputs',result.returncode!=0 and all(not(r/x).exists() for x in gone))
    report={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),'case_count':len(checks),
            'failure_count':sum(not x['passed'] for x in checks),'checks':checks}
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));return int(bool(report['failure_count']))
if __name__=='__main__':raise SystemExit(main())
