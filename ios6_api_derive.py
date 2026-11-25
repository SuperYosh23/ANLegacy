#!/usr/bin/env python3
"""Derive the iOS 7+ API rules from the SDK headers instead of hand-listing them.

Why
---
The compatibility gate used to carry a hand-written list of iOS 7+ API
spellings, and every time a new one was used the list had to be extended by
hand. It was extended three times and missed three crashes in a row:

    -[LTHomeRecentsCell setSeparatorInset:]: unrecognized selector
    -[UIView setTintColor:]: unrecognized selector
    -[LTCardNavBar setBarTintColor:]: unrecognized selector

Each was a property the platform added in iOS 7, sent to a view on iOS 6,
which is a crash on launch rather than a missing feature.

The SDK this app compiles against (iOS 9.3) marks everything newer than the
deployment target with NS_AVAILABLE_IOS(7_0) and friends. So the list does
not need to be written by hand at all - it can be read out of the headers,
where it is always right and always complete.

What this produces
------------------
Two kinds of rule, both matched against the app's source:

  property   the source mentions ".tintColor" - either reading or writing an
             iOS 7+ property. Both are an unrecognised selector on iOS 6.

  selector   the source sends a method that did not exist in iOS 6, e.g.
             "drawViewHierarchyInRect:".

Run directly for a report; import ios7_apis()/scan() for the gate.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent

# The SDK the armv7 slice compiles against. Anything newer in the headers is
# still valid to call, but it tells us nothing about iOS 6.
SDK = ROOT.parent / "theos/sdks/iPhoneOS9.3.sdk"

# The frameworks whose headers carry the UIKit and Foundation APIs the app
# actually reaches for.
FRAMEWORK_HEADERS = [
    "System/Library/Frameworks/UIKit.framework/Headers",
    "System/Library/Frameworks/Foundation.framework/Headers",
    "System/Library/Frameworks/CoreGraphics.framework/Headers",
    "System/Library/Frameworks/QuartzCore.framework/Headers",
    "System/Library/Frameworks/AVFoundation.framework/Headers",
]

# The deployment target the app has to keep working on.
MIN_IOS = 7

# NS_AVAILABLE_IOS(7_0) in the 9.3 SDK, API_AVAILABLE(ios(7.0)) in newer ones.
_AVAIL = re.compile(
    r"NS_AVAILABLE_IOS\(\s*(\d+)_(\d+)\s*\)"
    r"|API_AVAILABLE\(\s*ios\(\s*(\d+)(?:\.(\d+))?\s*\)\s*\)"
    r"|NS_AVAILABLE\(\s*(\d+)(?:\.(\d+))?\s*\)"
)

# Attributes that are not part of a selector or a property name.
_ATTR = re.compile(r"\b(?:NS|UI|CF|CA|AV|k)_\w+(?:\([^)]*\))?")


def _min_ios(decl):
    """The lowest iOS version the declaration is available on, or None."""
    best = None
    for m in _AVAIL.finditer(decl):
        nums = [g for g in m.groups() if g is not None]
        if not nums:
            continue
        major = int(nums[0])
        if best is None or major < best:
            best = major
    return best


def _strip_comments(text):
    """Remove // and /* */ comments, leaving the code and the line structure."""
    out = []
    i, n = 0, len(text)
    while i < n:
        two = text[i:i + 2]
        if two == "//":
            j = text.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i))
            i = j
        elif two == "/*":
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            out.append("".join(c if c == "\n" else " " for c in text[i:j]))
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def _declarations(text, terminators=(";",)):
    """Yield the @property and method declarations in a header or an .m file.

    `terminators` also accepts "{" so that method *definitions* in an
    implementation are picked up: a method the app defines itself is not an
    SDK API, and flagging it would be a false positive.
    """
    buf = ""
    for line in _strip_comments(text).splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if not buf and not (stripped.startswith("@property")
                             or stripped.startswith("- (")
                             or stripped.startswith("+ (")):
            continue
        buf = (buf + " " + stripped).strip()
        if not any(stripped.endswith(t) for t in terminators):
            continue
        decl = buf
        buf = ""
        if decl:
            yield decl


def _property_name(decl):
    body = decl[decl.index("@property") + len("@property"):]
    body = _AVAIL.sub(" ", body)
    body = _ATTR.sub(" ", body)
    body = re.sub(r"\([^)]*\)", " ", body)          # attribute lists
    body = re.sub(r"<[^<>]*>", " ", body)           # generics
    body = body.replace("*", " ").replace(";", " ")
    names = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", body)
    return names[-1] if names else None


