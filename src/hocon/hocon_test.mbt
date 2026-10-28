// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "hocon: JSON with the punctuation relaxed" {
  let doc = @hocon.parse(
    "db {\n  host = localhost\n  port = 5432\n  tls = true\n  ratio: 0.5\n}\n",
  )
  assert_eq(doc.need_text("db.host"), "localhost")
  assert_eq(doc.need_int("db.port"), 5432L)
  assert_eq(doc.need_bool("db.tls"), true)
  assert_eq(doc.need("db.ratio").real(), 0.5)
}

///|
test "hocon: a dotted key builds the nesting it names" {
  let doc = @hocon.parse("a.b.c = 1\na.b.d = 2\n")
  assert_eq(doc.need_int("a.b.c"), 1L)
  assert_eq(doc.need_int("a.b.d"), 2L)
  assert_eq(doc.need("a.b").table().keys(), ["c", "d"])
}

///|
test "hocon: the same name twice merges what it holds" {
  let doc = @hocon.parse(
    "db { host = h, port = 1 }\ndb { port = 2, tls = true }\n",
  )
  let db = doc.need("db")
  assert_eq(db.need_text("host"), "h")
  assert_eq(db.need_int("port"), 2L)
  assert_eq(db.need_bool("tls"), true)
}

///|
test "hocon: arrays written twice join end to end" {
  let doc = @hocon.parse("hosts = [a]\nhosts = [b, c]\n")
  let hosts = doc.need("hosts").list()
  assert_eq(hosts.length(), 3)
  assert_eq(hosts[2].text(), "c")
}

///|
test "hocon: += appends to the array that was there" {
  let doc = @hocon.parse("hosts = [a]\nhosts += b\nhosts += c\n")
  let names = []
  for item in doc.need("hosts").list() {
    names.push(item.text())
  }
  assert_eq(names, ["a", "b", "c"])
}

///|
test "hocon: a reference is the value at the path it names" {
  let doc = @hocon.parse(
    "base { host = h, port = 1 }\nurl = ${base.host}:${base.port}\n",
  )
  assert_eq(doc.need_text("url"), "h:1")
}

///|
test "hocon: an optional reference that finds nothing leaves the name out" {
  let doc = @hocon.parse("a = 1\nb = ${?nope}\nc = ${?a}\n")
  assert_eq(doc.find("b"), None)
  assert_eq(doc.need_int("c"), 1L)
}

///|
test "hocon: a reference to nothing is refused, with the path it wanted" {
  match (Ok(@hocon.parse("a = ${nope}\n")) catch { error => Err(error) }) {
    Err(@hocon.Unresolved(path~, ..)) => assert_eq(path, "nope")
    _ => fail("an unresolved reference should be refused")
  }
}

///|
test "hocon: a reference that reaches itself is a cycle" {
  match
    (Ok(@hocon.parse("a = ${b}\nb = ${a}\n")) catch { error => Err(error) }) {
    Err(@hocon.Cycle(..)) => ()
    _ => fail("a cycle should be refused")
  }
}

///|
test "hocon: include asks the caller for the text" {
  let knobs = @hocon.Knobs::with_read(fn(name) {
    if name == "db.conf" {
      Some("host = h\nport = 1\n")
    } else {
      None
    }
  })
  let doc = @hocon.parse("include \"db.conf\"\nname = app\n", knobs~)
  assert_eq(doc.need_text("host"), "h")
  assert_eq(doc.need_text("name"), "app")
  let required = @hocon.Knobs::with_read(fn(_) { None })
  match
    (Ok(@hocon.parse("include required(file(\"gone.conf\"))\n", knobs=required)) catch {
      error => Err(error)
    }) {
    Err(@hocon.MissingInclude(name~, ..)) => assert_eq(name, "gone.conf")
    _ => fail("a required include that is missing should be refused")
  }
}

///|
test "hocon: comments run to the end of the line, both kinds" {
  let doc = @hocon.parse("# one\n// two\na = 1 # three\nb = 2 // four\n")
  assert_eq(doc.need_int("a"), 1L)
  assert_eq(doc.need_int("b"), 2L)
}

