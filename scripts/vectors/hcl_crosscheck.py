#!/usr/bin/env python3
"""Check the HCL vectors against a second reader, `hcl-rs`.

`src/hcl/vectors_test.mbt` holds the answers of the format's reference
implementation. This script puts the same documents to the reader in
`scripts/vectors/hcl_reader`, an independent implementation in Rust, and reports
where the two disagree.

A document that names a variable or calls a function is not comparable here: the
Rust reader is given no names and no functions, so it refuses those documents and
the script counts them as such. Everything else — values, arithmetic, templates,
`for` expressions, splats, blocks — is evaluated by both.

A disagreement is not a failure of this repository: where the two readers differ,
the vectors keep the reference's answer, and the report says what each does.

Run from the repository root:
    cargo build --manifest-path scripts/vectors/hcl_reader/Cargo.toml
    python scripts/vectors/hcl_crosscheck.py
"""

import json
import os
import re
import subprocess
import sys

import crosscheck

VECTORS = "src/hcl/vectors_test.mbt"
READER = os.environ.get(
    "HCL_READER", "scripts/vectors/hcl_reader/target/debug/hcl_reader"
)


def read(text):
    """The tree the Rust reader reads, or why it would not."""
    outcome = subprocess.run(
        [READER], input=text.encode("utf-8"), capture_output=True, check=False
    )
    if outcome.returncode != 0:
        return None, outcome.stderr.decode("utf-8", "replace").strip().split("\n")[0]
    answer = json.loads(outcome.stdout.decode("utf-8"))
    return answer, None


def main():
    text = open(VECTORS, encoding="utf-8").read()
    compared = 0
    agreed = 0
    skipped = []
    differed = []
    for block in crosscheck.BLOCK.finditer(text):
        name = block.group("name")
        body = block.group("body")
        want = crosscheck.expected(body, "tree")
        want_labels = crosscheck.labels(body)
        found = re.search(r"@hcl\.parse\(" + crosscheck.STRING, body)
        if found is None:
            skipped.append((name, "the input is not a literal document"))
            continue
        source = crosscheck.unquote(found.group(1))
        answer, why = read(source)
        if answer is None:
            # A document both readers refuse agrees; one only this reader refuses
            # is outside what it was given -- a name, a function, a context.
            if want.get("refused"):
                compared += 1
                agreed += 1
            else:
                skipped.append((name, "the Rust reader refuses it: " + why))
            continue
        compared += 1
        if want.get("refused"):
            differed.append((name, ["the reference refuses this document"]))
            continue
        got = crosscheck.flatten(answer["tree"])
        wrong = crosscheck.compare(want, got, want_labels, answer["labels"])
        if wrong:
            differed.append((name, wrong))
        else:
            agreed += 1

    crosscheck.report(compared, agreed, differed, skipped)
    return 0


if __name__ == "__main__":
    sys.exit(main())
