#!/usr/bin/env python3
"""Fail-closed L3 gate: exact decimal conversion + full-app independence."""
from __future__ import annotations
import argparse,json,os,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
from check_provenance import ROOT,validate_app,validate_foundation

def main():
    p=argparse.ArgumentParser();p.add_argument('--report-dir',type=Path,default=ROOT/'build/l3-evidence')
    p.add_argument('--require-empty-root',action='store_true');a=p.parse_args();out=a.report_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    result={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),'status':'running','steps':[],
            'executed_at_utc':datetime.now(timezone.utc).isoformat(),'counts':{}}
    target=out/'l3-summary.json'
    def save():target.write_text(json.dumps(result,indent=2)+'\n')
    save()
    try:
        validate_app('asmlab','release');validate_app('asmlab-debug','debug')
        validate_app('asmlab-libc-reference','release','libc-reference');validate_foundation()
        for name,script in [('decimal-exact','tests/decimal_exact.py'),('l3-core','tests/l3_core.py')]:
            report=out/(name+'.json');report.unlink(missing_ok=True)
            cmd=[sys.executable,script,'--report',str(report)]
            if name=='l3-core' and a.require_empty_root:cmd+=['--require-empty-root']
            run=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=120)
            (out/(name+'.log')).write_text('$ '+' '.join(cmd)+'\n'+run.stdout+run.stderr)
            result['steps'].append({'name':name,'exit_code':run.returncode});save()
            if run.returncode:raise RuntimeError(name+' failed; see '+str(out/(name+'.log')))
            data=json.loads(report.read_text())
            if data['failure_count']:raise RuntimeError(name+' reported failure')
            result['counts'][name]=data['case_count']
            if name=='l3-core':result['empty_root_skipped']=data['skipped']
        result.update(status='passed',failure_count=0,total_assertions=sum(result['counts'].values()))
        save();print(json.dumps(result,indent=2));return 0
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as exc:
        result.update(status='failed',error=str(exc));save();print(str(exc),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
