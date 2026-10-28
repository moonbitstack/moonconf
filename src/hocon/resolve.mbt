// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How far to look for a name a substitution refers to.
pub(all) struct Knobs {
  /// Where an `include` reads from: the wrapper it was written with — `file`,
  /// `url` or `classpath` — and the name inside it. Answering nothing for a
  /// name makes the include optional, unless it was written `required(...)`.
  /// Reading is the caller's job, because this package does no I/O.
  read : (String, String) -> String?
  /// Where a `${name}` that the document itself does not define is looked up:
  /// the process environment, an overlay, a test fixture. Nothing by default,
  /// because this package does no I/O.
  fallback : (String) -> String?
  /// The limit on nesting.
  depth : Int32
}

///|
/// A document that includes nothing and falls back to nothing.
pub let plain : Knobs = {
  read: fn(_, _) { None },
  fallback: fn(_) { None },
  depth: 64,
}

///|
/// A document whose includes are read by `read`, whatever wrapper they used.
pub fn Knobs::with_read(read : (String) -> String?) -> Knobs {
  { ..plain, read: fn(_, name) { read(name) }, }
}

///|
/// A document whose includes are read by `from`, told which wrapper was
/// written: `file`, `url` or `classpath`.
pub fn Knobs::with_includes(from : (String, String) -> String?) -> Knobs {
  { ..plain, read: from, }
}

///|
/// A document whose unresolved names fall back to `lookup`.
pub fn Knobs::with_fallback(lookup : (String) -> String?) -> Knobs {
  { ..plain, fallback: lookup, }
}

///|
/// A document being resolved: the tree, where an unresolved name may be found,
/// and the paths currently being resolved, which is how a cycle is caught.
priv struct Res {
  root : Raw
  fallback : (String) -> String?
  source : String
  stack : Array[String]
}

///|
/// The member called `part`, or nothing.
fn step(raw : Raw, part : String) -> Raw? {
  match raw {
    Obj(pairs) => {
      let mut found = None
      for pair in pairs {
        if pair.0 == part {
          found = Some(pair.1.raw)
        }
      }
      found
    }
    _ => None
  }
}

///|
/// The value written at `path`, or nothing.
fn Res::lookup(self : Res, path : String) -> Raw? {
  let parts = path.split(".").map(fn(part) { part.to_owned() }).to_array()
  let mut here = self.root
  for part in parts {
    match step(here, part) {
      Some(next) => here = next
      None => return None
    }
  }
  Some(here)
}

///|
/// Whether `path` is already being resolved.
fn Res::busy(self : Res, path : String) -> Bool {
  self.stack.contains(path)
}

///|
/// One value, with its references resolved. Nothing means the value is absent:
/// an optional reference that found nothing, or an object whose only member was
/// one.
fn Res::resolve(
  self : Res,
  item : Item,
  path : String,
) -> @moonconf.Node? raise Refused {
  let at = @moonconf.At::{
    at: item.at.at,
    line: item.at.line,
    column: item.at.column,
  }
  match item.raw {
    Space => None
    Null => Some(@moonconf.Node::new(@moonconf.Value::Null, self.source, at))
    Bool(flag) => Some(@moonconf.Node::flag(flag, self.source, at~))
    Number(text) => Some(number_of(text, self.source, at))
    Str(text) => Some(@moonconf.Node::str(text, self.source, at~))
    Arr(items) => {
      let out = []
      for child in items {
        match self.resolve(child, path) {
          Some(node) => out.push(node)
          None => ()
        }
      }
      Some(@moonconf.Node::seq(out, self.source, at~))
    }
    Obj(pairs) => {
      let table = @moonconf.Table::new()
      for pair in pairs {
        let child = if path == "" { pair.0 } else { path + "." + pair.0 }
        match self.resolve(pair.1, child) {
          Some(node) => table.set(pair.0, node)
          None => ()
        }
      }
      Some(@moonconf.Node::new(@moonconf.Value::Map(table), self.source, at))
    }
    Concat(items) => self.join(items, path, at)
    Ref(target, optional) => {
      if self.busy(target) {
        raise Cycle(path=target)
      }
      match self.lookup(target) {
        Some(raw) => {
          let pushed = self.stack.copy()
          pushed.push(target)
          let inner : Res = {
            root: self.root,
            fallback: self.fallback,
            source: self.source,
            stack: pushed,
          }
          inner.resolve({ raw, at: item.at, }, target)
        }
        None =>
          match (self.fallback)(target) {
            Some(text) => Some(@moonconf.Node::str(text, self.source, at~))
            None =>
              if optional {
                None
              } else {
                raise Unresolved(path=target, at=item.at)
              }
          }
      }
    }
  }
}

