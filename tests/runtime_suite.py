#!/usr/bin/env python3
"""Independent runtime foundation tests. Native assembly is tested via tiny
NASM-only shared fixtures; Python/ctypes/guard-page helpers are TEST infrastructure.
The separately linked smoke executable has no libc/CRT/dynamic interpreter.
"""
from __future__ import annotations
import argparse
from collections import Counter
import ctypes as C
from decimal import Decimal, localcontext
from fractions import Fraction
import hashlib
import json
import math
import mmap
import os
from pathlib import Path
import random
import signal
import struct
import subprocess
import sys
import tempfile
import threading
import time
ROOT=Path(__file__).resolve().parents[1]
U64=(1<<64)-1
PAGE=mmap.PAGESIZE
CAP=4096
R_SIZE=W_SIZE=4128

class Checks:
    def __init__(self): self.counts=Counter();self.failures=[]
    def check(self,group,ok,detail):
        self.counts[group]+=1
        if not ok:self.failures.append(group+': '+str(detail))
    def report(self):return {'case_count':sum(self.counts.values()),'group_counts':dict(self.counts),
                            'failure_count':len(self.failures),'failures':self.failures[:100]}

def ptr(b):return C.addressof(b)
def buf(b):return C.create_string_buffer(b,len(b)+1)
def s64(n):return C.c_int64(n).value
def sign(n):return (n>0)-(n<0)
def raw(b,n=None):return C.string_at(ptr(b),len(b) if n is None else n)

class Native:
    def __init__(self,filename,checks):
        self.lib=C.CDLL(str(ROOT/'bin/tests'/filename));self.checks=checks
        self.lib.rt_test_invoke.argtypes=[C.c_void_p,C.POINTER(C.c_uint64),C.POINTER(C.c_uint64)]
        self.lib.rt_test_invoke.restype=C.c_uint32
    def invoke(self,name,*args,group='abi',check_mxcsr=True):
        values=(C.c_uint64*6)(*[(v & U64) for v in args],*([0]*(6-len(args))))
        out=(C.c_uint64*4)()
        mask=self.lib.rt_test_invoke(C.cast(getattr(self.lib,name),C.c_void_p),values,out)
        self.checks.check(group,not(mask & (255 if check_mxcsr else 127)),f'{name}: ABI mask={mask}')
        return s64(out[0]),out[1]

