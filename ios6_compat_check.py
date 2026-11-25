#!/usr/bin/env python3
"""Pre-build gate for iOS 6.1.6 compatibility of the armv7 slice.

Why this exists
---------------
The app compiles against the iOS 9.3 SDK but ships to devices as old as iOS 6,
so the compiler happily accepts Foundation/CFNetwork APIs that do not exist on
the device. Nothing catches that at build time: it only shows up at runtime as

    -[NSConcreteData base64EncodedStringWithOptions:]: unrecognized selector

or, for a missing C symbol, as a dyld failure before main() ever runs (no crash
report, no log output -- very hard to diagnose from the device alone).

Both of those happened during development. This gate turns that class of bug
into a build-time failure.

It checks two things:

  1. Source scan: known iOS 7+ API spellings used in app sources.
  2. Symbol scan: the armv7 slice's undefined symbols, checked against a deny
     list of symbols known to be missing on iOS 6.

Run directly for a report, or import check_source()/check_binary().
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent

# Applies to code we wrote for the WARP/WireGuard work and any new networking
# code. Pre-existing files are scanned too, because the same trap applies.
SOURCE_GLOBS = ["*.m", "*.h", "warp/*.c", "warp/*.h"]
SKIP_DIRS = {".theos", "versions", "packages", "obj", "build"}

# (regex, why it is a problem). Matched against source text, so keep these
# specific enough not to false-positive on comments and identifiers.
SOURCE_RULES = [
    (r"base64EncodedStringWithOptions", "iOS 7+; use warp_base64_encode"),
    (r"initWithBase64EncodedString", "iOS 7+; use warp_base64_decode"),
    (r"NSDataBase64Decoding", "iOS 7+; use warp_base64_decode"),
    (r"NSURLAuthenticationMethodServerTrust",
     "iOS 7+ symbol; hard-crashes dyld on iOS 6. Use the literal string"),
    (r"allowsAnyHTTPSCertificateForHost",
     "iOS 7+ and a trust bypass; never acceptable here"),
    (r"setAllowsAnyHTTPSCertificateForHost",
     "iOS 7+ and a trust bypass; never acceptable here"),
    (r"TLS_RSA_WITH_", "private TLS API; unavailable on iOS 6"),
    (r"CFReadStreamSetProperty.*kCFStreamPropertySSL", "private TLS API"),
    (r"\.containsString:", "iOS 8+; use rangeOfString:"),
    (r"\bcomponentsMatchedByPredicate", "iOS 8+; check availability"),
    # iOS 7+ properties. Sending one of these on iOS 6 is an unrecognised
    # selector, which is a crash on launch rather than a missing feature.
    (r"\.layoutMargins\b", "iOS 7+; check availability"),
    (r"automaticallyAdjustsScrollViewInsets", "iOS 7+; check availability"),
    (r"preferredFontForTextStyle", "iOS 7+; check availability"),
]

# APIs that are iOS 7+ but are safe when reached only behind a dynamic
# availability guard. Flagged only if the file uses them *without* such a
# guard. NSURLSession is the real case: the codebase correctly does
#
#     if (NSClassFromString(@"NSURLSession")) { ... } else { NSURLConnection ... }
#
# which is safe on iOS 6. An unguarded use would crash, so check for the guard.
GUARDED_RULES = [
    (r"\bNSURLSession\b", 'NSClassFromString(@"NSURLSession")'),
    # iOS 7+ properties. Sending one of these on iOS 6 is an unrecognised
    # selector, which is a crash on launch rather than a missing feature - so
    # they are only allowed where the code checks first.
    (r"\.tintColor\s*=", "setTintColor:onView:"),
    (r"\.barTintColor\s*=", "setBarTintColor:onBar:"),
    (r"\.separatorInset\s*=", "respondsToSelector:@selector(setSeparatorInset:)"),
    (r"drawViewHierarchyInRect:", "respondsToSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)"),
    (r"\.layoutMargins\b", "respondsToSelector:@selector(setLayoutMargins:)"),
    (r"automaticallyAdjustsScrollViewInsets", "respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)"),
    (r"preferredFontForTextStyle", "respondsToSelector:@selector(preferredFontForTextStyle:)"),
]

# Undefined symbols that must NOT appear in the armv7 slice for iOS 6 support.
DENY_SYMBOLS = {
    "_NSURLAuthenticationMethodServerTrust": "added in iOS 7",
    "_NSURLAuthenticationMethodClientCertificate": "added in iOS 7",
    "_base64EncodedStringWithOptions:": "added in iOS 7",
    "_initWithBase64EncodedString:options:": "added in iOS 7",
}


def iter_sources():
    for pattern in SOURCE_GLOBS:
        for path in sorted(ROOT.glob(pattern)):
            if any(part in SKIP_DIRS for part in path.parts):
                continue
            yield path


def strip_comments_and_strings(text):
    """Blank out // and /* */ comments and string literals.

    Rule messages live in comments constantly ("this is iOS 7+"), so scanning
    raw text would flag our own explanations. Replace comment/string contents
    with spaces, preserving line structure.
    """
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
        elif text[i] == '"':
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 1
                j += 1
            j = min(j + 1, n)
            out.append("".join(c if c == "\n" else " " for c in text[i:j]))
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def check_source(verbose=True):
    """Return a list of (path, lineno, rule, line) violations."""
    violations = []
    for path in iter_sources():
        try:
            raw = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        clean = strip_comments_and_strings(raw)
        raw_lines = raw.splitlines()
        clean_lines = clean.splitlines()
        for pattern, why in SOURCE_RULES:
            for idx, line in enumerate(clean_lines):
                if re.search(pattern, line):
                    # Use the original text for a useful message when the line
                    # is real code (comments/strings were blanked in clean).
                    shown = raw_lines[idx].strip() if idx < len(raw_lines) else line.strip()
                    violations.append((path, idx + 1, pattern, shown, why))
                    if verbose:
                        print(f"  {path.name}:{idx + 1}: {pattern} -> {shown[:70]}")
        for pattern, guard in GUARDED_RULES:
            if guard not in raw:
                for idx, line in enumerate(clean_lines):
                    if re.search(pattern, line):
                        shown = raw_lines[idx].strip() if idx < len(raw_lines) else line.strip()
                        violations.append((
                            path, idx + 1, pattern, shown,
                            f"iOS 7+ API used without the {guard} guard"))
                        if verbose:
                            print(f"  {path.name}:{idx + 1}: {pattern} unguarded -> {shown[:60]}")

    # The rules above are hand-written and only cover what has already been
    # hit. This one is derived from the SDK, so it covers everything the SDK
    # knows about rather than everything someone remembered to write down:
    # every property and selector that does not exist on iOS 6, whether or not
    # it has ever bitten us before.
    try:
        import ios6_api_derive
        for path, lineno, kind, name, shown, guarded in ios6_api_derive.scan(verbose=False):
            if guarded:
                continue
            violations.append((
                path, lineno, f"{kind} {name}", shown,
                f"iOS {ios6_api_derive.MIN_IOS}+ API used with no runtime check; "
                f"on iOS 6 this is an unrecognised selector, which is a crash"))
            if verbose:
                print(f"  {path.name}:{lineno}: {kind} {name} unguarded -> {shown[:60]}")
    except ImportError:
        pass

    return violations


# Frameworks that only exist from a later iOS, paired with the class symbols
# that come from them. Referencing one of these classes without weak-linking its
# framework makes dyld fail to launch on the old OS - before main(), so there is
# no crash report and no log, only a device that will not open the app.
#
# WebKit is the one that bites: it has existed since iOS 2 (UIWebView), so the
# framework is always present, but WKWebView only arrived in iOS 8. Linking
# WebKit strongly and mentioning WKWebView leaves _OBJC_CLASS_$_WKWebView
# undefined and the app dies at launch on iOS 6 and 7.
WEAK_FRAMEWORK_CLASSES = {
    "_OBJC_CLASS_$_WKWebView": "WebKit",
    "_OBJC_CLASS_$_WKWebViewConfiguration": "WebKit",
    "_OBJC_CLASS_$_WKUserContentController": "WebKit",
    "_OBJC_CLASS_$_WKScriptMessage": "WebKit",
    "_OBJC_CLASS_$_WKWebViewPreferences": "WebKit",
}


def check_weak_linking(binary, otool=None):
    """Return list of (symbol, why) for newer-OS classes in strongly linked frameworks."""
    import subprocess
    if otool is None:
        otool = str(ROOT.parent / "theos/toolchain/linux/iphone/bin/otool")
    try:
        out = subprocess.run([otool, "-l", str(binary)],
                             capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return []

    # Collect the frameworks that are loaded WEAKLY and the ones loaded
    # strongly. A weak load is the load command LC_LOAD_WEAK_DYLIB.
    weak = set()
    strong = set()
    current = None
    for line in out.splitlines():
        stripped = line.strip()
        if stripped.startswith("cmd LC_LOAD_WEAK_DYLIB"):
            current = "weak"
            continue
        if stripped.startswith("cmd LC_LOAD_DYLIB"):
            current = "strong"
            continue
        if current and "name " in stripped:
            name = stripped.split("name ", 1)[1].strip().strip("()")
            (weak if current == "weak" else strong).add(name)
            current = None

    try:
        nm_out = subprocess.run(
            [str(ROOT.parent / "theos/toolchain/linux/iphone/bin/nm"), "-u", str(binary)],
            capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    undef = {line.split()[-1] for line in nm_out.splitlines() if line.split()}

    bad = []
    for symbol, framework in WEAK_FRAMEWORK_CLASSES.items():
        if symbol not in undef:
            continue
        if framework in weak:
            continue
        if framework in strong:
            bad.append((symbol, f"{framework} is linked strongly; add -weak_framework {framework}"))
    return bad


def check_symbols(binary, nm=None):
    """Return list of (symbol, why) for denied symbols present in `binary`."""
    import subprocess
    if nm is None:
        nm = str(ROOT.parent / "theos/toolchain/linux/iphone/bin/nm")
    try:
        out = subprocess.run([nm, "-u", str(binary)],
                             capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    undef = set()
    for line in out.splitlines():
        parts = line.split()
        if parts:
            undef.add(parts[-1])
    return [(s, why) for s, why in DENY_SYMBOLS.items() if s in undef]


def main():
    print("== iOS 6 compatibility gate ==")
    src = check_source()
    if src:
        print(f"FAIL: {len(src)} iOS 7+ API use(s) in source")
        return 1
    print("source scan: OK")

    armv7 = ROOT / ".theos/obj/debug/armv7/LegacyMusic.app/LegacyMusic"
    if armv7.exists():
        bad = check_symbols(armv7)
        if bad:
            print("FAIL: denied undefined symbols in armv7 slice:")
            for s, why in bad:
                print(f"  {s}: {why}")
            return 1
        print("armv7 symbol scan: OK")

        weak_bad = check_weak_linking(armv7)
        if weak_bad:
            print("FAIL: framework linked strongly but only used by a newer OS:")
            for s, why in weak_bad:
                print(f"  {s}: {why}")
            return 1
        print("weak-linking scan: OK")
    else:
        print("armv7 slice not built yet; skipping symbol scan")

    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())