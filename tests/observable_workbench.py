#!/usr/bin/env python3
"""Observable Workbench integration tests. Test host only; no Python runtime UI.
The tests compare execution paths, inspect real ELF code/trace, and drive PTYs.
"""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import pty
import random
import re
import select
import signal
import statistics
import struct
import subprocess
import sys
import termios
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from check_provenance import ROOT, validate_app
from elf64 import ELF64

class Checks:
    def __init__(self): self.counts=Counter(); self.failures=[]
    def check(self, group, condition, detail=''):
        self.counts[group]+=1
        if not condition: self.failures.append(f'{group}: {detail}')

def run(binary, *args, data=None, timeout=30):
    return subprocess.run([str(binary),*args],input=data,capture_output=True,text=True,timeout=timeout)

def bits(number): return struct.pack('<d', float(number)).hex()

def trace(binary, expression, mode='observe'):
    r=run(binary,'--mode',mode,'--trace-json','-e',expression)
    rows=r.stdout.splitlines()
    if len(rows)!=1: raise AssertionError(f'Trace output must be one JSON record: {expression!r}: {len(rows)}')
    return r, json.loads(rows[0])

OP_BYTES={'addsd':'f20f58c1','subsd':'f20f5cc1','mulsd':'f20f59c1','divsd':'f20f5ec1',
          'sqrtsd':'f20f51c1','addpd':'660f58c1','subpd':'660f5cc1','mulpd':'660f59c1',
          'divpd':'660f5ec1','sqrtpd':'660f51c1','movapd':'660f28c1','xorpd':'660f57c1'}

class Terminal:
    """Own a controlling PTY; always restore/close test resources, even on failure."""
    def __init__(self, binary, args, rows=34, cols=120):
        self.master,self.slave=pty.openpty();self.data=bytearray()
        self.rows=rows;self.cols=cols
        fcntl.ioctl(self.slave,termios.TIOCSWINSZ,struct.pack('HHHH',rows,cols,0,0))
        self.before=termios.tcgetattr(self.slave)
        slave=self.slave
        def child():
            os.setsid();fcntl.ioctl(slave,termios.TIOCSCTTY,0)
        self.process=subprocess.Popen([str(binary),*args],stdin=self.slave,stdout=self.slave,stderr=self.slave,
                    preexec_fn=child,env={**os.environ,'TERM':'xterm-256color'})
        self.pump(.2)
    def pump(self,seconds=.06):
        end=time.monotonic()+seconds;piece=bytearray()
        while time.monotonic()<end:
            ready,_,_=select.select([self.master],[],[],min(.02,max(0,end-time.monotonic())))
            if ready:
                try: block=os.read(self.master,65536)
                except OSError: break
                if not block:break
                piece.extend(block);self.data.extend(block)
        return bytes(piece)
    def screen(self):
        # The native renderer emits complete fixed-size ASCII frames after CUP.
        frame=bytes(self.data).split(b'\x1b[H')[-1]
        return re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]',b'',frame).decode('ascii','replace')
    def send(self,keys,seconds=.07):
        os.write(self.master,keys);return self.pump(seconds)
    def wait_for(self,needle,timeout=3):
        end=time.monotonic()+timeout
        while needle not in self.screen() and self.process.poll() is None and time.monotonic()<end:self.pump(.05)
        return needle in self.screen()
    def resize(self,rows,cols):
        self.rows=rows;self.cols=cols
        fcntl.ioctl(self.slave,termios.TIOCSWINSZ,struct.pack('HHHH',rows,cols,0,0));self.pump(.18)
    def quit(self):
        self.send(b'q',.1);self.pump(.1)
        return self.process.wait(timeout=3)
    def restored(self):return termios.tcgetattr(self.slave)==self.before
    def close(self):
        if self.process.poll() is None:
            self.process.kill();self.process.wait(timeout=3)
        os.close(self.master);os.close(self.slave)
    def __enter__(self):return self
    def __exit__(self,*exc):self.close()

