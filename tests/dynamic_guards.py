#!/usr/bin/env python3
"""Fail-closed tests for dynamic allocator sources, objects, and fixture isolation."""
import argparse,json,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);a=p.parse_args();checks=[]
    with tempfile.TemporaryDirectory(prefix='asmlab dynamic gate ') as td:
        r=Path(td)/'project with spaces';shutil.copytree(ROOT,r,ignore=shutil.ignore_patterns('evidence','__pycache__','.git','*.lst','*.log','*.disassembly.txt'))
        paths=['bin/asmlab.build.json','bin/runtime-foundation.build.json','bin/tests/dynamic-memory.so',
               'build/release/rt-dynamic-memory.o','src/rt/dynamic_memory.asm','src/workspace_functions.asm']
        def reset():
            for name in paths:shutil.copy2(ROOT/name,r/name)
        def gate():
            run=subprocess.run([sys.executable,'tools/dynamic_gate.py','--report-dir','build/dynamic-guards'],cwd=r,capture_output=True,text=True,timeout=170)
            return run.returncode,json.loads((r/'build/dynamic-guards/dynamic-summary.json').read_text())
        def mark(name,ok):checks.append({'name':name,'passed':bool(ok)})
        status,data=gate();mark('relocated_dynamic_tree_verifies',status==0)
        for name in ['bin/tests/dynamic-memory.so','build/release/rt-dynamic-memory.o','src/rt/dynamic_memory.asm','src/workspace_functions.asm']:
            reset()
            with (r/name).open('ab') as f:f.write(b'\n# tamper\n')
            status,data=gate();mark('reject_before_execution:'+name,status!=0 and not data['steps'])
        reset();path=r/'bin/runtime-foundation.build.json';m=json.loads(path.read_text());next(t for t in m['targets'] if t['path']=='bin/tests/dynamic-memory.so')['objects'].append('libc_io');path.write_text(json.dumps(m))
        status,data=gate();mark('libc_in_allocator_fixture_rejected',status!=0 and not data['steps'])
        reset();(r/'bin/tests/dynamic-memory.so').unlink();status,data=gate();mark('missing_allocator_fixture_rejected',status!=0 and not data['steps'])
        reset();path=r/'bin/asmlab.build.json';m=json.loads(path.read_text());m['commands'][-1].append('-lc');path.write_text(json.dumps(m))
        status,data=gate();mark('hidden_libc_input_rejected',status!=0 and not data['steps'])
    report={'case_count':len(checks),'failure_count':sum(not x['passed'] for x in checks),'checks':checks}
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));return int(bool(report['failure_count']))
if __name__=='__main__':raise SystemExit(main())
