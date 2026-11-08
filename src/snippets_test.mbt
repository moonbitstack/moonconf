// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The examples the README and the skill show are compiled by
/// `scripts/check_snippets.py`, which checks that they compile and nothing more.
/// The values they print are pinned here, so a reader who copies a block gets
/// what the page promised.
test "snippets: the layered reading answers what the README prints" {
  let defaults = @hocon.parse(
    "db {\n  host = localhost\n  port = 5432\n}\n",
    source="defaults.conf",
  )
  let file = @ini.parse("[db]\nhost = db.internal\n").tree(source="app.ini")
  let environment = @moonconf.Node::map(
    [
      (
        "db",
        @moonconf.Node::map(
          [("port", @moonconf.Node::str("6432", "env"))],
          "env",
        ),
      ),
    ],
    "env",
  )
  let merged = @moonconf.merge([
    @moonconf.Source::new(@moonconf.Env, "env", environment),
    @moonconf.Source::new(@moonconf.File, "app.ini", file),
    @moonconf.Source::new(@moonconf.Default, "defaults.conf", defaults),
  ])
  assert_eq(merged.need_text("db.host"), "db.internal")
  assert_eq(merged.need_text("db.port"), "6432")
  assert_eq(merged.need("db.port").source, "env")
  assert_eq(merged.need("db.port").at.line, 1)
}

///|
test "snippets: binding the section is the record the skill prints" {
  let merged = @moonconf.of_json(
    "{\"db\":{\"host\":\"db.internal\",\"port\":\"6432\"}}",
    source="env",
  )
  let model = @moonmodel.Model::new("Db", [
    @moonmodel.Field::new("host", @moonmodel.Type::Text, required=true),
    @moonmodel.Field::new("port", @moonmodel.Type::Int, required=true),
    @moonmodel.Field::new(
      "pool",
      @moonmodel.Type::Int,
      default=Json::number(4.0),
    ),
  ])
  assert_eq(
    @moonconf.bind(merged.need("db"), model).stringify(),
    "{\"host\":\"db.internal\",\"port\":6432,\"pool\":4}",
  )
}

///|
/// The trap the skill names: an environment layer is text, and `need_int` does not
/// read text as a number. Binding is what reads it.
test "snippets: a value the environment wrote is text to need_int" {
  let merged = @moonconf.of_json("{\"db\":{\"port\":\"6432\"}}", source="env")
  assert_eq(merged.need_text("db.port"), "6432")
  match (Ok(merged.need_int("db.port")) catch { error => Err(error) }) {
    Err(@moonconf.Type(want~, got~, path~, ..)) => {
      assert_eq(want, "integer")
      assert_eq(got, "text")
      assert_eq(path, "db.port")
    }
    _ => fail("text read as an integer should be refused")
  }
}

///|
test "snippets: whole and decimal read one value of text" {
  assert_eq(@moonconf.whole("6432"), Some(6432L))
  assert_eq(@moonconf.whole("-1"), Some(-1L))
  assert_eq(@moonconf.whole("http"), None)
  assert_eq(@moonconf.decimal("0.5"), Some(0.5))
  assert_eq(@moonconf.decimal("half"), None)
}

///|
test "snippets: the expansion forms the skill lists answer what it shows" {
  let vars = @expand.Vars::of_map(Map([("HOME", "/srv"), ("PORT", "8080")]))
  assert_eq(@expand.expand("${HOME}/etc/app", vars), "/srv/etc/app")
  assert_eq(@expand.expand("${PORT:-80}", vars), "8080")
  assert_eq(@expand.expand("${MISSING:-80}", vars), "80")
}

///|
test "snippets: a later assignment in a .env file wins" {
  let env = @dotenv.load("HOST=first\nHOST=second\n")
  assert_eq(env.get("HOST"), Some("second"))
}
