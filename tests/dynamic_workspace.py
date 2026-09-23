#!/usr/bin/env python3
"""Dynamic Workspace regression + allocator ABI checks. Python is test-only.
No fabricated capacities, oracle substitutions, or simulated allocation success.
"""
from __future__ import annotations
import argparse
import ctypes as C
import hashlib
import json
import math
import os
import errno
import pty
import select
import time
import tty
from pathlib import Path
import random
import resource
import shutil
import struct
import subprocess
import tempfile
from runtime_suite import Checks, Native, ptr, s64, U64
from native_contract import frames
ROOT=Path(__file__).resolve().parents[1]
BINS=['asmlab','asmlab-debug','asmlab-libc-reference']
PAGE=4096

def bits(x):return struct.pack('<d',float(x)).hex()
def execute(name,expr=None,script=None,args=(),rlimit=None):
    def restrict():resource.setrlimit(resource.RLIMIT_AS,(rlimit,rlimit))
    cmd=[str(ROOT/'bin'/name),'--json',*args]
    if expr is not None:cmd+=['-e',expr]
    p=subprocess.run(cmd,input=script,text=True,capture_output=True,timeout=30,preexec_fn=restrict if rlimit else None)
    rows=[json.loads(line,parse_int=lambda s: -0.0 if s=="-0" else int(s)) for line in p.stdout.splitlines() if line.strip()]
    return p,rows

