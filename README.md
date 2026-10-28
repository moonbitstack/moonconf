# moonconf

Configuration for MoonBit: the formats a deployment actually ships — INI, Java
properties, `.env`, HOCON and HCL — read into one tree, layered in the order a
program wants them, checked against a model, and bound to typed values.

This package reads bytes and builds mappings. It does not open files, read the
environment or fetch a URL: a caller reads its sources and hands them in, which
is what makes every part of it testable on every target.

## The tree

Every reader produces the same tree, so a value from an INI file and a value from
the environment can be compared, merged and bound the same way.

```moonbit check
test {
  let node = @moonconf.Node::map([
    ("db", @moonconf.Node::map([("host", @moonconf.Node::str("localhost", "app.ini"))], "app.ini")),
  ], "app.ini")
  assert_eq(node.need_text("db.host"), "localhost")
}
```

- A value is `null`, `boolean`, `integer`, `real`, `text`, a `list`, or a
  `mapping`. An integer stays an integer, so `8080` is not printed back as
  `8080.0`.
- A mapping remembers the order its members were written in, so a file written
  back is the file that was read.
- Every value carries the source it came from and the position in it, which is
  what an error message needs to be useful.

Lookups use a dotted path; a segment of digits indexes a list, and `\.` is a
literal dot.

```moonbit check
test {
  let node = @moonconf.Node::map([
    ("servers", @moonconf.Node::seq([
      @moonconf.Node::str("one", "app.conf"),
      @moonconf.Node::str("two", "app.conf"),
    ], "app.conf")),
  ], "app.conf")
  assert_eq(node.need_text("servers.1"), "two")
}
```

## Layers

A configuration is usually four answers to the same question, and the last one
said is the one meant. `merge` takes them in any order and settles it by tier.

```moonbit check
test {
  let defaults = @moonconf.Node::map([
    ("port", @moonconf.Node::num(5432, "defaults")),
  ], "defaults")
  let file = @moonconf.Node::map([
    ("port", @moonconf.Node::num(6432, "app.ini")),
  ], "app.ini")
  let merged = @moonconf.merge([
    @moonconf.Source::new(@moonconf.File, "app.ini", file),
    @moonconf.Source::new(@moonconf.Default, "defaults", defaults),
  ])
  assert_eq(merged.need_int("port"), 6432L)
}
```

- The tiers run `Default`, `File`, `Env`, `Override`. The order is a field of
  `Knobs`, so it can be reversed — a patch read *under* a document — without
  touching a parser.
- Mappings merge member by member: a later file that sets one key under `db`
  keeps the rest of the earlier file's `db`. Lists replace, because a list is one
  decision.
- A disagreement is `Clash::Last` (the default), `Clash::First`, or
  `Clash::Refuse`, which reports both positions.

## Formats

| Package | Reads | Writes | Knobs |
|:--|:--|:--|:--|
| `moonconf/ini` | sections, `=` or `:`, continuations, defaults, two interpolations | yes | `standard`, `extended`, `literal` |
| `moonconf/props` | Java properties, ISO-8859-1 and escapes | yes | — |
| `moonconf/dotenv` | `.env` with quotes, escapes, continuation and references | yes | `interpolated`, `verbatim` |
| `moonconf/expand` | POSIX parameter expansion | — | `strict`, `lenient`, `deferred` |
| `moonconf/hocon` | JSON with relaxed punctuation, merging, references, includes | — | `plain`, `with_read`, `with_fallback` |
| `moonconf/hcl` | HCL 2 native and JSON syntax, evaluated against a context | — | `Context`, `standard` |

### INI

<!-- nocheck -->
```ini
[DEFAULT]
host = localhost

[db]
port = 5432
url = postgres://%(host)s/db
```

```moonbit check
test {
  let doc = @ini.parse("[db]\nport = 5432\nurl = postgres://localhost/db\n")
  assert_eq(doc.get("db", "url"), "postgres://localhost/db")
  assert_eq(doc.sections(), ["db"])
}
```

