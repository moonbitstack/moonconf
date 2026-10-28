// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A value as it was written, before references are resolved.
priv enum Raw {
  Null
  Bool(Bool)
  Number(String)
  Str(String)
  Arr(Array[Item])
  Obj(Array[(String, Item)])
  Concat(Array[Item])
  Ref(String, Bool)
  /// Whitespace between two values that were written next to each other, kept
  /// so that joining text joins it as it was written.
  Space
}

///|
priv struct Item {
  raw : Raw
  at : At
}

///|
fn is_space(c : Int32) -> Bool {
  c == ' '.to_int() || c == '\t'.to_int() || c == '\f'.to_int()
}

///|
fn is_break(c : Int32) -> Bool {
  c == '\n'.to_int() || c == '\r'.to_int()
}

///|
fn is_key_end(c : Int32) -> Bool {
  c == '.'.to_int() ||
  c == '='.to_int() ||
  c == ':'.to_int() ||
  c == '+'.to_int() ||
  c == '{'.to_int() ||
  c == '}'.to_int() ||
  c == '['.to_int() ||
  c == ']'.to_int() ||
  c == ','.to_int() ||
  c == '#'.to_int() ||
  c == '"'.to_int() ||
  is_space(c) ||
  is_break(c)
}

///|
priv struct Parser {
  src : StringView
  read : (String, String) -> String?
  depth : Int32
  mut i : Int32
}

///|
fn Parser::at(self : Parser, index : Int32) -> Int32 {
  if index < self.src.length() {
    self.src.at(index).to_int()
  } else {
    -1
  }
}

///|
fn Parser::here(self : Parser) -> Int32 {
  self.at(self.i)
}

///|
fn Parser::spot(self : Parser, index : Int32) -> At {
  let mut line = 1
  let mut column = 1
  let mut i = 0
  while i < index && i < self.src.length() {
    if self.src.at(i).to_int() == 0x0A {
      line += 1
      column = 1
    } else {
      column += 1
    }
    i += 1
  }
  { at: index, line, column, }
}

///|
/// Past whitespace, line endings, commas and comments: everything an object
/// ignores between its members.
fn Parser::idle(self : Parser) -> Unit {
  while true {
    let c = self.here()
    if is_space(c) || is_break(c) || c == ','.to_int() {
      self.i += 1
      continue
    }
    if c == '#'.to_int() {
      while self.here() != -1 && !is_break(self.here()) {
        self.i += 1
      }
      continue
    }
    if c == '/'.to_int() && self.at(self.i + 1) == '/'.to_int() {
      while self.here() != -1 && !is_break(self.here()) {
        self.i += 1
      }
      continue
    }
    return
  }
}

///|
/// A quoted string, with its escapes decoded. A triple-quoted string is raw.
fn Parser::string(self : Parser) -> String raise Refused {
  let start = self.i
  if self.here() == '"'.to_int() &&
    self.at(self.i + 1) == '"'.to_int() &&
    self.at(self.i + 2) == '"'.to_int() {
    self.i += 3
    let out = StringBuilder()
    while true {
      if self.i >= self.src.length() {
        raise Unclosed(at=self.spot(start), got="\"\"\"")
      }
      if self.here() == '"'.to_int() &&
        self.at(self.i + 1) == '"'.to_int() &&
        self.at(self.i + 2) == '"'.to_int() {
        self.i += 3
        return out.to_string()
      }
      out.write_char(self.here().unsafe_to_char())
      self.i += 1
    }
  }
  self.i += 1
  let out = StringBuilder()
  while true {
    let c = self.here()
    if c == -1 || is_break(c) {
      raise Unclosed(at=self.spot(start), got="\"")
    }
    if c == '"'.to_int() {
      self.i += 1
      return out.to_string()
    }
    if c == '\\'.to_int() {
      let next = self.at(self.i + 1)
      match next {
        0x6E => out.write_char('\n')
        0x74 => out.write_char('\t')
        0x72 => out.write_char('\r')
        0x62 => out.write_char('\u{08}')
        0x66 => out.write_char('\u{0C}')
        0x22 => out.write_char('"')
        0x5C => out.write_char('\\')
        0x2F => out.write_char('/')
        0x75 => {
          let mut value = 0
          let mut k = 0
          while k < 4 {
            let digit = hex(self.at(self.i + 2 + k))
            match digit {
              Some(digit) => value = value * 16 + digit
              None => raise Unclosed(at=self.spot(self.i), got="\\u")
            }
            k += 1
          }
          out.write_char(value.unsafe_to_char())
          self.i += 4
        }
        _ => {
          out.write_char('\\')
          out.write_char(next.unsafe_to_char())
        }
      }
      self.i += 2
      continue
    }
    out.write_char(c.unsafe_to_char())
    self.i += 1
  }
  out.to_string()
}

