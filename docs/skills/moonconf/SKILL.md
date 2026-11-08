---
name: moonconf
description: "Configuration for MoonBit: read INI, Java properties, .env, HOCON and HCL into one tree, layer defaults, file, environment and explicit overrides, and bind the result to a typed model. Use when a program loads settings from files or the environment, or when a refusal has to name the field, the source and the line it was written on."
---

# moonconf

Every format a deployment ships — INI, Java properties, `.env`, HOCON, HCL — is
read into the same tree: a value, the name of the source it came from, and the
position in that source. Layers merge by tier, and a model turns a section into
typed values. Nothing here opens a file: you read, this parses, which is why all
of it runs on every target.

## Install

```bash
moon add moonbitstack/moonconf
```

```moonbit
import {
  "moonbitstack/moonconf",
  "moonbitstack/moonconf/dotenv",
  "moonbitstack/moonconf/expand",
  "moonbitstack/moonconf/hcl",
  "moonbitstack/moonconf/hocon",
  "moonbitstack/moonconf/ini",
  "moonbitstack/moonconf/props",
}
```

The root package holds the tree, the merge and the binding. `ini`, `props`,
`dotenv`, `hocon` and `hcl` read their format; `expand` is the shell's parameter
expansion on its own, and is what an INI value and a `.env` line already use.

## Read each source, then settle the layers

A source is a tree, the tier it belongs to, and a name for error messages. Hand
them to `merge` in any order: `Default` loses to `File`, which loses to `Env`,
which loses to `Override`. Mappings merge member by member.

```moonbit
let defaults = @hocon.parse(
  "db {\n  host = localhost\n  port = 5432\n}\n",
  source="defaults.conf",
)
let file = @ini.parse("[db]\nhost = db.internal\n").tree(source="app.ini")
let environment = @moonconf.Node::map([
  ("db", @moonconf.Node::map([
    ("port", @moonconf.Node::str("6432", "env")),
  ], "env")),
], "env")

let merged = @moonconf.merge([
  @moonconf.Source::new(@moonconf.Env, "env", environment),
  @moonconf.Source::new(@moonconf.File, "app.ini", file),
  @moonconf.Source::new(@moonconf.Default, "defaults.conf", defaults),
])
assert_eq(merged.need_text("db.host"), "db.internal")
assert_eq(merged.need_text("db.port"), "6432")
assert_eq(merged.need("db.port").source, "env")
assert_eq(merged.need("db.port").at.line, 1)
```

Each leaf still remembers where it was written, so a program that prints its own
configuration can print where each value came from.

## Bind a section to a model

A model describes one section: which fields it has, which are required, what each
is and what it is when nobody wrote it. `bind` reads the node's own members
through that description and answers JSON in the shape the model describes;
`@json.from_json` turns that into a struct of your own.

```moonbit
let model = @moonmodel.Model::new("Db", [
  @moonmodel.Field::new("host", @moonmodel.Type::Text, required=true),
  @moonmodel.Field::new("port", @moonmodel.Type::Int, required=true),
  @moonmodel.Field::new("pool", @moonmodel.Type::Int, default=Json::number(4.0)),
])
let db = @moonconf.bind(merged.need("db"), model)
assert_eq(db.stringify(), "{\"host\":\"db.internal\",\"port\":6432,\"pool\":4}")
```

Binding is also what reads text as the number it spells, which is what makes an
environment variable — always text — usable as a port. `validate` answers every
mistake at once instead of stopping at the first, for a message shown to whoever
wrote the file.

## Expand what a shell would expand

`${A}`, `${A:-b}`, `${A:?msg}`, `${#A}`, nested, with escapes. A name with no
value is refused by default: `@expand.lenient` reads it as empty and
`@expand.deferred` leaves the reference for a later pass.

```moonbit
let vars = @expand.Vars::of_map(Map([("HOME", "/srv"), ("PORT", "8080")]))
assert_eq(@expand.expand("${HOME}/etc/app", vars), "/srv/etc/app")
assert_eq(@expand.expand("${PORT:-80}", vars), "8080")
assert_eq(@expand.expand("${MISSING:-80}", vars), "80")
```

An INI value (`%(name)s`, `${section:name}`) and a `.env` reference resolve
against entries the file has already defined, so the order in the file is the
order of evaluation.

## Things that catch people out

- `need_int` wants an integer and refuses text; `bind` reads text as the type it
  spells. For one value on its own, `@moonconf.whole("6432")` and
  `@moonconf.decimal("0.5")` answer `Some` only when the text spells a number.
- A path is member names joined by dots, a segment of digits indexes a list, and
  `\.` is a literal dot: `servers.1.host`, `a\.b`. `find` answers nothing when the
  path is absent; `need` refuses.
- A list replaces as a whole, because a list in a configuration is one decision.
  Mappings merge: a later file that sets one key under `db` keeps the rest.
- `clash` decides what a disagreement means — `Last` (the default), `First`, or
  `Refuse`, which names both positions. `wins` is the tier order itself, so a
  patch read *under* a document is a change of knobs rather than of code.
- `props.load` takes bytes as ISO-8859-1, one byte to one character; `parse` takes
  text. In properties a name is a name, not a path: `db.host` is one key.
- A `.env` line that is not an assignment — a stray word, a quote that never
  closes — is kept in `Doc::skipped` rather than failing the file. A later
  assignment wins.
- HOCON consults the process environment for a name the document does not define,
  which is what the format means by a substitution; `@hocon.plain` reads the
  document on its own. `include "x"` asks the `read` you gave the knobs, and
  nothing is fetched by this library.
- HCL evaluates expressions as it reads them, against a `@hcl.Context` of names
  and functions. `@hcl.standard()` has the string and list functions a
  configuration file uses; add your own with `Context::function`.
- Numbers keep their kind: `8080` stays an integer and is not printed back as
  `8080.0`.