def mode_tests(c,binaries,evidence):
    rng=random.Random(5012026)
    expressions=['0','-0','sqrt(-0)','sin(-0)','pi','e','0.1+0.2','1e-320/2',
      'A=ones(17,19)','B=A','A=A+2','B(17,19)','size(A)','A=A/0','A(1,1)','ans',
      'x=linspace(-1,1,65)','sum(sin(x))','size(transpose(A))','sum(A*A\')',
      'zeros(0)','(1+2)*3','-2^2','2^-2','1/0','log(0)','sqrt(-1)','cos(1000001)']
    for _ in range(340):
        a,b,d=[rng.uniform(.01,40) for i in range(3)]
        expressions.append(f'(sin({a:.17g})+log({b:.17g}))*sqrt({d:.17g})')
    for _ in range(150):
        a=[rng.randrange(-30,31) for i in range(12)]
        expressions.append(f'[{a[0]},{a[1]},{a[2]};{a[3]},{a[4]},{a[5]}]*[{a[6]},{a[7]};{a[8]},{a[9]};{a[10]},{a[11]}]')
    data='\n'.join(expressions)+'\n';all_outputs=[]
    for binary in binaries:
        outputs=[]
        for mode in ('observe','compute'):
            r=run(binary,'--json','--mode',mode,data=data)
            rows=[json.loads(line) for line in r.stdout.splitlines()]
            c.check('batch_status',r.returncode==1 and len(rows)==len(expressions),(binary.name,mode,r.returncode,len(rows)))
            outputs.append(rows)
        for index,(a,b) in enumerate(zip(*outputs)):
            c.check('mode_result_bits',a['ok']==b['ok'] and (a==b if not a['ok'] else
                    (a['rows'],a['cols'],[bits(v) for v in a['data']])==(b['rows'],b['cols'],[bits(v) for v in b['data']])),
                    (binary.name,index,expressions[index]))
        all_outputs.append(outputs)
    c.check('profile_outputs',all_outputs[0]==all_outputs[1],'release/debug result records')
    binary=binaries[0]
    for args in [('--mode','bad'),('--mode',),('--workbench','--json'),('--workbench','-f','examples/walkthrough.asmlab')]:
        r=run(binary,*args);c.check('invalid_cli',r.returncode!=0,args)
    for mode in ('observe','compute'):
        r=run(binary,'--json','--memory-mib','1','--mode',mode,data='A=1\n99\nA=ones(210,210)\nans\nA\n')
        rows=[json.loads(line) for line in r.stdout.splitlines()]
        c.check('quota_rollback_modes',not rows[2]['ok'] and rows[3]['data']==[99] and rows[4]['data']==[1],mode)
    evidence['mode_result_records_per_profile_per_mode']=len(expressions)