///|
fn hex(c : Int32) -> Int32? {
  if c >= '0'.to_int() && c <= '9'.to_int() {
    Some(c - '0'.to_int())
  } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
    Some(c - 'a'.to_int() + 10)
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    Some(c - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// A key, as the segments its dots divide it into.
fn Parser::key(self : Parser) -> Array[String] raise Refused {
  let parts = []
  while true {
    self.idle()
    if self.here() == '"'.to_int() {
      parts.push(self.string())
    } else {
      let start = self.i
      while self.here() != -1 && !is_key_end(self.here()) {
        self.i += 1
      }
      if self.i == start {
        raise Unexpected(at=self.spot(self.i), got=self.describe_here())
      }
      parts.push(self.src[start:self.i].to_owned())
    }
    // A dot glues the next segment on.
    let mut probe = self.i
    while probe < self.src.length() && is_space(self.src.at(probe).to_int()) {
      probe += 1
    }
    if probe < self.src.length() && self.src.at(probe).to_int() == '.'.to_int() {
      self.i = probe + 1
      continue
    }
    return parts
  }
  parts
}

///|
fn Parser::describe_here(self : Parser) -> String {
  let c = self.here()
  if c == -1 {
    "the end"
  } else if is_break(c) {
    "a line ending"
  } else {
    c.unsafe_to_char().to_string()
  }
}

///|
/// Insert `value` at `path`, merging what is already there.
fn insert(
  pairs : Array[(String, Item)],
  path : Array[String],
  index : Int32,
  value : Item,
  append : Bool,
) -> Unit {
  let key = path[index]
  let last = index + 1 == path.length()
  if last {
    let mut found = -1
    let mut i = 0
    while i < pairs.length() {
      if pairs[i].0 == key {
        found = i
      }
      i += 1
    }
    if found >= 0 {
      let before = pairs[found].1
      // A value written twice may refer to itself: `a = 1` then `a = ${a} 2`
      // means "what `a` was, and then `2`". The reference is bound to the earlier
      // value before the two are merged, which is what makes an override that
      // builds on what it overrides work at all.
      let full = path[0:index + 1].join(".")
      let bound = rebind(value, full, before.raw)
      if append {
        pairs[found] = (key, { raw: appended(before, bound), at: before.at, })
      } else {
        pairs[found] = (
          key,
          { raw: merged(before.raw, bound.raw), at: before.at, },
        )
      }
    } else if append {
      pairs.push((key, { raw: Arr([value]), at: value.at, }))
    } else {
      pairs.push((key, value))
    }
    return
  }
  let mut found = -1
  let mut i = 0
  while i < pairs.length() {
    if pairs[i].0 == key {
      found = i
    }
    i += 1
  }
  if found < 0 {
    let child : Array[(String, Item)] = []
    pairs.push((key, { raw: Obj(child), at: value.at, }))
    found = pairs.length() - 1
  }
  match pairs[found].1.raw {
    Obj(child) => insert(child, path, index + 1, value, append)
    _ => {
      let child : Array[(String, Item)] = []
      pairs[found] = (key, { raw: Obj(child), at: pairs[found].1.at, })
      match pairs[found].1.raw {
        Obj(child) => insert(child, path, index + 1, value, append)
        _ => ()
      }
    }
  }
}

///|
/// Replace a reference to `path` with the value that path held before this
/// definition, everywhere inside `item`.
fn rebind(item : Item, path : String, previous : Raw) -> Item {
  match item.raw {
    Ref(target, _) =>
      if target == path {
        { raw: previous, at: item.at, }
      } else {
        item
      }
    Arr(items) =>
      {
        raw: Arr(items.map(fn(child) { rebind(child, path, previous) })),
        at: item.at,
      }
    Obj(pairs) =>
      {
        raw: Obj(
          pairs.map(fn(pair) { (pair.0, rebind(pair.1, path, previous)) }),
        ),
        at: item.at,
      }
    Concat(items) =>
      {
        raw: Concat(items.map(fn(child) { rebind(child, path, previous) })),
        at: item.at,
      }
    _ => item
  }
}

///|
/// `+=`: the value appended to what was there, or an array holding it.
fn appended(before : Item, value : Item) -> Raw {
  match before.raw {
    Arr(items) => {
      let out = items.copy()
      out.push(value)
      Arr(out)
    }
    _ => Arr([before, value])
  }
}

///|
/// Two values written under the same name: objects merge, arrays join, and
/// anything else keeps the later one, which is what `HOCON` means by merge.
fn merged(a : Raw, b : Raw) -> Raw {
  match (a, b) {
    (Obj(left), Obj(right)) => {
      let out = left.copy()
      for pair in right {
        let mut found = -1
        let mut i = 0
        while i < out.length() {
          if out[i].0 == pair.0 {
            found = i
          }
          i += 1
        }
        if found >= 0 {
          out[found] = (
            pair.0,
            { raw: merged(out[found].1.raw, pair.1.raw), at: out[found].1.at, },
          )
        } else {
          out.push(pair)
        }
      }
      Obj(out)
    }
    (Arr(left), Arr(right)) => {
      let out = left.copy()
      for item in right {
        out.push(item)
      }
      Arr(out)
    }
    (_, _) => b
  }
}

///|
/// One value: a run of atoms joined by nothing but whitespace.
fn Parser::value(self : Parser, level : Int32) -> Item raise Refused {
  if level > self.depth {
    raise TooDeep(at=self.spot(self.i), limit=self.depth)
  }
  let start = self.i
  let atoms : Array[Item] = []
  let mut gap = false
  while true {
    while is_space(self.here()) {
      self.i += 1
      gap = true
    }
    // The gap is recorded only once another value follows it, so that the spaces
    // before a line ending are not part of the value.
    let spaced = gap && atoms.length() > 0
    gap = false
    let c = self.here()
    if c == -1 ||
      is_break(c) ||
      c == ','.to_int() ||
      c == '}'.to_int() ||
      c == ']'.to_int() {
      break
    }
    if c == '#'.to_int() {
      break
    }
    if c == '/'.to_int() && self.at(self.i + 1) == '/'.to_int() {
      break
    }
    if c == '{'.to_int() {
      let item = self.object(level + 1)
      if spaced {
        atoms.push({ raw: Space, at: item.at, })
      }
      atoms.push(item)
      continue
    }
    if c == '['.to_int() {
      let item = self.array(level + 1)
      if spaced {
        atoms.push({ raw: Space, at: item.at, })
      }
      atoms.push(item)
      continue
    }
    if c == '"'.to_int() {
      let at = self.spot(self.i)
      let item = splice(self.string(), at)
      if spaced {
        atoms.push({ raw: Space, at, })
      }
      atoms.push(item)
      continue
    }
    if c == '$'.to_int() && self.at(self.i + 1) == '{'.to_int() {
      let item = self.reference()
      if spaced {
        atoms.push({ raw: Space, at: item.at, })
      }
      atoms.push(item)
      continue
    }
    // Unquoted text runs to whitespace or a delimiter. If what follows the run
    // is a separator, the run was a key and this value has already ended.
    let from = self.i
    while self.here() != -1 &&
          !is_space(self.here()) &&
          !is_break(self.here()) &&
          self.here() != ','.to_int() &&
          self.here() != '}'.to_int() &&
          self.here() != ']'.to_int() &&
          self.here() != '{'.to_int() &&
          self.here() != '['.to_int() &&
          self.here() != '$'.to_int() &&
          self.here() != '#'.to_int() &&
          !(self.here() == '/'.to_int() && self.at(self.i + 1) == '/'.to_int()) {
      self.i += 1
    }
    let token = self.src[from:self.i].to_owned()
    let after = self.peek_after_spaces()
    if atoms.length() == 0 &&
      (
        after == '='.to_int() ||
        after == ':'.to_int() ||
        (after == '+'.to_int() && self.peek_sign() == '='.to_int())
      ) {
      self.i = from
      break
    }
    let at = self.spot(from)
    if spaced {
      atoms.push({ raw: Space, at, })
    }
    match token {
      "true" => atoms.push({ raw: Bool(true), at, })
      "false" => atoms.push({ raw: Bool(false), at, })
      "null" => atoms.push({ raw: Null, at, })
      _ => atoms.push({ raw: Number(token), at, })
    }
  }
  if atoms.length() == 0 {
    raise MissingValue(at=self.spot(start), got=self.describe_here())
  }
  if atoms.length() == 1 {
    let only = atoms[0]
    // A number is decided by what it looks like, not by how it was written.
    match only.raw {
      Number(text) =>
        if is_number(text) {
          only
        } else {
          { raw: Str(text), at: only.at, }
        }
      _ => only
    }
  } else {
    { raw: Concat(atoms), at: self.spot(start), }
  }
}

///|
/// The first character after the spaces at the current position.
fn Parser::peek_after_spaces(self : Parser) -> Int32 {
  let mut i = self.i
  while i < self.src.length() && is_space(self.src.at(i).to_int()) {
    i += 1
  }
  self.at(i)
}

///|
/// The character after the spaces, skipping one `+` — for recognising `+=`.
fn Parser::peek_sign(self : Parser) -> Int32 {
  let mut i = self.i
  while i < self.src.length() && is_space(self.src.at(i).to_int()) {
    i += 1
  }
  if i < self.src.length() && self.src.at(i).to_int() == '+'.to_int() {
    return self.at(i + 1)
  }
  -1
}

///|
/// A quoted string with the references inside it pulled out, because a
/// substitution means the same thing inside quotes as outside: `"a${b}c"` is the
/// three values joined.
fn splice(text : String, at : At) -> Item {
  if !text.contains("${") {
    return { raw: Str(text), at, }
  }
  let view = text[:]
  let atoms : Array[Item] = []
  let mut i = 0
  let mut plain = 0
  while i < view.length() {
    if view.at(i).to_int() == '$'.to_int() &&
      i + 1 < view.length() &&
      view.at(i + 1).to_int() == '{'.to_int() {
      if i > plain {
        atoms.push({ raw: Str(view[plain:i].to_owned()), at, })
      }
      let mut end = i + 2
      let mut optional = false
      if end < view.length() && view.at(end).to_int() == '?'.to_int() {
        optional = true
        end += 1
      }
      let from = end
      while end < view.length() && view.at(end).to_int() != '}'.to_int() {
        end += 1
      }
      if end >= view.length() {
        atoms.push({ raw: Str(view[i:end].to_owned()), at, })
        plain = end
        i = end
        continue
      }
      atoms.push({ raw: Ref(view[from:end].to_owned(), optional), at, })
      i = end + 1
      plain = i
      continue
    }
    i += 1
  }
  if plain < view.length() {
    atoms.push({ raw: Str(view[plain:].to_owned()), at, })
  }
  if atoms.length() == 1 {
    return atoms[0]
  }
  { raw: Concat(atoms), at, }
}

///|
/// Whether a run of text is a number rather than a word that looks like one.
fn is_number(text : String) -> Bool {
  let view = text[:]
  if view.length() == 0 {
    return false
  }
  let mut i = 0
  if view.at(0).to_int() == '-'.to_int() || view.at(0).to_int() == '+'.to_int() {
    i = 1
  }
  let mut digits = 0
  while i < view.length() {
    let c = view.at(i).to_int()
    if c >= '0'.to_int() && c <= '9'.to_int() {
      digits += 1
      i += 1
      continue
    }
    if c == '.'.to_int() ||
      c == 'e'.to_int() ||
      c == 'E'.to_int() ||
      c == '-'.to_int() ||
      c == '+'.to_int() {
      i += 1
      continue
    }
    return false
  }
  digits > 0
}

///|
/// `${path}` and `${?path}`.
fn Parser::reference(self : Parser) -> Item raise Refused {
  let start = self.i
  self.i += 2
  let optional = self.here() == '?'.to_int()
  if optional {
    self.i += 1
  }
  let body = StringBuilder()
  while true {
    let c = self.here()
    if c == -1 || is_break(c) {
      raise Unclosed(at=self.spot(start), got="${")
    }
    if c == '}'.to_int() {
      self.i += 1
      break
    }
    body.write_char(c.unsafe_to_char())
    self.i += 1
  }
  let path = body.to_string()
  if path == "" {
    raise Unexpected(at=self.spot(start), got="${}")
  }
  { raw: Ref(path, optional), at: self.spot(start), }
}

///|
/// `{ … }`.
fn Parser::object(self : Parser, level : Int32) -> Item raise Refused {
  self.i += 1
  self.members(level, true)
}

///|
fn Parser::describe_path(self : Parser, path : Array[String]) -> String {
  ignore(self)
  path.join(".")
}

///|
/// Whitespace after a key, but not past a line ending: a key and its value are
/// on the same line unless the value is an object or an array.
fn Parser::idle_after_key(self : Parser) -> Unit {
  while is_space(self.here()) {
    self.i += 1
  }
}

///|
/// `[ … ]`.
fn Parser::array(self : Parser, level : Int32) -> Item raise Refused {
  if level > self.depth {
    raise TooDeep(at=self.spot(self.i), limit=self.depth)
  }
  let start = self.i
  self.i += 1
  let items : Array[Item] = []
  while true {
    self.idle()
    if self.here() == -1 {
      raise Unclosed(at=self.spot(start), got="[")
    }
    if self.here() == ']'.to_int() {
      self.i += 1
      return { raw: Arr(items), at: self.spot(start), }
    }
    items.push(self.value(level + 1))
  }
  { raw: Arr(items), at: self.spot(start), }
}

///|
/// Whether an `include` starts here.
fn Parser::is_include(self : Parser) -> Bool {
  let word = "include"
  let mut i = 0
  while i < word.length() {
    if self.at(self.i + i) != word.at(i).to_int() {
      return false
    }
    i += 1
  }
  let next = self.at(self.i + word.length())
  is_space(next) || next == '"'.to_int() || next == '('.to_int()
}

///|
/// `include "name"`, `include required(file("name"))` and the other wrappers.
///
/// Every wrapper ends at the same place: a name the caller is asked for. `url`
/// and `classpath` are not fetched here, because reading a stream is I/O and this
/// package does none; a caller that can fetch a URL answers the same function it
/// answers for a file, and is told which wrapper was written.
fn Parser::include_at(
  self : Parser,
  pairs : Array[(String, Item)],
  level : Int32,
) -> Unit raise Refused {
  let start = self.i
  self.i += 7
  let mut required = false
  // The wrapper the include was written with: `file` unless it says otherwise.
  let mut kind = "file"
  while true {
    while is_space(self.here()) || is_break(self.here()) {
      self.i += 1
    }
    if self.here() == '"'.to_int() {
      break
    }
    if self.here() == -1 {
      raise Unclosed(at=self.spot(start), got="include")
    }
    let from = self.i
    while self.here() != -1 &&
          !is_space(self.here()) &&
          self.here() != '('.to_int() &&
          self.here() != '"'.to_int() {
      self.i += 1
    }
    let word = self.src[from:self.i].to_owned()
    if word == "required" {
      required = true
    } else if word == "file" || word == "url" || word == "classpath" {
      // The wrapper names where the text comes from. The caller decides what
      // that means, because reading a file or a URL is I/O and this package
      // does none.
      kind = word
    }
    while is_space(self.here()) {
      self.i += 1
    }
    if self.here() == '('.to_int() {
      self.i += 1
    }
  }
  let name = self.string()
  while true {
    while is_space(self.here()) {
      self.i += 1
    }
    if self.here() == ')'.to_int() {
      self.i += 1
      continue
    }
    break
  }
  let text = match (self.read)(kind, name) {
    Some(text) => text
    None =>
      if required {
        raise MissingInclude(name~, at=self.spot(start))
      } else {
        return
      }
  }
  let nested : Parser = {
    src: text[:],
    read: self.read,
    depth: self.depth,
    i: 0,
  }
  let included = nested.document(level + 1)
  match included.raw {
    Obj(inner) =>
      for pair in inner {
        insert(pairs, [pair.0], 0, pair.1, false)
      }
    _ => ()
  }
}

///|
/// A whole document: an object, with or without its braces.
fn Parser::document(self : Parser, level : Int32) -> Item raise Refused {
  self.idle()
  if self.here() == '{'.to_int() {
    let item = self.object(level)
    self.idle()
    if self.here() != -1 {
      raise Unexpected(at=self.spot(self.i), got=self.describe_here())
    }
    return item
  }
  self.members(level, false)
}

///|
/// The members of an object, up to the closing brace or the end of the text.
fn Parser::members(
  self : Parser,
  level : Int32,
  braced : Bool,
) -> Item raise Refused {
  if level > self.depth {
    raise TooDeep(at=self.spot(self.i), limit=self.depth)
  }
  let start = self.i
  let pairs : Array[(String, Item)] = []
  while true {
    self.idle()
    if self.here() == -1 {
      if braced {
        raise Unclosed(at=self.spot(start), got="{")
      }
      return { raw: Obj(pairs), at: self.spot(start), }
    }
    if self.here() == '}'.to_int() {
      if !braced {
        raise Unexpected(at=self.spot(self.i), got="}")
      }
      self.i += 1
      return { raw: Obj(pairs), at: self.spot(start), }
    }
    if self.is_include() {
      self.include_at(pairs, level)
      continue
    }
    let path = self.key()
    self.idle_after_key()
    let mut append = false
    match self.here() {
      c if c == '='.to_int() => self.i += 1
      c if c == ':'.to_int() => self.i += 1
      c if c == '+'.to_int() && self.at(self.i + 1) == '='.to_int() => {
        self.i += 2
        append = true
      }
      c if c == '{'.to_int() => ()
      _ =>
        raise MissingValue(at=self.spot(self.i), got=self.describe_path(path))
    }
    let item = self.value(level + 1)
    insert(pairs, path, 0, item, append)
  }
  { raw: Obj(pairs), at: self.spot(start), }
}
