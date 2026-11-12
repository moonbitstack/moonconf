#!/usr/bin/env python3
"""Check the HOCON vectors against a second reader, `pyhocon`.

`src/hocon/vectors_test.mbt` holds the answers of the format's reference
implementation. This script reads the same inputs with `pyhocon` — an
independent reader, written from the specification — and reports where the two
disagree, so that a divergence is known rather than discovered later.

A disagreement is not a failure of this repository: where the two readers differ,
the vectors keep the reference's answer, and the report says what each of them
does instead. Cases with an `include` are not comparable: the vector hands the
included text to the reader, and `pyhocon` would go looking for a file.

Run from the repository root, with `pyhocon` installed:
    python scripts/vectors/hocon_crosscheck.py
"""

import re
import sys

import crosscheck

VECTORS = "src/hocon/vectors_test.mbt"


def main():
    from pyhocon import ConfigFactory

    text = open(VECTORS, encoding="utf-8").read()
    compared = 0
    agreed = 0
    skipped = []
    differed = []
    for block in crosscheck.BLOCK.finditer(text):
        name = block.group("name")
        body = block.group("body")
        want = crosscheck.expected(body, "doc")
        found = re.search(r"@hocon\.parse\(" + crosscheck.STRING, body)
        if found is None:
            skipped.append((name, "the input is built from a callback"))
            continue
        source = crosscheck.unquote(found.group(1))
        if "include" in source:
            skipped.append((name, "the included text is supplied by the vector"))
            continue
        if want.get("refused"):
            compared += 1
            try:
                ConfigFactory.parse_string(source).as_plain_ordered_dict()
            except Exception:
                agreed += 1
            else:
                differed.append((name, ["the reference refuses this document"]))
            continue
        compared += 1
        try:
            got = crosscheck.flatten(
                ConfigFactory.parse_string(source).as_plain_ordered_dict()
            )
        except Exception as error:
            differed.append((name, ["pyhocon refuses: " + str(error).split("\n")[0]]))
            continue
        wrong = crosscheck.compare(want, got, {}, {})
        if wrong:
            differed.append((name, wrong))
        else:
            agreed += 1

    crosscheck.report(compared, agreed, differed, skipped)
    return 0


if __name__ == "__main__":
    sys.exit(main())