def trace_tests(c,binaries,evidence):
    corpus=['sqrt([1,4,9,16])+2','-[0,1,2]','[1,2,3]+[4,5,6]','[1,2,3]./[2,3,4]',
      '[1,2,3;4,5,6]*[2,3;4,5;6,7]','transpose(ones(3,2))','sum([1,2,3])',
      'sin(-0)','cos(0)','sin(pi/4)','sin(999999.5)','log(1e-320)','log(1e200)',
      '2^-3','linspace(-1,1,9)','(sin(pi/4) + 2)','(1+2)*(3+4)',
      'A = sqrt([1,4,9,16])+2','sqrt(ones(3,5))','sum(sin(linspace(-2,2,17)))',
      'eye(3)','size(ones(2,3))','1e-320*1e-3']
    total=0
    for binary in binaries:
        meta=json.loads(Path(str(binary)+'.build.json').read_text());elf=ELF64(binary)
        for expr in corpus:
            r,o=trace(binary,expr);_,n=trace(binary,expr,'compute')
            c.check('trace_identity',r.returncode==0 and o['schema_version']==2 and o['build_id']==meta['source_build_id']
                    and o['source']==expr and o['isa']=='x86_64' and o['backend']=='sse2',(binary.name,expr))
            c.check('final_fp_parity',o['final_mxcsr']==n['final_mxcsr'],expr)
            c.check('trace_compute_disabled',n['mode']=='compute' and n['events']==[] and n['capture']=={
                'policy':'disabled-compute','capacity':8192,'retained':0,'executed_watched':None,'dropped':0,'dispatcher_entries':0},expr)
            c.check('trace_results',o['result']==n['result'],expr)
            cap=o['capture'];c.check('capture_accounting',cap['executed_watched']==cap['retained']+cap['dropped'] and
                    cap['dispatcher_entries']==cap['executed_watched'] and cap['retained']==len(o['events']),expr)
            nodes={v['id']:v for v in o['nodes']}
            for node in nodes.values():
                start,end=node['span']
                c.check('node_span',0<=start<end<=len(expr), (expr,node))
                for child in node['children']:
                    c.check('ast_links',child in nodes and start<=nodes[child]['span'][0] and nodes[child]['span'][1]<=end,(expr,node['id'],child))
            for index,event in enumerate(o['events']):
                total+=1;opcode=event['instruction']['opcode'].split()[0];site='watched_'+opcode
                c.check('event_source_link',event['node'] in nodes and event['span']==nodes[event['node']]['span'] and
                        event['expression_id']==o['expression_id'] and event['sequence']==index+1,(expr,index))
                c.check('instruction_evidence',int(event['instruction']['pc'],16)==elf.symbols[site][0] and
                        elf.bytes_at_symbol(site,4)==bytes.fromhex(OP_BYTES[opcode]),(expr,index,opcode))
                c.check('event_lanes',event['lanes']['active'] in (1,2) and event['lanes']['hardware'] in (1,2) and
                        event['lanes']['active']<=event['lanes']['hardware'],(expr,index,event['lanes']))
                c.check('event_raw_registers',all(re.fullmatch(r'0x[0-9a-f]{16}',v) for k in ('before','source','after') for v in event[k])
                        and all(len(event[k])==2 for k in ('before','source','after')),(expr,index))
                ctx=event['context'];c.check('matrix_context',ctx['rows']>0 and ctx['cols']>0 and
                        ctx['row']*ctx['cols']+ctx['col']==ctx['element'] and ctx['row']<ctx['rows'] and ctx['col']<ctx['cols'],(expr,index,ctx))
                c.check('fp_control',all((int(event[k],16)&0xffc0)==0x1f80 for k in ('mxcsr_before','mxcsr_after')),(expr,index))
            if expr=='sqrt([1,4,9,16])+2':
                expected=[[1,2],[3,4],[3,4],[5,6]]
                c.check('known_simd_lanes',[[struct.unpack('<d',int(w,16).to_bytes(8,'little'))[0] for w in e['after']] for e in o['events']]==expected,binary.name)
            if expr=='(sin(pi/4) + 2)':c.check('parenthesized_span',o['nodes'][-2]['span']==[0,len(expr)],expr)
        for expr in ('1/0','sqrt(-1)','1+'):
            r,v=trace(binary,expr);c.check('error_trace_contract',r.returncode==1 and v['ok'] is False and v['schema_version']==2 and v['snapshot_available'] is False,expr)
        r,v=trace(binary,'sin(linspace(0,10,700))')
        c.check('trace_overflow',len(v['events'])==8192 and v['capture']['dropped']>0 and
                v['capture']['executed_watched']==8192+v['capture']['dropped'] and v['events'][-1]['sequence']==8192,binary.name)
        r=run(binary,'--trace-json',data='A=ones(2,3)+1\n:mode compute\n:trace json\n:drop A\n:trace json\n2+3\n:clear\n:trace json\n')
        rows=[json.loads(line) for line in r.stdout.splitlines()]
        c.check('snapshot_mode_lifetime',len(rows)==5 and rows[0]==rows[1]==rows[2] and rows[3]['mode']=='compute' and not rows[4]['ok'],(binary.name,len(rows)))
        r=run(binary,'--trace-json',data='A=ones(2,3)\nA(2,3)\n')
        rows=[json.loads(line) for line in r.stdout.splitlines()]
        c.check('index_semantics',rows[1]['events'][-1]['stage']=='index-read' and rows[1]['result']['data']==[1],binary.name)
    evidence['retained_frames_checked']=total

def code_tests(c,binaries,evidence):
    code_evidence=[]
    for binary in binaries:
        e=ELF64(binary);start=e.symbols['compute_section_begin'][0];end=e.symbols['compute_section_end'][0]
        r=run('objdump','-d','-Mintel',f'--start-address={start}',f'--stop-address={end}',str(binary))
        text=r.stdout;c.check('compute_region',r.returncode==0 and end>start,(binary.name,start,end))
        c.check('compute_no_dispatch',not re.search(r'\b(?:call|jmp)\s+[^\n]*<(?:exec_sse|watched_)',text),binary.name)
        c.check('compute_no_trace_state',not re.search(r'<(?:trace_|dispatch_entries|node_starts)',text),binary.name)
        targets=re.findall(r'\bcall\s+[^\n]*<([^>]+)>',text)
        allowed={'value_allocate','validate_value','set_error','set_error_at','workspace_find',
                 'temp_allocate','rt_memcpy','rt_memset','rt_strcmp','rt_heap_alloc','workspace_lookup'}
        # Reject any call from the Compute specialization back into a numerical Observe function.
        observed={'eval_node','apply_function','eval_call','math_sin','math_cos','math_trig','math_log','math_power',
                  'elementwise','matmul','transpose_value','negate_value','linspace_value','index_value','size_value','create_array'}
        c.check('compute_no_observe_calls',not observed.intersection(targets),(binary.name,sorted(set(targets))))
        for opcode in OP_BYTES:
            c.check('compute_inline_sse',bool(re.search(r'\b'+opcode+r'\s+xmm0,xmm1',text)),(binary.name,opcode))
        code_evidence.append({'binary':binary.name,'start':hex(start),'end':hex(end),'byte_length':end-start,
                              'call_targets':sorted(set(targets)),'disassembly_sha256':hashlib.sha256(text.encode()).hexdigest()})
    evidence['compute_code_audit']=code_evidence

