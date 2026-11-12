#!/usr/bin/env python3
"""The parts two cross-check scripts share.

`hocon_crosscheck.py` and `hcl_crosscheck.py` each read the vectors of their
format and put the same inputs to a second reader. Both need to take a vector
file apart, compare what it asserts with what the second reader says, and report
the differences the same way, so that lives here.
"""

import re

STRING = r'"((?:[^"\\]|\\.)*)"'
BLOCK = re.compile(r'test "(?P<name>[^"]+)" \{\n(?P<body>.*?)\n\}', re.S)

ASSERTIONS = (
    (r'assert_eq\(%s\.need_text\(' + STRING + r'\), ' + STRING + r'\)', "text"),
    (r'assert_eq\(%s\.need_int\(' + STRING + r'\), (-?\d+)L\)', "int"),
    (r'assert_eq\(%s\.need_bool\(' + STRING + r'\), (true|false)\)', "bool"),
    (r'assert_eq\(%s\.need\(' + STRING + r'\)\.real\(\), ([-\d.eE+]+)\)', "real"),
    (r'assert_eq\(%s\.need\(' + STRING + r'\)\.kind\(\), "null"\)', "null"),
    (r'assert_eq\(%s\.need\(' + STRING + r'\)\.list\(\)\.length\(\), (\d+)\)', "length"),
    (r'assert_eq\(%s\.need\(' + STRING + r'\)\.table\(\)\.length\(\), (\d+)\)', "length"),
    (r'assert_eq\(%s\.table\(\)\.length\(\), (\d+)\)', "root"),
)

LABELS = re.compile(
    r'assert_eq\(body\.blocks_of\(' + STRING + r'\)\.map\(fn\(b\) \{ b\.labels\.join\("/"\) \}\), \[(.*?)\]\)',
    re.S,
)


def unquote(text):
    out = []
    i = 0
    while i < len(text):
        c = text[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        out.append({"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"'}[text[i + 1]])
        i += 2
    return "".join(out)


def expected(body, root):
    """The paths and values a vector block asserts, as a table."""
    want = {}
    if "should be refused" in body:
        return {"refused": True}
    for pattern, kind in ASSERTIONS:
        for match in re.finditer(pattern % re.escape(root), body):
            if kind == "root":
                want[""] = ("length", int(match.group(1)))
                continue
            path = unquote(match.group(1))
            raw = match.group(2) if match.re.groups >= 2 else None
            if kind == "text":
                want[path] = unquote(raw)
            elif kind == "int":
                want[path] = int(raw)
            elif kind == "bool":
                want[path] = raw == "true"
            elif kind == "real":
                want[path] = float(raw)
            elif kind == "null":
                want[path] = None
            else:
                want[path] = ("length", int(raw))
    return want


def labels(body):
    """The block labels a vector block asserts, by block name."""
    out = {}
    for match in LABELS.finditer(body):
        kind = unquote(match.group(1))
        found = re.findall(STRING, match.group(2))
        out[kind] = [unquote(one) for one in found]
    return out


def flatten(value, path=""):
    """A tree as path -> value, with a list or mapping counted where it stands."""
    out = {}
    if isinstance(value, dict):
        out[path] = ("length", len(value))
        for key, item in value.items():
            step = str(key) if not path else path + "." + str(key).replace(".", "\\.")
            out.update(flatten(item, step))
    elif isinstance(value, list):
        out[path] = ("length", len(value))
        for index, item in enumerate(value):
            out.update(flatten(item, path + "." + str(index)))
    else:
        out[path] = value
    return out


def same(want, got):
    if isinstance(want, tuple) and want[0] == "length":
        if isinstance(got, tuple) and got[0] == "length":
            return want[1] == got[1]
        return False
    if want is None:
        return got is None
    if isinstance(want, bool) or isinstance(got, bool):
        return want is got or want == got
    if isinstance(want, (int, float)) and isinstance(got, (int, float)):
        return float(want) == float(got)
    return want == got


def compare(want, got, want_labels, got_labels):
    """The paths on which the two disagree."""
    wrong = []
    for path, value in want.items():
        if path not in got:
            wrong.append(f"{path}: the vectors have a value, the second reader has none")
        elif not same(value, got[path]):
            wrong.append(f"{path}: vectors {value!r}, second reader {got[path]!r}")
    for kind, want_names in want_labels.items():
        found = got_labels.get(kind)
        if found is None:
            wrong.append(f"{kind}: the vectors have blocks, the second reader has none")
        elif found != want_names:
            wrong.append(f"{kind}: vectors {want_names!r}, second reader {found!r}")
    return wrong


def report(compared, agreed, differed, skipped):
    for name, reason in skipped:
        print(f"skipped   {name}: {reason}")
    for name, problems in differed:
        print(f"differs   {name}")
        for problem in problems:
            print(f"          {problem}")
    print(
        f"\n{compared} cases compared, {agreed} agree, {len(differed)} differ, "
        f"{len(skipped)} not comparable"
    )
