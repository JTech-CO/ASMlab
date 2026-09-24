#!/usr/bin/env python3
"""Fail-closed Observable Workbench gate, native Linux x86-64 only."""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import subprocess
import sys
from check_provenance import ROOT,validate_app

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report-dir',type=Path,default=ROOT/'build/workbench-evidence')
    p.add_argument('--check-only',action='store_true',help='Integrity validation only; no feature tests. For guard tests.')
    a=p.parse_args();out=a.report_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    summary={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),'status':'running','steps':[],
             'executed_at_utc':datetime.now(timezone.utc).isoformat(),'validation_only':a.check_only}
    path=out/'workbench-summary.json'
    def save():path.write_text(json.dumps(summary,indent=2)+'\n')
    save()
    try:
        validate_app('asmlab','release');validate_app('asmlab-debug','debug')
        counts={}
        if not a.check_only:
            tasks=[('release-observe',['tests/verify.py','bin/asmlab','--numeric-mode','observe']),
                   ('debug-observe',['tests/verify.py','bin/asmlab-debug','--numeric-mode','observe']),
                   ('observable-workbench',['tests/observable_workbench.py'])]
            for label,args in tasks:
                report=out/(label+'.json');report.unlink(missing_ok=True)
                cmd=[sys.executable,*args,'--report',str(report)]
                result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=150)
                (out/(label+'.log')).write_text('$ '+' '.join(cmd)+'\n'+result.stdout+result.stderr)
                summary['steps'].append({'name':label,'exit_code':result.returncode});save()
                if result.returncode:raise RuntimeError('Workbench gate failed: '+label)
                data=json.loads(report.read_text())
                if data['failure_count']:raise RuntimeError('Reported failures: '+label)
                counts[label]=data['case_count']
        summary.update(status='passed',counts=counts,total_assertions=sum(counts.values()),failure_count=0)
        save();print(json.dumps(summary,indent=2));return 0
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as e:
        summary.update(status='failed',error=str(e));save();print(str(e),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
