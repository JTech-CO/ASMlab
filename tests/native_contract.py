#!/usr/bin/env python3
"""Native Gate contracts: ELF/constants/provenance/real SSE2 traces/profile parity.
Uses only Python's standard library and objdump. Not an all-input accuracy proof.
"""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import random
import re
import struct
import subprocess
import sys
from elf64 import ELF64

ROOT = Path(__file__).resolve().parents[1]
OPS = {'addsd','subsd','mulsd','divsd','sqrtsd','addpd','subpd','mulpd','divpd','sqrtpd','movapd','xorpd'}
OP_BYTES = {
 'addsd':'f20f58c1','subsd':'f20f5cc1','mulsd':'f20f59c1','divsd':'f20f5ec1','sqrtsd':'f20f51c1',
 'addpd':'660f58c1','subpd':'660f5cc1','mulpd':'660f59c1','divpd':'660f5ec1','sqrtpd':'660f51c1',
 'movapd':'660f28c1','xorpd':'660f57c1'}

def sha(p: Path) -> str: return hashlib.sha256(p.read_bytes()).hexdigest()
def f64(word: int) -> float: return struct.unpack('<d',struct.pack('<Q',word))[0]
def bits(x: float) -> int: return struct.unpack('<Q',struct.pack('<d',x))[0]
def run(binary: Path, *args: str, text: str = ''):
    return subprocess.run([str(binary.resolve()),*args],input=text,text=True,capture_output=True,timeout=20)

class Checks:
    def __init__(self): self.counts=Counter();self.failures=[]
    def check(self, group: str, ok: bool, detail: str):
        self.counts[group]+=1
        if not ok:self.failures.append(group+': '+detail)

def frames(output: str):
    found=[]
    for block in re.split(r'\n  frame ',output)[1:]:
        head=re.match(r'(\d+) \| node #(\d+) \| element (\d+) \| active lanes (\d+)/2',block)
        op=re.search(r'@0x([0-9a-f]+)\s+(\w+) xmm0, xmm1',block)
        state={name:re.search(name+r' bits\s+\[ 0x([0-9a-f]+) \| 0x([0-9a-f]+) \]',block)
               for name in ('before','source','after')}
        mx=re.search(r'MXCSR 0x([0-9a-f]+) -> 0x([0-9a-f]+)',block)
        if not head or not op or not all(state.values()) or not mx:
            raise AssertionError('Incomplete displayed frame')
        found.append({'index':int(head[1]),'node':int(head[2]),'element':int(head[3]),'lanes':int(head[4]),
                      'address':int(op[1],16),'op':op[2],
                      **{k:[int(m[1],16),int(m[2],16)] for k,m in state.items()},
                      'mxcsr':[int(mx[1],16),int(mx[2],16)]})
    return found

