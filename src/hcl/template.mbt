// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One piece of a template.
priv enum Tmpl {
  /// Text, as written.
  Lit(String)
  /// `${ … }`: an expression whose value is inserted.
  Hole(String)
  /// `%{ if c } … %{ else } … %{ endif }`.
  If(String, Array[Tmpl], Array[Tmpl])
  /// `%{ for x in xs } … %{ endfor }`, with an optional second name for the key.
  Each(String, String?, String, Array[Tmpl])
}

///|
/// What the reader stopped at: the nodes so far, and the `%{ … }` that ended
/// them, when one did.
priv struct Piece {
  nodes : Array[Tmpl]
  stop : String
}

///|
priv struct TParser {
  src : StringView
  ctx : Context
  source : String
  at : At
  mut i : Int32
}

///|
fn TParser::here(self : TParser) -> Int32 {
  if self.i < self.src.length() {
    self.src.at(self.i).to_int()
  } else {
    -1
  }
}

///|
fn TParser::starts(self : TParser, text : String) -> Bool {
  let view = text[:]
  let mut i = 0
  while i < view.length() {
    if self.i + i >= self.src.length() ||
      self.src.at(self.i + i).to_int() != view.at(i).to_int() {
      return false
    }
    i += 1
  }
  true
}

///|
/// The index of the `}` that closes a `${` or `%{` whose body starts at `from`,
/// counting the braces an object inside the expression opens.
fn TParser::close_of(self : TParser, from : Int32) -> Int32? {
  let mut depth = 0
  let mut i = from
  while i < self.src.length() {
    let c = self.src.at(i).to_int()
    if c == '{'.to_int() {
      depth += 1
    } else if c == '}'.to_int() {
      if depth == 0 {
        return Some(i)
      }
      depth -= 1
    }
    i += 1
  }
  None
}

///|
/// The body of a marker, its trim markers taken off, and whether each was there.
fn TParser::body(
  self : TParser,
  from : Int32,
  to : Int32,
) -> (String, Bool, Bool) {
  if from >= to {
    return ("", false, false)
  }
  let mut start = from
  let mut end = to
  let mut left = false
  let mut right = false
  if self.src.at(start).to_int() == '~'.to_int() {
    left = true
    start += 1
  }
  if end > start && self.src.at(end - 1).to_int() == '~'.to_int() {
    right = true
    end -= 1
  }
  (trimmed(self.src[start:end]), left, right)
}

///|
/// A view without the whitespace at either end.
fn trimmed(view : StringView) -> String {
  let mut from = 0
  let mut to = view.length()
  while from < to {
    let c = view.at(from).to_int()
    if c == ' '.to_int() ||
      c == '\t'.to_int() ||
      c == '\n'.to_int() ||
      c == '\r'.to_int() {
      from += 1
    } else {
      break
    }
  }
  while to > from {
    let c = view.at(to - 1).to_int()
    if c == ' '.to_int() ||
      c == '\t'.to_int() ||
      c == '\n'.to_int() ||
      c == '\r'.to_int() {
      to -= 1
    } else {
      break
    }
  }
  view[from:to].to_owned()
}

///|
fn is_blank(c : Int32) -> Bool {
  c == ' '.to_int() ||
  c == '\t'.to_int() ||
  c == '\n'.to_int() ||
  c == '\r'.to_int()
}

///|
/// Take the whitespace at the end of the last literal, for a `~` on the left.
fn trim_tail(nodes : Array[Tmpl]) -> Unit {
  if nodes.length() == 0 {
    return
  }
  let last = nodes.length() - 1
  match nodes[last] {
    Lit(text) => {
      let view = text[:]
      let mut to = view.length()
      while to > 0 && is_blank(view.at(to - 1).to_int()) {
        to -= 1
      }
      nodes[last] = Lit(view[0:to].to_owned())
    }
    _ => ()
  }
}

///|
/// The first word of `text` and the rest of it, trimmed.
fn split_word(text : String) -> (String, String) {
  let view = text[:]
  let mut i = 0
  while i < view.length() && !is_blank(view.at(i).to_int()) {
    i += 1
  }
  let word = view[0:i].to_owned()
  (word, trimmed(view[i:]))
}