def pty_tests(c,binaries,evidence,artifacts):
    for binary in binaries:
        with Terminal(binary,['--workbench','-e','sqrt([1,4,9,16])+2']) as t:
            c.check('pty_enter',t.wait_for('REGISTERS') and not (termios.tcgetattr(t.slave)[3]&termios.ICANON),binary.name)
            initial=t.screen();c.check('pty_panels',all(x in initial for x in ('AST','INSTRUCTIONS','completed node','sqrtpd')),initial[:200])
            t.send(b'\x1b[B');c.check('pty_event_link', '3 | 4' in t.screen() or '3  | 4' in t.screen() or 'frame 2' in t.screen(),t.screen())
            t.send(b'b');c.check('pty_register_bits','4008000000000000' in t.screen() and '4010000000000000' in t.screen(),binary.name)
            t.send(b'eA=ones(20,30)\r',.25);c.check('pty_editor_submit',t.wait_for('A=ones(20,30)') and '20x30' in t.screen().replace(' ',''),t.screen())
            t.send(b'\t\tG');c.check('pty_value_viewport','r20 c30: 1' in t.screen(),t.screen())
            t.send(b'ex=linspace(-1,1,9)\r',.2)
            t.send(b'ey=sin(x)\r',.25)
            t.send(b'/polynomial\r',.15);c.check('pty_search', 'trig-polynomial' in t.screen(),t.screen())
            t.send(b'f');c.check('pty_search_next','trig-polynomial' in t.screen(),binary.name)
            t.send(b'/ZZZ-not-an-op\r');c.check('pty_search_notfound','No matching' in t.screen(),t.screen())
            t.send(b'e\x1b[A',.15);c.check('pty_history','y=sin(x)' in t.screen(),binary.name)
            t.send(b'\x1b',.15)
            # Capture an actual screen; no invented UI or externally generated image.
            t.send(b'/polynomial\r',.1)
            if binary.name=='asmlab':
                (artifacts/'workbench-120x34.txt').write_text(t.screen())
            t.resize(24,80);c.check('pty_resize',t.process.poll() is None and 'ASMlab' in t.screen(),t.screen()[:100])
            if binary.name=='asmlab': (artifacts/'workbench-80x24.txt').write_text(t.screen())
            t.resize(8,35);c.check('pty_small_window','80' in t.screen() and '24' in t.screen(),t.screen())
            t.resize(1,1);c.check('pty_minimal_window',t.process.poll() is None,binary.name)
            t.resize(34,120)
            t.send(b'm');c.check('pty_next_not_last','NEXT: compute' in t.screen() and 'LAST: observe' in t.screen(),t.screen()[:200])
            t.send(b'esum(y)\r',.2);c.check('pty_compute_screen',t.wait_for('LAST: compute') and 'no' in t.screen().lower(),t.screen())
            t.send(b'e\x15(1+2)\x1b[D\x7f4\r',.2);c.check('pty_edit_keys','(1+4)' in t.screen() and 'r1 c1: 5' in t.screen(),'cursor/backspace produce 5')
            t.send(b'e1/0\r',.12);c.check('pty_error_no_snapshot','No completed value' in t.screen(),t.screen())
            t.send(b'\t\tG\x1b[B\x1b[C',.06);c.check('pty_error_navigation',t.process.poll() is None,binary.name)
            t.send(b'eans\r',.12);c.check('pty_error_preserves_ans','r1 c1: 5' in t.screen(),t.screen())
            t.send(b'c');c.check('pty_clear','cleared' in t.screen().lower() and 'no' in t.screen().lower(),t.screen())
            rc=t.quit();c.check('pty_exit_restore',rc==1 and t.restored() and b'\x1b[?1049l' in t.data,(binary.name,rc))
        for sig in (signal.SIGINT,signal.SIGTERM,signal.SIGHUP,signal.SIGQUIT,signal.SIGPIPE):
            with Terminal(binary,['--workbench','-e','1+2']) as t:
                t.wait_for('REGISTERS');os.kill(t.process.pid,sig);t.pump(.15)
                rc=t.process.wait(timeout=3)
                c.check('pty_signal_restore',rc==128+sig and t.restored() and b'\x1b[?25h' in t.data,(binary.name,sig,rc))
        with Terminal(binary,['--workbench','-e','1+2']) as t:
            t.wait_for('REGISTERS');os.kill(t.process.pid,signal.SIGTSTP)
            stop=False
            for _ in range(50):
                t.pump(.02)
                status=Path(f'/proc/{t.process.pid}/status').read_text()
                if re.search(r'^State:\s+T',status,re.M):stop=True;break
            c.check('pty_suspend_restore',stop and t.restored(),binary.name)
            os.kill(t.process.pid,signal.SIGCONT);t.pump(.2)
            c.check('pty_resume',t.process.poll() is None and not (termios.tcgetattr(t.slave)[3]&termios.ICANON),binary.name)
            rc=t.quit();c.check('pty_resume_exit',rc==0 and t.restored(),binary.name)
        # Legacy canonical REPL may prefetch input. Entering/leaving workbench must not drop it.
        with Terminal(binary,[]) as t:
            t.send(b'1+2\n:workbench\nq\n7+8\n:quit\n',.35)
            rc=t.process.wait(timeout=3)
            c.check('pty_buffered_repl',rc==0 and t.restored() and b'7+8' in t.data and b'15' in t.data,(binary.name,rc))
    evidence['pty_profiles']=[b.name for b in binaries]
    evidence['pty_scope']='Controlling Linux PTY: edit/history/search/focus/value scroll, resize to 1x1 and back, signals, suspend/resume, buffered REPL. No physical WSL terminal tested.'

