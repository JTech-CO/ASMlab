#!/usr/bin/env python3
"""Local validation bridge, not an assembler or part of the ASMlab runtime.
Translate the small, explicit NASM syntax subset used here to GNU Intel syntax.
Instruction selection is unchanged; NASM-native build remains authoritative.
"""
import re, sys, struct, pathlib
root=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); macros={}; lines=[]; defines={}
def strip_comment(s):
    quote=None
    for i,c in enumerate(s):
        if quote:
            if c==quote: quote=None
        elif c in "\"'": quote=c
        elif c==';': return s[:i]
    return s

def split_items(s):
    return [x.strip() for x in re.split(r',(?=(?:[^\'\"]|\'[^\']*\'|\"[^\"]*\")*$)',s)]
def load(path):
    src=path.read_text().splitlines(); i=0
    while i<len(src):
        raw=strip_comment(src[i]).strip(); i+=1
        if not raw: continue
        if raw.startswith('%include'):
            yield from load(root/re.search(r'"(.*)"',raw).group(1)); continue
        if raw.startswith('%macro'):
            _,name,n=raw.split(); body=[]
            while i<len(src) and not src[i].strip().startswith('%endmacro'):
                body.append(strip_comment(src[i]).strip());i+=1
            i+=1;macros[name]=(int(n),body);continue
        yield raw

def expand(s):
    k=s.split()[0]
    if k not in macros: yield s;return
    n,body=macros[k]; args=split_items(s[len(k):].strip()) if n else []
    assert len(args)==n,(s,n,args)
    for line in body:
        for j,a in enumerate(args,1):line=line.replace('%'+str(j),a)
        if line: yield from expand(line)

src=list(load(root/'src/asmlab.asm')); out=['.intel_syntax noprefix'];scope='';symbol_re=re.compile(r'(?<![\w.])\.[A-Za-z_]\w*')
reg_re=re.compile(r'\b(?:r(?:[abcd]x|[sb]p|[sd]i|[89]|1[0-5])|e(?:[abcd]x|[sb]p|[sd]i)|rip)\b')
for original in src:
  for s in expand(original):
    if s.startswith('%define '):
        _,name,value=s.split(None,2); defines[name]=value; continue
    s = re.sub(r'\b[A-Z][A-Z_0-9]*\b', lambda m: defines.get(m.group(0), m.group(0)), s)
    if s.startswith(('bits ','default ')):continue
    if s.startswith('section '):
        sec=s.split()[1];out.append('.section '+sec+(',"",@progbits' if sec=='.note.GNU-stack' else ''));continue
    if s.startswith('extern '):
        for x in split_items(s[7:]):out.append('.extern '+x)
        continue
    if s.startswith('global '):out.append('.global '+s[7:]);continue
    if s.startswith(('align ', 'alignb ')):out.append('.balign '+s.split(None,1)[1]);continue
    m=re.match(r'([A-Za-z_.]\w*(?:\.\w+)*):\s*(.*)',s)
    if m:
        lab, s=m.groups()
        if lab.startswith('.'): lab=scope+lab
        else: scope=lab
        out.append(lab+':')
        if not s:continue
    if s.startswith(('db ','dq ','dd ','resb ','resq ','resd ')):
        k,rest=s.split(None,1)
        if k.startswith('res'):
            scale={'resb':1,'resq':8,'resd':4}[k];out.append(f'.zero ({rest}) * {scale}');continue
        for v in split_items(rest):
            if k=='db' and v[0:1] in ("'",'"'):
                b=v[1:-1].encode();out.append('.byte '+','.join(str(c) for c in b));continue
            if k in ('dq','dd') and re.match(r'[-+]?\d*\.\d',v):
                bits=int.from_bytes(struct.pack('<d' if k=='dq' else '<f',float(v)),'little');v=hex(bits)
            out.append({'db':'.byte ','dq':'.quad ','dd':'.long '}[k]+v)
        continue
    s=symbol_re.sub(lambda m:scope+m.group(0),s)
    s=re.sub(r"'(.)'",lambda m:str(ord(m.group(1))),s)
    s=re.sub(r'\b(qword|dword|word|byte)\s*\[',lambda m:m.group(1)+' ptr [',s)
    def mem(m):
        inner=m.group(1)
        if not reg_re.search(inner) and re.search(r'[a-zA-Z_]',inner):inner='rip+'+inner
        return '['+inner+']'
    s=re.sub(r'\[([^\]]+)\]',mem,s)
    out.append(s)
output.write_text('\n'.join(out)+'\n')
print(f'Validation translation: {len(out)} lines -> {output}')