def _selector(decl):
    """The selector of a method declaration, e.g. "drawViewHierarchyInRect:"."""
    m = re.match(r"[-+]\s*\(", decl)
    if not m:
        return None
    # Find the closing parenthesis of the return type, which may itself
    # contain parentheses: -(id<UIAppearance>)foo;
    i = decl.index("(", m.start())
    depth = 0
    end = -1
    for j in range(i, len(decl)):
        if decl[j] == "(":
            depth += 1
        elif decl[j] == ")":
            depth -= 1
            if depth == 0:
                end = j
                break
    if end < 0:
        return None
    body = decl[end + 1:]
    body = _AVAIL.sub(" ", body)
    body = re.sub(r"\([^)]*\)", " ", body)          # parameter types
    body = body.split(";")[0]
    # Drop the return type: it is everything up to the first selector keyword.
    kw = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*:", body)
    if kw:
        return kw.group(1) + ":"
    # A method with no arguments: the name is the last identifier before the
    # attributes, which are already gone.
    names = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", body)
    return names[-1] if names else None


def _collect(sdk=SDK):
    """Return (property_versions, selector_versions): name -> lowest iOS it appears on."""
    props, sels = {}, {}
    sdk = Path(sdk)
    for rel in FRAMEWORK_HEADERS:
        headers = sdk / rel
        if not headers.is_dir():
            continue
        for path in sorted(headers.glob("*.h")):
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for decl in _declarations(text):
                # A declaration with no availability macro has been there since
                # the beginning, iOS 2. That is what makes a name ambiguous:
                # -backgroundColor carries no macro on UIView (iOS 2) and
                # NS_AVAILABLE_IOS(7_0) on UIPopoverController, so the name
                # alone cannot tell you whether a use is safe on iOS 6.
                version = _min_ios(decl)
                if version is None:
                    version = 2
                if decl.startswith("@property"):
                    name = _property_name(decl)
                    if not name or name.startswith("_"):
                        continue
                    props[name] = min(props.get(name, 99), version)
                else:
                    sel = _selector(decl)
                    if not sel or sel.startswith("_"):
                        continue
                    sels[sel] = min(sels.get(sel, 99), version)
    return props, sels


def ios7_apis(sdk=SDK):
    """Return (properties, selectors) that only exist from iOS 7 onwards.

    A name is only usable as a rule if *every* declaration of it in the SDK is
    iOS 7 or later. That matters because property names are per class:
    -backgroundColor arrived in iOS 7 on UIPopoverController, but it has been on
    UIView since iOS 2, so "something.backgroundColor" is safe on iOS 6 and
    flagging the name would be wrong. -tintColor, on the other hand, is iOS 7
    everywhere it appears, so any use of it is unsafe on iOS 6.
    """
    props, sels = _collect(sdk)
    props = {k for k, v in props.items() if v >= MIN_IOS}
    sels = {k for k, v in sels.items() if v >= MIN_IOS}
    return props, sels


CACHE = ROOT / ".ios6_api_cache.json"


def _cached_apis():
    """The derived API sets, cached to disk.

    Reading every UIKit header takes a few seconds, and the SDK headers do not
    change between builds, so the result is cached. The cache is keyed on the
    SDK path and the header mtimes, so replacing the SDK invalidates it.
    """
    import json
    key = {}
    for rel in FRAMEWORK_HEADERS:
        headers = Path(SDK) / rel
        if headers.is_dir():
            newest = max((p.stat().st_mtime for p in headers.glob("*.h")), default=0)
            key[rel] = int(newest)
    try:
        cached = json.loads(CACHE.read_text())
        if cached.get("key") == key and cached.get("version") == MIN_IOS:
            return set(cached["properties"]), set(cached["selectors"])
    except (OSError, ValueError, KeyError):
        pass
    props, sels = ios7_apis()
    if not props and not sels:
        raise RuntimeError(
            f"no SDK headers under {SDK}: the derived iOS 7+ rules would be "
            f"empty and the gate would pass without checking anything")
    try:
        CACHE.write_text(json.dumps({
            "key": key,
            "version": MIN_IOS,
            "properties": sorted(props),
            "selectors": sorted(sels),
        }))
    except OSError:
        pass
    return props, sels


