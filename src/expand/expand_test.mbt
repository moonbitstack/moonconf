// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "expand: ${A:=b} writes back, and a later reference sees it" {
  let entries = Map([("B", "fallback")])
  let vars = @expand.Vars::of_map(entries)
  assert_eq(@expand.expand("${A:=${B}}-${A}", vars), "fallback-fallback")
  assert_eq(entries.get("A"), Some("fallback"))
}

///|
test "expand: an assignment with nowhere to write is refused, not dropped" {
  let vars = @expand.Vars::of(fn(name) {
    if name == "A" {
      Some("set")
    } else {
      None
    }
  })
  match (Ok(@expand.expand("${Z:=x}", vars)) catch { error => Err(error) }) {
    Err(@expand.ReadOnly(name~, ..)) => assert_eq(name, "Z")
    _ => fail("a read-only assignment should be refused")
  }
}

///|
test "expand: strict, lenient and deferred differ only on a missing variable" {
  let vars = @expand.Vars::none()
  match (Ok(@expand.expand("${A}", vars)) catch { error => Err(error) }) {
    Err(@expand.Undefined(name~, ..)) => assert_eq(name, "A")
    _ => fail("strict should refuse a missing variable")
  }
  assert_eq(@expand.expand("${A}", vars, knobs=@expand.lenient), "")
  assert_eq(@expand.expand("${A}", vars, knobs=@expand.deferred), "${A}")
  assert_eq(@expand.expand("$A", vars, knobs=@expand.deferred), "$A")
}

///|
test "expand: the question form carries its message" {
  let vars = @expand.Vars::none()
  match
    (Ok(@expand.expand("${PORT:?set the port first}", vars)) catch {
      error => Err(error)
    }) {
    Err(@expand.Required(name~, why~, ..)) => {
      assert_eq(name, "PORT")
      assert_eq(why, "set the port first")
    }
    _ => fail("a required variable should be reported")
  }
}

///|
test "expand: a colon form reads an empty value as missing" {
  let vars = @expand.Vars::of_map(Map([("A", "")]))
  assert_eq(@expand.expand("${A:-fallback}|${A-fallback}", vars), "fallback|")
  assert_eq(@expand.expand("${A:+yes}|${A+yes}", vars), "|yes")
}

///|
test "expand: a broken form says what is broken and where" {
  let vars = @expand.Vars::of_map(Map([("A", "v")]))
  match (Ok(@expand.expand("a\n${A", vars)) catch { error => Err(error) }) {
    Err(@expand.Unclosed(at~)) => {
      assert_eq(at.line, 2)
      assert_eq(at.column, 1)
    }
    _ => fail("an unclosed form should be reported")
  }
  match (Ok(@expand.expand("${}", vars)) catch { error => Err(error) }) {
    Err(@expand.BadName(got~, ..)) => assert_eq(got, "")
    _ => fail("an empty name should be refused")
  }
  match (Ok(@expand.expand("${A:1:2}", vars)) catch { error => Err(error) }) {
    Err(@expand.BadOperator(got~, ..)) => assert_eq(got, "1:2")
    _ => fail("an unknown operator should be refused")
  }
}

///|
test "expand: nesting stops before the stack does" {
  let vars = @expand.Vars::of_map(Map([("A", "v")]))
  let text = "${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${B:-${A}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}"
  match (Ok(@expand.expand(text, vars)) catch { error => Err(error) }) {
    Err(@expand.TooDeep(..)) => ()
    _ => fail("deep nesting should be refused")
  }
}

///|
test "expand: the length form counts characters" {
  let vars = @expand.Vars::of_map(Map([("A", "hello"), ("B", "")]))
  assert_eq(@expand.expand("${#A}/${#B}", vars), "5/0")
}
