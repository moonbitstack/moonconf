// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A HOCON document with a reference, an optional reference and an include.
///
///     moon run src/examples/typesafe
#coverage.skip
fn main raise {
  let knobs = @hocon.Knobs::with_read(name => {
    if name == "base.conf" {
      Some("db {\n  host = localhost\n  port = 5432\n}\n")
    } else {
      None
    }
  })
  let text = "include \"base.conf\"\n" +
    "db.name = app\n" +
    "url = \"postgres://${db.host}:${db.port}/${db.name}\"\n" +
    "cache = ${?missing}\n" +
    "hosts = [a]\n" +
    "hosts = [b]\n" +
    "hosts += c\n"
  let doc = @hocon.parse(text[:], knobs~)
  println("url   -> \{doc.need_text("url")}")
  println("cache -> \{doc.has("cache")}")
  let names = []
  for host in doc.need("hosts").list() {
    names.push(host.text())
  }
  println("hosts -> \{names.join(", ")}")
}
