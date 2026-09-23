#!/usr/bin/env python3
"""Exercise fail-closed gate behavior in disposable copies of the project."""
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
    p=argparse.ArgumentParser();p.add_argument('--report',type=Path,default=ROOT/'build/gate-guards.json');a=p.parse_args()
    checks=[]
    with tempfile.TemporaryDirectory(prefix='asmlab gate ') as temp:
        r=Path(temp)/'relocated project'
        shutil.copytree(ROOT,r,ignore=shutil.ignore_patterns('build','evidence','__pycache__','.git'))
        def reset():
            for f in ['bin/asmlab','bin/asmlab-debug','bin/asmlab.build.json','bin/asmlab-debug.build.json','src/view.asm']:
                shutil.copy2(ROOT/f,r/f)
        def gate():
            return subprocess.run([sys.executable,'tools/native_gate.py','--report-dir','build/guards'],cwd=r,text=True,capture_output=True,timeout=60)
        def mark(name,ok):checks.append({'name':name,'passed':bool(ok)})
        result=gate();mark('relocated_tree_with_spaces_verifies',result.returncode==0)
        # Never execute a binary whose checksum no longer matches its sidecar.
        with (r/'bin/asmlab').open('ab') as f:f.write(b'tamper')
        result=gate();state=json.loads((r/'build/guards/gate-summary.json').read_text())
        mark('tampered_binary_is_rejected',result.returncode!=0 and state['status']=='failed' and not state['steps'])
        reset();meta=r/'bin/asmlab.build.json';v=json.loads(meta.read_text());v['build_kind']='gas-validation-bridge';meta.write_text(json.dumps(v))
        result=gate();mark('bridge_provenance_is_rejected',result.returncode!=0)
        reset();(r/'src/view.asm').write_text((r/'src/view.asm').read_text()+'\n; post-build source mutation\n')
        result=gate();mark('changed_build_input_is_rejected',result.returncode!=0)
        reset();(r/'bin/asmlab-debug.build.json').unlink();result=gate()
        mark('missing_profile_metadata_is_rejected',result.returncode!=0)
        reset();result=subprocess.run([sys.executable,'tools/build_native.py','--profile','release','--nasm','/nonexistent/asmlab-gate/nasm'],cwd=r,text=True,capture_output=True,timeout=20)
        mark('missing_nasm_fails_without_stale_release',result.returncode!=0 and not (r/'bin/asmlab').exists() and not (r/'bin/asmlab.build.json').exists())
    report={'schema_version':1,'case_count':len(checks),'failure_count':sum(not c['passed'] for c in checks),'checks':checks}
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    return int(report['failure_count']!=0)
if __name__=='__main__':raise SystemExit(main())
