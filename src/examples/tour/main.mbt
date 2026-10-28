// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The four layers and the binding, in one run.
///
///     moon run src/examples/tour
#coverage.skip
fn main raise {
  // What the program carries.
  let defaults = @moonconf.Node::map(
    [
      (
        "db",
        @moonconf.Node::map(
          [
            ("host", @moonconf.Node::str("localhost", "defaults")),
            ("port", @moonconf.Node::num(5432, "defaults")),
          ],
          "defaults",
        ),
      ),
    ],
    "defaults",
  )

  // What the deployment shipped, as an INI file.
  let file = @ini.parse("[db]\nhost = db.internal\npool = 8\n").tree(
    source="app.ini",
  )

  // What the environment says. A process environment arrives as text, which is
  // why the binding below reads text as the type it spells.
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
    @moonconf.Source::new(@moonconf.Default, "defaults", defaults),
    @moonconf.Source::new(@moonconf.File, "app.ini", file),
  ])
  println("host  -> \{merged.need_text("db.host")}")
  println("port  -> \{merged.need_text("db.port")}")
  println("pool  -> \{merged.need_text("db.pool")}")

  // The model says what a valid configuration is; binding says whether this one
  // is, and fills in what was not written.
  let db = @moonmodel.Model::new("Db", [
    @moonmodel.Field::new("host", @moonmodel.Type::Text, required=true),
    @moonmodel.Field::new("port", @moonmodel.Type::Int, required=true),
    @moonmodel.Field::new(
      "pool",
      @moonmodel.Type::Int,
      default=Json::number(4.0),
    ),
  ])
  println("bound -> \{@moonconf.bind(merged.need("db"), db).stringify()}")

  // A `.env` file is the same idea with fewer brackets, and its references are
  // expanded in file order.
  let env = @dotenv.load("HOST=db.internal\nDSN=postgres://${HOST}/app\n")
  println("dsn   -> \{env.get("DSN").unwrap()}")

  // Text expansion stands on its own, for a value written as a shell would.
  let vars = @expand.Vars::of_map(Map([("PORT", "8080")]))
  let template = "http://localhost:${PORT:-80}/"
  println("url   -> \{@expand.expand(template, vars)}")
}
