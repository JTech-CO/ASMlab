#!/usr/bin/env python3
"""Development-only verification. ASMlab itself contains no Python runtime.
Uses the host Python math module as a numerical reference, not as application code.
Run: python3 tests/verify.py ./bin/asmlab [--report evidence/verification.json]
"""
from __future__ import annotations
import argparse
from dataclasses import dataclass
import json
import math
from pathlib import Path
import random
import re
import select
import struct
import subprocess
import time
import os
import pty
import fcntl
import termios
from typing import Any

@dataclass
class Case:
    expression: str
    data: list[float]
    rows: int = 1
    cols: int = 1
    family: str = 'regression'
    atol: float = 1e-12
    rtol: float = 1e-12

class Suite:
    def __init__(self, binary: Path, numeric_mode: str | None = None):
        self.binary = str(binary.resolve())
        self.numeric_mode = numeric_mode
        self.counts: dict[str, int] = {}
        self.worst: dict[str, dict[str, Any]] = {}
        self.failures: list[str] = []
        self.started = time.monotonic()
    def mark(self, family: str, condition: bool, detail: str = '') -> None:
        self.counts[family] = self.counts.get(family, 0) + 1
        if not condition:
            self.failures.append(f'{family}: {detail}')
    def invoke(self, text: str | bytes, *flags: str) -> subprocess.CompletedProcess:
        return subprocess.run([self.binary, *(['--mode',self.numeric_mode] if self.numeric_mode and '--json' in flags else []), *flags], input=text,
                              capture_output=True, text=isinstance(text, str), timeout=30)
    def numeric(self, cases: list[Case]) -> None:
        response = self.invoke('\n'.join(c.expression for c in cases) + '\n', '--json')
        lines = response.stdout.splitlines()
        if response.returncode != 0 or len(lines) != len(cases):
            raise AssertionError(f'Numerical batch: exit={response.returncode}; '
                                 f'lines={len(lines)}/{len(cases)}; stderr={response.stderr[:500]}')
        for c, line in zip(cases, lines):
            value = json.loads(line)
            okay = (value.get('ok') is True and value.get('rows') == c.rows and
                    value.get('cols') == c.cols and len(value.get('data', [])) == len(c.data))
            error = 0.0
            if okay:
                for got, expected in zip(value['data'], c.data):
                    delta = abs(got - expected)
                    error = max(error, delta)
                    okay &= math.isfinite(got) and delta <= c.atol + c.rtol * abs(expected)
            self.mark(c.family, okay, f'{c.expression}: {value}, expected {c.data}')
            if c.family not in self.worst or error > self.worst[c.family]['max_absolute_error']:
                self.worst[c.family] = {'max_absolute_error': error,
                                       'expression': c.expression,
                                       'absolute_tolerance': c.atol, 'relative_tolerance': c.rtol}
    def errors(self, expressions: list[str]) -> None:
        response = self.invoke('\n'.join(expressions) + '\n', '--json')
        lines = response.stdout.splitlines()
        if len(lines) != len(expressions):
            raise AssertionError(f'Error batch length {len(lines)}/{len(expressions)}')
        for expr, line in zip(expressions, lines):
            value = json.loads(line)
            self.mark('rejected_inputs', value.get('ok') is False, f'{expr}: {line}')
        self.mark('exit_status', response.returncode == 1, str(response.returncode))
    def finish(self) -> dict[str, Any]:
        return {'schema_version': 1, 'binary': Path(self.binary).name,
                'seed': 20260922, 'numeric_mode': self.numeric_mode or 'default', 'case_count': sum(self.counts.values()),
                'group_counts': self.counts, 'failure_count': len(self.failures),
                'failures': self.failures, 'numeric_comparisons': self.worst,
                'reference': 'host Python standard-library math and direct scalar formulas',
                'elapsed_seconds': round(time.monotonic()-self.started, 3),
                'limitations': ['Finite seeded tests are not a proof of correct rounding.',
                    'Fuzz tests check bounded execution and structured output, not all semantics.',
                    'Check BUILD_ORIGIN.txt for NASM-native versus validation-bridge provenance.']}

def literal(a: list[list[float]]) -> str:
    return '['+';'.join(','.join(format(x, '.17g') for x in row) for row in a)+']'