`doc.tree()` turns a document into the shared tree: one mapping per section, with
the defaults folded in and the references resolved.

### Properties

<!-- nocheck -->
```properties
# a note
db.host=localhost
greeting=\u4f60\u597d
```

```moonbit check
test {
  let doc = @props.parse("db.host=localhost\n")
  assert_eq(doc.get("db.host"), Some("localhost"))
}
```

Names are names, not paths: `db.host` is one key. `load` takes bytes as
ISO-8859-1, one byte to one character; `parse` takes text.

### `.env`

<!-- nocheck -->
```dotenv
export HOST=localhost
DSN="postgres://${HOST}/app"
LITERAL='${not expanded}'
```

```moonbit check
test {
  let env = @dotenv.load("HOST=localhost\nDSN=\"postgres://${HOST}/app\"\n")
  assert_eq(env.get("DSN"), Some("postgres://localhost/app"))
}
```

A reference sees the entries above it, so the order in the file is the order of
evaluation. Single quotes are literal; double quotes decode escapes and expand;
an unquoted value keeps its `#`.

### POSIX expansion

```moonbit check
test {
  let vars = @expand.Vars::of_map(Map([("PORT", "8080")]))
  assert_eq(@expand.expand(":${PORT:-80}", vars), ":8080")
  assert_eq(@expand.expand("${MISSING:-fallback}", vars), "fallback")
}
```

`${A}`, `$A`, `${A:-b}`, `${A-b}`, `${A:=b}`, `${A=b}`, `${A:?msg}`, `${A?msg}`,
`${A:+b}`, `${A+b}` and `${#A}`, with `\` escaping `$`, `\`, `"` and a backtick.

A name with no value is an error by default — a missing setting is nearly always
the bug. `lenient` reads it as empty, `deferred` leaves `${A}` for a later pass,
and `{ unset: Keep }` does the same field by field.

### HOCON

<!-- nocheck -->
```hocon
include "base.conf"

db.name = app
url = "postgres://${db.host}:${db.port}/${db.name}"
hosts = [a, b]
hosts += c
cache = ${?optional}
```

```moonbit check
test {
  let doc = @hocon.parse("db { host = localhost }\nurl = \"pg://${db.host}/x\"\n")
  assert_eq(doc.need_text("url"), "pg://localhost/x")
}
```

- The same name twice merges: objects member by member, arrays end to end, and
  anything else keeps the later one.
- `${a.b}` is the value at that path; `${?a.b}` is that value when it is there
  and nothing at all when it is not, so a field that depends on an unset name
  simply is not there.
- `include "x"` asks the caller's `read` for the text. Nothing is fetched here.
- A cycle is reported as one, rather than resolved into nonsense.

### HCL

<!-- nocheck -->
```hcl
region = var.region
name   = upper("web")

server "web" {
  port = 80 + 1
}
```

```moonbit check
test {
  let names = @moonconf.Node::map([("region", @moonconf.Node::str("eu-west-1", "vars"))], "vars")
  let body = @hcl.parse("region = var.region\n", context=@hcl.Context::new().bind("var", names))
  assert_eq(body.get("region").unwrap().text(), "eu-west-1")
}
```

Expressions are evaluated as they are read, against a `Context`: names are
values, functions are functions, and a string interpolates what an expression
inside it evaluates to. `@hcl.standard()` provides `upper`, `lower`, `trim`,
`length`, `join`, `concat` and `coalesce`; a caller adds its own with
`Context::function`.

`parse_json` reads the JSON syntax, where an object whose members are all objects
is a block and the member names are its labels.

`Body::tree()` turns a body into the shared tree: attributes under their names,
and blocks under theirs, so a document of blocks merges like any other.

Not part of this reader: template directives (`%{ if }`), heredocs, and `for`
expressions.

## Binding

A model says what a valid configuration is. Binding checks the tree against it,
fills in the defaults, and hands back JSON in the shape the model describes, which
`@json.from_json` turns into a struct of the caller's own.

