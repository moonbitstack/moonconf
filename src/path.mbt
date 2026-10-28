// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Split a dotted path into its segments.
///
/// A dot separates members; `\.` is a literal dot, so a key that contains one
/// can still be named. An empty segment — `a..b`, `.a`, `a.` — is refused
/// rather than skipped, because a path with a hole in it is a typo.
pub fn segments(path : String) -> Array[String] raise Refused {
  let out = []
  let view = path[:]
  let current = StringBuilder()
  let mut i = 0
  let length = view.length()
  while i < length {
    let c = view.at(i).to_int()
    if c == '\\'.to_int() &&
      i + 1 < length &&
      view.at(i + 1).to_int() == '.'.to_int() {
      current.write_char('.')
      i += 2
      continue
    }
    if c == '.'.to_int() {
      if current.is_empty() {
        raise Path(got=path, at=i)
      }
      out.push(current.to_string())
      current.reset()
      i += 1
      continue
    }
    current.write_char(c.unsafe_to_char())
    i += 1
  }
  if current.is_empty() {
    if out.is_empty() && path == "" {
      return out
    }
    raise Path(got=path, at=i)
  }
  out.push(current.to_string())
  out
}

///|
/// The value at `path`, or nothing.
///
/// A segment of digits indexes into a list, so `servers.0.host` names the first
/// server's host without a second notation to learn.
pub fn Node::find(self : Node, path : String) -> Node? {
  let parts = segments(path) catch { _ => return None }
  if parts.is_empty() {
    return Some(self)
  }
  let mut here = self
  for part in parts {
    let next = match here.value {
      Map(table) => table.get(part)
      List(items) =>
        match whole(part[:]) {
          Some(index) => {
            let index = index.to_int()
            if index >= 0 && index < items.length() {
              Some(items[index])
            } else {
              None
            }
          }
          None => None
        }
      _ => None
    }
    match next {
      Some(node) => here = node
      None => return None
    }
  }
  Some(here)
}

///|
/// The value at `path`, or a [`Missing`] refusal naming the path.
pub fn Node::need(self : Node, path : String) -> Node raise Refused {
  match self.find(path) {
    Some(node) => node
    None => raise Missing(path~, want="a value")
  }
}

///|
/// The text at `path`.
pub fn Node::need_text(self : Node, path : String) -> String raise Refused {
  self.need(path).text()
}

///|
/// The integer at `path`.
pub fn Node::need_int(self : Node, path : String) -> Int64 raise Refused {
  self.need(path).int()
}

///|
/// The boolean at `path`.
pub fn Node::need_bool(self : Node, path : String) -> Bool raise Refused {
  self.need(path).bool()
}

///|
/// Whether a path is present.
pub fn Node::has(self : Node, path : String) -> Bool {
  self.find(path) is Some(_)
}
