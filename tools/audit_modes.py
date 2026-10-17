# -*- coding: utf-8 -*-
"""SPEC 140: prove nothing of the arena, the tricks, the training or delivery is left.

Comments are allowed to remember history -- the spec is full of it -- so this separates CODE from
COMMENTS and only fails on code. It also checks the things a grep for "arena" misses: the input map,
user-visible strings, and `res://` paths that no longer resolve.

    python tools/audit_modes.py
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORDS = re.compile(r'\b(arena|arenas|stunt|stunts|trick|tricks|training|delivery|banger|gabber|dockside)\b', re.I)
# Identifiers that would actually break something if they survived. Note the surrounding `\w*`:
# `selected_arena` and `training_done` do NOT match a plain `\barena\b`, and the first version of this
# audit passed `tools/shoot_screen.gd` while it still set both.
SYMBOLS = re.compile(r'\w*(Arena|arena|TrickWatch|TrickTally|RunPanel|Training|training_done'
                     r'|Delivery|delivery|MapZone|MapSpawn|MapSurface|OilArt)\w*')
RES_PATH = re.compile(r'res://[\w./-]+')

problems = []
notes = []


def scan_code():
    for sub in ('scripts', 'tests', 'tools'):
        d = os.path.join(ROOT, sub)
        for name in sorted(os.listdir(d)):
            if not name.endswith(('.gd', '.sh')):
                continue
            if name == 'release_notes_data.gd':
                continue          # the baked changelog is history, by design
            path = os.path.join(d, name)
            for n, line in enumerate(io.open(path, encoding='utf-8', errors='replace'), 1):
                stripped = line.strip()
                if stripped.startswith('#'):
                    continue
                code = line.split('#')[0]
                # Strip string literals: a check() TITLE that says "the arena is gone" is evidence,
                # not a leftover. Only real identifiers should fail the audit.
                bare = re.sub(r'"[^"]*"', '""', code)
                bare = re.sub(r"'[^']*'", "''", bare)
                # An assertion that a button is ABSENT is the opposite of a leftover.
                if 'find_child(' in code and '== null' in code:
                    continue
                if SYMBOLS.search(bare):
                    problems.append('%s/%s:%d  symbol: %s' % (sub, name, n, stripped[:90]))
                elif WORDS.search(code) and ('"' in code or "'" in code):
                    notes.append('%s/%s:%d  text: %s' % (sub, name, n, stripped[:90]))


def scan_scenes():
    d = os.path.join(ROOT, 'scenes')
    for base, _dirs, files in os.walk(d):
        for name in files:
            if not name.endswith('.tscn'):
                continue
            p = os.path.join(base, name)
            body = io.open(p, encoding='utf-8', errors='replace').read()
            if SYMBOLS.search(body) or WORDS.search(body):
                problems.append('scene %s mentions a removed mode' % os.path.relpath(p, ROOT))


def scan_input_map():
    p = os.path.join(ROOT, 'project.godot')
    body = io.open(p, encoding='utf-8', errors='replace').read()
    section = body.split('[input]')[1].split('\n[')[0] if '[input]' in body else ''
    for line in section.split('\n'):
        if WORDS.search(line):
            problems.append('project.godot input map: %s' % line.strip()[:90])
    for line in body.split('\n'):
        if SYMBOLS.search(line):
            problems.append('project.godot: %s' % line.strip()[:90])


def scan_res_paths():
    """Every res:// path referenced from code must exist."""
    seen = {}
    for sub in ('scripts', 'tests', 'tools', 'scenes'):
        d = os.path.join(ROOT, sub)
        for base, _dirs, files in os.walk(d):
            for name in files:
                if not name.endswith(('.gd', '.tscn')):
                    continue
                if name == 'release_notes_data.gd':
                    continue
                p = os.path.join(base, name)
                for n, line in enumerate(io.open(p, encoding='utf-8', errors='replace'), 1):
                    if line.strip().startswith('#'):
                        continue
                    for m in RES_PATH.findall(line):
                        # `res://art/bg_` is a string PREFIX the tool builds a name from, and
                        # `res://.visual_frames` is a directory the demo creates rather than reads.
                        if '%' in m or m.endswith('/') or m.endswith('_') or m == 'res://.visual_frames':
                            continue
                        seen.setdefault(m, (os.path.relpath(p, ROOT), n))
    for path, (where, n) in sorted(seen.items()):
        disk = os.path.join(ROOT, path[len('res://'):].replace('/', os.sep))
        if not os.path.exists(disk):
            problems.append('%s:%d  dangling path %s' % (where, n, path))


def scan_orphan_art():
    """Art files nothing references any more -- not a failure, but worth listing."""
    used = set()
    for sub in ('scripts', 'tests', 'tools', 'scenes'):
        d = os.path.join(ROOT, sub)
        for base, _dirs, files in os.walk(d):
            for name in files:
                if not name.endswith(('.gd', '.tscn')):
                    continue
                body = io.open(os.path.join(base, name), encoding='utf-8', errors='replace').read()
                used.update(RES_PATH.findall(body))
    art = os.path.join(ROOT, 'art')
    for base, _dirs, files in os.walk(art):
        for name in files:
            if name.endswith('.import'):
                continue
            rel = 'res://' + os.path.relpath(os.path.join(base, name), ROOT).replace(os.sep, '/')
            if rel not in used and WORDS.search(name):
                notes.append('orphan art: %s' % rel)


scan_code()
scan_scenes()
scan_input_map()
scan_res_paths()
scan_orphan_art()

print('')
if problems:
    print('PROBLEMS (%d):' % len(problems))
    for p in problems:
        print('  ' + p)
else:
    print('No code, scene, input-map or path references to the removed modes.')
print('')
if notes:
    print('For review -- strings and orphan files (%d):' % len(notes))
    for n in notes:
        print('  ' + n)
print('')
sys.exit(1 if problems else 0)
