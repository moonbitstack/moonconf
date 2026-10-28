#!/usr/bin/env python3
"""Generate the `.env` vectors, and check them against a reference reader.

The reference below is a direct transcription of the rules this package
documents -- `export`, comments on their own line, single quotes literal, double
quotes decoded, quoted values that may span lines, references expanded against
the entries above them. It is written out again here rather than imported so that
the two implementations are independent: a case that passes is one where two
readers written from the same rules agree.

Run from the repository root: python scripts/vectors/dotenv.py
"""

import os
import re

NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")

CASES = [
    ("bare", ["A=1"], [("A", "1")]),
    ("spaces around", ["A = 1"], [("A", "1")]),
    ("empty value", ["A="], [("A", "")]),
    ("name alone", ["A"], [("A", "")]),
    ("comment line", ["# A=1", "B=2"], [("B", "2")]),
    ("indented comment", ["   # A=1", "B=2"], [("B", "2")]),
    ("export", ["export A=1"], [("A", "1")]),
    ("export tab", ["export\tA=1"], [("A", "1")]),
    ("hash in value", ["A=a#b"], [("A", "a#b")]),
    ("hash after value", ["A=a # b"], [("A", "a # b")]),
    ("comment after quote", ['A="a" # note'], [("A", "a")]),
    ("single quotes", ["A='a b'"], [("A", "a b")]),
    ("single quotes keep dollar", ["A='${B}'", "B=x"], [("A", "${B}"), ("B", "x")]),
    ("double quotes", ['A="a b"'], [("A", "a b")]),
    ("double quote escapes", ['A="a\\nb\\tc"'], [("A", "a\nb\tc")]),
    ("double quote escaped dollar", ['A="\\${B}"', "B=x"], [("A", "${B}"), ("B", "x")]),
    ("double quote backslash", ['A="a\\\\b"'], [("A", "a\\b")]),
    ("double quote unknown escape", ['A="a\\qb"'], [("A", "a\\qb")]),
    ("multiline double", ['A="one', 'two"'], [("A", "one\ntwo")]),
    ("multiline single", ["A='one", "two'"], [("A", "one\ntwo")]),
    ("reference above", ["B=x", "A=${B}-y"], [("A", "x-y"), ("B", "x")]),
    ("reference bare", ["B=x", "A=$B-y"], [("A", "x-y"), ("B", "x")]),
    ("reference below is empty", ["A=${B}-y", "B=x"], [("A", "-y"), ("B", "x")]),
    ("reference default", ["A=${B:-fallback}"], [("A", "fallback")]),
    ("self reference", ["PATH=/usr/bin", "PATH=${PATH}:/opt/bin"], [("PATH", "/usr/bin:/opt/bin")]),
    ("later wins", ["A=1", "A=2"], [("A", "2")]),
    ("blank lines", ["", "A=1", "", ""], [("A", "1")]),
    ("crlf", ["A=1\r", "B=2\r"], [("A", "1"), ("B", "2")]),
    ("no trailing newline", ["A=1"], [("A", "1")]),
    ("value with equals", ["A=b=c"], [("A", "b=c")]),
    ("path value", ["P=/opt/a:/opt/b"], [("P", "/opt/a:/opt/b")]),
    ("unicode", ["A=héllo"], [("A", "héllo")]),
    ("export with spaces", ["export   A=1"], [("A", "1")]),
    ("quoted empty", ['A=""'], [("A", "")]),
    ("quoted with hash", ['A="#not a comment"'], [("A", "#not a comment")]),
]


