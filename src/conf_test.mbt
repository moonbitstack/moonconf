// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn map(
  pairs : Array[(String, @moonconf.Node)],
  source : String,
) -> @moonconf.Node {
  @moonconf.Node::map(pairs, source)
}

///|
fn text(value : String, source : String) -> @moonconf.Node {
  @moonconf.Node::str(value, source)
}

///|
fn whole(value : Int64, source : String) -> @moonconf.Node {
  @moonconf.Node::num(value, source)
}

///|
test "merge: the stronger tier wins and the weaker keeps what it had" {
  let defaults = map(
    [
      (
        "db",
        map(
          [
            ("host", text("localhost", "defaults")),
            ("port", whole(5432, "defaults")),
          ],
          "defaults",
        ),
      ),
      ("debug", @moonconf.Node::flag(false, "defaults")),
    ],
    "defaults",
  )
  let file = map(
    [("db", map([("port", whole(6432, "app.conf"))], "app.conf"))],
    "app.conf",
  )
  let env = map(
    [("db", map([("host", text("db.internal", "env"))], "env"))],
    "env",
  )
  let merged = @moonconf.merge([
    @moonconf.Source::new(@moonconf.File, "app.conf", file),
    @moonconf.Source::new(@moonconf.Default, "defaults", defaults),
    @moonconf.Source::new(@moonconf.Env, "env", env),
  ])
  assert_eq(merged.need_text("db.host"), "db.internal")
  assert_eq(merged.need_int("db.port"), 6432L)
  assert_eq(merged.need_bool("debug"), false)
}

///|
test "merge: reversing the order lets the earlier layer win" {
  let base = map([("name", text("base", "base"))], "base")
  let patch = map([("name", text("patch", "patch"))], "patch")
  let reversed : @moonconf.Knobs = {
    order: [
      @moonconf.Override,
      @moonconf.Env,
      @moonconf.File,
      @moonconf.Default,
    ],
    clash: @moonconf.Last,
  }
  let merged = @moonconf.merge(
    [
      @moonconf.Source::new(@moonconf.File, "base", base),
      @moonconf.Source::new(@moonconf.Default, "patch", patch),
    ],
    knobs=reversed,
  )
  assert_eq(merged.need_text("name"), "patch")
}

///|
test "merge: a clash can keep the first, keep the last, or refuse both" {
  let a = map([("k", text("a", "a.conf"))], "a.conf")
  let b = map([("k", text("b", "b.conf"))], "b.conf")
  let sources = [
    @moonconf.Source::new(@moonconf.File, "a", a),
    @moonconf.Source::new(@moonconf.File, "b", b),
  ]
  let both : @moonconf.Knobs = {
    order: [@moonconf.File],
    clash: @moonconf.Last,
  }
  let early : @moonconf.Knobs = {
    order: [@moonconf.File],
    clash: @moonconf.First,
  }
  let strict : @moonconf.Knobs = {
    order: [@moonconf.File],
    clash: @moonconf.Refuse,
  }
  let last = @moonconf.merge(sources, knobs=both)
  let first = @moonconf.merge(sources, knobs=early)
  assert_eq(last.need_text("k"), "b")
  assert_eq(first.need_text("k"), "a")
  let refused = Ok(@moonconf.merge(sources, knobs=strict)) catch {
    error => Err(error)
  }
  match refused {
    Err(@moonconf.Clash(path~, first~, second~)) => {
      assert_eq(path, "k")
      assert_eq(first, "a.conf@1:1")
      assert_eq(second, "b.conf@1:1")
    }
    _ => fail("a clash under Refuse should be reported")
  }
}

///|
test "merge: lists replace rather than concatenate" {
  let base = map(
    [("hosts", @moonconf.Node::seq([text("a", "base")], "base"))],
    "base",
  )
  let over = map(
    [("hosts", @moonconf.Node::seq([text("b", "over")], "over"))],
    "over",
  )
  let merged = @moonconf.merge([
    @moonconf.Source::new(@moonconf.File, "base", base),
    @moonconf.Source::new(@moonconf.File, "over", over),
  ])
  let hosts = merged.need("hosts").list()
  assert_eq(hosts.length(), 1)
  assert_eq(hosts[0].text(), "b")
}

///|
test "merge: identical values from two layers are not a clash" {
  let a = map([("k", text("same", "a"))], "a")
  let b = map([("k", text("same", "b"))], "b")
  let strict : @moonconf.Knobs = {
    order: [@moonconf.File],
    clash: @moonconf.Refuse,
  }
  let merged = @moonconf.merge(
    [
      @moonconf.Source::new(@moonconf.File, "a", a),
      @moonconf.Source::new(@moonconf.File, "b", b),
    ],
    knobs=strict,
  )
  assert_eq(merged.need_text("k"), "same")
}

///|
test "find: dotted paths reach through mappings and index lists" {
  let tree = map(
    [
      (
        "servers",
        @moonconf.Node::seq(
          [
            map([("host", text("one", "cfg"))], "cfg"),
            map([("host", text("two", "cfg"))], "cfg"),
          ],
          "cfg",
        ),
      ),
      ("a.b", text("dotted", "cfg")),
    ],
    "cfg",
  )
  assert_eq(tree.need_text("servers.1.host"), "two")
  assert_eq(tree.need_text("a\\.b"), "dotted")
  assert_eq(tree.find("servers.9.host"), None)
  assert_eq(tree.has("servers.0"), true)
}

///|
test "find: a path with a hole in it is nothing" {
  let tree = map([("a", text("x", "cfg"))], "cfg")
  assert_eq(tree.find("a..b"), None)
  match
    (Ok(@moonconf.segments("a..b") |> ignore) catch { error => Err(error) }) {
    Err(@moonconf.Path(got=_, at~)) => assert_eq(at, 2)
    _ => fail("an empty segment should be refused")
  }
}