```moonbit check
test {
  let model = @moonmodel.Model::new("Db", [
    @moonmodel.Field::new("host", @moonmodel.Type::Text, required=true),
    @moonmodel.Field::new("port", @moonmodel.Type::Int, required=true),
    @moonmodel.Field::new("pool", @moonmodel.Type::Int, default=Json::number(4.0)),
  ])
  let tree = @moonconf.Node::map([
    ("host", @moonconf.Node::str("localhost", "app.ini")),
    ("port", @moonconf.Node::str("5432", "env")),
  ], "app.ini")
  assert_eq(
    @moonconf.bind(tree, model),
    @json.parse("{\"host\":\"localhost\",\"port\":5432,\"pool\":4}"),
  )
}
```

Text is read as the number or the boolean it spells, because an environment
variable is always text. Text that does not spell the type is refused, not
guessed at.

`validate` reports every mistake at once instead of stopping at the first, for a
caller that wants to show a person everything wrong with their file.

## Errors

One error type per package, and one shape: what was wanted, what was there, and
where.

<!-- nocheck -->
```
db.port (env@1:1): want integer, got text
```

- `path` names the field, as a dotted path.
- `want` and `got` name the shapes, in the words a person would use.
- `at` is the position in the source, and `source` is the name the caller gave it.

## API

### `moonconf`

| Function | Meaning |
|:--|:--|
| `merge(sources, knobs?)` | Merge layers into one tree |
| `Node::merge(base, over, clash?=Last)` | Merge two trees |
| `Node::find(path)` / `need(path)` | The value at a dotted path |
| `Node::need_text/int/bool/real/list/table(path)` | The value, as a type |
| `bind(node, model, known?, knobs?)` | Check against a model, as JSON |
| `validate(node, model, known?, knobs?)` | Every refusal, not just the first |
| `native(node)` | The tree as JSON, without provenance |
| `of_json/of_yaml/of_toml(text, source?)` | Read a borrowed format into the tree |

### `moonconf/expand`

| Function | Meaning |
|:--|:--|
| `expand(text, vars, knobs?)` | Expand a text in the shell's parameter syntax |
| `Vars::of(get)` / `Vars::writing(get, set)` / `Vars::of_map(map)` | Where names come from |

### `moonconf/ini`

| Function | Meaning |
|:--|:--|
| `parse(text, knobs?)` | Read a document |
| `Doc::get(section, option)` / `raw` / `get_or` | The value, interpolated or not |
| `Doc::sections()` / `options(section)` / `has_option` | What is in it |
| `Doc::tree(source?)` | The document as the shared tree |
| `dumps(doc)` | Write it back |

### `moonconf/props`

| Function | Meaning |
|:--|:--|
| `parse(text)` / `load(bytes)` | Read text, or bytes as ISO-8859-1 |
| `Doc::get(key)` / `keys()` / `items()` | The pairs |
| `Doc::tree(source?)` | The file as the shared tree |
| `dumps(doc, comment?)` | Write it back |

### `moonconf/dotenv`

| Function | Meaning |
|:--|:--|
| `parse(text, source?)` | The entries, as written |
| `load(text, vars?, knobs?, source?)` | The variables, references expanded |
| `tree(text, vars?, knobs?, source?)` | The file as the shared tree |
| `dumps(entries)` | Write it back |

### `moonconf/hocon`

| Function | Meaning |
|:--|:--|
| `parse(text, knobs?, source?)` | Read a document into the shared tree |
| `Knobs::with_read(read)` / `with_fallback(lookup)` | Where includes and unresolved names come from |

### `moonconf/hcl`

| Function | Meaning |
|:--|:--|
| `parse(text, context?, source?)` | Read the native syntax |
| `parse_json(text, source?)` | Read the JSON syntax |
| `Body::get(name)` / `blocks_of(kind)` / `tree(source)` | What is in a body |
| `Context::new()` / `bind(name, value)` / `function(name, body)` | Names and functions in scope |
| `standard()` | The functions a configuration file usually needs |

## License

Apache-2.0.
