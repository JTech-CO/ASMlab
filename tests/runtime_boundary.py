#!/usr/bin/env python3
"""Source/object/runtime boundary audit + development libc-reference parity."""
from __future__ import annotations
import argparse
from collections import Counter
import json
from pathlib import Path
import random
import re
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from check_provenance import ROOT, validate_app, validate_foundation
from native_contract import frames

class Checks:
    def __init__(self):self.counts=Counter();self.failures=[]
    def check(self,group,ok,detail):
        self.counts[group]+=1
        if not ok:self.failures.append(group+': '+str(detail))

def command(*args):
    return subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,check=True,timeout=30).stdout

def undefined(path,dynamic=False):
    return {line.split()[-1].split('@')[0] for line in command('nm',*(['-D'] if dynamic else []),
            '--undefined-only',path).splitlines() if line.strip()}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report',type=Path,required=True);a=p.parse_args();c=Checks()
    full=[validate_app('asmlab','release'),validate_app('asmlab-debug','debug'),
          validate_app('asmlab-libc-reference','release','libc-reference')]
    foundation=validate_foundation()
    c.check('provenance',True,'all artifacts/input inventories validated before execution')
    rt_imports={'rt_console_format','rt_console_puts','rt_decimal_from_cstr','rt_input_close',
                'rt_input_error','rt_input_getc','rt_input_gets','rt_input_open_read','rt_input_stdin',
                'rt_is_tty','rt_memcpy','rt_memset','rt_strnlen','rt_memcmp','rt_output_flush','rt_strcmp','rt_strlen',
                'rt_heap_alloc','rt_heap_free','rt_memory_set_limit','rt_memory_stats','rt_parse_u64'}
    core_paths=list((ROOT/'src').glob('*.asm'))+list((ROOT/'include').glob('*.inc'))+[ROOT/'include/rt/api.inc']
    forbidden=r'\b(call|jmp)\s+(?:printf|puts|fopen|fclose|fflush|fgetc|fgets|ferror|strtod|memcpy|memset|memcmp|memmove|strcmp|strlen|strnlen|isatty)\b|\[\s*stdin\s*\]'
    for path in core_paths:
        code='\n'.join(line.split(';')[0] for line in path.read_text().splitlines())
        c.check('source_boundary',not re.search(forbidden,code),str(path.relative_to(ROOT)))
        c.check('source_no_syscall',not re.search(r'^\s*syscall\b',code,re.M),str(path.relative_to(ROOT)))
    for name in ['core.inc','layout.inc','abi.inc']:
        code=(ROOT/'include'/name).read_text()
        c.check('storage_free_headers',not re.search(r'^\s*section\b',code,re.M),name)
    primitive_names={'memcpy','memmove','memset','memcmp','strlen','strnlen','strcmp'}
    for meta in full:
        name=meta['binary'];objects=meta['project_objects'];is_reference=meta['runtime_backend']=='libc-reference'
        c.check('app_object_imports',undefined(ROOT/objects[0]['path'])==rt_imports,name)
        imports=undefined(ROOT/objects[1]['path'])
        c.check('primitive_object_imports',imports==primitive_names if is_reference else not imports,name)
        imported=undefined(ROOT/name,is_reference)
        c.check('dynamic_primitive_boundary',primitive_names<=imported if is_reference else not primitive_names & imported,name)
        c.check('no_fixture_linkage',not any('tests/' in o['source'] for o in objects),name)
    for i,target in enumerate(foundation['targets']):
        path=ROOT/target['path'];programs=command('readelf','-lW',path);dynamic=command('readelf','-dW',path)
        c.check('foundation_no_interp','INTERP' not in programs,target['path'])
        needed=re.findall(r'\(NEEDED\).*?\[(.*?)\]',dynamic)
        c.check('foundation_dependencies',needed==(['libc.so.6'] if i==3 else []),target['path']+str(needed))
        c.check('foundation_nx',bool(re.search(r'GNU_STACK.*\bRW\b',programs)) and not re.search(r'LOAD.*RWE',programs),target['path'])
        if i!=3:c.check('foundation_no_undefined',not undefined(path),target['path'])
        if i==0:
            hdr=command('readelf','-hW',path);symbols=command('nm',path)
            c.check('standalone_entry',bool(re.search(r'\bT _start$',symbols,re.M)) and 'EXEC' in hdr,target['path'])
            c.check('standalone_no_crt',all(x not in symbols for x in ['__libc_start_main','printf','strtod','_IO_']),target['path'])
            c.check('standalone_not_math','parse_statement' not in symbols and 'exec_sse' not in symbols,target['path'])
    # Same inputs across native release/debug and development libc primitive backend.
    rng=random.Random(20260926)
    expressions=['0','-0','sqrt(-0)','sin(-0)','1e-320','pi','e','1/0','log(-1)','sqrt(-1)',
                 'A=[1,2;3,4]','B=A','A=4','B','B*B','x=7','x=sqrt(-1)','x','ans']
    for _ in range(500):
        x,y,z=[rng.uniform(.01,20) for _ in range(3)]
        expressions.append(f'(sin({x:.17g})+log({y:.17g}))*sqrt({z:.17g})')
    for _ in range(120):
        v=[rng.randint(-9,9) for _ in range(8)]
        expressions.append(f'[{v[0]},{v[1]};{v[2]},{v[3]}]*[{v[4]},{v[5]};{v[6]},{v[7]}]')
    text='\n'.join(expressions)+'\n';binaries=[ROOT/x['binary'] for x in full];outputs=[]
    for binary in binaries:
        result=subprocess.run([str(binary),'--json'],input=text,capture_output=True,text=True,timeout=30)
        rows=result.stdout.splitlines();outputs.append(rows)
        c.check('reference_batch_status',result.returncode==1 and len(rows)==len(expressions),binary.name)
    for i,rows in enumerate(zip(*outputs)):
        c.check('reference_result_parity',len(set(rows))==1,f'row {i}')
    trace_expr=['sqrt([1,4,9])+2','[1,2;3,4]*[5,6;7,8]','sin(pi/4)','log(2)','-[0,2,3]']
    total_frames=0
    for expr in trace_expr:
        traces=[]
        for binary in binaries:
            out=command(binary,'--bits','--all','--no-color','-e',expr)
            traces.append([{k:v for k,v in f.items() if k!='address'} for f in frames(out)])
        c.check('reference_trace_presence',bool(traces[0]),expr)
        c.check('reference_trace_parity',traces[0]==traces[1]==traces[2],expr)
        total_frames+=len(traces[0])
    report={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),
            'case_count':sum(c.counts.values()),'group_counts':dict(c.counts),'failure_count':len(c.failures),
            'failures':c.failures,'reference_result_records':len(expressions),'reference_trace_frames_per_backend':total_frames,
            'limitations':['Runtime relocation/module boundaries audited, not a security certification.',
                           'Reference still uses libc; it is comparison evidence, not an independent high-precision math oracle.']}
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));return int(bool(c.failures))
if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as e:
        print('Runtime boundary gate aborted: '+str(e),file=sys.stderr);raise SystemExit(1)
