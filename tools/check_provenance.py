#!/usr/bin/env python3
"""Validate exactly the recorded inputs/objects/targets before executing artifacts.
Checksums are local integrity evidence, NOT signatures or a trust authority.
"""
from __future__ import annotations
import json
from pathlib import Path
from build_native import ROOT, digest, build_inputs
from build_foundation import foundation_inputs

def local(path: str) -> Path:
    p=(ROOT/path).resolve()
    if not p.is_relative_to(ROOT):raise RuntimeError('Artifact path escapes project root: '+path)
    return p

def hashes(expected: dict[str,str], actual_paths: list[Path]) -> None:
    wanted={str(p.relative_to(ROOT)) for p in actual_paths}
    if set(expected)!=wanted:raise RuntimeError('Incomplete or unexpected build-input inventory')
    for name,value in expected.items():
        if digest(local(name))!=value:raise RuntimeError('Build input hash changed: '+name)

def validate_app(name: str, profile: str, backend: str='native') -> dict:
    binary=local('bin/'+name);meta=json.loads(Path(str(binary)+'.build.json').read_text())
    if meta.get('build_kind')!='nasm-native' or meta.get('profile')!=profile or meta.get('runtime_backend')!=backend:
        raise RuntimeError('Missing/stale/non-native/wrong-backend provenance: '+name)
    if meta.get('version')!=(ROOT/'VERSION').read_text().strip():raise RuntimeError('Version mismatch: '+name)
    if meta.get('binary')!='bin/'+name or meta.get('binary_sha256')!=digest(binary):raise RuntimeError('Binary hash mismatch: '+name)
    hashes(meta.get('source_sha256',{}),build_inputs())
    modules=meta.get('project_objects',[])
    sources=['src/asmlab.asm',
             'src/rt/primitives.asm' if backend=='native' else 'dev/runtime/libc_primitives.asm',
             'src/rt/adapters/libc_io.asm']
    if [x['source'] for x in modules]!=sources:raise RuntimeError('Wrong project object boundary: '+name)
    for obj in modules:
        if digest(local(obj['path']))!=obj['sha256']:raise RuntimeError('Object hash changed: '+obj['path'])
    if digest(local(meta['link_map']))!=meta['link_map_sha256']:raise RuntimeError('Link map changed: '+name)
    commands=meta.get('commands',[])
    if not commands or any('validation_bridge' in ' '.join(x) for x in commands):raise RuntimeError('Invalid native build commands')
    return meta

def validate_foundation() -> dict:
    meta=json.loads((ROOT/'bin/runtime-foundation.build.json').read_text())
    if meta.get('build_kind')!='nasm-native-foundation' or meta.get('version')!=(ROOT/'VERSION').read_text().strip():
        raise RuntimeError('Wrong foundation build kind or version')
    hashes(meta.get('source_sha256',{}),foundation_inputs())
    wanted={'primitives':'src/rt/primitives.asm','integer':'src/rt/integer.asm','fd_io':'src/rt/fd_io.asm',
            'syscalls':'src/platform/linux/syscalls.asm','start':'src/platform/linux/start.asm',
            'smoke':'tests/runtime/smoke.asm','probe':'tests/runtime/abi_probe.asm',
            'fake_syscalls':'tests/runtime/fake_syscalls.asm','libc_io':'src/rt/adapters/libc_io.asm'}
    objects=meta.get('objects',{})
    if {k:v['source'] for k,v in objects.items()}!=wanted:raise RuntimeError('Incomplete foundation object inventory')
    for obj in objects.values():
        if digest(local(obj['path']))!=obj['sha256']:raise RuntimeError('Foundation object changed: '+obj['path'])
    targets=meta.get('targets',[])
    if [x['path'] for x in targets]!=['bin/asmlab-runtime-smoke','bin/tests/runtime-primitives.so',
                                    'bin/tests/runtime-faults.so','bin/tests/decimal-adapter.so']:
        raise RuntimeError('Incomplete foundation target inventory')
    wanted_groups=[['start','smoke','primitives','integer','fd_io','syscalls'],
                   ['primitives','integer','fd_io','syscalls','probe'],
                   ['primitives','integer','fd_io','fake_syscalls','probe'],['libc_io','probe']]
    for target,group in zip(targets,wanted_groups):
        if target['objects']!=group:raise RuntimeError('Wrong fixture/runtime boundary: '+target['path'])
        if digest(local(target['path']))!=target['sha256']:raise RuntimeError('Foundation target changed: '+target['path'])
        if digest(local(target['link_map']))!=target['link_map_sha256']:raise RuntimeError('Foundation link map changed')
    return meta
