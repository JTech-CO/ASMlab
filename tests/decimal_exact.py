#!/usr/bin/env python3
"""Exact-decimal unit tests. Rational rounding intervals and Decimal quantization
are TEST oracles; none of this Python/ctypes code is in the application runtime.
"""
from __future__ import annotations
import argparse
from collections import Counter
import ctypes as C
from decimal import Decimal, localcontext, ROUND_HALF_EVEN
from fractions import Fraction
import json, math, mmap, os, random, re, struct, sys, time
from pathlib import Path
from runtime_suite import Native, Checks, ptr, buf, raw, U64
ROOT=Path(__file__).resolve().parents[1]
SIGN=1<<63; INF=0x7ff0000000000000; MAX=INF-1

def frac(word):
    """Exact magnitude represented by finite binary64 bits, no float math."""
    exp=(word>>52)&2047; mant=word&((1<<52)-1)
    if exp: mant|=1<<52
    e=exp-1075 if exp else -1074
    return Fraction(mant<<e,1) if e>=0 else Fraction(mant,1<<-e)

def exact_text(s):
    sign=s.startswith('-');s=s.lstrip('+-');parts=re.split('[eE]',s)
    exponent=int(parts[1]) if len(parts)>1 else 0
    a=parts[0].split('.');digits=''.join(a);exponent-=len(a[1]) if len(a)>1 else 0
    coefficient=int(digits)
    if not coefficient:return sign,Fraction(0)
    # Values outside these very conservative ranges need no huge power allocation.
    adjusted=len(str(coefficient))-1+exponent
    if adjusted>400:return sign,'huge'
    if adjusted< -500:return sign,'tiny'
    return sign,(Fraction(coefficient*10**exponent) if exponent>=0 else Fraction(coefficient,10**-exponent))

def rounding_interval(s,status,word):
    """Validate the returned bits against exact adjacent midpoint intervals.
    This does NOT trust Python float(s) or reproduce the assembly division code.
    """
    sign,value=exact_text(s);mag=word & (SIGN-1)
    if bool(word&SIGN)!=sign:return False
    if value=='huge':return status==-34 and mag==INF
    if value=='tiny':return status==0 and mag==0
    overflow=(frac(MAX)+Fraction(1<<1024))/2
    if value>=overflow:return status==-34 and mag==INF
    if status!=0 or mag>=INF:return False
    if mag==0:return value<=Fraction(1,1<<1075)
    center=frac(mag);low=(frac(mag-1)+center)/2
    high=(center+(frac(mag+1) if mag<MAX else Fraction(1<<1024)))/2
    return (low<value<high) or (not(mag&1) and value in (low,high))

def exact_decimal_text(value):
    # Fraction whose denominator is a power of 2 -> terminating decimal exactly.
    den=value.denominator;k=den.bit_length()-1
    assert den==1<<k
    digits=str(value.numerator*5**k)
    if k:
        digits=digits.zfill(k+1);return digits[:-k]+'.'+digits[-k:]
    return digits

