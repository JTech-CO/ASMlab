#!/usr/bin/env python3
"""L3 integration: empty-root execution, no runtime mappings, bounded I/O,
shared replay input and reference rendering. Not a public-server security test.
"""
from __future__ import annotations
import argparse, errno, hashlib, json, os, pty, re, select, shutil, signal, subprocess, sys, tempfile, time, tty
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from check_provenance import ROOT,validate_app,validate_foundation
from runtime_suite import Checks

def run(binary,*args,**kwargs):
    return subprocess.run([str(binary),*args],capture_output=True,text=True,timeout=10,**kwargs)

def main():
    p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True)
    p.add_argument('--require-empty-root',action='store_true');a=p.parse_args();c=Checks();evidence=[];skips=[]
    metas=[validate_app('asmlab','release'),validate_app('asmlab-debug','debug')];validate_foundation()
    binaries=[ROOT/m['binary'] for m in metas]
    for meta,binary in zip(metas,binaries):
        c.check('elf_audit',subprocess.run(['sh','tests/audit.sh',str(binary)],cwd=ROOT,capture_output=True).returncode==0,binary.name)
        # Exact linker boundary: direct ld, exclusively owned NASM object inputs.
        command=meta['commands'][-1]
        c.check('static_link_inputs','-static' in command and '--no-undefined' in command and '-e' in command
                and not any(t.endswith(('.a','.so')) or t.startswith('-l') for t in command[1:]),binary.name)
        objects=meta['project_objects']
        c.check('assembly_only_objects',all(o['source'].startswith('src/') and o['source'].endswith('.asm')
                and 'libc_' not in o['source'] and '/tests/' not in o['source'] for o in objects),binary.name)
        maps=''
        proc=subprocess.Popen([str(binary),'--json'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            time.sleep(.03)
            maps=Path(f'/proc/{proc.pid}/maps').read_text()
            mappings=[line.split(maxsplit=5)[5] for line in maps.splitlines() if len(line.split(maxsplit=5))==6]
            backed={x for x in mappings if x.startswith('/')}
            c.check('runtime_file_mappings',backed=={str(binary.resolve())},sorted(backed))
            out,err=proc.communicate(b'sqrt(4)\n',timeout=5)
            c.check('mapped_process_result',proc.returncode==0 and json.loads(out)['data']==[2],binary.name)
            evidence.append({'binary':binary.name,'file_backed_mappings':sorted(backed),'kernel_special_mappings':sorted({x for x in mappings if x.startswith('[')})})
        finally:
            if proc.poll() is None:proc.kill();proc.wait()
        # Correct final flushing is mandatory on all short-lived paths.
        for arg in ['--version','--help']:
            rr=run(binary,arg);c.check('early_exit_flush',rr.returncode==0 and len(rr.stdout)>20 and not rr.stderr,(binary.name,arg))
        if Path('/dev/full').exists():
            with open('/dev/full','wb') as full:
                rr=subprocess.run([str(binary),'--json','-e','1+2'],stdout=full,stderr=subprocess.PIPE,timeout=5)
            c.check('output_failure_exit',rr.returncode==2 and b'write/flush failed' in rr.stderr,binary.name)
        # Closed stdin is a stream error, never an EOF-success or partial expression.
        rr=run(binary,'--json',preexec_fn=lambda:os.close(0))
        c.check('closed_input_error',rr.returncode==2 and not json.loads(rr.stdout)['ok'],binary.name)
        rr=run(binary,'--json','-f',str(ROOT/'src'))
        c.check('directory_read_error',rr.returncode==2 and not json.loads(rr.stdout)['ok'],binary.name)
        rr=run(binary,'--json',input='1+2')
        c.check('unterminated_final_line',rr.returncode==0 and json.loads(rr.stdout)['data']==[3],binary.name)
        payload='A=7\n'+'1'*4096+'\nA\nans\n'
        rr=run(binary,'--json',input=payload);rows=[json.loads(x) for x in rr.stdout.splitlines()]
        c.check('large_line_buffer_recovery',rr.returncode==1 and len(rows)==4 and not rows[1]['ok'] and rows[2]['data']==rows[3]['data']==[7],binary.name)
        rr=run(binary,'--json',input='9\n1e999999\nans\n0e999999\n-1e-999999\n')
        rows=[json.loads(x) for x in rr.stdout.splitlines()]
        c.check('decimal_overflow_rollback',rr.returncode==1 and not rows[1]['ok'] and rows[2]['data']==[9] and rows[3]['data']==[0] and '[-0]' in rr.stdout,binary.name)
        env={**os.environ,'PATH':'/not-present','LANG':'de_DE.UTF-8','LC_ALL':'de_DE.UTF-8','LD_PRELOAD':'/not-present/fake.so'}
        rr=run(binary,'--json','-e','0.1+0.2',env=env)
        c.check('locale_loader_independent',rr.returncode==0 and not rr.stderr and json.loads(rr.stdout)['data']==[0.30000000000000004],binary.name)
        # All queued commands fit in one raw TTY read: replay must consume the
        # same Reader as the REPL rather than resetting/refetching stdin.
        master,slave=pty.openpty();tty.setraw(slave)
        proc=subprocess.Popen([str(binary),'--step','--bits','--no-color'],stdin=slave,stdout=slave,stderr=slave,close_fds=True)
        os.close(slave);data=bytearray()
        try:
            os.write(master,b'sqrt([1,4,9,16])+2\nn\np\nq\n7*8\nq\n:quit\n')
            deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                ready,_,_=select.select([master],[],[],.05)
                if ready:
                    try:
                        block=os.read(master,65536)
                        if not block:break
                        data+=block
                    except OSError as exc:
                        if exc.errno==errno.EIO:break
                        raise
                if proc.poll() is not None and not ready:break
            if proc.poll() is None:proc.kill()
            proc.wait(timeout=2)
            c.check('shared_reader_replay_queue',proc.returncode==0 and b'input  7*8' in data and b'56' in data and data.count(b'CAPTURE REPLAY')>=4,binary.name)
        finally:
            os.close(master)
            if proc.poll() is None:proc.kill();proc.wait()
        # Parser conversion must not contaminate the numerical trace's flags.
        rr=run(binary,'--all','--bits','--no-color','-e','0.1+0.2')
        pairs=re.findall(r'MXCSR 0x([a-f0-9]+) -> 0x([a-f0-9]+)',rr.stdout)
        c.check('clean_evaluator_fp_entry',len(pairs)==1 and int(pairs[0][0],16)==0x1f80 and (int(pairs[0][1],16)&0x20)!=0,binary.name)
    # Rendering parity is stronger than just numeric JSON equality. Program
    # counters differ with linking and are intentionally normalized.
    reference=ROOT/'bin/asmlab-libc-reference'
    exprs=['1.25','-0','sqrt([1,4,9,16])+2','sin(0.1)','log(1e-320)',
           '[1e-320,-1e308,0.1,1234,999.99]', '[[1]]', '1/0', '-[0,1e-30,3]',
           '1e-320+0', '[1,2;3,4]*[5,6;7,8]']
    for expr in exprs:
        for mode in ['--quiet','--json','--bits']:
            a1=run(binaries[0],mode,'--all','--no-color','-e',expr)
            b1=run(reference,mode,'--all','--no-color','-e',expr)
            norm=lambda s:re.sub(r'@0x[0-9a-f]+','@PC',s)
            c.check('reference_rendering',a1.returncode==b1.returncode and norm(a1.stdout)==norm(b1.stdout),(expr,mode))
    # All-input correctness is not inferred from an empty filesystem. This is
    # a concrete proof of execution without a userspace loader/library/shell.
    if os.geteuid()==0:
        for binary in binaries:
            with tempfile.TemporaryDirectory(prefix='asmlab empty root ') as td:
                root=Path(td);root.chmod(0o755)
                shutil.copy2(binary,root/'asmlab');(root/'asmlab').chmod(0o755)
                (root/'script.asmlab').write_text('A=[1,2;3,4]\nA*A\nsqrt([1,4,9,16])+2\n');(root/'script.asmlab').chmod(0o644)
                def isolate():
                    os.chroot(root);os.chdir('/');os.setgroups([]);os.setgid(65534);os.setuid(65534)
                for args,stdin,expected in [(['--json','-e','log(1)'],None,[0]),
                      (['--json'],'0.1+0.2\n',[0.30000000000000004]),
                      (['--json','-f','/script.asmlab'],None,[3,4,5,6])]:
                    rr=subprocess.run(['/asmlab',*args],input=stdin,text=True,capture_output=True,timeout=5,
                                      preexec_fn=isolate,env={'PATH':'/missing','LD_PRELOAD':'/missing/libc.so'})
                    rows=[json.loads(x) for x in rr.stdout.splitlines()]
                    c.check('empty_root_no_libc',rr.returncode==0 and not rr.stderr and rows[-1]['data']==expected,(binary.name,args,rr.stderr))
                evidence.append({'empty_root_binary':binary.name,'root_files':['/asmlab','/script.asmlab'],
                   'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
                   'no_lib_no_loader_no_shell':True,'execution_uid':65534,'cases':3})
    else:
        skips.append('Empty-root execution requires chroot capability/root; ELF and /proc mapping audits still run.')
        if a.require_empty_root:c.check('required_empty_root',False,skips[-1])
    report=c.report();report.update(schema_version=1,version=(ROOT/'VERSION').read_text().strip(),evidence=evidence,skipped=skips,
             limitations=['The empty-root check is an execution-dependency test, not an application sandbox/security certification.',
               'Only Linux x86-64 tested. No remote CI, WSL2 host, ARM64, Raspberry Pi or server implementation asserted.',
               'Default SIGPIPE/SIGINT behavior retained; TUI does not modify termios settings.'])
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));return int(bool(c.failures))
if __name__=='__main__':raise SystemExit(main())