def parse(text):
    """The reference reader: (key, value, quoted) in file order."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        while i < n and text[i] in " \t":
            i += 1
        if i >= n:
            break
        if text[i] in "\r\n":
            i += 2 if text[i] == "\r" and i + 1 < n and text[i + 1] == "\n" else 1
            continue
        if text[i] == "#":
            while i < n and text[i] not in "\r\n":
                i += 1
            continue
        if text.startswith("export", i) and i + 6 < n and text[i + 6] in " \t":
            i += 6
            while i < n and text[i] in " \t":
                i += 1
        start = i
        while i < n and text[i] not in "= \t\r\n":
            i += 1
        key = text[start:i]
        if not NAME.match(key):
            raise SyntaxError("bad name")
        while i < n and text[i] in " \t":
            i += 1
        value, quoted = "", False
        if i < n and text[i] == "=":
            i += 1
            while i < n and text[i] in " \t":
                i += 1
            if i < n and text[i] == "'":
                j = text.index("'", i + 1)
                value = text[i + 1:j]
                quoted = True
                i = j + 1
                i = tail(text, i)
            elif i < n and text[i] == '"':
                j = i + 1
                buf = []
                while j < n and text[j] != '"':
                    if text[j] == "\\":
                        nxt = text[j + 1:j + 2]
                        decoded = {
                            "n": "\n", "r": "\r", "t": "\t", "a": "\a",
                            "b": "\b", "f": "\f", "v": "\v", "\\": "\\",
                            '"': '"', "'": "'",
                        }.get(nxt)
                        if decoded is None:
                            buf.append("\\" + nxt)
                        else:
                            buf.append(decoded)
                        j += 2
                        continue
                    buf.append(text[j])
                    j += 1
                value = "".join(buf)
                i = j + 1
                i = tail(text, i)
            else:
                j = i
                while j < n and text[j] not in "\r\n":
                    j += 1
                value = text[i:j].rstrip(" \t")
                i = j
        elif i < n and text[i] not in "\r\n":
            raise SyntaxError("trailing")
        out.append((key, value, quoted))
        while i < n and text[i] in " \t":
            i += 1
        if i < n and text[i] == "#":
            while i < n and text[i] not in "\r\n":
                i += 1
        if i < n and text[i] == "\r":
            i += 2 if i + 1 < n and text[i + 1] == "\n" else 1
        elif i < n and text[i] == "\n":
            i += 1
    return out


def tail(text, i):
    """After a quoted value: spaces, then a comment or the end of the line."""
    n = len(text)
    while i < n and text[i] in " \t":
        i += 1
    if i < n and text[i] == "#":
        while i < n and text[i] not in "\r\n":
            i += 1
        return i
    if i < n and text[i] not in "\r\n":
        raise SyntaxError("trailing")
    return i


def expand(value, env):
    """`${A}`, `${A:-b}` and `$A`, reading a missing name as empty."""
    out = []
    i = 0
    n = len(value)
    while i < n:
        if value[i] == "\\" and value[i + 1:i + 2] == "$":
            out.append("$")
            i += 2
            continue
        if value[i] != "$":
            out.append(value[i])
            i += 1
            continue
        if value[i + 1:i + 2] == "{":
            end = value.index("}", i + 2)
            body = value[i + 2:end]
            if ":-" in body:
                name, default = body.split(":-", 1)
                out.append(env.get(name, "") or default)
            else:
                out.append(env.get(body, ""))
            i = end + 1
            continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", value[i + 1:])
        if m:
            out.append(env.get(m.group(0), ""))
            i += 1 + len(m.group(0))
            continue
        out.append("$")
        i += 1
    return "".join(out)


def load(text):
    env = {}
    for key, value, quoted in parse(text):
        env[key] = value if quoted else expand(value, env)
    return env


def escape(text):
    return (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
    )


def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    target = os.path.join(root, "src", "dotenv", "vectors_test.mbt")
    lines = [
        "// Copyright 2026 Leo Cheng",
        "// SPDX-License-Identifier: Apache-2.0",
        "",
        "// Generated by scripts/vectors/dotenv.py from the reference reader described",
        "// there. Do not edit by hand.",
        "",
    ]
    for label, source_lines, expected in CASES:
        text = "\n".join(source_lines)
        if source_lines and not text.endswith("\n"):
            text += "\n"
        try:
            env = load(text)
            keys = [key for key, _, _ in parse(text)]
        except (SyntaxError, ValueError):
            lines.append("///|")
            lines.append(f'test "reference: {label}" {{')
            lines.append(f'  let refused = try Ok(@dotenv.load("{escape(text)}")) catch {{')
            lines.append("    error => Err(error)")
            lines.append("  }")
            lines.append("  match refused {")
            lines.append("    Err(_) => ()")
            lines.append('    Ok(_) => fail("the reference reader refuses this text")')
            lines.append("  }")
            lines.append("}")
            lines.append("")
            continue
        lines.append("///|")
        lines.append(f'test "reference: {label}" {{')
        lines.append(f'  let text = "{escape(text)}"')
        lines.append("  let env = @dotenv.load(text)")
        for key, value in expected:
            lines.append(
                f'  assert_eq(env.get("{key}"), Some("{escape(value)}"))'
            )
        if env != dict(expected):
            raise SystemExit(f"{label}: reference disagrees with the case: {env}")
        lines.append(
            "  assert_eq(@dotenv.parse(text).map(fn(entry) { entry.key }), ["
            + ", ".join(f'"{key}"' for key in keys)
            + "])"
        )
        lines.append("}")
        lines.append("")
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    print(f"wrote {target} ({len(CASES)} cases)")


if __name__ == "__main__":
    main()