def profile(c: Checks, name: str, binary: Path):
    elf=ELF64(binary)
    m=json.loads(Path(str(binary)+'.build.json').read_text())
    c.check(name+'.elf',elf.machine==62 and elf.type==2,'not x86-64 non-PIE executable')
    c.check(name+'.debug',('.debug_info' in elf.by_name)==(name=='debug'),'profile debug sections')
    c.check(name+'.provenance',m['build_kind']=='nasm-native' and m['profile']==name,'wrong build kind/profile')
    c.check(name+'.provenance',m['binary_sha256']==sha(binary),'binary SHA256 mismatch')
    c.check(name+'.provenance',all(sha(ROOT/p)==h for p,h in m['source_sha256'].items()),'build inputs changed')
    c.check(name+'.provenance',all('validation_bridge' not in ' '.join(a) for a in m['commands']), 'bridge command in build')
    c.check(name+'.version',run(binary,'--version').stdout.strip()==
            'ASMlab '+(ROOT/'VERSION').read_text().strip()+' | NASM x86-64 | float64 | SSE2','version banner')
    constants=json.loads((ROOT/'tests/fixtures/constants-binary64.json').read_text())['entries']
    c.check(name+'.constant_fixture',len(constants)==19 and sum(len(e['bits']) for e in constants)==50,'fixture coverage')
    for entry in constants:
        data=elf.bytes_at_symbol(entry['symbol'],8*len(entry['bits']))
        for i,want in enumerate(entry['bits']):
            got=f'{struct.unpack_from("<Q",data,i*8)[0]:016x}'
            c.check(name+'.constant_bits',got==want,entry['symbol']+f'[{i}] {got} != {want}')
    for symbol in ['abs_mask','sign_mask','input_buf']:
        c.check(name+'.alignment',elf.symbols[symbol][0]%16==0,symbol)
    dis=subprocess.run(['objdump','-d','-Mintel',str(binary)],text=True,capture_output=True,check=True).stdout
    for op in sorted(OPS):
        symbol='watched_'+op; address=elf.symbols[symbol][0]
        c.check(name+'.instruction_bytes',elf.bytes_at_symbol(symbol,4).hex()==OP_BYTES[op],op)
        c.check(name+'.instruction_disassembly',re.search(rf'^\s*{address:x}:.*\b{op}\s+xmm0,xmm1',dis,re.M) is not None,op)
    expressions=['1+2','5-2','3*4','6/2','sqrt(9)',
                 '[1,2]+[3,4]','[5,8]-[2,4]','[3,4].*[2,3]','[6,8]./[2,4]',
                 'sqrt([4,9])','transpose([1,2])','-[0,2,3]',
                 'sqrt([1,4,9])+2','[1,2;3,4]*[5,6;7,8]','sin(pi/4)','log(2)']
    seen=set(); normalized=[]
    for expression in expressions:
        result=run(binary,'--bits','--all','--no-color','-e',expression)
        fs=frames(result.stdout)
        c.check(name+'.trace_presence',result.returncode==0 and bool(fs),expression)
        for frame in fs:
            op=frame['op'];seen.add(op)
            c.check(name+'.trace_address',frame['address']==elf.symbols['watched_'+op][0],op)
            a,b=frame['before'],frame['source'];expected=list(a)
            if op=='movapd':expected=list(b)
            elif op=='xorpd':expected=[x^y for x,y in zip(a,b)]
            else:
                for i in range(2 if op.endswith('pd') else 1):
                    x,y=f64(a[i]),f64(b[i])
                    v= math.sqrt(y) if op.startswith('sqrt') else {
                        'add':lambda:x+y,'sub':lambda:x-y,'mul':lambda:x*y,'div':lambda:x/y}[op[:3]]()
                    expected[i]=bits(v)
            c.check(name+'.trace_raw_bits',expected==frame['after'],f'{expression} frame {frame["index"]}')
            c.check(name+'.mxcsr_control',all((v & 0xffc0)==0x1f80 for v in frame['mxcsr']),expression)
            normalized.append({k:v for k,v in frame.items() if k!='address'})
    c.check(name+'.opcode_coverage',seen==OPS,'missing '+str(OPS-seen))
    r=run(binary,'--bits','--all','--no-color',text='1/10\n1+2\n')
    fs=frames(r.stdout)
    c.check(name+'.mxcsr_status',len(fs)==2 and bool(fs[0]['mxcsr'][1]&0x20),'inexact flag')
    c.check(name+'.mxcsr_reset',len(fs)==2 and fs[1]['mxcsr']==[0x1f80,0x1f80],'expression reset')
    c.check(name+'.cli',run(binary,'-e').returncode==2,'missing -e operand')
    c.check(name+'.cli',run(binary,'-f').returncode==2,'missing -f operand')
    r=run(binary,'--json',text='A=7\nA=sqrt(-1)\nA\nans\n')
    records=[json.loads(x) for x in r.stdout.splitlines()]
    c.check(name+'.rollback',r.returncode==1 and len(records)==4 and not records[1]['ok']
            and records[2]['data']==[7] and records[3]['data']==[7],'failed assignment state')
    r=run(binary,'--json','-f',str(ROOT/'examples/numeric.asmlab'))
    c.check(name+'.file_input',r.returncode==0 and len(r.stdout.splitlines())>0,'numeric script')
    return normalized

def main():
    p=argparse.ArgumentParser();p.add_argument('--release',type=Path,default=ROOT/'bin/asmlab')
    p.add_argument('--debug',type=Path,default=ROOT/'bin/asmlab-debug')
    p.add_argument('--report',type=Path,required=True);args=p.parse_args();c=Checks()
    a=profile(c,'release',args.release);b=profile(c,'debug',args.debug)
    c.check('profile_trace_parity',a==b,'capture values/control/node context differ (addresses intentionally excluded)')
    rng=random.Random(20260923)
    expressions=['-0','sqrt(-0)','sin(-0)','pi','e','1e-320','1e308','2^-1024']
    for _ in range(512):
        x,y,z=[rng.uniform(.125,16) for _ in range(3)]
        expressions.append(f'(sin({x:.17g})+log({y:.17g}))*sqrt({z:.17g})')
    text='\n'.join(expressions)+'\n'
    r=run(args.release,'--json',text=text);d=run(args.debug,'--json',text=text)
    x,y=r.stdout.splitlines(),d.stdout.splitlines()
    c.check('profile_result_count',r.returncode==d.returncode==0 and len(x)==len(y)==len(expressions),'batch result count')
    for i,(v,w) in enumerate(zip(x,y)):
        c.check('profile_result_parity',v==w,f'expression {i}')
    report={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),'case_count':sum(c.counts.values()),
            'group_counts':dict(c.counts),'failure_count':len(c.failures),'failures':c.failures,
            'constants_words_per_profile':sum(len(e['bits']) for e in json.loads((ROOT/'tests/fixtures/constants-binary64.json').read_text())['entries']),
            'limitations':['Finite tests; no correct-rounding proof.','Raw flags/lane checks cover the listed observed operations, not all CPU instructions.',
                           'NASM host binary provenance is recorded, not a toolchain supply-chain security certification.']}
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return int(bool(c.failures))

if __name__=='__main__':
    try: raise SystemExit(main())
    except (OSError,ValueError,KeyError,AssertionError,subprocess.SubprocessError) as e:
        print('Native contract test aborted: '+str(e),file=sys.stderr);raise SystemExit(1)
