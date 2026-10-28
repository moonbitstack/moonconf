// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "ini: a document written back reads the same" {
  let text = "[db]\nhost = localhost\nport = 5432\n\n[auth]\ntoken = abc\n"
  let doc = @ini.parse(text)
  let again = @ini.parse(@ini.dumps(doc))
  assert_eq(again.sections(), ["db", "auth"])
  assert_eq(again.get("auth", "token"), "abc")
  assert_eq(again.get("db", "port"), "5432")
}

///|
test "ini: the raw value keeps the reference the value was written with" {
  let doc = @ini.parse("[db]\nhost = h\nurl = pg://%(host)s/db\n")
  assert_eq(doc.get("db", "url"), "pg://h/db")
  assert_eq(doc.raw("db", "url"), Some("pg://%(host)s/db"))
}

///|
test "ini: a section written twice is refused, or merged when asked" {
  match
    (Ok(@ini.parse("[a]\nx = 1\n[a]\ny = 2\n")) catch { error => Err(error) }) {
    Err(@ini.DuplicateSection(name~, ..)) => assert_eq(name, "a")
    _ => fail("a repeated section should be refused")
  }
  let merged = @ini.parse("[a]\nx = 1\n[a]\ny = 2\n", knobs={
    ..@ini.standard,
    strict: false,
  })
  assert_eq(merged.options("a"), ["x", "y"])
}

///|
test "ini: an option name may be folded either way" {
  let upper = @ini.parse("[db]\nHost = x\n", knobs={
    ..@ini.standard,
    case: Upper,
  })
  assert_eq(upper.options("db"), ["HOST"])
  assert_eq(upper.get("db", "host"), "x")
  let kept = @ini.parse("[db]\nHost = x\n", knobs={
    ..@ini.standard,
    case: Preserve,
  })
  assert_eq(kept.options("db"), ["Host"])
  assert_eq(kept.get("db", "Host"), "x")
}

///|
test "ini: an option before any section is refused rather than filed nowhere" {
  match (Ok(@ini.parse("x = 1\n")) catch { error => Err(error) }) {
    Err(@ini.MissingSection(at~)) => assert_eq(at.line, 1)
    _ => fail("an option before a section should be refused")
  }
}

///|
test "ini: a lookup names the section or the option it could not find" {
  let doc = @ini.parse("[db]\nx = 1\n")
  match (Ok(doc.get("nope", "x")) catch { error => Err(error) }) {
    Err(@ini.NoSection(section~)) => assert_eq(section, "nope")
    _ => fail("a missing section should be named")
  }
  match (Ok(doc.get("db", "y")) catch { error => Err(error) }) {
    Err(@ini.NoOption(option~, ..)) => assert_eq(option, "y")
    _ => fail("a missing option should be named")
  }
  assert_eq(doc.get_or("db", "y", "fallback"), "fallback")
  assert_eq(doc.has_option("db", "x"), true)
  assert_eq(doc.has_option("db", "y"), false)
}

///|
test "ini: extended interpolation reaches another section, and reports a cycle" {
  let doc = @ini.parse(
    "[a]\nhost = h\n[b]\nurl = ${a:host}/x\n",
    knobs=@ini.extended,
  )
  assert_eq(doc.get("b", "url"), "h/x")
  let cyclic = @ini.parse("[a]\nx = ${y}\ny = ${x}\n", knobs=@ini.extended)
  match (Ok(cyclic.get("a", "x")) catch { error => Err(error) }) {
    Err(@ini.TooDeep(..)) => ()
    _ => fail("a cycle should stop at the depth limit")
  }
}

///|
test "ini: a literal document takes percent and dollar signs as characters" {
  let doc = @ini.parse("[db]\nrate = 100%\nprice = $5\n", knobs=@ini.literal)
  assert_eq(doc.get("db", "rate"), "100%")
  assert_eq(doc.get("db", "price"), "$5")
}

///|
test "ini: an option may stand alone when the dialect allows it" {
  let doc = @ini.parse("[flags]\nverbose\nquiet\n", knobs=@ini.literal)
  assert_eq(doc.options("flags"), ["verbose", "quiet"])
  assert_eq(doc.get("flags", "verbose"), "")
}

///|
test "ini: the defaults are found through every section" {
  let doc = @ini.parse("[DEFAULT]\nhost = base\nport = 1\n[db]\nport = 2\n")
  assert_eq(doc.sections(), ["db"])
  assert_eq(doc.get("db", "host"), "base")
  assert_eq(doc.get("db", "port"), "2")
  assert_eq(doc.options("db"), ["port", "host"])
}

///|
test "ini: the dialect switches say what a file means" {
  // A file that separates only with `=`, comments with `%`, and calls its
  // defaults `COMMON`.
  let knobs : @ini.Knobs = {
    ..@ini.standard,
    delimiters: "=",
    comment: "%",
    default_section: "COMMON",
  }
  let doc = @ini.parse(
    "% a note\n[COMMON]\nhost = base\n[db]\nport = 1\n",
    knobs~,
  )
  assert_eq(doc.get("db", "host"), "base")
  assert_eq(doc.get("db", "port"), "1")
  // `:` no longer separates, so a line written with one is not an option.
  match (Ok(@ini.parse("[a]\nx: 1\n", knobs~)) catch { error => Err(error) }) {
    Err(@ini.BadLine(..)) => ()
    _ => fail("a colon should not separate under these knobs")
  }
}

///|
test "ini: the tree folds the defaults into every section" {
  let doc = @ini.parse(
    "[DEFAULT]\nhost = base\n[db]\nport = 1\n[auth]\nuser = u\n",
  )
  let tree = doc.tree(source="app.ini")
  assert_eq(tree.need_text("db.host"), "base")
  assert_eq(tree.need_text("auth.host"), "base")
  assert_eq(tree.need_text("db.port"), "1")
  assert_eq(tree.find("DEFAULT"), None)
}
