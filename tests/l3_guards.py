#!/usr/bin/env python3
"""Reject tampered/missing L3 conversion and link artifacts before executing them."""
import argparse,json,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);a=p.parse_args();checks=[]
    with tempfile.TemporaryDirectory(prefix='asmlab L3 gate ') as td:
        r=Path(td)/'project with spaces';shutil.copytree(ROOT,r,ignore=shutil.ignore_patterns('evidence','__pycache__','.git','*.lst','*.log','*.disassembly.txt'))
        paths=['bin/asmlab.build.json','bin/runtime-foundation.build.json','bin/tests/decimal-native.so',
               'build/release/rt-decimal-parse.o','build/release/asmlab.map','src/rt/decimal_parse.asm']
        def reset():
            for name in paths:shutil.copy2(ROOT/name,r/name)
        def gate():
            run=subprocess.run([sys.executable,'tools/l3_gate.py','--report-dir','build/l3-guards'],cwd=r,capture_output=True,text=True,timeout=60)
            data=json.loads((r/'build/l3-guards/l3-summary.json').read_text());return run.returncode,data
        def mark(name,ok):checks.append({'name':name,'passed':bool(ok)})
        status,data=gate();mark('relocated_l3_tree_verifies',status==0)
        for name in ['bin/tests/decimal-native.so','build/release/rt-decimal-parse.o','build/release/asmlab.map','src/rt/decimal_parse.asm']:
            reset()
            with (r/name).open('ab') as f:f.write(b'\n# tamper\n')
            status,data=gate();mark('reject_before_execution:'+name,status!=0 and not data['steps'])
        reset();path=r/'bin/asmlab.build.json';m=json.loads(path.read_text());m['commands'][-1].append('-lc');path.write_text(json.dumps(m))
        status,data=gate();mark('hidden_library_link_argument_rejected',status!=0 and not data['steps'])
        reset();path=r/'bin/runtime-foundation.build.json';m=json.loads(path.read_text());next(t for t in m['targets'] if t['path']=='bin/tests/decimal-native.so')['objects'].append('libc_io');path.write_text(json.dumps(m))
        status,data=gate();mark('libc_in_native_decimal_fixture_rejected',status!=0 and not data['steps'])
        reset();(r/'bin/tests/decimal-native.so').unlink();status,data=gate()
        mark('missing_decimal_fixture_rejected',status!=0 and not data['steps'])
        reset();run=subprocess.run([sys.executable,'tools/build_native.py','--profile','release','--nasm','/not-here/nasm'],cwd=r,capture_output=True,timeout=10)
        mark('missing_nasm_clears_stale_l3_binary',run.returncode!=0 and not (r/'bin/asmlab').exists())
    report={'case_count':len(checks),'failure_count':sum(not x['passed'] for x in checks),'checks':checks}
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));return int(bool(report['failure_count']))
if __name__=='__main__':raise SystemExit(main())