def alloc_tests(c):
    n=Native('dynamic-memory.so',c)
    def call(fn,*a):return n.invoke(fn,*a,group='allocator_abi')
    def stats():
        out=(C.c_uint64*6)();ret,_=call('rt_memory_stats',ptr(out))
        c.check('allocator_stats_status',ret==0,ret);return list(out)
    c.check('allocator_start',stats()==[0,0,67108864,0,0,0],'fresh fixture')
    for lim in [0,1,1048575,1073741825,U64]:
        old=stats();ret,_=call('rt_memory_set_limit',lim)
        c.check('quota_invalid',ret==-22 and stats()==old,lim)
    for size in [0,U64,U64-1,U64-4095]:
        old=stats();p,e=call('rt_heap_alloc',size)
        c.check('allocation_reject',p==0 and s64(e)<0 and stats()==old,(size,p,s64(e)))
    old=stats();ret,_=call('rt_heap_free',0);c.check('free_null',ret==0 and stats()==old,ret)
    live=[];rng=random.Random(20260924)
    for size in [1,15,16,17,63,64,4063,4064,4065,4095,4096,4097,65520,65536]+[rng.randrange(1,18000) for _ in range(200)]:
        old=stats();p,e=call('rt_heap_alloc',size)
        c.check('allocate',p>0 and e==0,(size,p,e))
        if p<=0:continue
        charge=((size+32+4095)//4096)*4096
        after=stats()
        c.check('mapping_accounting',after[0]==old[0]+charge and after[3]==old[3]+1 and after[4]==old[4]+1,(size,old,after))
        c.check('alignment',p%16==0,(size,p))
        c.check('anonymous_zero',C.string_at(p,size)==bytes(size),size)
        value=rng.randrange(1,256);C.memset(p,value,size)
        live.append((p,size,value,charge))
        if len(live)>8:
            j=rng.randrange(len(live));q,sz,v,ch=live.pop(j)
            c.check('live_payload',C.string_at(q,sz)==bytes([v])*sz,sz)
            before=stats();ret,_=call('rt_heap_free',q);after=stats()
            c.check('free_accounting',ret==0 and after[0]==before[0]-ch and after[3]==before[3]-1 and after[5]==before[5]+1,sz)
    for q,sz,v,ch in live:
        c.check('retained_payload',C.string_at(q,sz)==bytes([v])*sz,sz);call('rt_heap_free',q)
    st=stats();c.check('all_freed',st[0]==st[3]==0 and st[4]==st[5],st)
    ret,_=call('rt_memory_set_limit',1048576);c.check('quota_min',ret==0,ret)
    p,e=call('rt_heap_alloc',1048576-32)
    c.check('exact_mapping_limit',p>0 and stats()[0]==1048576,(p,e))
    old=stats();q,e=call('rt_heap_alloc',1)
    c.check('quota_no_mutation',q==0 and s64(e)==-12 and stats()==old,(q,e))
    call('rt_heap_free',p);call('rt_memory_set_limit',4194304)
    p,e=call('rt_heap_alloc',2097152)
    old=stats();ret,_=call('rt_memory_set_limit',1048576)
    c.check('quota_live_busy',ret==-16 and stats()==old,(ret,old))
    call('rt_heap_free',p);call('rt_memory_set_limit',67108864)
    st=stats();c.check('allocator_final',st[0]==st[3]==0 and st[4]==st[5],st)
    return {'successful_mappings':st[4],'unmaps':st[5],'peak_bytes':st[1]}

def numeric_tests(c,name):
    rng=random.Random(40300)
    def check(expr,r,col,expected):
        p,rows=execute(name,expr)
        ok=p.returncode==0 and len(rows)==1 and rows[0].get('ok') is True
        c.check(name+'.success',ok,expr)
        if not ok:return
        got=rows[0];c.check(name+'.shape',(got['rows'],got['cols'])==(r,col),expr)
        c.check(name+'.values',len(got['data'])==len(expected) and all(bits(a)==bits(b) for a,b in zip(got['data'],expected)),expr)
    for n,m in [(1,1),(1,17),(17,1),(17,19),(32,31),(65,7)]+[(rng.randint(1,36),rng.randint(1,36)) for _ in range(35)]:
        check(f'zeros({n},{m})',n,m,[0]*(n*m))
        check(f'ones({n},{m})',n,m,[1]*(n*m))
        check(f'eye({n},{m})',n,m,[int(i==j) for i in range(n) for j in range(m)])
        check(f'size(ones({n},{m}))',1,2,[n,m])
        check(f'size(ones({n},{m}),1)',1,1,[n])
        check(f'size(ones({n},{m}),2)',1,1,[m])
        check(f"size(ones({n},{m})')",1,2,[m,n])
    for n in [1,2,17,33]:
        check(f'ones({n})',n,n,[1]*(n*n));check(f'zeros({n})',n,n,[0]*(n*n))
        check(f'eye({n})',n,n,[int(i==j) for i in range(n) for j in range(n)])
    for a,b,n in [(0,1,1),(-7,5,2),(-1,1,17),(7,-4,101),(0,1,1001),(-1e308,1e308,5),(-0.0,0.0,7),(0.0,-0.0,2)]+[(rng.uniform(-5,5),rng.uniform(-5,5),rng.randint(2,120)) for _ in range(30)]:
        values=[b] if n==1 else [a]+[(float(i)/float(n-1))*b+(1.-float(i)/float(n-1))*a for i in range(1,n-1)]+[b]
        check(f'linspace({a!r},{b!r},{n})',1,n,values)
    for n,k,m in [(17,3,19),(3,17,2),(23,19,5),(33,2,31)]:
        check(f'ones({n},{k})*ones({k},{m})',n,m,[k]*(n*m))
        check(f'(ones({n},{k})+2).*ones({n},{k})',n,k,[3]*(n*k))
        check(f'sqrt(ones({n},{k})*4)',n,k,[2]*(n*k))
    vals=list(range(1,324));literal='['+';'.join(','.join(map(str,vals[i*19:(i+1)*19])) for i in range(17))+']'
    check(literal,17,19,vals)
    check(literal+"'",19,17,[vals[i*19+j] for j in range(19) for i in range(17)])
    check(literal+'./2',17,19,[v/2 for v in vals])
    b=[i%11 for i in range(19*7)]
    rhs='['+';'.join(','.join(map(str,b[i*7:(i+1)*7])) for i in range(19))+']'
    check(literal+'*'+rhs,17,7,[sum(vals[i*19+k]*b[k*7+j] for k in range(19)) for i in range(17) for j in range(7)])
    check('ones(size(eye(17,19),1),size(eye(17,19),2))',17,19,[1]*323)
    check('size(zeros(1024))',1,2,[1024,1024])
    check('size(zeros(1,1048576))',1,2,[1,1048576])
    return None

def bad_inputs(c,name):
    invalid=['zeros()','ones(1,2,3)','eye(1,2,3)','size()','size(1,1,1)','linspace(1,2)',
      'linspace(1,2,3,4)','sin(1,2)','zeros(0)','zeros(-1)','ones(1.1)','eye(1,0)',
      'zeros(1,1048577)','ones(1048576,1048576)','zeros(1e200,1)','zeros([1,2])',
      'size(ones(2),0)','size(ones(2),3)','size(ones(2),1.5)','linspace([1,2],3,10)',
      'linspace(1,[2,3],10)','linspace(0,1,0)','linspace(0,1,1.5)','ones(1,)',
      'ones(,1)','size(ones(2),)','ones(1,2','zeros(1 2)','missing(1,1)',
      'ones(257)*ones(257)','ones(16,17)*ones(16,17)','linspace=7','zeros=3',
      'size=4','eye=4','ones=7']
    for expr in invalid:
        p,rows=execute(name,expr);c.check(name+'.reject',p.returncode==1 and len(rows)==1 and rows[0].get('ok') is False,expr)
    for expr in ['A(0,1)','A(18,1)','A(1,20)','A(-1,1)','A(1,1.5)','A([1,2],1)',
                 'A(1)','A(1,2,3)','A(1,1)=3','A(:,1)','A(1:end,1)']:
        p,rows=execute(name,script=f'A=ones(17,19)\n{expr}\n')
        c.check(name+'.index_reject',p.returncode==1 and len(rows)==2 and rows[-1].get('ok') is False,expr)
    for text in ['0','1025','1.5','-1','foo','18446744073709551616']:
        p=subprocess.run([str(ROOT/'bin'/name),'--memory-mib',text],text=True,capture_output=True,timeout=10)
        c.check(name+'.quota_cli',p.returncode==2,text)

def sessions(c,name):
    script='A=ones(17,19)\nB=A\nA=A+1\nB(17,19)\nA(17,19)\nA=A\nA=A\'\nsize(A)\nA(19,17)\n:size\n:clear\n:memory\nans\n'
    p,rows=execute(name,script=script)
    expected={3:[1],4:[2],7:[19,17],8:[2],11:[0]}
    c.check(name+'.session_shape',len(rows)==12,len(rows))
    for i,v in expected.items():c.check(name+'.session_copy',len(rows)>i and rows[i].get('data')==v,(i,v))
    mem=next((x['memory'] for x in rows if 'memory'in x),{})
    c.check(name+'.clear_release',mem.get('used_bytes')==mem.get('live_mappings')==0 and mem.get('maps')==mem.get('unmaps'),mem)
    # Shape/domain/syntax errors never publish a partial new target or ans.
    for expr in ['A=zeros(1048576,2)','A=sqrt(-1)','A=ones(2,3)+ones(3,2)','A=linspace(1,2,0)','A=ones(2,)']:
        p,rows=execute(name,script=f'A=ones(17,19)\n99\n{expr}\nans\nA(17,19)\n:clear\n:memory\n')
        c.check(name+'.atomic_error',p.returncode==1 and rows[2].get('ok') is False and rows[3].get('data')==[99] and rows[4].get('data')==[1],expr)
        c.check(name+'.error_cleanup',rows[-1]['memory']['used_bytes']==0,expr)
    script='\n'.join(f'v{i}={i}' for i in range(320))+'\n:memory\nv0+v319\n:drop v159\n:drop v319\n:drop v0\n:memory\nv160\nv159\n:clear\n:memory\n'
    p,rows=execute(name,script=script)
    mem=[x['memory'] for x in rows if 'memory'in x]
    c.check(name+'.symbols_growth',mem[0]['user_variables']==320 and mem[1]['user_variables']==317,mem)
    c.check(name+'.symbols_lookup',rows[321].get('data')==[319] and rows[-3].get('data')==[160] and rows[-2].get('ok') is False, 'linked lookup/deletion')
    c.check(name+'.symbols_clear',mem[-1]['used_bytes']==0 and mem[-1]['maps']==mem[-1]['unmaps'],mem[-1])
    p,rows=execute(name,script='A=7\n:drop A\nans\n:drop ans\nans\n:clear\n:memory\n')
    c.check(name+'.drop_ans',rows[1].get('data')==[7] and rows[2].get('ok') is False and rows[3].get('data')==[7],rows)
    # No alias to a cleared arena and no increasing leak on replacement/drop/clear.
    script=('A=ones(19,23)\nB=A\nA=A+1\nB(19,23)\n:drop B\n:clear\n:memory\n')*180
    p,rows=execute(name,script=script)
    mem=[x['memory'] for x in rows if 'memory'in x]
    c.check(name+'.churn_exit',p.returncode==0 and len(mem)==180,p.returncode)
    for i,m in enumerate(mem):c.check(name+'.churn_balanced',m['used_bytes']==m['live_mappings']==0 and m['maps']==m['unmaps'] and m['peak_bytes']<1048576,(i,m))

def failure_tests(c,name):
    detail=[]
    for target in ['A','B']:
        script=f'A=ones(1,25000)\n99\n:memory\n{target}=zeros(1,40000)\n:memory\nans\nA(1,25000)\n'
        if target=='B':script+='B(1,1)\n'
        script+=':clear\n:memory\n'
        p,rows=execute(name,script=script,args=['--memory-mib','1'])
        m=[x['memory'] for x in rows if 'memory'in x]
        c.check(name+'.oom_commit',p.returncode==1 and rows[3].get('ok') is False and rows[5].get('data')==[99] and rows[6].get('data')==[1],target)
        # Three or four successful maps followed by failure: staged target copied,
        # but ans allocation denied. New-symbol case also staged an entry.
        c.check(name+'.oom_stage_reached',m[1]['maps']-m[0]['maps']==(3 if target=='A' else 4),m)
        c.check(name+'.oom_no_orphan',m[1]['user_variables']==1 and (target=='A' or rows[7].get('ok') is False),target)
        c.check(name+'.oom_temp_reclaimed',m[1]['used_bytes']==208896 and m[1]['live_mappings']==3,m[1])
        c.check(name+'.oom_clear',m[-1]['used_bytes']==m[-1]['live_mappings']==0 and m[-1]['maps']==m[-1]['unmaps'],m[-1])
        detail.append({'profile':name,'target':target,'memory_before':m[0],'memory_after_failure':m[1],'memory_after_clear':m[-1]})
    # OS-enforced mmap failure, independent of our default 64MiB budget.
    p,rows=execute(name,script='A=7\n99\nA=zeros(1,1048576)\nans\nA(1,1)\n:clear\n:memory\n',rlimit=8*1048576)
    c.check(name+'.kernel_oom',p.returncode==1 and len(rows)==6 and rows[2].get('ok') is False and rows[3].get('data')==[99] and rows[4].get('data')==[7],str(rows)[-1200:])
    c.check(name+'.kernel_oom_cleanup',rows[-1].get('memory',{}).get('used_bytes')==0,str(rows)[-800:])
    return detail

def visual_tests(c,name):
    p=subprocess.run([str(ROOT/'bin'/name),'--bits','-e','linspace(-1,1,5)'],text=True,capture_output=True,timeout=20)
    f=frames(p.stdout)
    c.check(name+'.linspace_trace',p.returncode==0 and len(f)==6 and f[1]['op']=='movapd' and f[1]['after'][0]==int.from_bytes(struct.pack('<d',-1),'little'), 'real endpoint/default6 frames')
    c.check(name+'.linspace_ast',p.stdout.count('number')>=3 and 'linspace' in p.stdout,'three argument AST')
    p=subprocess.run([str(ROOT/'bin'/name),'--bits'],input='A=ones(17,19)\nA(17,19)\n',text=True,capture_output=True,timeout=20)
    f=frames(p.stdout)
    c.check(name+'.index_trace',p.returncode==0 and any(x['element']==322 and x['op']=='movapd' and x['after'][0]==0x3ff0000000000000 for x in f),'read element322 value1')
    p=subprocess.run([str(ROOT/'bin'/name),'-e','ones(24,31)'],text=True,capture_output=True,timeout=20)
    c.check(name+'.bounded_preview',p.returncode==0 and len(p.stdout)<9000 and 'preview' in p.stdout.lower(),len(p.stdout))
    p,rows=execute(name,'ones(24,31)');c.check(name+'.json_not_truncated',len(rows[0]['data'])==744,'744 values')
    p=subprocess.run([str(ROOT/'bin'/name),'--quiet','-e','ones(1,1001)'],text=True,capture_output=True,timeout=20)
    c.check(name+'.quiet_not_truncated',p.returncode==0 and len(p.stdout.split())==1001,len(p.stdout.split()))



def lifetime_tests(c,name):
    # Queued PTY replay proves trace/AST values survive dropping their source.
    # clear/failure intentionally invalidate the captured-expression lifetime.
    for suffix,expect_exit in [(':clear\n:replay\n:memory\n:quit\n',0),
                               ('sqrt(-1)\n:replay\n:clear\n:memory\n:quit\n',1)]:
        master,slave=pty.openpty();tty.setraw(slave)
        proc=subprocess.Popen([str(ROOT/'bin'/name),'--bits','--no-color'],stdin=slave,stdout=slave,stderr=slave,close_fds=True)
        os.close(slave);data=bytearray()
        try:
            os.write(master,('A=ones(17,19)\nA(17,19)+2\n:drop A\n:replay\nn\np\nq\n'+suffix).encode())
            end=time.monotonic()+10
            while time.monotonic()<end:
                ready,_,_=select.select([master],[],[],.05)
                if ready:
                    try:
                        block=os.read(master,65536)
                        if not block:break
                        data+=block
                    except OSError as e:
                        if e.errno==errno.EIO:break
                        raise
                if proc.poll() is not None and not ready:break
            if proc.poll() is None:proc.kill()
            proc.wait(timeout=2)
            c.check(name+'.replay_drop_survives',proc.returncode==expect_exit and data.count(b'CAPTURE REPLAY')==3,(proc.returncode,len(data)))
            c.check(name+'.replay_invalidated',data.count(b'Replay needs a TTY')==1 and b'MEMORY  mapped 0 bytes' in data, len(data))
        finally:
            os.close(master)
            if proc.poll() is None:proc.kill();proc.wait()
    # No CLI-level variable assignment rewrites the parse tree from which the
    # interpreter is currently reading; all returned values are owned copies.
    p,rows=execute(name,script='A=ones(17,19)\n[size(A,1),A(1,1);size(A,2),A(17,19)]\n')
    c.check(name+'.nested_arguments_matrix',p.returncode==0 and rows[-1].get('data')==[17,1,19,1],rows[-1])
    p=subprocess.run([str(ROOT/'bin'/name),'--bits','-e','sin(linspace(0,1,3000))'],text=True,capture_output=True,timeout=20)
    c.check(name+'.trace_overflow_visible',p.returncode==0 and ('not retained' in p.stdout or '8192' in p.stdout),len(p.stdout))
    rng=random.Random(4400)
    expressions=[]
    atoms=['0','1','-1','1.5','1e300','[1,2]','ones(2,3)','size(eye(2))','missing']
    for _ in range(450):
        fn=rng.choice(['ones','zeros','eye','size','linspace','sqrt','A','sin'])
        args=','.join(rng.choice(atoms) for _ in range(rng.randrange(5)))
        expressions.append(fn+'('+args+rng.choice([')',')+1',',)',']','))']))
    # Limit to 1 MiB and clear after every case, whether accepted or rejected.
    script=''.join(expr+'\n:clear\n:memory\n' for expr in expressions)
    p,rows=execute(name,script=script,args=['--memory-mib','1'])
    mem=[r['memory'] for r in rows if 'memory'in r]
    c.check(name+'.dynamic_fuzz_exit',p.returncode in (0,1) and len(rows)==900 and len(mem)==450,p.returncode)
    for i,m in enumerate(mem):c.check(name+'.dynamic_fuzz_cleanup',m['used_bytes']==m['live_mappings']==0 and m['maps']==m['unmaps'],i)


def empty_root_dynamic(c):
    evidence=[]
    if os.geteuid()!=0:return [{'skipped':'chroot privilege required; never claimed executed'}]
    for name in BINS[:2]:
        binary=ROOT/'bin'/name
        with tempfile.TemporaryDirectory(prefix='asmlab dynamic empty root ') as td:
            root=Path(td);root.chmod(0o755);shutil.copy2(binary,root/'asmlab');(root/'asmlab').chmod(0o755)
            script='A=ones(32,33)\nB=A\nA=A+2\nB(32,33)\n:drop A\n:clear\n:memory\n'
            (root/'script').write_text(script);(root/'script').chmod(0o644)
            def isolate():
                os.chroot(root);os.chdir('/');os.setgroups([]);os.setgid(65534);os.setuid(65534)
            for args,stdin in [(['--json','-f','/script'],None),(['--json'],script)]:
                rr=subprocess.run(['/asmlab',*args],input=stdin,text=True,capture_output=True,timeout=10,preexec_fn=isolate,env={'PATH':'/missing'})
                rows=[json.loads(x) for x in rr.stdout.splitlines()]
                c.check('dynamic_empty_root',rr.returncode==0 and not rr.stderr and rows[3].get('data')==[1] and rows[-1]['memory']['used_bytes']==0,(name,args))
            evidence.append({'binary':name,'root_files':['/asmlab','/script'],'execution_uid':65534,'cases':2,
                             'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()})
    return evidence

def parity(c):
    lines=['A=linspace(-2,3,37)','B=ones(17,19)','C=B\'','C(19,17)','size(C)','sum(A)','sqrt(B*9)',
           'A(1,37)','B=ones(19,17)','C(19,17)',':drop B',':clear','ans','eye(17,19)','linspace(1,-1,19)',
           'ones(17,3)*ones(3,19)','size(zeros(1,1048576))']
    # Quotas/errors/addresses intentionally not normalized into pretending to match.
    outputs=[]
    for name in BINS:
        p,rows=execute(name,script='\n'.join(lines)+'\n');outputs.append(rows)
        c.check('parity_exit',p.returncode==0,name)
    for i,records in enumerate(zip(*outputs)):
        c.check('backend_parity',records[0]==records[1]==records[2],i)
    return len(outputs[0])

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--report',type=Path,default=ROOT/'build/dynamic-workspace.json');args=ap.parse_args()
    c=Checks();evidence={}
    try:
        evidence['allocator']=alloc_tests(c)
        evidence['atomic_oom']=[]
        for name in BINS:
            numeric_tests(c,name);bad_inputs(c,name);sessions(c,name)
            evidence['atomic_oom']+=failure_tests(c,name);visual_tests(c,name);lifetime_tests(c,name)
        evidence['backend_result_records']=parity(c)
        evidence['dynamic_empty_root']=empty_root_dynamic(c)
    except Exception as e:
        import traceback
        c.check('suite_exception',False,str(e));evidence['exception']=traceback.format_exc()
    result=c.report();result.update(schema_version=1,version=(ROOT/'VERSION').read_text().strip(),evidence=evidence,
      limitations=['Tests are finite samples, not formal memory-safety or numerical proofs.',
                  'Quota accounts page-rounded dynamic mappings, not stack, static storage, total RSS or CPU time.',
                  'Arbitrary/double free is outside the allocator ABI; no thread-safe API or user-code execution.',
                  'Operating-system OOM-killer termination is not a recoverable allocation-error guarantee.'])
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='evidence'},indent=2));return int(bool(c.failures))
if __name__=='__main__':raise SystemExit(main())