def main():
    p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    c=Checks();n=Native('decimal-native.so',c);rng=random.Random(20260930);t=time.monotonic()
    counts=Counter()
    texts=['0','-0','+0','.0','1.','0.1','-0.1','1e308','-1e309','1e-320','5e-324',
      '2.4703282292062327e-324','2.4703282292062328e-324','2.2250738585072014e-308',
      '1.7976931348623157e308','1.7976931348623159e308','9007199254740993',
      '000001.00000000000000011102230246251565404236316680908203125',
      '0e'+('9'*100),'1e'+('9'*100),'-1e-'+('9'*100),'0.'+'0'*120+'1']
    # Exact halfway values and neighboring decimals (not merely random samples).
    for exponent in [-220,-100,-30,-2,0,2,30,100,500,900]:
        e=exponent+1023
        for tail in [0,1,2,(1<<52)-3,(1<<52)-2]:
            w=(e<<52)|tail
            mid=(frac(w)+frac(w+1))/2;s=exact_decimal_text(mid)
            # Full fixed strings may exceed lexer bounds; exact scientific trim.
            if len(s)>120:
                d=Decimal(s)
                with localcontext() as ctx:
                    ctx.prec=1200
                    s=str(d.normalize()) if len(d.as_tuple().digits)<100 else s
            if len(s)<=126:
                texts.extend([s,'-'+s])
    # Exhaust a useful matrix of decimal exponents and significands.
    for exp in range(-350,321):
        for mant in ('1','5','9999999999999999'):
            texts.append(mant+'e'+str(exp))
    for _ in range(8000):
        digits=''.join(str(rng.randrange(10)) for _ in range(rng.randrange(1,106)))
        split=rng.randrange(len(digits)+1)
        s=digits[:split]+'.'+digits[split:]+'e'+str(rng.randrange(-470,350))
        if rng.randrange(2):s='-'+s
        texts.append(s)
    for text in texts:
        b=buf(text.encode());status,word=n.invoke('rt_parse_f64',ptr(b),len(text),group='parse_abi')
        ok=rounding_interval(text,status,word)
        c.check('parse_exact_interval',ok,(text,status,hex(word)));counts['parse_cases']+=1
    invalid=[b'',b'+',b'-',b'.',b'+.',b'1e',b'1e+',b'1e-',b'e1',b'..1',b'1.2.3',b'--1',
             b'1 ',b' 1',b'\t1',b'1\n',b'1\0',b'12\x003',b'inf',b'NaN',b'0x1p0',b'\xff',b'0'*128,b'1'*128]
    for text in invalid:
        b=buf(text);s,w=n.invoke('rt_parse_f64',ptr(b),len(text),group='parse_abi')
        c.check('parse_rejection',s==-22 and w==0,(text,s,w))
    # Every binary exponent, edges, subnormals, random raw patterns.
    words=[0,SIGN,1,SIGN|1,(1<<52)-1,1<<52,(1<<52)+1,MAX,SIGN|MAX]
    words += [(exp<<52)|tail for exp in range(1,2047) for tail in [0,1,(1<<52)-1]]
    words += [rng.getrandbits(64) for _ in range(8000)]
    destination=C.create_string_buffer(96)
    for i,word in enumerate(words):
        if (word&~SIGN)>=INF:continue
        value=struct.unpack('<d',struct.pack('<Q',word))[0]
        precision=[1,8,10,12,16,17][i%6]
        destination.raw=b'\xa5'*96
        length,_=n.invoke('rt_format_f64',ptr(destination)+4,64,word,precision,group='format_abi')
        data=raw(destination);text=data[4:4+length].decode() if 0<length<64 else ''
        expected=format(value,f'.{precision}g')
        c.check('format_spelling',text==expected and data[:4]==b'\xa5'*4 and data[4+length]==0
                 and data[5+length:]==b'\xa5'*(91-length),(hex(word),precision,text,expected))
        with localcontext() as ctx:
            ctx.prec=1200
            exact=Decimal.from_float(value)
            quantum=Decimal(1).scaleb(exact.adjusted()-precision+1)
            want=exact.quantize(quantum,rounding=ROUND_HALF_EVEN)
            c.check('format_exact_quantization',bool(text) and Decimal(text)==want,(hex(word),precision))
        counts['format_cases']+=1
        # Independent raw -> own format17 -> own parse equality. Also compare
        # each component above/below independently, so shared bugs cannot suffice.
        length,_=n.invoke('rt_format_f64',ptr(destination),96,word,17,group='roundtrip_abi')
        text=C.string_at(ptr(destination),length)
        status,got=n.invoke('rt_parse_f64',ptr(destination),length,group='roundtrip_abi')
        c.check('roundtrip_bits',status==0 and got==word,(hex(word),text,status,hex(got)))
        counts['roundtrip_cases']+=1
    # All requested significant precisions, halfway decimal rounding, carries.
    for value in [1.25,1.75,9.5,99.5,999.5,0.0000999995,1e-4,1e-5,0.1,math.pi,
                  -0.0,5e-324,1.7976931348623157e308]:
        word=struct.unpack('<Q',struct.pack('<d',value))[0]
        for precision in range(1,18):
            want=format(value,f'.{precision}g').encode()
            for capacity in [0,len(want),len(want)+1]:
                destination.raw=b'\xa5'*96
                length,_=n.invoke('rt_format_f64',ptr(destination)+4,capacity,word,precision,group='format_abi')
                expected=bytearray(b'\xa5'*96)
                if capacity>len(want):expected[4:5+len(want)]=want+b'\0'
                c.check('format_buffer_boundary',length==(len(want) if capacity>len(want) else -28)
                        and raw(destination)==expected,(value,precision,capacity))
    for precision in [0,18,U64]:
        destination.raw=b'\xa5'*96
        length,_=n.invoke('rt_format_f64',ptr(destination),96,0,precision)
        c.check('format_precision_error',length==-22 and raw(destination)==b'\xa5'*96,precision)
    for word,want in [(INF,b'inf'),(SIGN|INF,b'-inf'),(INF+1,b'nan'),(SIGN|INF|1,b'-nan')]:
        length,_=n.invoke('rt_format_f64',ptr(destination),96,word,17)
        c.check('trace_nonfinite_display',length==len(want) and destination.value==want,hex(word))
    # Guard-page subprocesses: no reading past span/terminator or writing beyond
    # capacity. Python uses libc solely to configure TEST memory protections.
    if hasattr(os,'fork'):
        for mode in ['parse','adapter','format']:
            pid=os.fork()
            if pid==0:
                try:
                    pages=mmap.mmap(-1,mmap.PAGESIZE*2,prot=mmap.PROT_READ|mmap.PROT_WRITE)
                    base=C.addressof(C.c_char.from_buffer(pages));libc=C.CDLL(None)
                    libc.mprotect.argtypes=[C.c_void_p,C.c_size_t,C.c_int]
                    assert libc.mprotect(base+mmap.PAGESIZE,mmap.PAGESIZE,0)==0
                    if mode=='parse':
                        text=b'1.00000000000000011102230246251565404236316680908203125'
                        address=base+mmap.PAGESIZE-len(text);C.memmove(address,text,len(text))
                        s,w=n.invoke('rt_parse_f64',address,len(text));assert s==0 and w==0x3ff0000000000000
                    elif mode=='adapter':
                        text=b'0.'+b'0'*124+b'1'+b'\0';assert len(text)==128
                        address=base+mmap.PAGESIZE-len(text);C.memmove(address,text,len(text))
                        f=n.lib.rt_decimal_from_cstr;f.argtypes=[C.c_void_p,C.c_void_p];f.restype=C.c_double
                        assert f(address,None)==float(text[:-1])
                    else:
                        address=base+mmap.PAGESIZE-2
                        s,_=n.invoke('rt_format_f64',address,2,0,17);assert s==1 and C.string_at(address,2)==b'0\0'
                    os._exit(0)
                except BaseException:os._exit(1)
            _,status=os.waitpid(pid,0);c.check('decimal_guard_pages',status==0,(mode,status))
    report=c.report();report.update(schema_version=1,version=(ROOT/'VERSION').read_text().strip(),
           independent_cases=dict(counts),elapsed_seconds=round(time.monotonic()-t,3),
           oracle='Exact rational neighboring-binary64 midpoint intervals; Decimal exact quantization; Python spelling cross-check.',
           limitations=['Finite corpus, not an exhaustive proof over all decimal inputs or all binary64 patterns.',
             'Integer reference algorithm targets correct nearest-even rounding; no libm correct-rounding claim.',
             'ctypes/Decimal/Fraction and protected-page setup belong to the test host only.'])
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));return int(bool(c.failures))
if __name__=='__main__':raise SystemExit(main())