///|
/// A number as written: an integer when it has neither a point nor an exponent.
fn number_of(
  text : String,
  source : String,
  at : @moonconf.At,
) -> @moonconf.Node {
  if text.contains(".") || text.contains("e") || text.contains("E") {
    match @moonconf.decimal(text[:]) {
      Some(value) => @moonconf.Node::of_real(value, source, at~)
      None => @moonconf.Node::str(text, source, at~)
    }
  } else {
    match @moonconf.whole(text[:]) {
      Some(value) => @moonconf.Node::num(value, source, at~)
      None => @moonconf.Node::str(text, source, at~)
    }
  }
}

///|
/// Values written next to each other, joined: text joins text, an object joins
/// an object, an array joins an array. Anything else has no join, and saying so
/// beats picking one of the two.
fn Res::join(
  self : Res,
  items : Array[Item],
  path : String,
  at : @moonconf.At,
) -> @moonconf.Node? raise Refused {
  let nodes = []
  for child in items {
    match self.resolve(child, path) {
      Some(node) => nodes.push(node)
      None => ()
    }
  }
  if nodes.length() == 0 {
    return None
  }
  if nodes.length() == 1 {
    return Some(nodes[0])
  }
  let mut text = true
  let mut table = true
  let mut list = true
  for node in nodes {
    if node.is_map() {
      text = false
      list = false
    } else if node.is_list() {
      text = false
      table = false
    } else {
      table = false
      list = false
    }
  }
  if text {
    let out = StringBuilder()
    for item in items {
      match item.raw {
        Space => out.write_char(' ')
        _ =>
          match self.resolve(item, path) {
            Some(node) => out.write_string(scalar(node))
            None => ()
          }
      }
    }
    return Some(@moonconf.Node::str(out.to_string(), self.source, at~))
  }
  if table {
    let out = @moonconf.Table::new()
    for node in nodes {
      match node.value {
        @moonconf.Value::Map(table) =>
          for pair in table.items() {
            out.set(pair.0, pair.1)
          }
        _ => ()
      }
    }
    return Some(@moonconf.Node::new(@moonconf.Value::Map(out), self.source, at))
  }
  if list {
    let out = []
    for node in nodes {
      match node.value {
        @moonconf.Value::List(items) =>
          for item in items {
            out.push(item)
          }
        _ => ()
      }
    }
    return Some(@moonconf.Node::seq(out, self.source, at~))
  }
  raise Concat(
    at={ at: at.at, line: at.line, column: at.column, },
    got="a value with another",
  )
}

///|
/// A scalar as the text it was written as, which is what joining does to one.
fn scalar(node : @moonconf.Node) -> String {
  match node.value {
    @moonconf.Value::Null => "null"
    @moonconf.Value::Bool(flag) => flag.to_string()
    @moonconf.Value::Int(n) => n.to_string()
    @moonconf.Value::Real(x) => x.to_string()
    @moonconf.Value::Text(text) => text
    _ => ""
  }
}

///|
/// Read a HOCON document.
///
/// The syntax is JSON's with the punctuation relaxed — no commas needed, no
/// quotes around a word that has no punctuation in it, `=` or `:` before a value,
/// `#` or `//` starting a comment — plus the three things that make it a
/// configuration language rather than a data format:
///
/// - **Merging.** The same name twice merges its values: objects member by
///   member, arrays end to end, and anything else keeps the later one.
/// - **References.** `${a.b}` is the value at that path; `${?a.b}` is that value
///   when it is there and nothing at all when it is not.
/// - **Includes.** `include "name"` asks `knobs.read` for the text, which is how
///   this package reads a second file without doing any I/O itself.
pub fn parse(
  text : StringView,
  knobs? : Knobs,
  source~ : String = "",
) -> @moonconf.Node raise Refused {
  let knobs = knobs.unwrap_or(plain)
  let parser : Parser = {
    src: text,
    read: knobs.read,
    depth: knobs.depth,
    i: 0,
  }
  let root = parser.document(0)
  let res : Res = {
    root: root.raw,
    fallback: knobs.fallback,
    source,
    stack: [],
  }
  match res.resolve(root, "") {
    Some(node) => node
    None => @moonconf.Node::map([], source)
  }
}
