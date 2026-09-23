#!/usr/bin/env python3
"""Fail-closed Runtime Foundation gate on already built artifacts."""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import subprocess
import sys
from check_provenance import ROOT,validate_app,validate_foundation

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report-dir',type=Path,default=ROOT/'build/runtime-evidence')
    a=p.parse_args();out=a.report_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    summary={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),'status':'running',
             'executed_at_utc':datetime.now(timezone.utc).isoformat(),'steps':[],'counts':{},
             'limitations':['The full native app and standalone smoke are libc-free; reference fixtures may use libc.',
                            'No ARM64/server/graph implementation or hardware verification.']}
    path=out/'runtime-summary.json'
    def save():path.write_text(json.dumps(summary,indent=2)+'\n')
    def step(name,cmd,report=None):
        print('+ '+' '.join(map(str,cmd)),flush=True)
        result=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,text=True,timeout=120)
        (out/(name+'.log')).write_text('$ '+' '.join(map(str,cmd))+'\n'+result.stdout+result.stderr)
        summary['steps'].append({'name':name,'exit_code':result.returncode});save()
        if result.returncode:raise RuntimeError(name+' failed: '+str(out/(name+'.log')))
        if report:
            data=json.loads(report.read_text())
            if data['failure_count']:raise RuntimeError(name+' reported failures')
            summary['counts'][name]=data['case_count']
    save()
    try:
        validate_app('asmlab','release');validate_app('asmlab-debug','debug')
        validate_app('asmlab-libc-reference','release','libc-reference');validate_foundation()
        for name,script in [('runtime-boundary','tests/runtime_boundary.py'),('runtime-unit','tests/runtime_suite.py'),
                            ('libc-reference-regression','tests/verify.py')]:
            report=out/(name+'.json');report.unlink(missing_ok=True)
            cmd=[sys.executable,script]
            if name=='libc-reference-regression':cmd+=[ROOT/'bin/asmlab-libc-reference']
            step(name,cmd+['--report',report],report)
        step('libc-reference-audit',['sh','tests/audit.sh',ROOT/'bin/asmlab-libc-reference','reference'])
        summary.update(status='passed',total_assertions=sum(summary['counts'].values()),failure_count=0)
        save();print(json.dumps(summary,indent=2));return 0
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as e:
        summary.update(status='failed',error=str(e));save();print(str(e),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
