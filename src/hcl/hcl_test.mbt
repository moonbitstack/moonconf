// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "hcl: attributes and blocks" {
  let body = @hcl.parse(
    "# a note\nname = \"web\"\ncount = 3\nenabled = true\n\nserver \"web\" \"main\" {\n  port = 8080\n}\n",
  )
  assert_eq(body.get("name").unwrap().text(), "web")
  assert_eq(body.blocks.length(), 1)
  let block = body.blocks[0]
  assert_eq(block.kind, "server")
  assert_eq(block.labels, ["web", "main"])
  assert_eq(block.body.get("port").unwrap().int(), 8080L)
}

///|
test "hcl: a body becomes the shared tree" {
  let body = @hcl.parse(
    "name = \"web\"\nserver \"a\" { port = 1 }\nserver \"b\" { port = 2 }\n",
  )
  let tree = body.tree("main.hcl")
  assert_eq(tree.need_text("name"), "web")
  assert_eq(tree.need("server").list().length(), 2)
  assert_eq(tree.need("server").list()[1].need_int("port"), 2L)
}

///|
test "hcl: lists, objects and arithmetic" {
  let body = @hcl.parse(
    "ports = [80, 443]\ntags = { env = \"prod\", team = \"core\" }\ntotal = 1 + 2 * 3\n",
  )
  assert_eq(body.get("ports").unwrap().list().length(), 2)
  assert_eq(body.get("tags").unwrap().need_text("env"), "prod")
  assert_eq(body.get("total").unwrap().int(), 7L)
}

///|
test "hcl: names come from the context and are walked" {
  let vars = @moonconf.Node::map(
    [
      ("region", @moonconf.Node::str("eu-west", "")),
      (
        "tags",
        @moonconf.Node::map([("env", @moonconf.Node::str("prod", ""))], ""),
      ),
    ],
    "vars",
  )
  let context = @hcl.Context::new().bind("var", vars)
  let body = @hcl.parse(
    "region = var.region\ntag = var.tags[\"env\"]\n",
    context~,
  )
  assert_eq(body.get("region").unwrap().text(), "eu-west")
  assert_eq(body.get("tag").unwrap().text(), "prod")
}

///|
test "hcl: a name nothing defines is refused" {
  match (Ok(@hcl.parse("a = var.nope\n")) catch { error => Err(error) }) {
    Err(@hcl.UnknownName(name~, ..)) => assert_eq(name, "var")
    _ => fail("an unknown name should be refused")
  }
}

///|
test "hcl: strings interpolate an expression" {
  let vars = @moonconf.Node::map(
    [("name", @moonconf.Node::str("web", ""))],
    "vars",
  )
  let context = @hcl.Context::new().bind("var", vars)
  let body = @hcl.parse("url = \"http://${var.name}:8080\"\n", context~)
  assert_eq(body.get("url").unwrap().text(), "http://web:8080")
}

///|
test "hcl: a function comes from the context, and the standard ones are there" {
  let context = @hcl.standard()
  let body = @hcl.parse(
    "a = upper(\"web\")\nb = join(\",\", [\"x\", \"y\"])\nc = length(\"abc\")\n",
    context~,
  )
  assert_eq(body.get("a").unwrap().text(), "WEB")
  assert_eq(body.get("b").unwrap().text(), "x,y")
  assert_eq(body.get("c").unwrap().int(), 3L)
}

///|
test "hcl: a caller adds a function of its own" {
  let context = @hcl.Context::new().function("twice", fn(args) {
    let text = match args[0].value {
      @moonconf.Value::Text(text) => text
      _ => ""
    }
    @moonconf.Node::str(text + text, "")
  })
  let body = @hcl.parse("a = twice(\"ha\")\n", context~)
  assert_eq(body.get("a").unwrap().text(), "haha")
}

///|
test "hcl: comparison and conditionals" {
  let body = @hcl.parse(
    "big = 3 > 2\nsmall = 3 < 2\npick = 3 > 2 ? \"yes\" : \"no\"\nboth = true && !false\n",
  )
  assert_eq(body.get("big").unwrap().bool(), true)
  assert_eq(body.get("small").unwrap().bool(), false)
  assert_eq(body.get("pick").unwrap().text(), "yes")
  assert_eq(body.get("both").unwrap().bool(), true)
}

///|
test "hcl: JSON syntax reads the same body" {
  let body = @hcl.parse_json(
    "{\"name\": \"web\", \"resource\": {\"aws_instance\": {\"web\": {\"ami\": \"abc\"}}}}",
  )
  assert_eq(body.get("name").unwrap().text(), "web")
  let block = body.blocks[0]
  assert_eq(block.kind, "resource")
  assert_eq(block.labels, ["aws_instance", "web"])
  assert_eq(block.body.get("ami").unwrap().text(), "abc")
}

///|
test "hcl: a body that never closes is refused where it opened" {
  match (Ok(@hcl.parse("a = 1\nb {\n")) catch { error => Err(error) }) {
    Err(@hcl.Unclosed(at~, ..)) => assert_eq(at.line, 3)
    _ => fail("an unclosed body should be refused")
  }
}
