// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A block of a body: a name, its labels, and the body inside its braces.
pub(all) struct Block {
  /// The name in front of the braces: `resource`, `server`, `module`.
  kind : String
  /// The labels between the name and the braces, in order.
  labels : Array[String]
  /// The contents.
  body : Body
  /// Where the name was written.
  at : At
} derive(Eq, Debug)

///|
/// The members of a body, in the order they were written.
///
/// A body holds two kinds of thing, and the format keeps them apart: attributes,
/// which are data — `name = "web"` — and blocks, which are the format's own
/// nesting — `server "web" { … }`. A reader that folded the two together would
/// make `server { }` and `server = {}` the same document, and they are not.
pub(all) struct Body {
  /// The attributes, in the order they were written.
  attributes : Array[(String, @moonconf.Node)]
  /// The blocks, in the order they were written.
  blocks : Array[Block]
} derive(Eq, Debug)

///|
pub extend Body with Eq::{equal, not_equal}

///|
pub extend Body with Debug::{to_repr}

///|
pub extend Block with Eq::{equal, not_equal}

///|
pub extend Block with Debug::{to_repr}

///|
/// The value of the attribute called `name`, or nothing.
pub fn Body::get(self : Body, name : String) -> @moonconf.Node? {
  for pair in self.attributes {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// The blocks called `kind`, in the order they were written.
pub fn Body::blocks_of(self : Body, kind : String) -> Array[Block] {
  let out = []
  for block in self.blocks {
    if block.kind == kind {
      out.push(block)
    }
  }
  out
}

///|
/// The members as the same tree the rest of this repository uses: attributes
/// under their names, blocks under theirs, a repeated block name collecting an
/// array.
pub fn Body::tree(self : Body, source : String) -> @moonconf.Node {
  let table = @moonconf.Table::new()
  for pair in self.attributes {
    table.set(pair.0, pair.1)
  }
  let seen = []
  for block in self.blocks {
    if !seen.contains(block.kind) {
      seen.push(block.kind)
      let same = self.blocks_of(block.kind)
      if same.length() == 1 {
        table.set(block.kind, block.body.tree(source))
      } else {
        let items = []
        for one in same {
          items.push(one.body.tree(source))
        }
        table.set(block.kind, @moonconf.Node::seq(items, source))
      }
    }
  }
  @moonconf.Node::new(@moonconf.Value::Map(table), source, @moonconf.start)
}

///|
/// The names in scope while an expression is evaluated.
///
/// A name is a whole tree, not a string: `var.region` is a member of `var`, which
/// is itself a mapping. Functions are values too — a caller adds one by putting a
/// function in the table, which is how a special function is spelled without
/// touching this package.
pub(all) struct Context {
  /// The names in scope, by their first segment.
  names : Map[String, @moonconf.Node]
  /// The functions a call may use.
  functions : Map[
    String,
    (Array[@moonconf.Node]) -> @moonconf.Node raise Refused,
  ]
}

///|
/// A context with no names and no functions.
pub fn Context::new() -> Context {
  { names: Map([]), functions: Map([]), }
}

///|
/// The same context with `name` bound to `value`.
pub fn Context::bind(
  self : Context,
  name : String,
  value : @moonconf.Node,
) -> Context {
  self.names.set(name, value)
  self
}

///|
/// The same context with `name` answered by `body`.
pub fn Context::function(
  self : Context,
  name : String,
  body : (Array[@moonconf.Node]) -> @moonconf.Node raise Refused,
) -> Context {
  self.functions.set(name, body)
  self
}

///|
/// A position of this package, in the terms the shared tree uses.
pub fn root_at(at : At) -> @moonconf.At {
  { at: at.at, line: at.line, column: at.column, }
}

///|
/// A position the shared tree carries, in this package's terms.
pub fn here_at(at : @moonconf.At) -> At {
  { at: at.at, line: at.line, column: at.column, }
}

///|
/// The text of a value, or a refusal naming what was there instead.
fn as_text(node : @moonconf.Node, at : At) -> String raise Refused {
  match node.value {
    @moonconf.Value::Text(text) => text
    @moonconf.Value::Int(n) => n.to_string()
    @moonconf.Value::Real(x) => x.to_string()
    @moonconf.Value::Bool(flag) => flag.to_string()
    _ => raise BadOperation(why="want text, got " + node.kind(), at~)
  }
}

///|
/// The members of a list, or a refusal.
fn as_list(
  node : @moonconf.Node,
  at : At,
) -> Array[@moonconf.Node] raise Refused {
  match node.value {
    @moonconf.Value::List(items) => items
    _ => raise BadOperation(why="want a list, got " + node.kind(), at~)
  }
}

///|
/// The functions every context starts with: the string and list operations a
/// configuration file uses, and nothing that reads the world.
pub fn standard() -> Context {
  let context = Context::new()
  ignore(
    context.function("upper", fn(args) raise Refused {
      guard args.length() == 1 else {
        raise BadArity(name="upper", want="1", got=args.length(), at=nowhere)
      }
      @moonconf.Node::str(as_text(args[0], nowhere).to_upper(), "")
    }),
  )
  ignore(
    context.function("lower", fn(args) raise Refused {
      guard args.length() == 1 else {
        raise BadArity(name="lower", want="1", got=args.length(), at=nowhere)
      }
      @moonconf.Node::str(as_text(args[0], nowhere).to_lower(), "")
    }),
  )
  ignore(
    context.function("trim", fn(args) raise Refused {
      guard args.length() == 1 else {
        raise BadArity(name="trim", want="1", got=args.length(), at=nowhere)
      }
      @moonconf.Node::str(as_text(args[0], nowhere).trim().to_owned(), "")
    }),
  )
  ignore(
    context.function("length", fn(args) raise Refused {
      guard args.length() == 1 else {
        raise BadArity(name="length", want="1", got=args.length(), at=nowhere)
      }
      match args[0].value {
        @moonconf.Value::List(items) =>
          @moonconf.Node::num(items.length().to_int64(), "")
        @moonconf.Value::Map(table) =>
          @moonconf.Node::num(table.length().to_int64(), "")
        _ =>
          @moonconf.Node::num(as_text(args[0], nowhere).length().to_int64(), "")
      }
    }),
  )
  ignore(
    context.function("join", fn(args) raise Refused {
      guard args.length() == 2 else {
        raise BadArity(name="join", want="2", got=args.length(), at=nowhere)
      }
      let separator = as_text(args[0], nowhere)
      let items = as_list(args[1], nowhere)
      let parts = []
      for item in items {
        parts.push(as_text(item, nowhere))
      }
      @moonconf.Node::str(parts.join(separator), "")
    }),
  )
  ignore(
    context.function("concat", fn(args) raise Refused {
      let out = []
      for arg in args {
        for item in as_list(arg, nowhere) {
          out.push(item)
        }
      }
      @moonconf.Node::seq(out, "")
    }),
  )
  ignore(
    context.function("coalesce", fn(args) {
      let mut first = @moonconf.Node::new(
        @moonconf.Value::Null,
        "",
        @moonconf.start,
      )
      for arg in args {
        match arg.value {
          @moonconf.Value::Null => ()
          @moonconf.Value::Text(text) =>
            if text != "" {
              first = arg
              break
            }
          _ => {
            first = arg
            break
          }
        }
      }
      first
    }),
  )
  context
}
