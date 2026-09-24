#!/usr/bin/env python3
"""Run native, foundation, L3, and Dynamic Workspace and Observable Workbench gates; fail closed."""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from check_provenance import ROOT,validate_app,validate_foundation

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report-dir',type=Path,default=ROOT/'build/evidence')
    a=p.parse_args();out=a.report_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    result={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),'status':'running','steps':[],
            'executed_at_utc':datetime.now(timezone.utc).isoformat(),'remote_ci_executed':os.getenv('GITHUB_ACTIONS')=='true'}
    path=out/'release-summary.json'
    def save():path.write_text(json.dumps(result,indent=2)+'\n')
    save()
    try:
        validate_app('asmlab','release');validate_app('asmlab-debug','debug')
        validate_app('asmlab-libc-reference','release','libc-reference');validate_foundation()
        for label,script in [('native','tools/native_gate.py'),('runtime','tools/runtime_gate.py'),('l3','tools/l3_gate.py'),('dynamic','tools/dynamic_gate.py'),('workbench','tools/workbench_gate.py')]:
            r=subprocess.run([sys.executable,script,'--report-dir',str(out/label)],cwd=ROOT,text=True,capture_output=True,timeout=180)
            (out/(label+'.log')).write_text(r.stdout+r.stderr)
            result['steps'].append({'name':label,'exit_code':r.returncode});save()
            if r.returncode:raise RuntimeError(label+' gate failed; see '+str(out/(label+'.log')))
        native=json.loads((out/'native/gate-summary.json').read_text())
        runtime=json.loads((out/'runtime/runtime-summary.json').read_text())
        l3=json.loads((out/'l3/l3-summary.json').read_text())
        dynamic=json.loads((out/'dynamic/dynamic-summary.json').read_text())
        workbench=json.loads((out/'workbench/workbench-summary.json').read_text())
        result['workbench_assertions']=workbench['total_assertions']
        result.update(dynamic_assertions=dynamic['total_assertions'],dynamic_empty_root_skipped=dynamic['empty_root_skipped'])
        result.update(status='passed',l3_assertions=l3['total_assertions'],empty_root_skipped=l3['empty_root_skipped'],native_assertions=native['total_assertions'],
                      runtime_assertions=runtime['total_assertions'],
                      total_assertions=native['total_assertions']+runtime['total_assertions']+l3['total_assertions']+dynamic['total_assertions']+workbench['total_assertions'],failure_count=0)
        result['test_sources_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
               for p in sorted([*ROOT.glob('tests/**/*.py'),*ROOT.glob('tests/**/*.asm'),*ROOT.glob('tools/*.py')])}
        result['limitations']=['Counts include repeated corpus executions on different profiles/backends and ABI assertions; not unique mathematical cases.',
                               'Not formal correctness, complete memory safety, high-precision math certification or cross-platform verification.',
                               'Full production app is libc/CRT-free; development comparison binaries/fixtures may intentionally link libc.']
        save();print(json.dumps({k:v for k,v in result.items() if k!='test_sources_sha256'},indent=2));return 0
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as e:
        result.update(status='failed',error=str(e));save();print(str(e),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
