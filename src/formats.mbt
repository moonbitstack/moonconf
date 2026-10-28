// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A borrowed reader's position, in this package's terms.
fn at_of(at : Int32, line : Int32, column : Int32) -> At {
  { at, line, column, }
}

///|
/// Carry a JSON value into the tree.
///
/// A number keeps the text the reader kept for it: `8080` becomes an integer and
/// `8080.5` a real, and a value written with an exponent that lands on a whole
/// number still reads as a real, because it was written as one.
///
/// An object's members come out sorted, because the JSON reader hands back a map
/// and a map has no order to preserve. The other formats in this repository keep
/// the order they were written in; this one cannot, and says so here rather than
/// pretending otherwise.
fn of_json_value(value : Json, source : String) -> Node {
  let node = match value {
    Json::Null => Node::new(Null, source, start)
    Json::True => Node::new(Bool(true), source, start)
    Json::False => Node::new(Bool(false), source, start)
    Json::String(text) => Node::new(Text(text), source, start)
    Json::Number(x, repr~) => {
      let written = match repr {
        Some(text) =>
          text.contains(".") || text.contains("e") || text.contains("E")
        None => x != x.trunc()
      }
      if written {
        Node::new(Real(x), source, start)
      } else {
        match repr {
          Some(text) =>
            match whole(text[:]) {
              Some(n) => Node::new(Int(n), source, start)
              None => Node::new(Real(x), source, start)
            }
          None => Node::new(Int(x.to_int64()), source, start)
        }
      }
    }
    Json::Array(items) =>
      Node::new(
        List(items.map(fn(item) { of_json_value(item, source) })),
        source,
        start,
      )
    Json::Object(members) => {
      let keys = members.keys().to_array()
      keys.sort()
      let table = Table::new()
      for key in keys {
        table.set(key, of_json_value(members[key], source))
      }
      Node::new(Map(table), source, start)
    }
  }
  node
}

///|
/// Read a JSON document into the tree.
///
/// Positions are not carried: the reader this borrows reports where it refused,
/// not where each value sat, so a value carries the source name and the first
/// position. A refusal keeps the reader's own position.
pub fn of_json(text : StringView, source~ : String = "") -> Node raise Refused {
  let value = @moonjson.loads(text, @moonjson.strict) catch {
    refused =>
      match refused.at() {
        Some(at) =>
          raise Format(
            why=refused.to_repr().to_string(),
            at=Some(at_of(at.at, at.line, at.column)),
          )
        None => raise Format(why=refused.to_repr().to_string(), at=None)
      }
  }
  of_json_value(value, source)
}

///|
/// Read a YAML document into the tree.
///
/// One document, in YAML 1.2 core schema. Anchors, aliases and merge keys are
/// resolved by the reader; what arrives here is the value.
pub fn of_yaml(text : StringView, source~ : String = "") -> Node raise Refused {
  let value = @moonyaml.loads(text) catch {
    refused =>
      raise Format(
        why=refused.to_string(),
        at=Some(at_of(refused.at().at, refused.at().line, refused.at().column)),
      )
  }
  of_json_value(value, source)
}

///|
/// Read a TOML document into the tree.
pub fn of_toml(text : StringView, source~ : String = "") -> Node raise Refused {
  let value = @moontoml.loads(text) catch {
    refused =>
      raise Format(
        why=refused.to_string(),
        at=Some(at_of(refused.at().at, refused.at().line, refused.at().column)),
      )
  }
  of_json_value(value, source)
}
