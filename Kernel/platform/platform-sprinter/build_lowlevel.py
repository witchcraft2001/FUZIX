#!/usr/bin/env python3
"""Adapt IRQ boundaries and exec entry without editing the shared Z80 source."""
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
changes = {
    '.include "../build/kernel.def"': '.include "kernel.def"',
    '.include "../cpu-z80/kernel-z80.def"':
        '.include "../../cpu-z80/kernel-z80.def"',
    'unix_pop_noei:\n\tpop af\n        ret':
        'unix_pop_noei:\n\tpop af\n\t.globl _spr_user_ret\n\tjp _spr_user_ret',
    '\tld a, (_sprinter_bringup_noei)\n\tor a\n\tjr nz, syscall_keep_di\n        ei\nsyscall_keep_di:':
        '\txor a\n\tld (_int_disabled), a\n\tei\nsyscall_keep_di:',
}
for old, new in changes.items():
    if source.count(old) != 1:
        raise SystemExit("Sprinter lowlevel adapter: source boundary changed: " + old)
    source = source.replace(old, new)
# The platform supplies exec entry; keep only one copy in common memory.
begin = '_doexec:\n'
end = ';\n;  Called from process context (hopefully)'
if source.count(begin) != 1 or source.count(end) != 1:
    raise SystemExit("Sprinter lowlevel adapter: exec boundary changed")
first, last = source.index(begin), source.index(end)
if last <= first:
    raise SystemExit("Sprinter lowlevel adapter: invalid exec boundaries")
source = source[:first] + source[last:]
Path(sys.argv[2]).write_text(source)
