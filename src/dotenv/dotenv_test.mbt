// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn entry(key : String, value : String?) -> @dotenv.Entry {
  { key, value, at: { at: 0, line: 1, column: 1, }, }
}

///|
test "dotenv: dumps quotes what a reader would otherwise split" {
  let entries = [
    entry("PLAIN", Some("a/b-c")),
    entry("SPACED", Some("a b")),
    entry("NEWLINE", Some("a\nb")),
    entry("EMPTY", Some("")),
    entry("DECLARED", None),
  ]
  assert_eq(
    @dotenv.dumps(entries),
    "PLAIN=a/b-c\nSPACED=\"a b\"\nNEWLINE=\"a\\nb\"\nEMPTY=\"\"\nDECLARED\n",
  )
}

///|
test "dotenv: a written file reads back the same" {
  let entries = [
    entry("A", Some("a b")),
    entry("B", Some("${A}")),
    entry("C", Some("*")),
    entry("D", None),
  ]
  let text = @dotenv.dumps(entries)
  let doc = @dotenv.parse(text[:])
  assert_eq(doc.keys(), ["A", "B", "C", "D"])
  assert_eq(doc.get("A"), Some("a b"))
  assert_eq(doc.get("C"), Some("*"))
  assert_eq(doc.get("D"), None)
  // The reference survives being written and read, because `${A}` inside quotes
  // is a reference and `A` is defined above it.
  assert_eq(@dotenv.load(text[:]).get("B"), Some("a b"))
}

///|
test "dotenv: a line that is not an assignment is kept, not fatal" {
  let doc = @dotenv.parse("A=1\nA b\nB=2\n")
  assert_eq(doc.keys(), ["A", "B"])
  assert_eq(doc.skipped.length(), 1)
  assert_eq(doc.skipped[0].text, "A b")
  assert_eq(doc.skipped[0].at.line, 2)
}

///|
test "dotenv: a quote that never closes skips the line it starts on" {
  let doc = @dotenv.parse("A=\"x\nB=2\n")
  assert_eq(doc.keys(), ["B"])
  assert_eq(doc.skipped.length(), 1)
}

///|
test "dotenv: the tree is the variables the file sets" {
  let tree = @dotenv.tree("A=1\nB=${A}2\nC\n", source=".env")
  assert_eq(tree.need_text("A"), "1")
  assert_eq(tree.need_text("B"), "12")
  assert_eq(tree.find("C"), None)
}

///|
test "dotenv: a caller's variables are the base a reference reads" {
  let base = Map([("HOME", "/home/a")])
  let env = @dotenv.load("PATH=${HOME}/bin\n", vars=base)
  assert_eq(env.get("PATH"), Some("/home/a/bin"))
}

///|
test "dotenv: verbatim leaves references as written" {
  let text = "A=x\nB=${A}\n"
  assert_eq(@dotenv.load(text).get("B"), Some("x"))
  assert_eq(@dotenv.load(text, knobs=@dotenv.verbatim).get("B"), Some("${A}"))
}

///|
test "dotenv: windows line endings and a byte-order mark are not part of a name" {
  let doc = @dotenv.parse("\u{FEFF}A=1\r\nB=2\r\n")
  assert_eq(doc.keys(), ["A", "B"])
  assert_eq(doc.get("A"), Some("1"))
}

///|
test "dotenv: the tree keeps the line each value was written on" {
  let tree = @dotenv.tree("A=1\nB=2\n", source=".env")
  assert_eq(tree.need("B").at.line, 2)
  assert_eq(tree.need("B").source, ".env")
}
