#!/usr/bin/env python3
"""Run the Native Gate against existing release/debug binaries. Fail closed.
A build sidecar is required; a GAS bridge cannot count as a passing native gate.
"""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import hashlib
from check_provenance import validate_app

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report-dir',type=Path,default=ROOT/'build/evidence')
    a=p.parse_args();out=a.report_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    summary={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),'status':'running',
             'executed_at_utc':datetime.now(timezone.utc).isoformat(),'steps':[],
             'native_regression_counts':{},'remote_ci_executed':os.environ.get('GITHUB_ACTIONS')=='true',
             'limitations':['Linux x86-64 process execution only; no other platform was tested by this gate.','Not a Level 3 runtime; libc and CRT are retained.',
                            'Not a Pi/ARM64, Windows-native or web-server implementation.']}
    path=out/'gate-summary.json'
    def save():path.write_text(json.dumps(summary,indent=2)+'\n')
    def step(name,cmd):
        print('+ '+' '.join(map(str,cmd)),flush=True)
        r=subprocess.run(list(map(str,cmd)),cwd=ROOT,text=True,capture_output=True,timeout=90)
        (out/(name+'.log')).write_text('$ '+' '.join(map(str,cmd))+'\n'+r.stdout+r.stderr)
        summary['steps'].append({'name':name,'exit_code':r.returncode})
        save()
        if r.returncode:raise RuntimeError(f'{name} failed; see {out/name}.log')
    save()
    try:
        for profile,filename in [('release','asmlab'),('debug','asmlab-debug')]:
            validate_app(filename,profile)
        for profile,filename in [('release','asmlab'),('debug','asmlab-debug')]:
            binary=ROOT/'bin'/filename
            target=out/(profile+'-regression.json');target.unlink(missing_ok=True)
            step(profile+'-regression',[sys.executable,'tests/verify.py',binary,'--report',target])
            report=json.loads(target.read_text())
            if report['failure_count'] or report['case_count']!=14410:
                raise RuntimeError('Original regression corpus failed or changed size: '+profile)
            summary['native_regression_counts'][profile]=report['case_count']
            step(profile+'-audit',['sh','tests/audit.sh',binary])
        target=out/'native-contract.json';target.unlink(missing_ok=True)
        step('native-contract',[sys.executable,'tests/native_contract.py','--report',target])
        contract=json.loads(target.read_text())
        if contract['failure_count']:raise RuntimeError('Native contract failures')
        summary.update({'status':'passed','native_contract_count':contract['case_count'],
                        'total_assertions':sum(summary['native_regression_counts'].values())+contract['case_count'],
                        'failure_count':0})
        # ELF dependency audits are separate pass/fail checks, not counted above.
        save();print(json.dumps(summary,indent=2));return 0
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as e:
        summary.update({'status':'failed','error':str(e)});save()
        print(str(e),file=sys.stderr);return 1

if __name__=='__main__':raise SystemExit(main())