def benchmark(binary,evidence):
    expr='sum(sin(linspace(-3,3,8192)))';timings={}
    for mode in ('observe','compute'):
        values=[]
        for _ in range(5):
            started=time.perf_counter();r=run(binary,'--json','--mode',mode,'-e',expr)
            if r.returncode:raise AssertionError('benchmark expression failed')
            values.append(time.perf_counter()-started)
        timings[mode]={'seconds':values,'median_seconds':statistics.median(values)}
    evidence['illustrative_end_to_end_timing']={'expression':expr,'runs_per_mode':5,'results':timings,
        'scope':'Includes process launch, parser, allocation, JSON formatting; one local host and workload, not a performance guarantee. Observe caps retained frames but runs all watched instructions.'}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report',type=Path,required=True)
    a=p.parse_args();a.report.parent.mkdir(parents=True,exist_ok=True);c=Checks();evidence={};started=time.monotonic()
    try:
        metas=[validate_app('asmlab','release'),validate_app('asmlab-debug','debug')]
        binaries=[ROOT/m['binary'] for m in metas]
        for name,fn,args in [('modes',mode_tests,(c,binaries,evidence)),('trace',trace_tests,(c,binaries,evidence)),
                ('code',code_tests,(c,binaries,evidence)),('pty',pty_tests,(c,binaries,evidence,a.report.parent))]:
            print('Testing '+name,flush=True);fn(*args)
        benchmark(binaries[0],evidence)
    except (OSError,ValueError,KeyError,RuntimeError,AssertionError,subprocess.SubprocessError) as e:
        c.check('fatal',False,repr(e))
    result={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),'executed_at_utc':datetime.now(timezone.utc).isoformat(),
      'case_count':sum(c.counts.values()),'group_counts':dict(c.counts),'failure_count':len(c.failures),'failures':c.failures,
      'elapsed_seconds':round(time.monotonic()-started,3),'evidence':evidence,
      'limitations':['Finite tests, not formal correctness or safety proof. Actual selected SSE2 captures, not full CPU trace.',
                     'Compute is a build-time specialization, not a JIT or a claim of global speed superiority.',
                     'Workbench displays completed node values; it is not a debugger resuming halfway through execution.',
                     'Signals are serviced at UI boundaries; uncatchable SIGKILL/SIGSTOP or a crash cannot guarantee cleanup.']}
    a.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='evidence'},indent=2));return int(bool(c.failures))
if __name__=='__main__':raise SystemExit(main())
