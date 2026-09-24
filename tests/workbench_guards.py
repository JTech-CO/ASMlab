#!/usr/bin/env python3
"""Verify fail-closed validation of workbench code, assembly specializations, and trace build identity."""
import argparse,json,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);a=p.parse_args();checks=[]
    with tempfile.TemporaryDirectory(prefix='asmlab workbench guard ') as td:
        root=Path(td)/'relocated project';shutil.copytree(ROOT,root,ignore=shutil.ignore_patterns('evidence','__pycache__','.git','*.lst','*.log','*.disassembly.txt'))
        paths=['bin/asmlab.build.json','src/platform/linux/terminal.asm','src/workbench.asm',
               'include/observation.inc','src/trace_v2.asm','build/release/rt-terminal.o','bin/asmlab-debug']
        def reset():
            for name in paths:shutil.copy2(ROOT/name,root/name)
        def gate():
            r=subprocess.run([sys.executable,'tools/workbench_gate.py','--check-only','--report-dir','build/wb-guards'],cwd=root,
                               capture_output=True,text=True,timeout=30)
            return r.returncode,json.loads((root/'build/wb-guards/workbench-summary.json').read_text())
        def mark(name,condition):checks.append({'name':name,'passed':bool(condition)})
        status,data=gate();mark('relocated_tree_integrity',status==0 and data['validation_only'] and not data['steps'])
        for name in paths[1:-1]:
            reset()
            with (root/name).open('ab') as f:f.write(b'\n; changed\n')
            status,data=gate();mark('reject_changed:'+name,status!=0 and not data['steps'])
        reset();path=root/'bin/asmlab.build.json';meta=json.loads(path.read_text());meta['source_build_id']='forged';path.write_text(json.dumps(meta))
        status,data=gate();mark('reject_wrong_trace_build_identity',status!=0 and not data['steps'])
        reset();(root/'bin/asmlab-debug').unlink();status,data=gate();mark('reject_missing_debug',status!=0 and not data['steps'])
        reset();path=root/'bin/asmlab.build.json';meta=json.loads(path.read_text());meta['commands'][-1].append('-lncurses');path.write_text(json.dumps(meta))
        status,data=gate();mark('reject_hidden_tui_library',status!=0 and not data['steps'])
    report={'case_count':len(checks),'failure_count':sum(not c['passed'] for c in checks),'checks':checks,
            'scope':'Integrity-only guard mode, not a duplicate execution of feature tests. Hashes are not signed attestations.'}
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    return int(bool(report['failure_count']))
if __name__=='__main__':raise SystemExit(main())
