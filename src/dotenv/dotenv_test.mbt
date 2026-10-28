// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn entry(key : String, value : String) -> @dotenv.Entry {
  { key, value, quoted: false, at: { at: 0, line: 1, column: 1, }, }
}

///|
test "dotenv: dumps quotes what a reader would otherwise split" {
  let entries = [
    entry("PLAIN", "a/b-c"),
    entry("SPACED", "a b"),
    entry("NEWLINE", "a\nb"),
    entry("DOLLAR", "${X}"),
  ]
  assert_eq(
    @dotenv.dumps(entries),
    "PLAIN=a/b-c\nSPACED=\"a b\"\nNEWLINE=\"a\\nb\"\nDOLLAR=\"\\${X}\"\n",
  )
}

///|
test "dotenv: a written file reads back the same" {
  let entries = [entry("A", "a b"), entry("B", "${A}"), entry("C", "*")]
  let again = @dotenv.parse(@dotenv.dumps(entries)[:])
  assert_eq(again.map(fn(entry) { entry.key }), ["A", "B", "C"])
  assert_eq(again[0].value, "a b")
  // The escape survives `parse`, which does not expand; `load` is what reads it
  // as a literal dollar.
  assert_eq(again[1].value, "\\${A}")
  assert_eq(@dotenv.load(@dotenv.dumps(entries)[:]).get("B"), Some("${A}"))
  assert_eq(again[2].value, "*")
}

///|
test "dotenv: a quote that never closes is refused where it opened" {
  match (Ok(@dotenv.parse("A=1\nB=\"x\n")) catch { error => Err(error) }) {
    Err(@dotenv.Unclosed(at~)) => {
      assert_eq(at.line, 2)
      assert_eq(at.column, 3)
    }
    _ => fail("an unclosed quote should be refused")
  }
}

///|
test "dotenv: junk after a value is refused" {
  match (Ok(@dotenv.parse("A=\"x\" y\n")) catch { error => Err(error) }) {
    Err(@dotenv.Trailing(got~, ..)) => assert_eq(got, "y")
    _ => fail("trailing text should be refused")
  }
}

///|
test "dotenv: a name a shell could not set is refused" {
  match (Ok(@dotenv.parse("1A=x\n")) catch { error => Err(error) }) {
    Err(@dotenv.BadName(got~, ..)) => assert_eq(got, "1A")
    _ => fail("a name starting with a digit should be refused")
  }
}

///|
test "dotenv: verbatim leaves references as written" {
  let text = "A=x\nB=${A}\n"
  let expanded = @dotenv.load(text)
  let literal = @dotenv.load(text, knobs=@dotenv.verbatim)
  assert_eq(expanded.get("B"), Some("x"))
  assert_eq(literal.get("B"), Some("${A}"))
}

///|
test "dotenv: an entry records where it was written" {
  let entries = @dotenv.parse("# one\nA=1\n\nB=2\n")
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].at.line, 2)
  assert_eq(entries[1].at.line, 4)
  assert_eq(entries[1].at.column, 1)
}

///|
test "dotenv: the tree is the variables the file sets" {
  let tree = @dotenv.tree("A=1\nB=${A}2\n", source=".env")
  assert_eq(tree.need_text("A"), "1")
  assert_eq(tree.need_text("B"), "12")
}