def flat(a: list[list[float]]) -> list[float]:
    return [x for row in a for x in row]

def replay_test(s: Suite) -> None:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 42, 100, 0, 0))
    proc = subprocess.Popen([s.binary, '--step', '--bits', '--no-color', '-e',
                             'sqrt([1,4,9,16]) + 2'],
                            stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)
    captured = bytearray()
    def until_prompt() -> bytes:
        start = len(captured)
        end = time.monotonic()+5
        while time.monotonic() < end:
            if select.select([master], [], [], 0.1)[0]:
                try: piece = os.read(master, 65536)
                except OSError: break
                if not piece: break
                captured.extend(piece)
                if b'[q] finish  > ' in captured[start:]: return bytes(captured[start:])
        raise AssertionError('PTY replay prompt timeout')
    try:
        first = until_prompt()
        os.write(master, b'n\n')
        nxt = until_prompt()
        os.write(master, b'p\n')
        prev = until_prompt()
        os.write(master, b'q\n')
        proc.wait(timeout=5)
        s.mark('pty_replay', b'CAPTURE REPLAY' in first, 'missing replay view')
        s.mark('pty_replay', b'frame 0002' in nxt, 'next did not select frame 2')
        s.mark('pty_replay', b'frame 0001' in prev, 'previous did not select frame 1')
        s.mark('pty_replay', proc.returncode == 0, 'replay did not exit successfully')
    finally:
        if proc.poll() is None: proc.kill(); proc.wait()
        os.close(master)

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('binary', type=Path)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--numeric-mode', choices=['observe','compute'], help='Override mode for JSON numeric/error batches; legacy capture UI tests remain Observe.')
    args = parser.parse_args()
    s = Suite(args.binary, args.numeric_mode)
    rng = random.Random(20260922)
    cases: list[Case] = []
    for fn in ('sin', 'cos'):
        xs = [0.0,-0.0,1e-300,-1e-300,math.pi/2,math.pi,2*math.pi,1e6,-1e6]
        xs += [rng.uniform(-1e6,1e6) for _ in range(3000)]
        for x in xs:
            cases.append(Case(f'{fn}({x:.17g})', [getattr(math, fn)(x)],
                              family=fn, atol=3e-14, rtol=0))
    xs = [5e-324,1e-320,1e-308,1.,1.+2**-52,1.-2**-53,math.e,1e308]
    xs += [10**rng.uniform(-320,308) for _ in range(3000)]
    for x in xs:
        cases.append(Case(f'log({x:.17g})', [math.log(x)], family='log', atol=3e-13, rtol=0))
    xs = [0.,5e-324,1e-300,1e300]+[10**rng.uniform(-320,308) for _ in range(1000)]
    for x in xs:
        cases.append(Case(f'sqrt({x:.17g})', [math.sqrt(x)], family='sqrt', atol=0, rtol=1e-15))
    for expression, expected in [('1+2*3',7),('(1+2)*3',9),('-2^2',-4),
            ('(-2)^2',4),('2^-2',.25),('2^3^2',512),('2^(-3)',.125),
            ('0^0',1),('1e-3+.5',.501),('1.',1),('2.*3',6),('2./4',.5),
            ('sum([1,2;3,4])',10),('sin(pi/6)',.5),('cos(pi)',-1),
            ('log(1)',0),('1e-300/2',5e-301),('(1e200)^-2',0),
            ('2^1023',float(2**1023)),('2^-1024',2.**-1024),(' 3 + 4 # comment',7)]:
        cases.append(Case(expression,[expected],family='scalar_regression',atol=1e-14))
    for _ in range(300):
        x = rng.uniform(.2,2); exponent=rng.randint(-12,12)
        cases.append(Case(f'({x:.17g})^{exponent}',[x**exponent],family='integer_power'))
    for _ in range(200):
        a,b,c,d=[rng.uniform(-10,10) for _ in range(4)]
        d=abs(d)+.1
        expr=f'(({a:.17g})+({b:.17g}))*({c:.17g})/({d:.17g})'
        cases.append(Case(expr,[(a+b)*c/d],family='scalar_composition'))
    for _ in range(160):
        m,k,n=[rng.randint(1,6) for _ in range(3)]
        a=[[rng.randint(-9,9) for _ in range(k)] for _ in range(m)]
        b=[[rng.randint(-9,9) for _ in range(n)] for _ in range(k)]
        out=[[sum(a[i][t]*b[t][j] for t in range(k)) for j in range(n)] for i in range(m)]
        cases.append(Case(f'{literal(a)}*{literal(b)}',flat(out),m,n,'matrix_product',0,0))
        b2=[[rng.randint(1,9) for _ in range(k)] for _ in range(m)]
        for op in ['+','-','.*','./']:
            fun={'+':lambda x,y:x+y,'-':lambda x,y:x-y,
                 '.*':lambda x,y:x*y,'./':lambda x,y:x/y}[op]
            expected=[[fun(a[i][j],b2[i][j]) for j in range(k)] for i in range(m)]
            cases.append(Case(f'{literal(a)}{op}{literal(b2)}',flat(expected),m,k,'elementwise'))
        tr=[[a[i][j] for i in range(m)] for j in range(k)]
        cases.append(Case(f"({literal(a)})'",flat(tr),k,m,'transpose',0,0))
        cases.append(Case(f'{literal(a)}+3',[x+3 for x in flat(a)],m,k,'broadcast',0,0))
        cases.append(Case(f'-({literal(a)})',[-x for x in flat(a)],m,k,'negation',0,0))
    cases += [Case('sqrt([0,1,2,4,9])',[0,1,math.sqrt(2),2,3],1,5,'vector_functions'),
              Case('sin([0,pi/6,pi/4,pi/2])',[0,.5,math.sqrt(.5),1],1,4,'vector_functions'),
              Case('cos([0,pi/2,pi])',[1,0,-1],1,3,'vector_functions'),
              Case('log([1,e,10])',[0,1,math.log(10)],1,3,'vector_functions')]
    # v0.4 intentionally accepts the former 16-cell dimension boundary.
    cases += [Case('['+','.join('1' for _ in range(17))+']',[1.]*17,1,17,'dynamic_17_axis',0,0),
              Case('['+';'.join('1' for _ in range(17))+']',[1.]*17,17,1,'dynamic_17_axis',0,0)]
    s.numeric(cases)
    errors=['1/0','1/(-0)','sqrt(-1)','log(0)','log(-1)','sin(1000000.1)',
            'cos(-1000000.1)','[1,2]+[1;2]','[1,2]*[3,4]',
            '[1,2]/[3,4]','1./[2,0]','[1,2;3]','[]','[1,]','[;1]',
            '1 2','1e','1e+','1e309','1e308*1e308','undefined',
            'foo(1)','sin(1,2)','(1+2','1+','2^0.5','[1,2]^2','2^1025',
            '0^-1','pi=1','e=1','ans=1','sin=1','[1,[2,3]]','1==1',
            'a'*32,'9'*128,
            '('*70+'1'+')'*70,'+'.join('1' for _ in range(300)),
            'A[1]','[1 2]','1..2','x = y = 2','1 + @']
    s.errors(errors)
    # Transactional variables, deep copy, workspace reset, and reserved ans.
    text='A=[1,2;3,4]\nB=A\nA=A+1\nB\nA=sqrt(-1)\nA\n:clear\nans\n'
    r=s.invoke(text,'--json'); vals=[json.loads(x) for x in r.stdout.splitlines()]
    checks=[(len(vals)==7,'record count'),(vals[3]['data']==[1,2,3,4],'alias isolation'),
            (vals[4]['ok'] is False,'error'),(vals[5]['data']==[2,3,4,5],'rollback'),
            (vals[6]['data']==[0],'clear resets ans')]
    for ok,detail in checks:s.mark('workspace',ok,detail)
    text='\n'.join(f'v{i}={i}' for i in range(63))+'\noverflow=5\nv0=123\nv0\n'
    r=s.invoke(text,'--json');vals=[json.loads(x) for x in r.stdout.splitlines()]
    s.mark('workspace',r.returncode==0 and len(vals)==66 and vals[63]['data']==[5] and vals[-1]['data']==[123], 'dynamic growth beyond 63 users/replacement')
    for blob in [b'A=7\nA=9'+b' '*5000+b'\nA\n',b'A=7\nA=9\0ignored\nA\n',
                 b'A=7\nA=9\x1b[2J\nA\n']:
        r=s.invoke(blob,'--json');v=[json.loads(x) for x in r.stdout.splitlines()]
        s.mark('whole_line_rejection',len(v)==3 and not v[1]['ok'] and v[2]['data']==[7],repr(blob[:30]))
    for expr in ['-0','sin(-0)','sqrt(-0)']:
        r=s.invoke('', '-q','-e',expr)
        s.mark('signed_zero',r.stdout.strip()=='-0',f'{expr}: {r.stdout}')
    # Former maximum matrix product, including the last cell in each buffer.
    a=[[float(i*16+j+1) for j in range(16)] for i in range(16)]
    ident=[[float(i==j) for j in range(16)] for i in range(16)]
    r=s.invoke(f'A={literal(a)}\nI={literal(ident)}\nA*I\n','--json')
    vals=[json.loads(x) for x in r.stdout.splitlines()]
    s.mark('matrix_bounds',r.returncode==0 and vals[-1]['data']==flat(a),'16x16 identity product')
    # Capture overflow is disclosed, never silently represented as a complete trace.
    r=s.invoke(f'A={literal(a)}\nlog(A)\n','--no-color')
    s.mark('trace_capacity',r.returncode==0 and 'Capture cap reached' in r.stdout,'missing truncation disclosure')
    # Check actual saved 128-bit values AND the displayed instruction's address.
    r=s.invoke('', '--bits','--all','--no-color','-e','sqrt([1,4,9,16]) + 2')
    dis=subprocess.run(['objdump','-d','-Mintel',s.binary],text=True,capture_output=True,check=True).stdout
    frames=re.findall(r'@0x([0-9a-f]+)\s+(\w+) xmm0, xmm1',r.stdout)
    raw=re.findall(r'after bits\s+\[ 0x([0-9a-f]+) \| 0x([0-9a-f]+) \]',r.stdout)
    actual=[[struct.unpack('<d',bytes.fromhex(x)[::-1])[0] for x in row] for row in raw]
    s.mark('register_capture',actual==[[1,2],[3,4],[3,4],[5,6]],str(actual))
    for address,op in frames:
        pattern=rf'^\s*{int(address,16):x}:.*\b{op}\s+xmm0,xmm1'
        s.mark('instruction_address',re.search(pattern,dis,re.M) is not None,f'{address} {op}')
    # Deterministic malformed-input fuzzing. Every line starts with '(' so it
    # cannot be a workspace command, a blank line, or an ignored comment.
    alphabet='0123456789ab_+-*/^().,;[] =eE@?!%'
    fuzz=['('+''.join(rng.choice(alphabet) for _ in range(rng.randrange(150)))+')' for _ in range(2500)]
    r=s.invoke('\n'.join(fuzz)+'\n','--json')
    lines=r.stdout.splitlines()
    s.mark('fuzz_batch',r.returncode in (0,1) and len(lines)==len(fuzz),f'exit {r.returncode}, lines {len(lines)}')
    for i,line in enumerate(lines):
        value=json.loads(line)
        s.mark('malformed_fuzz',isinstance(value.get('ok'),bool),str(i))
    replay_test(s)
    # File mode, EOF without newline, CLI errors and noninteractive step guard.
    r=s.invoke('4+5','--json')
    s.mark('io_cli',r.returncode==0 and json.loads(r.stdout)['data']==[9],'EOF without newline')
    r=s.invoke('', '--json','-f','/does/not/exist/asmlab')
    s.mark('io_cli',r.returncode==2 and json.loads(r.stdout)['ok'] is False,'missing file')
    r=s.invoke('', '--nonsense')
    s.mark('io_cli',r.returncode==2,'unknown CLI option')
    r=s.invoke('1+2\n3+4\n','--step','--no-color')
    s.mark('io_cli',r.returncode==0 and r.stdout.count('03 / RESULT')==2,'non-TTY replay consumed input')
    report=s.finish()
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'case_count':report['case_count'],'failure_count':report['failure_count'],
                      'groups':report['group_counts'],'elapsed_seconds':report['elapsed_seconds']},indent=2))
    for failure in report['failures'][:30]:print('FAIL:',failure)
    return int(bool(report['failures']))

if __name__=='__main__':
    raise SystemExit(main())