///|
/// Read template nodes until one of the `stops` directives, which is consumed.
fn TParser::nodes(self : TParser, stops : Array[String]) -> Piece raise Refused {
  let out : Array[Tmpl] = []
  let text = StringBuilder()
  while self.i < self.src.length() {
    if self.starts("$${") || self.starts("%%{") {
      // An escaped opener: the marker itself, as text.
      text.write_char(self.here().unsafe_to_char())
      text.write_char('{')
      self.i += 3
      continue
    }
    if self.starts("${") {
      let close = match self.close_of(self.i + 2) {
        Some(index) => index
        None => raise Unclosed(at=self.at, got="${")
      }
      let (body, left, right) = self.body(self.i + 2, close)
      if left {
        trim_tail(out)
      }
      if !text.is_empty() {
        out.push(Lit(text.to_string()))
        text.reset()
      }
      out.push(Hole(body))
      self.i = close + 1
      if right {
        while self.here() != -1 && is_blank(self.here()) {
          self.i += 1
        }
      }
      continue
    }
    if self.starts("%{") {
      let close = match self.close_of(self.i + 2) {
        Some(index) => index
        None => raise Unclosed(at=self.at, got="%{")
      }
      let (body, left, right) = self.body(self.i + 2, close)
      if left {
        trim_tail(out)
      }
      if !text.is_empty() {
        out.push(Lit(text.to_string()))
        text.reset()
      }
      self.i = close + 1
      if right {
        while self.here() != -1 && is_blank(self.here()) {
          self.i += 1
        }
      }
      let (word, rest) = split_word(body)
      if stops.contains(word) {
        ignore(rest)
        return { nodes: out, stop: word, }
      }
      match word {
        "if" => {
          let yes = self.nodes(["else", "endif"])
          let no = if yes.stop == "else" {
            let otherwise = self.nodes(["endif"])
            if otherwise.stop != "endif" {
              raise Unclosed(at=self.at, got="%{ if")
            }
            otherwise.nodes
          } else {
            []
          }
          out.push(If(rest, yes.nodes, no))
        }
        "for" => {
          let (name, second, collection) = for_header(rest)
          let body_nodes = self.nodes(["endfor"])
          if body_nodes.stop != "endfor" {
            raise Unclosed(at=self.at, got="%{ for")
          }
          out.push(Each(name, second, collection, body_nodes.nodes))
        }
        _ => raise Unexpected(at=self.at, got="%{" + body + "}")
      }
      continue
    }
    text.write_char(self.here().unsafe_to_char())
    self.i += 1
  }
  if !text.is_empty() {
    out.push(Lit(text.to_string()))
  }
  { nodes: out, stop: "", }
}

///|
/// `x in xs`, `k, v in map` — the header of a `%{ for }`.
fn for_header(text : String) -> (String, String?, String) {
  match text[:].find(" in ") {
    Some(at) => {
      let bound = trimmed(text[:at])
      let collection = trimmed(text[at + 4:])
      let parts = bound.split(",").map(fn(part) { trimmed(part) }).to_array()
      match parts.length() {
        2 => (parts[0], Some(parts[1]), collection)
        _ => (bound, None, collection)
      }
    }
    None => ("", None, "")
  }
}

///|
/// Evaluate a template to the text it stands for.
fn TParser::eval(
  self : TParser,
  nodes : Array[Tmpl],
  out : StringBuilder,
) -> Unit raise Refused {
  for node in nodes {
    match node {
      Lit(text) => out.write_string(text)
      Hole(body) =>
        out.write_string(render(eval_fragment(body, self.ctx, self.source)))
      If(condition, yes, no) =>
        if truth(eval_fragment(condition, self.ctx, self.source)) {
          self.eval(yes, out)
        } else {
          self.eval(no, out)
        }
      Each(first, second, collection, body) => {
        let items = eval_fragment(collection, self.ctx, self.source)
        match items.value {
          @moonconf.Value::List(entries) => {
            let mut index = 0
            for entry in entries {
              let inner = self.ctx
              match second {
                Some(key) => {
                  ignore(
                    inner.bind(
                      first,
                      @moonconf.Node::num(index.to_int64(), self.source),
                    ),
                  )
                  ignore(inner.bind(key, entry))
                }
                None => ignore(inner.bind(first, entry))
              }
              let scoped : TParser = {
                src: self.src,
                ctx: inner,
                source: self.source,
                at: self.at,
                i: 0,
              }
              scoped.eval(body, out)
              index += 1
            }
          }
          @moonconf.Value::Map(table) =>
            for pair in table.items() {
              let inner = self.ctx
              match second {
                Some(value_name) => {
                  ignore(
                    inner.bind(first, @moonconf.Node::str(pair.0, self.source)),
                  )
                  ignore(inner.bind(value_name, pair.1))
                }
                None => ignore(inner.bind(first, pair.1))
              }
              let scoped : TParser = {
                src: self.src,
                ctx: inner,
                source: self.source,
                at: self.at,
                i: 0,
              }
              scoped.eval(body, out)
            }
          _ =>
            raise BadOperation(
              why="%{ for } wants a list or a mapping",
              at=self.at,
            )
        }
      }
    }
  }
}

///|
/// Expand the `${…}` and `%{…}` forms in `raw`, which is a string whose escapes
/// have already been decoded.
fn expand_template(
  raw : String,
  ctx : Context,
  source : String,
  at : At,
) -> String raise Refused {
  let parser : TParser = { src: raw[:], ctx, source, at, i: 0, }
  let piece = parser.nodes([])
  let out = StringBuilder()
  parser.eval(piece.nodes, out)
  out.to_string()
}