///|
test "hocon: a triple-quoted string keeps its text and its newlines" {
  let doc = @hocon.parse("a = \"\"\"one\n  two\"\"\"\n")
  assert_eq(doc.need_text("a"), "one\n  two")
}

///|
test "hocon: values written next to each other are joined" {
  let doc = @hocon.parse("base = x\na = ${base} and y\nb = one two\n")
  assert_eq(doc.need_text("a"), "x and y")
  assert_eq(doc.need_text("b"), "one two")
}

///|
test "hocon: a fallback answers what the document does not define" {
  let knobs = @hocon.Knobs::with_fallback(fn(name) {
    if name == "HOME" {
      Some("/home/a")
    } else {
      None
    }
  })
  let doc = @hocon.parse("path = ${HOME}/bin\n", knobs~)
  assert_eq(doc.need_text("path"), "/home/a/bin")
}

///|
test "hocon: a key with a quoted segment keeps its dot" {
  let doc = @hocon.parse("\"a.b\" = 1\n")
  assert_eq(doc.need_int("a\\.b"), 1L)
  assert_eq(doc.find("a"), None)
}

///|
test "hocon: an object that never closes is refused where it opened" {
  match (Ok(@hocon.parse("a {\n b = 1\n")) catch { error => Err(error) }) {
    Err(@hocon.Unclosed(at~, ..)) => assert_eq(at.line, 1)
    _ => fail("an unclosed object should be refused")
  }
}

///|
test "hocon: a second definition may build on the first" {
  let doc = @hocon.parse("a = 1\na = ${a} 2\nb = [1]\nb = ${b} [2]\n")
  assert_eq(doc.need_text("a"), "1 2")
  assert_eq(doc.need("b").list().length(), 2)
}

///|
test "hocon: an override that names itself merges what it overrides" {
  let doc = @hocon.parse("db { host = h, port = 1 }\ndb = ${db} { port = 2 }\n")
  let db = doc.need("db")
  assert_eq(db.need_text("host"), "h")
  assert_eq(db.need_int("port"), 2L)
}

///|
test "hocon: a reference *after* the merge still follows the document" {
  let doc = @hocon.parse("a = 1\na = ${a} 2\nb = ${a}\n")
  assert_eq(doc.need_text("b"), "1 2")
}

///|
test "hocon: an include tells the caller which wrapper it used" {
  let seen = []
  let knobs = @hocon.Knobs::with_includes(fn(kind, name) {
    seen.push(kind + ":" + name)
    if name == "base.conf" {
      Some("a = 1\n")
    } else {
      None
    }
  })
  let doc = @hocon.parse(
    "include \"base.conf\"\ninclude url(\"http://host/y.conf\")\ninclude classpath(\"z.conf\")\n",
    knobs~,
  )
  assert_eq(doc.need_int("a"), 1L)
  assert_eq(seen, [
    "file:base.conf", "url:http://host/y.conf", "classpath:z.conf",
  ])
}

///|
test "hocon: windows line endings read the same as unix ones" {
  let doc = @hocon.parse("a = 1\r\nb {\r\n  c = 2\r\n}\r\n")
  assert_eq(doc.need_int("a"), 1L)
  assert_eq(doc.need_int("b.c"), 2L)
}

///|
test "hocon: the environment answers a name the document does not define" {
  @env.set_env_var("MOONCONF_ENV_PROBE", "from-env")
  let doc = @hocon.parse("a = ${MOONCONF_ENV_PROBE}\n")
  assert_eq(doc.need_text("a"), "from-env")
  @env.unset_env_var("MOONCONF_ENV_PROBE")
}

///|
test "hocon: a hermetic reading refuses a name only the environment knows" {
  @env.set_env_var("MOONCONF_ENV_PROBE", "from-env")
  let outcome = Ok(
    @hocon.parse("a = ${MOONCONF_ENV_PROBE}\n", knobs=@hocon.plain),
  ) catch {
    error => Err(error)
  }
  @env.unset_env_var("MOONCONF_ENV_PROBE")
  match outcome {
    Err(@hocon.Unresolved(path~, ..)) => assert_eq(path, "MOONCONF_ENV_PROBE")
    _ => fail("a hermetic reading should not see the environment")
  }
}
