#!/usr/bin/env python3
"""Insert ObjC code at a precise spot, verified by re-reading the file after."""
import io, sys


def read(p):
    return io.open(p, encoding='utf-8').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8').write(s)


def method_range(lines, signature):
    """Return (start, end_exclusive) line indices of a method body."""
    start = None
    for i, l in enumerate(lines):
        if l.strip() == signature:
            start = i
            break
    if start is None:
        raise SystemExit('signature not found: %r' % signature)
    depth = 0
    seen = False
    for j in range(start, len(lines)):
        depth += lines[j].count('{') - lines[j].count('}')
        if '{' in lines[j]:
            seen = True
        if seen and depth == 0:
            return start, j + 1
    raise SystemExit('unbalanced braces for %r' % signature)


def insert_before_method_end(path, signature, code):
    lines = read(path).split('\n')
    _, end = method_range(lines, signature)
    assert lines[end - 1].strip() == '}', repr(lines[end - 1])
    new = lines[:end - 1] + code.strip('\n').split('\n') + [lines[end - 1]] + lines[end:]
    write(path, '\n'.join(new))
    return end


def insert_in_implementation(path, code, before_last_end=True):
    """Append code just inside the final @implementation's @end."""
    lines = read(path).split('\n')
    ends = [i for i, l in enumerate(lines) if l.rstrip() == '@end']
    if not ends:
        raise SystemExit('no @end in %s' % path)
    target = ends[-1]
    # Some files leave a blank line between the last method's } and @end.
    body_end = target - 1
    while body_end > 0 and not lines[body_end].strip():
        body_end -= 1
    assert lines[body_end].rstrip().endswith('}'), repr(lines[body_end])
    # Insert AFTER the final method's closing brace, never inside it.
    new = lines[:body_end + 1] + code.strip('\n').split('\n') + lines[body_end + 1:]
    write(path, '\n'.join(new))


def add_before_last_end(path, anchor, addition, count=1):
    s = read(path)
    if addition.strip() in s:
        print('already present, skipped')
        return
    if s.count(anchor) != count:
        raise SystemExit('anchor count %d != %d in %s' % (s.count(anchor), count, path))
    s = s.replace(anchor, addition + anchor, count)
    write(path, s)


if __name__ == '__main__':
    print(__doc__)