///|
test "bind: fields are checked, text is read as the type it spells" {
  let model = @moonmodel.Model::new("Server", [
    @moonmodel.Field::new("host", @moonmodel.Type::Text, required=true),
    @moonmodel.Field::new("port", @moonmodel.Type::Int),
    @moonmodel.Field::new(
      "tls",
      @moonmodel.Type::Bool,
      default=Json::boolean(true),
    ),
    @moonmodel.Field::new("tags", @moonmodel.Type::List(@moonmodel.Type::Text)),
  ])
  let tree = map(
    [
      ("host", text("example.org", "app.conf")),
      ("port", text("8080", "app.conf")),
      ("tags", @moonconf.Node::seq([text("edge", "app.conf")], "app.conf")),
    ],
    "app.conf",
  )
  let bound = @moonconf.bind(tree, model)
  assert_eq(
    bound,
    @json.parse(
      "{\"host\":\"example.org\",\"port\":8080,\"tags\":[\"edge\"],\"tls\":true}",
    ),
  )
}

///|
test "bind: a missing required field names the field" {
  let model = @moonmodel.Model::new("Server", [
    @moonmodel.Field::new("host", @moonmodel.Type::Text, required=true),
  ])
  match
    (Ok(@moonconf.bind(map([], "app.conf"), model)) catch {
      error => Err(error)
    }) {
    Err(@moonconf.Missing(path~, want~)) => {
      assert_eq(path, "host")
      assert_eq(want, "text")
    }
    _ => fail("a missing required field should be reported")
  }
}

///|
test "bind: a value of the wrong shape names the field and both shapes" {
  let model = @moonmodel.Model::new("Server", [
    @moonmodel.Field::new("port", @moonmodel.Type::Int, required=true),
  ])
  let tree = map([("port", text("eighty", "app.conf"))], "app.conf")
  match (Ok(@moonconf.bind(tree, model)) catch { error => Err(error) }) {
    Err(@moonconf.Type(want~, got~, path~, source~, at=_)) => {
      assert_eq(want, "integer")
      assert_eq(got, "text")
      assert_eq(path, "port")
      assert_eq(source, "app.conf")
    }
    _ => fail("a wrong shape should be reported")
  }
}

///|
test "bind: a closed binding refuses a member no field describes" {
  let model = @moonmodel.Model::new("Server", [
    @moonmodel.Field::new("port", @moonmodel.Type::Int, required=false),
  ])
  let tree = map([("prot", whole(8080, "app.conf"))], "app.conf")
  match
    (Ok(@moonconf.bind(tree, model, knobs=@moonconf.closed)) catch {
      error => Err(error)
    }) {
    Err(@moonconf.Unknown(path~, got~)) => {
      assert_eq(path, "prot")
      assert_eq(got, "integer")
    }
    _ => fail("an undescribed member should be refused")
  }
  assert_eq(@moonconf.bind(tree, model), @json.parse("{}"))
}

///|
test "bind: a nested model is walked field by field" {
  let db = @moonmodel.Model::new("Db", [
    @moonmodel.Field::new("host", @moonmodel.Type::Text, required=true),
  ])
  let model = @moonmodel.Model::new("App", [
    @moonmodel.Field::new("db", @moonmodel.Type::Ref("Db"), required=true),
  ])
  let tree = map(
    [("db", map([("host", text("db.internal", "env"))], "env"))],
    "env",
  )
  let bound = @moonconf.bind(tree, model, known=[db])
  assert_eq(bound, @json.parse("{\"db\":{\"host\":\"db.internal\"}}"))
}

///|
test "validate: every mistake in the tree is reported, not just the first" {
  let model = @moonmodel.Model::new("Server", [
    @moonmodel.Field::new("host", @moonmodel.Type::Text, required=true),
    @moonmodel.Field::new("port", @moonmodel.Type::Int, required=true),
  ])
  let tree = map([("port", text("eighty", "app.conf"))], "app.conf")
  let issues = @moonconf.validate(tree, model)
  assert_eq(issues.length(), 2)
}

///|
test "of_json: numbers keep their kind and objects come out sorted" {
  let tree = @moonconf.of_json(
    "{\"b\": 1, \"a\": [1, 2.5, true, null]}",
    source="app.json",
  )
  assert_eq(tree.need_int("b"), 1L)
  assert_eq(tree.need("a").list()[1].real(), 2.5)
  assert_eq(tree.need("a").list()[2].bool(), true)
  assert_eq(tree.table().keys(), ["a", "b"])
}

///|
test "of_json: a refusal keeps the reader's position" {
  match
    (Ok(@moonconf.of_json("{\"a\": }", source="broken.json")) catch {
      error => Err(error)
    }) {
    Err(@moonconf.Format(why=_, at=Some(at))) => assert_eq(at.line, 1)
    _ => fail("a broken document should keep its position")
  }
}

///|
test "of_yaml and of_toml read the same tree" {
  let yaml = @moonconf.of_yaml(
    "db:\n  host: localhost\n  port: 5432\n",
    source="app.yaml",
  )
  let toml = @moonconf.of_toml(
    "[db]\nhost = \"localhost\"\nport = 5432\n",
    source="app.toml",
  )
  assert_eq(yaml.need_text("db.host"), "localhost")
  assert_eq(toml.need_int("db.port"), 5432L)
  assert_eq(
    @moonconf.native(yaml.need("db")).stringify(),
    @moonconf.native(toml.need("db")).stringify(),
  )
}
