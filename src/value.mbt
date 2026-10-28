// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A mapping that remembers the order its members arrived in, because a
/// configuration file does: an INI file written back with its sections sorted
/// alphabetically is a different file, and a person diffing it sees noise
/// instead of their change.
pub(all) struct Table {
  entries : Array[(String, Node)]
} derive(Eq, Debug)

///|
pub fn Table::new() -> Table {
  { entries: [], }
}

///|
pub fn Table::length(self : Table) -> Int32 {
  self.entries.length()
}

///|
pub fn Table::is_empty(self : Table) -> Bool {
  self.entries.is_empty()
}

///|
/// The member called `key`, or nothing.
pub fn Table::get(self : Table, key : String) -> Node? {
  for entry in self.entries {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Whether `key` has a member.
pub fn Table::has(self : Table, key : String) -> Bool {
  self.get(key) is Some(_)
}

///|
/// Put `value` under `key`, in the place `key` already holds if it holds one.
///
/// Keeping the position is what makes a merge readable: the winner of a clash
/// stays where the losing value was, so the merged document still reads in the
/// order a person wrote it.
pub fn Table::set(self : Table, key : String, value : Node) -> Unit {
  let mut i = 0
  while i < self.entries.length() {
    if self.entries[i].0 == key {
      self.entries[i] = (key, value)
      return
    }
    i += 1
  }
  self.entries.push((key, value))
}

///|
/// Drop `key`, giving back what it held.
pub fn Table::remove(self : Table, key : String) -> Node? {
  let mut i = 0
  while i < self.entries.length() {
    if self.entries[i].0 == key {
      let gone = self.entries[i].1
      self.entries.remove(i) |> ignore
      return Some(gone)
    }
    i += 1
  }
  None
}

///|
/// The members in the order they were written.
pub fn Table::items(self : Table) -> ArrayView[(String, Node)] {
  self.entries[:]
}

///|
/// The names, in the order they were written.
pub fn Table::keys(self : Table) -> Array[String] {
  self.entries.map(fn(entry) { entry.0 })
}

///|
/// A copy, one level deep: the members are shared, the mapping is not.
pub fn Table::copy(self : Table) -> Table {
  { entries: self.entries.copy(), }
}

///|
/// A value in a configuration tree.
///
/// Numbers keep their kind: an integer stays an integer so that a port number
/// written as `8080` is not printed back as `8080.0`, and so that a binding to
/// an `Int` field can accept it without guessing.
pub(all) enum Value {
  /// Nothing was written, and nothing was meant.
  Null
  /// `true` or `false`.
  Bool(Bool)
  /// A whole number.
  Int(Int64)
  /// A number with a fractional part.
  Real(Double)
  /// Text, however it was quoted.
  Text(String)
  /// An ordered sequence.
  List(Array[Node])
  /// A mapping, in the order its members were written.
  Map(Table)
} derive(Eq, Debug)

///|
/// A value and the provenance that makes an error message usable: which source
/// it came from, and where in that source it was written.
pub(all) struct Node {
  /// The value itself.
  value : Value
  /// The name the caller gave the source — a file name, `env`, `defaults`.
  source : String
  /// Where in that source the value was written.
  at : At
} derive(Eq, Debug)

///|
pub fn Node::new(value : Value, source : String, at : At) -> Node {
  { value, source, at, }
}

///|
/// The same value, said to come from somewhere else. A merge uses this to
/// remember which layer won.
pub fn Node::from(self : Node, source : String, at? : At) -> Node {
  { value: self.value, source, at: at.unwrap_or(self.at), }
}

///|
/// The name of the shape a value has, for error messages: `text`, `integer`,
/// `real`, `boolean`, `null`, `list`, `mapping`.
pub fn Node::kind(self : Node) -> String {
  match self.value {
    Null => "null"
    Bool(_) => "boolean"
    Int(_) => "integer"
    Real(_) => "real"
    Text(_) => "text"
    List(_) => "list"
    Map(_) => "mapping"
  }
}

///|
/// The text, or a [`Type`] refusal naming what was there instead.
pub fn Node::text(self : Node) -> String raise Refused {
  match self.value {
    Text(text) => text
    _ =>
      raise Type(
        want="text",
        got=self.kind(),
        path="",
        source=self.source,
        at=self.at,
      )
  }
}

///|
/// The integer, or a [`Type`] refusal. A real with no fractional part is
/// accepted, because `8080.0` and `8080` are the same port.
pub fn Node::int(self : Node) -> Int64 raise Refused {
  match self.value {
    Int(n) => n
    Real(x) =>
      if x == x.trunc() && x.abs() < 9.007199254740992e15 {
        x.to_int64()
      } else {
        raise Type(
          want="integer",
          got="real",
          path="",
          source=self.source,
          at=self.at,
        )
      }
    _ =>
      raise Type(
        want="integer",
        got=self.kind(),
        path="",
        source=self.source,
        at=self.at,
      )
  }
}

///|
/// The number as a real.
pub fn Node::real(self : Node) -> Double raise Refused {
  match self.value {
    Real(x) => x
    Int(n) => n.to_double()
    _ =>
      raise Type(
        want="real",
        got=self.kind(),
        path="",
        source=self.source,
        at=self.at,
      )
  }
}

///|
/// The boolean.
pub fn Node::bool(self : Node) -> Bool raise Refused {
  match self.value {
    Bool(b) => b
    _ =>
      raise Type(
        want="boolean",
        got=self.kind(),
        path="",
        source=self.source,
        at=self.at,
      )
  }
}

///|
/// The members of a list.
pub fn Node::list(self : Node) -> Array[Node] raise Refused {
  match self.value {
    List(items) => items
    _ =>
      raise Type(
        want="list",
        got=self.kind(),
        path="",
        source=self.source,
        at=self.at,
      )
  }
}

///|
/// The members of a mapping.
pub fn Node::table(self : Node) -> Table raise Refused {
  match self.value {
    Map(table) => table
    _ =>
      raise Type(
        want="mapping",
        got=self.kind(),
        path="",
        source=self.source,
        at=self.at,
      )
  }
}

///|
/// Whether this is a mapping.
pub fn Node::is_map(self : Node) -> Bool {
  match self.value {
    Map(_) => true
    _ => false
  }
}

///|
/// Whether this is a list.
pub fn Node::is_list(self : Node) -> Bool {
  match self.value {
    List(_) => true
    _ => false
  }
}

///|
/// A mapping node built from pairs, in the order given.
pub fn Node::map(
  pairs : Array[(String, Node)],
  source : String,
  at? : At,
) -> Node {
  let table = Table::new()
  for pair in pairs {
    table.set(pair.0, pair.1)
  }
  { value: Map(table), source, at: at.unwrap_or(start), }
}

///|
/// A list node.
pub fn Node::seq(items : Array[Node], source : String, at? : At) -> Node {
  { value: List(items), source, at: at.unwrap_or(start), }
}

///|
/// A text node.
pub fn Node::str(text : String, source : String, at? : At) -> Node {
  { value: Text(text), source, at: at.unwrap_or(start), }
}

///|
/// A real-number node.
pub fn Node::of_real(value : Double, source : String, at? : At) -> Node {
  { value: Real(value), source, at: at.unwrap_or(start), }
}

///|
/// A boolean node.
pub fn Node::flag(flag : Bool, source : String, at? : At) -> Node {
  { value: Bool(flag), source, at: at.unwrap_or(start), }
}

///|
/// An integer node.
pub fn Node::num(n : Int64, source : String, at? : At) -> Node {
  { value: Int(n), source, at: at.unwrap_or(start), }
}

///|
/// A deep copy: the tree a caller gets back is theirs to change without
/// disturbing the one it came from.
pub fn Node::copy(self : Node) -> Node {
  let value = match self.value {
    List(items) => List(items.map(fn(item) { item.copy() }))
    Map(table) => {
      let out = Table::new()
      for entry in table.entries {
        out.set(entry.0, entry.1.copy())
      }
      Map(out)
    }
    other => other
  }
  { value, source: self.source, at: self.at, }
}

///|
pub extend Table with Eq::{equal, not_equal}

///|
pub extend Table with Debug::{to_repr}

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Value with Debug::{to_repr}

///|
pub extend Node with Eq::{equal, not_equal}

///|
pub extend Node with Debug::{to_repr}