def _all_keywords(decl):
    """Every keyword of a selector, e.g. "drawViewHierarchyInRect:" and
    "afterScreenUpdates:" for -drawViewHierarchyInRect:afterScreenUpdates:."""
    m = re.match(r"[-+]\s*\(", decl)
    if not m:
        return []
    i = decl.index("(", m.start())
    depth = 0
    end = -1
    for j in range(i, len(decl)):
        if decl[j] == "(":
            depth += 1
        elif decl[j] == ")":
            depth -= 1
            if depth == 0:
                end = j
                break
    if end < 0:
        return []
    body = decl[end + 1:]
    body = _AVAIL.sub(" ", body)
    body = re.sub(r"\([^)]*\)", " ", body)
    body = body.split(";")[0].split("{")[0]
    return [kw + ":" for kw in re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*:", body)]


def _app_selectors(root=ROOT):
    """Selectors the app defines itself, so SDK rules do not flag our own code."""
    own = set()
    for path in sorted(root.glob("*.m")) + sorted(root.glob("*.h")):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for decl in _declarations(text, terminators=(";", "{")):
            for kw in _all_keywords(decl):
                own.add(kw)
            sel = _selector(decl)
            if sel:
                own.add(sel)
    return own


# A use of an iOS 7+ API is safe on iOS 6 if the code checks the platform first.
# These are the ways the app does that.
GUARD_MARKERS = (
    "respondsToSelector",
    "objc_msgSend",
    "methodForSelector",
    "performSelector",
    "NSClassFromString",
    "NSSelectorFromString",
)


def _is_guarded(lines, idx):
    """Whether the use at `idx` sits next to a runtime check of the platform.

    The window is tight on purpose. A guard can be written before the use
    (the usual form) or after it (when the selector is fetched into a
    variable first and the check follows), so both directions are looked at -
    but only immediately adjacent lines, or an unrelated check further up
    would mark an unguarded use as safe.
    """
    lo = max(0, idx - 2)
    hi = min(len(lines), idx + 3)
    window = "\n".join(lines[lo:hi])
    return any(marker in window for marker in GUARD_MARKERS)


def _scan_regexes(props, sels):
    """One combined pattern per kind, so the scan is a pass per line.

    The names are sorted longest first so that a name which is a prefix of
    another cannot shadow it.
    """
    def build(names, prefix, suffix):
        if not names:
            return None
        alts = "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True))
        return re.compile(prefix + "(?P<hit>" + alts + ")" + suffix)

    return (
        build(props, r"\.\s*", r"\b"),
        build(sels, r"\b", ""),
    )


def scan(root=ROOT, verbose=True):
    """Return a list of (path, lineno, kind, name, line, guarded) for iOS 7+ uses."""
    props, sels = _cached_apis()
    own = _app_selectors(root)
    sels = {s for s in sels if s not in own}
    prop_re, sel_re = _scan_regexes(props, sels)

    from ios6_compat_check import strip_comments_and_strings

    hits = []
    for path in sorted(root.glob("*.m")) + sorted(root.glob("*.h")):
        if path.name == "ios6_api_derive.py":
            continue
        try:
            raw = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        clean = strip_comments_and_strings(raw)
        raw_lines = raw.splitlines()
        clean_lines = clean.splitlines()
        for idx, line in enumerate(clean_lines):
            shown = raw_lines[idx].strip() if idx < len(raw_lines) else line.strip()
            guarded = _is_guarded(clean_lines, idx)
            if prop_re:
                for m in prop_re.finditer(line):
                    hits.append((path, idx + 1, "property", m.group("hit"), shown, guarded))
            if sel_re:
                for m in sel_re.finditer(line):
                    hits.append((path, idx + 1, "selector", m.group("hit"), shown, guarded))
    if verbose:
        for path, lineno, kind, name, shown, guarded in hits:
            mark = "guarded" if guarded else "UNGUARDED"
            print(f"  {path.name}:{lineno}: {mark} {kind} {name} -> {shown[:60]}")
    return hits


if __name__ == "__main__":
    props, sels = _cached_apis()
    print(f"derived from {SDK.name}: {len(props)} properties, {len(sels)} selectors")
    found = scan()
    unguarded = [h for h in found if not h[5]]
    print(f"\n{len(found)} iOS 7+ API use(s) in source, {len(unguarded)} unguarded")
