#!/usr/bin/env python3
"""Checks Resources/Localization/*.lproj/Localizable.strings against the sources.

Every key used via L("...") (or a SensorNames `Entry(name: "...")`) must exist in every language,
no language may carry stale keys, and each translation must keep the key's %@ / %1$@ placeholders.

    Scripts/check_localizations.py
"""
import glob, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
KEY_RE = re.compile(r'(?:\bL\(|Entry\(name: )"((?:[^"\\]|\\.)*)"')
LINE_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
PLACEHOLDER_RE = re.compile(r'%(?:\d+\$)?@')


def unescape(s):
    return re.sub(r'\\(.)', r'\1', s)


def placeholders(s):
    found = PLACEHOLDER_RE.findall(s)
    # "%@" and "%1$@" are interchangeable when a string has a single argument.
    return sorted("%1$@" if p == "%@" and len(found) == 1 else p for p in found)


def main():
    used = set()
    for path in glob.glob(os.path.join(ROOT, "Sources", "**", "*.swift"), recursive=True):
        used.update(unescape(k) for k in KEY_RE.findall(open(path, encoding="utf-8").read()))

    errors = []
    langs = sorted(glob.glob(os.path.join(ROOT, "Resources", "Localization", "*.lproj")))
    for lproj in langs:
        lang = os.path.basename(lproj)[:-len(".lproj")]
        table = {}
        for n, line in enumerate(open(os.path.join(lproj, "Localizable.strings"), encoding="utf-8"), 1):
            line = line.strip()
            if not line or line.startswith("/*") or line.startswith("//"):
                continue
            m = LINE_RE.match(line)
            if not m:
                errors.append(f"{lang}:{n}: unparsable line: {line}")
                continue
            key, value = unescape(m.group(1)), unescape(m.group(2))
            if key in table:
                errors.append(f"{lang}: duplicate key {key!r}")
            table[key] = value
            if placeholders(key) != placeholders(value):
                errors.append(f"{lang}: placeholder mismatch for {key!r}: {value!r}")
        errors += [f"{lang}: missing {k!r}" for k in sorted(used - table.keys())]
        errors += [f"{lang}: unused {k!r}" for k in sorted(table.keys() - used)]

    for e in errors:
        print(e)
    print(f"{len(langs)} languages, {len(used)} keys, {len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