def primitives(c,n):
    rng=random.Random(20260923)
    lengths=list(range(0,33))+[63,64,65,127,128,129,255,256,257,511,512,1024,4095,4096]
    for size in lengths:
        for so,do in [(0,0),(1,7),(7,1),(15,15)]:
            a=buf(rng.randbytes(size+40));b=buf(b'\xcc'*(size+40));old=raw(b)
            expect=bytearray(old);expect[do:do+size]=raw(a)[so:so+size]
            ret,_=n.invoke('rt_memcpy',ptr(b)+do,ptr(a)+so,size)
            c.check('memcpy',ret==ptr(b)+do and raw(b)==bytes(expect),f'n={size},src={so},dst={do}')
        for value in [0,1,127,255,256,-1,0x1234]:
            b=buf(b'\xa5'*(size+36));old=raw(b);expect=bytearray(old)
            expect[17:17+size]=bytes([value&255])*size
            ret,_=n.invoke('rt_memset',ptr(b)+17,value,size)
            c.check('memset',ret==ptr(b)+17 and raw(b)==bytes(expect),f'n={size},value={value}')
        for offset in [-31,-7,-1,0,1,7,31]:
            b=buf(rng.randbytes(2*size+160));old=raw(b);expect=bytearray(old);start=size+64
            expect[start+offset:start+offset+size]=old[start:start+size]
            ret,_=n.invoke('rt_memmove',ptr(b)+start+offset,ptr(b)+start,size)
            c.check('memmove',ret==ptr(b)+start+offset and raw(b)==bytes(expect),f'n={size},offset={offset}')
        a=buf(rng.randbytes(size));b=buf(raw(a))
        ret,_=n.invoke('rt_memcmp',ptr(a),ptr(b),size)
        c.check('memcmp',C.c_int32(ret).value==0,f'equal n={size}')
        if size:
            for pos in sorted({0,size//2,size-1}):
                a=buf(b'\x80'*size);b=buf(b'\x80'*size);b[pos]=b'\xff'
                ret,_=n.invoke('rt_memcmp',ptr(a),ptr(b),size)
                c.check('memcmp',C.c_int32(ret).value<0,f'unsigned n={size},pos={pos}')
                ret,_=n.invoke('rt_memcmp',ptr(b),ptr(a),size)
                c.check('memcmp',C.c_int32(ret).value>0,f'reverse n={size},pos={pos}')
    for size in lengths:
        value=bytes(rng.randrange(1,256) for _ in range(size));a=buf(value)
        ret,_=n.invoke('rt_strlen',ptr(a));c.check('strlen',ret==size,size)
        for cap in sorted({0,1,max(0,size-1),size,size+1,size+32}):
            ret,_=n.invoke('rt_strnlen',ptr(a),cap);c.check('strnlen',ret==min(size,cap),(size,cap))
    strings=[b'',b'a',b'aa',b'ab',b'a\x80',b'a\xff',b'\xff',b'\x01']
    strings += [bytes(rng.randrange(1,256) for _ in range(rng.randrange(60))) for _ in range(30)]
    for i,a in enumerate(strings):
        for b in strings[::5]+[a]:
            aa,bb=buf(a),buf(b);ret,_=n.invoke('rt_strcmp',ptr(aa),ptr(bb))
            c.check('strcmp',sign(C.c_int32(ret).value)==sign((a>b)-(a<b)),(i,len(b)))
    for name,args in [('rt_memcpy',(0,0,0)),('rt_memmove',(0,0,0)),('rt_memset',(0,255,0)),
                      ('rt_memcmp',(0,0,0)),('rt_strnlen',(0,0))]:
        ret,_=n.invoke(name,*args);c.check('zero_length',ret==0,name)

def integers(c,n):
    rng=random.Random(20260924)
    vals={0,1,9,10,99,100,255,256,1<<31,1<<32,1<<52,1<<53,(1<<63)-1,1<<63,U64}
    vals.update((10**e+d) for e in range(1,20) for d in [-1,0,1] if 0<=10**e+d<=U64)
    vals.update(rng.getrandbits(64) for _ in range(256))
    signed={s64(v) for v in vals}|{-(1<<63),-1,0,1,(1<<63)-1}
    for name,values,reference in [('rt_format_u64',sorted(vals),str),('rt_format_i64',sorted(signed),str),
                                  ('rt_format_hex64',sorted(vals),lambda v:f'{v:016x}')]:
        for v in values:
            expected=reference(v).encode();length=len(expected)
            for cap in sorted({0,max(0,length-1),length,length+1,length+7}):
                b=buf(b'\xa5'*48);old=raw(b);ret,_=n.invoke(name,ptr(b)+3,cap,v)
                want=bytearray(old)
                if cap>length:want[3:3+length+1]=expected+b'\0'
                c.check('integer_format',ret==(length if cap>length else -28) and raw(b)==bytes(want),
                        f'{name} value={v} cap={cap}')
    for name,values in [('rt_parse_u64',sorted(vals)),('rt_parse_i64',sorted(signed))]:
        for value in values:
            spellings=[str(value)]
            if value>=0:spellings+=['000'+str(value)]
            if name.endswith('i64') and value>=0:spellings+=['+'+str(value)]
            for text in spellings:
                b=buf(text.encode());status,got=n.invoke(name,ptr(b),len(text))
                c.check('integer_parse',status==0 and got==(value&U64),(name,text,status,got))
    invalid=[b'',b' ',b'+',b'-',b'--1',b'++1',b'+-1',b'1 ',b' 1',b'1.0',b'1e2',b'0x10',
             b'\0',b'12\x003',b'\xff',b'a']
    for name in ['rt_parse_u64','rt_parse_i64']:
        for text in invalid:
            b=buf(text);status,got=n.invoke(name,ptr(b),len(text))
            c.check('integer_parse_invalid',status==-22 and got==0,(name,text,status,got))
    for text in [b'+1',b'-1']:
        b=buf(text);status,got=n.invoke('rt_parse_u64',ptr(b),len(text))
        c.check('integer_parse_invalid',status==-22 and got==0,text)
    for name,text in [('rt_parse_u64','18446744073709551616'),('rt_parse_u64','9'*80),
                      ('rt_parse_i64','9223372036854775808'),('rt_parse_i64','-9223372036854775809'),
                      ('rt_parse_i64','18446744073709551616')]:
        b=buf(text.encode());status,got=n.invoke(name,ptr(b),len(text))
        c.check('integer_parse_overflow',status==-34 and got==0,(name,text))
    for text in [b'-0',b'+0',b'-0000']:
        b=buf(text);status,got=n.invoke('rt_parse_i64',ptr(b),len(text))
        c.check('integer_signed_zero',status==0 and got==0,text)

def actual_io(c,n):
    with tempfile.TemporaryDirectory(prefix='ASMlab IO ') as td:
        directory=Path(td);path=directory/'input with spaces.bin';payload=bytes(range(256))*35+b'no newline'
        path.write_bytes(payload);p=buf(os.fsencode(path))
        fd,_=n.invoke('rt_fd_open_read',ptr(p));c.check('fd_open',fd>=0,'existing file')
        if fd<0:return
        reader=C.create_string_buffer(R_SIZE);n.invoke('rt_reader_init',ptr(reader),fd)
        got=bytearray()
        for _ in range(len(payload)+2):
            v,error=n.invoke('rt_reader_getc',ptr(reader))
            if v==-1:break
            if v<0:raise AssertionError(f'Unexpected read error {v}/{s64(error)}')
            got.append(v)
        c.check('reader_binary',bytes(got)==payload,'multiple fills, NUL, no final newline')
        v,_=n.invoke('rt_reader_error',ptr(reader));c.check('reader_eof_status',v==0,'EOF is not error')
        for _ in range(3):
            v,e=n.invoke('rt_reader_getc',ptr(reader));c.check('reader_sticky_eof',v==-1 and e==0,'repeat EOF')
        v,_=n.invoke('rt_fd_close',fd);c.check('fd_close',v==0,'close once')
        missing=buf(os.fsencode(directory/'missing'));v,_=n.invoke('rt_fd_open_read',ptr(missing))
        c.check('fd_open_error',v==-2,'ENOENT')
        b=C.create_string_buffer(16);v,_=n.invoke('rt_fd_read',-1,ptr(b),16)
        c.check('fd_read_error',v==-9,'EBADF')
        v,w=n.invoke('rt_fd_write_all',-1,ptr(b),16);c.check('fd_write_error',v==-9 and w==0,'EBADF')
        v,w=n.invoke('rt_fd_write_all',-1,0,0);c.check('fd_zero_write',v==0 and w==0,'no syscall for length 0')
        # Explicit test of syscall arg4 (mode) going from RCX to R10.
        dfd=os.open(directory,os.O_RDONLY|os.O_DIRECTORY)
        relative=buf(b'created.bin')
        v,_=n.invoke('rt_sys_openat',dfd,ptr(relative),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        c.check('syscall_arg4',v>=0 and ((directory/'created.bin').stat().st_mode & 0o777)==0o600,'openat mode')
        if v>=0:n.invoke('rt_fd_close',v)
        os.close(dfd)
        # Shared fixture calls native syscalls with GIL released by ctypes.
        rd,wr=os.pipe();chunks=[]
        def drain():
            try:
                while True:
                    block=os.read(rd,2048)
                    if not block:break
                    chunks.append(block)
            finally:os.close(rd)
        t=threading.Thread(target=drain);t.start()
        try:
            writer=C.create_string_buffer(W_SIZE);n.invoke('rt_writer_init',ptr(writer),wr)
            text=buf(payload*4)
            status,accepted=n.invoke('rt_writer_write',ptr(writer),ptr(text),len(payload)*4)
            c.check('writer_acceptance',status==0 and accepted==len(payload)*4,'buffered large write')
            status,_=n.invoke('rt_writer_flush',ptr(writer));c.check('writer_flush',status==0,'final flush')
        finally:os.close(wr);t.join(timeout=10)
        c.check('writer_pipe_bytes',not t.is_alive() and b''.join(chunks)==payload*4,'complete binary output')
        # ioctl argument mapping on a PTY, separate from interactive UI tests.
        import pty,fcntl,termios
        master,slave=pty.openpty()
        try:
            fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',37,103,0,0))
            winsz=C.create_string_buffer(8)
            ret,_=n.invoke('rt_sys_ioctl',slave,termios.TIOCGWINSZ,ptr(winsz))
            c.check('syscall_ioctl',ret==0 and struct.unpack('HHHH',raw(winsz))[:2]==(37,103),'winsize')
        finally:os.close(master);os.close(slave)

# Python callbacks replace ONLY the leaf syscalls in a development fixture.
# MXCSR invariance is excluded for callbacks crossing the foreign interpreter.
IO_CB=C.CFUNCTYPE(C.c_long,C.c_long,C.c_void_p,C.c_size_t)
CLOSE_CB=C.CFUNCTYPE(C.c_long,C.c_long)
def injected_io(c):
    n=Native('runtime-faults.so',c)
    n.lib.rt_test_set_io.argtypes=[C.c_void_p]*3;n.lib.rt_test_set_io.restype=None
    def invoke(name,*args):return n.invoke(name,*args,group='fault_path_abi',check_mxcsr=False)
    for script,length,status,done in [([2,-4,1,-11],7,-11,3),([0],7,-5,0),([8],7,-5,0),
                                      ([1,2,4],7,0,7),([],0,0,0)]:
        calls=[];plan=list(script)
        @IO_CB
        def write(fd,p,size):
            calls.append((fd,C.string_at(p,size)));return plan.pop(0) if plan else int(size)
        n.lib.rt_test_set_io(None,write,None);b=buf(b'abcdefg')
        ret,got=invoke('rt_fd_write_all',9,ptr(b),length)
        c.check('write_fault_status',(ret,got)==(status,done),(script,ret,got))
        c.check('write_fault_calls',len(calls)==len(script),(script,len(calls)))
        if script==[2,-4,1,-11]:
            c.check('write_partial_offsets',[x[1] for x in calls]==[b'abcdefg',b'cdefg',b'cdefg',b'defg'],'no duplicate prefix')
    reader=C.create_string_buffer(R_SIZE)
    plan=[-4,b'ab',b'c\0',b''];reads=[]
    @IO_CB
    def read(fd,p,size):
        reads.append((fd,size));item=plan.pop(0)
        if isinstance(item,int):return item
        C.memmove(p,item,len(item));return len(item)
    n.lib.rt_test_set_io(read,None,None);invoke('rt_reader_init',ptr(reader),19)
    vals=[invoke('rt_reader_getc',ptr(reader)) for _ in range(7)]
    c.check('read_short_eintr',vals==[(97,0),(98,0),(99,0),(0,0),(-1,0),(-1,0),(-1,0)],vals)
    c.check('read_short_call_count',len(reads)==4,'buffer refill and sticky EOF')
    for error in [-1,-5,-9,-11]:
        seen=[]
        @IO_CB
        def fail_read(fd,p,size):seen.append(fd);return error
        n.lib.rt_test_set_io(fail_read,None,None);invoke('rt_reader_init',ptr(reader),19)
        vals=[invoke('rt_reader_getc',ptr(reader)) for _ in range(3)]
        status,_=invoke('rt_reader_error',ptr(reader))
        c.check('read_sticky_error',all(x==-2 and s64(y)==error for x,y in vals) and status==error and len(seen)==1,(error,vals))
    writer=C.create_string_buffer(W_SIZE);calls=[];plan=[2,-5]
    @IO_CB
    def partial(fd,p,size):calls.append(C.string_at(p,size));return plan.pop(0)
    n.lib.rt_test_set_io(None,partial,None);invoke('rt_writer_init',ptr(writer),7)
    b=buf(b'abcdef');status,accepted=invoke('rt_writer_write',ptr(writer),ptr(b),6)
    c.check('writer_buffer_only',status==0 and accepted==6 and not calls,'no syscall before flush')
    status,written=invoke('rt_writer_flush',ptr(writer))
    used=struct.unpack_from('<Q',raw(writer),8)[0]
    c.check('writer_partial_failure',status==-5 and written==2 and used==4 and raw(writer)[32:36]==b'cdef','preserve unwritten suffix')
    status,accepted=invoke('rt_writer_write',ptr(writer),ptr(b),6)
    again,count=invoke('rt_writer_flush',ptr(writer))
    c.check('writer_sticky_error',status==again==-5 and accepted==count==0 and len(calls)==2,'do not retry/output duplicate')
    output=bytearray()
    @IO_CB
    def capture(fd,p,size):output.extend(C.string_at(p,size));return size
    n.lib.rt_test_set_io(None,capture,None);invoke('rt_writer_init',ptr(writer),7)
    for fn,value in [('rt_writer_u64',U64),('rt_writer_i64',-(1<<63)),('rt_writer_hex64',0x123456789abcdef0)]:
        status,_=invoke(fn,ptr(writer),value);c.check('typed_writer',status==0,fn)
        sp=buf(b'|');invoke('rt_writer_cstr',ptr(writer),ptr(sp))
    invoke('rt_writer_flush',ptr(writer))
    c.check('typed_writer_output',bytes(output)==b'18446744073709551615|-9223372036854775808|123456789abcdef0|',bytes(output))
    close_calls=[]
    @CLOSE_CB
    def close(fd):close_calls.append(fd);return -4
    n.lib.rt_test_set_io(None,None,close);status,_=invoke('rt_fd_close',11)
    c.check('close_no_retry',status==-4 and close_calls==[11],'never retry close EINTR')
    # Large buffer rollover, binary payload and no-progress close behavior.
    output.clear();n.lib.rt_test_set_io(None,capture,None);invoke('rt_writer_init',ptr(writer),7)
    payload=bytes(range(256))*33+b'END';b=buf(payload)
    status,accepted=invoke('rt_writer_write',ptr(writer),ptr(b),len(payload))
    c.check('writer_rollover_accept',status==0 and accepted==len(payload),(status,accepted))
    status,_=invoke('rt_writer_flush',ptr(writer));c.check('writer_rollover_bytes',status==0 and output==payload,'full ordered output')

def guard_child(which):
    c=Checks();n=Native('runtime-primitives.so',c)
    libc=C.CDLL(None);libc.mprotect.argtypes=[C.c_void_p,C.c_size_t,C.c_int];libc.mprotect.restype=C.c_int
    regions=[]
    def region():
        mm=mmap.mmap(-1,3*PAGE,prot=mmap.PROT_READ|mmap.PROT_WRITE)
        address=C.addressof(C.c_char.from_buffer(mm));regions.append((mm,address))
        if libc.mprotect(address,PAGE,0) or libc.mprotect(address+2*PAGE,PAGE,0):
            raise OSError('guard mprotect failed')
        return address+PAGE,address+2*PAGE,address
    try:
        start,end,guard=region();start2,end2,guard2=region()
        if which=='zero_count':
            for name,args in [('rt_memcpy',(guard,guard2,0)),('rt_memmove',(guard,guard2,0)),
                              ('rt_memset',(guard,23,0)),('rt_memcmp',(guard,guard2,0)),('rt_strnlen',(guard,0))]:
                ret,_=n.invoke(name,*args)
                c.check('guard',ret==(guard if name in ('rt_memcpy','rt_memmove','rt_memset') else 0),name)
        elif which=='strnlen_bound':
            C.memmove(end-31,b'a'*31,31);ret,_=n.invoke('rt_strnlen',end-31,31)
            c.check('guard',ret==31,which)
        elif which=='strlen_terminator':
            C.memmove(end-64,b'a'*63+b'\0',64);ret,_=n.invoke('rt_strlen',end-64)
            c.check('guard',ret==63,which)
        elif which=='strcmp_terminator':
            C.memmove(end-32,b'a'*31+b'\0',32);C.memmove(end2-32,b'a'*31+b'\0',32)
            ret,_=n.invoke('rt_strcmp',end-32,end2-32);c.check('guard',ret==0,which)
        elif which=='memcpy_bound':
            data=bytes(range(33));C.memmove(end-33,data,33)
            ret,_=n.invoke('rt_memcpy',end2-33,end-33,33)
            c.check('guard',ret==end2-33 and C.string_at(end2-33,33)==data,which)
        elif which=='memset_bound':
            ret,_=n.invoke('rt_memset',end-31,0xab,31)
            c.check('guard',ret==end-31 and C.string_at(end-31,31)==b'\xab'*31,which)
        elif which=='memmove_overlap':
            C.memmove(end-65,bytes(range(65)),65)
            ret,_=n.invoke('rt_memmove',end-64,end-65,64)
            c.check('guard',ret==end-64 and C.string_at(end-64,64)==bytes(range(64)),which)
        elif which=='memcmp_bound':
            C.memmove(end-31,b'\xff'*31,31);C.memmove(end2-31,b'\xff'*31,31)
            ret,_=n.invoke('rt_memcmp',end-31,end2-31,31);c.check('guard',ret==0,which)
        elif which=='integer_span_bound':
            text=b'18446744073709551615';C.memmove(end-len(text),text,len(text))
            status,value=n.invoke('rt_parse_u64',end-len(text),len(text))
            c.check('guard',status==0 and value==U64,which)
        elif which=='format_exact_capacity':
            ret,_=n.invoke('rt_format_u64',end-21,21,U64)
            c.check('guard',ret==20 and C.string_at(end-21,21)==b'18446744073709551615\0',which)
        elif which=='format_no_capacity':
            for name,value in [('rt_format_u64',U64),('rt_format_i64',-(1<<63)),('rt_format_hex64',U64)]:
                ret,_=n.invoke(name,guard,0,value);c.check('guard',ret==-28,name)
        elif which=='parse_empty_guard':
            for name in ['rt_parse_u64','rt_parse_i64']:
                ret,value=n.invoke(name,guard,0);c.check('guard',ret==-22 and value==0,name)
        else:raise ValueError(which)
    finally:
        for mm,address in regions:
            libc.mprotect(address,3*PAGE,mmap.PROT_READ|mmap.PROT_WRITE);mm.close()
    return int(bool(c.failures))

def guard_tests(c):
    names=['zero_count','strnlen_bound','strlen_terminator','strcmp_terminator','memcpy_bound',
           'memset_bound','memmove_overlap','memcmp_bound','integer_span_bound','format_exact_capacity',
           'format_no_capacity','parse_empty_guard']
    for name in names:
        r=subprocess.run([sys.executable,str(Path(__file__).resolve()),'--guard-child',name],
                         cwd=ROOT,capture_output=True,timeout=10)
        c.check('guard_page_subprocess',r.returncode==0,(name,r.returncode,r.stderr.decode(errors='replace')[:300]))

def rational_bits(text):
    """Independent exact integer/rational rounding oracle for decimal -> binary64.
    No float(text), strtod or math library is used to compute expected bits.
    """
    # Decimal.__abs__ obeys the ambient precision. copy_abs is exact; rounding
    # the reference input here would invalidate midpoint/subnormal tests.
    d=Decimal(text);negative=d.is_signed();frac=Fraction(d.copy_abs());num,den=frac.numerator,frac.denominator
    sb=(1<<63) if negative else 0
    if num==0:return sb
    def round_ratio(n,d):
        q,r=divmod(n,d)
        return q+int(2*r>d or (2*r==d and q%2))
    e=num.bit_length()-den.bit_length()
    if (num<(den<<e) if e>=0 else (num<<(-e))<den):e-=1
    if e < -1022:
        return sb | round_ratio(num<<1074,den)
    scale=52-e
    q=round_ratio(num<<scale,den) if scale>=0 else round_ratio(num,den<<(-scale))
    if q==(1<<53):q>>=1;e+=1
    if e>1023:return sb | (0x7ff<<52)
    return sb | ((e+1023)<<52) | (q-(1<<52))

def decimal_boundary(c):
    for text,expected in [('0',0),('-0',1<<63),('1',0x3ff0000000000000),
                          ('1e-400',0),('1e309',0x7ff0000000000000),
                          ('1.00000000000000011102230246251565404236316680908203125',0x3ff0000000000000),
                          ('1.00000000000000033306690738754696212708950042724609375',0x3ff0000000000002)]:
        c.check('decimal_oracle_known_bits',rational_bits(text)==expected,text)
    lib=C.CDLL(str(ROOT/'bin/tests/decimal-adapter.so'))
    lib.rt_decimal_from_cstr.argtypes=[C.c_void_p,C.POINTER(C.c_void_p)]
    lib.rt_decimal_from_cstr.restype=C.c_double
    lib.rt_test_mxcsr_set.argtypes=[C.c_uint];lib.rt_test_mxcsr_set.restype=None
    lib.rt_test_mxcsr_get.argtypes=[];lib.rt_test_mxcsr_get.restype=C.c_uint
    saved=lib.rt_test_mxcsr_get()
    cases=['0','-0','+0','0.1','-0.1','1','1e-320','5e-324','2e-324','1e-400',
           '2.2250738585072014e-308','2.225073858507201e-308','1.7976931348623157e308',
           '1.7976931348623158e308','1.7976931348623159e308','1e309','9007199254740993',
           '1.00000000000000011102230246251565404236316680908203125',
           '1.00000000000000033306690738754696212708950042724609375']
    rng=random.Random(20260925)
    for _ in range(384):
        digits=str(rng.randrange(1,10**rng.randrange(1,42)))
        cases.append(('-' if rng.randrange(2) else '')+digits+'e'+str(rng.randrange(-355,310)))
    # Long exact subnormal midpoints test the isolated adapter, NOT new lexer limits.
    with localcontext() as ctx:
        ctx.prec=1400
        for numerator,power in [(1,1075),(3,1075),(5,1075),((1<<53)-1,1075)]:
            cases.append(format(Decimal(numerator)/(Decimal(2)**power),'f'))
    try:
        for text in cases:
            textbytes=text.encode();value=buf(textbytes+b'xyz');end=C.c_void_p()
            expected=rational_bits(text)
            lib.rt_test_mxcsr_set(0x1f80)
            result=lib.rt_decimal_from_cstr(ptr(value),C.byref(end))
            got=struct.unpack('<Q',struct.pack('<d',result))[0]
            c.check('decimal_adapter_rounding',got==expected,(text[:110],f'{got:016x}',f'{expected:016x}'))
            c.check('decimal_adapter_endptr',end.value==ptr(value)+len(textbytes),text[:110])
    finally:lib.rt_test_mxcsr_set(saved)

def smoke_tests(c):
    exe=str(ROOT/'bin/asmlab-runtime-smoke')
    def run(*args,data=b'',**kw):return subprocess.run([exe,*args],input=data,capture_output=True,timeout=10,**kw)
    r=run('--version');c.check('smoke_version',r.returncode==0 and b'0.2.0' in r.stdout and b'no libc/CRT' in r.stdout,'version')
    r=run();c.check('smoke_help',r.returncode==0 and b'not the math REPL' in r.stdout,'help')
    rng=random.Random(44)
    for length in [0,1,4095,4096,4097,8192,65539]:
        data=rng.randbytes(length);r=run('--echo',data=data)
        c.check('smoke_binary_echo',r.returncode==0 and r.stdout==data and not r.stderr,length)
    for flag,v,expected in [('--u64','18446744073709551615',b'18446744073709551615\n'),
                            ('--i64','-9223372036854775808',b'-9223372036854775808\n'),
                            ('--i64','+7',b'7\n'),('--hex64','18446744073709551615',b'ffffffffffffffff\n')]:
        r=run(flag,v);c.check('smoke_integer',r.returncode==0 and r.stdout==expected,(flag,v))
    for args in [('--u64','18446744073709551616'),('--i64','-9223372036854775809'),('--i64','-'),
                 ('--unknown',),('--cat',),('--echo','extra'),('--version','extra'),('--u64','1e2')]:
        r=run(*args);c.check('smoke_bad_args',r.returncode==2 and b'invalid arguments' in r.stderr and not r.stdout,args)
    with tempfile.TemporaryDirectory(prefix='ASMlab smoke ') as td:
        path=Path(td)/'file.bin';data=bytes(range(256))*41+b'last line';path.write_bytes(data)
        r=run('--cat',str(path));c.check('smoke_file',r.returncode==0 and r.stdout==data,'cat')
        r=run('--cat',str(path)+'-missing');c.check('smoke_missing_file',r.returncode==2 and b'I/O failure' in r.stderr,'ENOENT')
        r=run('--cat',td);c.check('smoke_directory',r.returncode==2 and b'I/O failure' in r.stderr,'EISDIR')
    with open('/dev/full','wb',buffering=0) as full:
        r=subprocess.run([exe,'--echo'],input=b'flush must fail',stdout=full,stderr=subprocess.PIPE,timeout=10)
        c.check('smoke_flush_failure',r.returncode==2 and b'I/O failure' in r.stderr,'/dev/full')
    def close_stdin():os.close(0)
    r=subprocess.run([exe,'--echo'],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                     preexec_fn=close_stdin,timeout=10)
    c.check('smoke_bad_fd',r.returncode==2 and b'I/O failure' in r.stderr,'closed stdin')
    rd,wr=os.pipe();os.close(rd)
    try:
        r=subprocess.run([exe,'--echo'],input=b'broken pipe',stdout=wr,stderr=subprocess.PIPE,timeout=10)
    finally:os.close(wr)
    c.check('smoke_sigpipe',r.returncode==-signal.SIGPIPE,'default SIGPIPE termination is documented')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report',type=Path,default=ROOT/'build/runtime-tests.json')
    p.add_argument('--guard-child');a=p.parse_args()
    if a.guard_child:return guard_child(a.guard_child)
    c=Checks();start=time.monotonic();fatal=None
    try:
        n=Native('runtime-primitives.so',c)
        primitives(c,n);integers(c,n);actual_io(c,n);injected_io(c)
        guard_tests(c);decimal_boundary(c);smoke_tests(c)
    except (OSError,ValueError,AssertionError,subprocess.SubprocessError) as e:
        fatal=str(e);c.check('fatal_error',False,str(e))
    report={'schema_version':1,'version':(ROOT/'VERSION').read_text().strip(),**c.report(),
            'elapsed_seconds':round(time.monotonic()-start,3),
            'limitations':['Finite tests, not formal verification or a security certification.',
                           'Guard pages cover listed boundary configurations; not all allocations.',
                           'Decimal tests verify the retained libc adapter, not a new standalone f64 converter.',
                           'Fault-provider callbacks are test-only; MXCSR preservation is checked on native paths, not inside Python callbacks.',
                           'Runtime-smoke has no parser, math evaluator, plots, server, or ARM64 backend.']}
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));return int(bool(c.failures) or fatal is not None)
if __name__=='__main__':raise SystemExit(main())
