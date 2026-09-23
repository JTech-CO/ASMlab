#!/usr/bin/env python3
"""Validate all inputs and runtime boundaries before executing dynamic tests."""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import subprocess
import sys
from check_provenance import ROOT,validate_app,validate_foundation

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report-dir',type=Path,default=ROOT/'build/dynamic-evidence')
    a=p.parse_args();out=a.report_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    summary={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),'status':'running','steps':[],
             'executed_at_utc':datetime.now(timezone.utc).isoformat()}
    path=out/'dynamic-summary.json'
    def save():path.write_text(json.dumps(summary,indent=2)+'\n')
    save()
    try:
        validate_app('asmlab','release');validate_app('asmlab-debug','debug')
        validate_app('asmlab-libc-reference','release','libc-reference');validate_foundation()
        report=out/'dynamic-workspace.json';report.unlink(missing_ok=True)
        cmd=[sys.executable,'tests/dynamic_workspace.py','--report',str(report)]
        result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=160)
        (out/'dynamic-workspace.log').write_text('$ '+' '.join(cmd)+'\n'+result.stdout+result.stderr)
        summary['steps'].append({'name':'dynamic-workspace','exit_code':result.returncode});save()
        if result.returncode:raise RuntimeError('Dynamic tests failed; see '+str(report))
        data=json.loads(report.read_text())
        if data['failure_count']:raise RuntimeError('Dynamic test report contains failures')
        summary.update(status='passed',total_assertions=data['case_count'],failure_count=0,
            empty_root_skipped=any('skipped' in x for x in data['evidence']['dynamic_empty_root']))
        save();print(json.dumps(summary,indent=2));return 0
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as e:
        summary.update(status='failed',error=str(e));save();print(str(e),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
