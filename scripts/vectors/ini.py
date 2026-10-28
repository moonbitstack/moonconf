#!/usr/bin/env python3
"""Generate the INI vectors from Python's `configparser`.

Every case is read twice by `configparser` -- once with the defaults, once with a
dialect switched -- and the sections, the names and the values it produces become
a MoonBit test. A case that `configparser` refuses is asserted to be refused
here too.

Run from the repository root: python scripts/vectors/ini.py
"""

import configparser
import os

CASES = [
    ("plain", "[db]\nhost = localhost\nport = 5432\n", {}),
    ("colon separator", "[db]\nhost: localhost\nport: 5432\n", {}),
    ("spaces around", "[db]\n  host   =   localhost  \n", {}),
    ("comment lines", "; a note\n[db]\n# another\nhost = x\n", {}),
    ("empty value", "[db]\nhost =\n", {}),
    ("value with equals", "[db]\nurl = postgres://a?b=c\n", {}),
    ("value with hash", "[db]\ncolor = a#b\n", {}),
    ("inline comment off", "[db]\ncolor = a # b\n", {}),
    (
        "inline comment on",
        "[db]\ncolor = a # b\n",
        {"inline_comment_prefixes": ("#", ";")},
    ),
    ("continuation", "[db]\nquery = one\n  two\n  three\n", {}),
    ("continuation keeps comment", "[db]\nq = one\n  # not a comment\n  two\n", {}),
    ("blank inside value", "[db]\nq = one\n\n  two\n", {}),
    (
        "blank ends value",
        "[db]\nq = one\n\n  two\n",
        {"empty_lines_in_values": False},
    ),
    ("two sections", "[a]\nx = 1\n[b]\ny = 2\n", {}),
    ("case folded", "[db]\nHost = x\n", {}),
    ("case preserved", "[db]\nHost = x\n", {"optionxform": str}),
    ("bare name off", "[db]\nflag\n", {}),
    ("bare name on", "[db]\nflag\n", {"allow_no_value": True}),
    ("defaults fall back", "[DEFAULT]\nhost = base\n[db]\nport = 1\n", {}),
    ("basic interpolation", "[db]\nhost = h\nurl = pg://%(host)s/db\n", {}),
    ("basic percent escape", "[db]\nrate = 100%%\n", {}),
    (
        "extended interpolation",
        "[db]\nhost = h\nurl = pg://${host}/db\n",
        {"interpolation": configparser.ExtendedInterpolation()},
    ),
    (
        "extended across sections",
        "[a]\nhost = h\n[b]\nurl = ${a:host}/x\n",
        {"interpolation": configparser.ExtendedInterpolation()},
    ),
    (
        "extended dollar escape",
        "[db]\nprice = $5\n",
        {"interpolation": configparser.ExtendedInterpolation()},
    ),
    ("duplicate option refused", "[db]\nx = 1\nx = 2\n", {}),
    ("duplicate option allowed", "[db]\nx = 1\nx = 2\n", {"strict": False}),
    ("option before section refused", "x = 1\n", {}),
    ("unclosed section refused", "[db\nx = 1\n", {}),
    ("missing option refused", "[db]\nx = 1\ny = %(nope)s\n", {}),
]


def build(text, options):
    options = dict(options)
    optionxform = options.pop("optionxform", None)
    cp = configparser.ConfigParser(**options)
    if optionxform is not None:
        cp.optionxform = optionxform
    cp.read_string(text)
    doc = {}
    for section in cp.sections():
        # A bare name comes back as `None`; this library keeps an empty value,
        # because a setting without a value is a setting whose value is empty.
        doc[section] = {
            name: cp.get(section, name) or "" for name in cp.options(section)
        }
    return doc


def _heavy(text, options):
    """The section and name whose lookup `configparser` refuses, if any."""
    options = dict(options)
    optionxform = options.pop("optionxform", None)
    cp = configparser.ConfigParser(**options)
    if optionxform is not None:
        cp.optionxform = optionxform
    try:
        cp.read_string(text)
    except Exception:
        return None
    for section in cp.sections():
        for name in cp.options(section):
            try:
                cp.get(section, name)
            except Exception:
                return (section, name)
    return None


def escape(text):
    return (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
    )


def knobs(options):
    """The MoonBit knobs that say the same thing as these configparser options."""
    fields = []
    if options.get("optionxform", str.lower) is str:
        fields.append("case: Preserve")
    if options.get("allow_no_value"):
        fields.append("allow_no_value: true")
    if options.get("strict") is False:
        fields.append("strict: false")
    if options.get("empty_lines_in_values") is False:
        fields.append("empty_lines_in_values: false")
    if options.get("inline_comment_prefixes"):
        fields.append('inline_comment: "#;"')
    interp = options.get("interpolation")
    if isinstance(interp, configparser.ExtendedInterpolation):
        fields.append("interp: Extended")
    if not fields:
        return "@ini.standard"
    return "{ ..@ini.standard, " + ", ".join(fields) + " }"


def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    target = os.path.join(root, "src", "ini", "vectors_test.mbt")
    lines = [
        "// Copyright 2026 Leo Cheng",
        "// SPDX-License-Identifier: Apache-2.0",
        "",
        "// Generated by scripts/vectors/ini.py from Python's `configparser`.",
        "// Do not edit by hand: the answers below are what that reader produced.",
        "",
    ]
    for label, text, options in CASES:
        try:
            doc = build(text, options)
        except Exception as error:  # configparser raises a family of errors
            heavy = _heavy(text, options)
            lines.append("///|")
            lines.append(f'test "configparser: {label}" {{')
            lines.append(
                f'  let doc = @ini.parse("{escape(text)}", knobs={knobs(options)})'
            )
            if heavy is None:
                # The text itself is refused.
                lines.pop()
                lines.append(
                    f'  let refused = try Ok(@ini.parse("{escape(text)}", knobs={knobs(options)}))'
                    " catch { error => Err(error) }"
                )
                lines.append("  match refused {")
                lines.append("    Err(_) => ()")
                lines.append(
                    f'    Ok(_) => fail("{escape(type(error).__name__)} should be refused")'
                )
                lines.append("  }")
            else:
                # The text reads, and a lookup is what fails.
                section, name = heavy
                lines.append(
                    f'  let refused = try Ok(doc.get("{section}", "{name}"))'
                    " catch { error => Err(error) }"
                )
                lines.append("  match refused {")
                lines.append("    Err(_) => ()")
                lines.append(
                    f'    Ok(_) => fail("{escape(type(error).__name__)} should be refused")'
                )
                lines.append("  }")
            lines.append("}")
            lines.append("")
            continue
        lines.append("///|")
        lines.append(f'test "configparser: {label}" {{')
        lines.append(f'  let doc = @ini.parse("{escape(text)}", knobs={knobs(options)})')
        lines.append(
            "  assert_eq(doc.sections(), ["
            + ", ".join(f'"{name}"' for name in doc)
            + "])"
        )
        for section, entries in doc.items():
            lines.append(
                f'  assert_eq(doc.options("{section}"), ['
                + ", ".join(f'"{name}"' for name in entries)
                + "])"
            )
            for name, value in entries.items():
                lines.append(
                    f'  assert_eq(doc.get("{section}", "{name}"), "{escape(value)}")'
                )
        lines.append("}")
        lines.append("")
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    print(f"wrote {target} ({len(CASES)} cases)")


if __name__ == "__main__":
    main()
