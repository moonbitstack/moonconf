// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "props: a written file keeps the comment it was given" {
  let doc = @props.Doc::new([
    @props.Pair::new("a", "1"),
    @props.Pair::new("b", "two words"),
  ])
  assert_eq(
    @props.dumps(doc, comment="written by hand"),
    "#written by hand\na=1\nb=two words\n",
  )
}

///|
test "props: the tree is one mapping of names to values" {
  let doc = @props.parse("db.host=localhost\ndb.port=5432\n")
  let tree = doc.tree(source="app.properties")
  assert_eq(tree.need_text("db\\.host"), "localhost")
  assert_eq(tree.find("db"), None)
}

///|
test "props: bytes are read as ISO-8859-1" {
  let doc = @props.load(b"A=caf\xe9\n")
  assert_eq(doc.get("A"), Some("caf\u{00E9}"))
}

///|
test "props: the tree keeps the line each value was written on" {
  let tree = @props.parse("a=1\nb=2\n").tree(source="app.properties")
  assert_eq(tree.need("b").at.line, 2)
  assert_eq(tree.need("b").source, "app.properties")
}
