// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One assignment, with the place it was written.
pub(all) struct Entry {
  /// The name.
  key : String
  /// The value, with quotes removed and escapes decoded, or nothing when the
  /// line names a variable without giving it a value.
  value : String?
  /// Where the name starts.
  at : At
} derive(Eq, Debug)

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend Entry with Debug::{to_repr}

///|
/// A line that is not an assignment.
///
/// A `.env` file in the wild has lines from other shells in it, and a reader
/// that stops at the first one is a reader that leaves a program with no
/// configuration. The line is kept here instead, so a caller can log it or fail
/// on it, and the rest of the file still reads.
pub(all) struct Skipped {
  /// The line as written, without its ending.
  text : String
  /// Where it starts.
  at : At
} derive(Eq, Debug)

///|
pub extend Skipped with Eq::{equal, not_equal}

///|
pub extend Skipped with Debug::{to_repr}

///|
/// How to read a `.env` file.
pub(all) struct Knobs {
  /// Whether `${A}` and `${A:-b}` are resolved against the entries above them.
  /// A bootstrap file for a program that reads its own variables wants this off.
  interpolate : Bool
} derive(Eq, Debug)

///|
pub extend Knobs with Eq::{equal, not_equal}

///|
pub extend Knobs with Debug::{to_repr}

///|
/// Values are resolved as the file is read.
pub let interpolated : Knobs = { interpolate: true, }

///|
/// Values are taken as written.
pub let verbatim : Knobs = { interpolate: false, }

///|
/// The longest text this reader accepts.
pub let limit : Int32 = 1_048_576

///|
/// A read file: the assignments, and the lines that were not ones.
pub(all) struct Doc {
  /// The assignments, in file order, duplicates included.
  entries : Array[Entry]
  /// The lines that were not assignments, in file order.
  skipped : Array[Skipped]
} derive(Eq, Debug)

///|
pub extend Doc with Eq::{equal, not_equal}

///|
pub extend Doc with Debug::{to_repr}

///|
/// The names, once each, in the order they first appear.
pub fn Doc::keys(self : Doc) -> Array[String] {
  let out = []
  for entry in self.entries {
    if !out.contains(entry.key) {
      out.push(entry.key)
    }
  }
  out
}

///|
/// The value of `key`, the last one written winning.
pub fn Doc::get(self : Doc, key : String) -> String? {
  let mut found : String? = None
  for entry in self.entries {
    if entry.key == key {
      found = entry.value
    }
  }
  found
}

///|
priv struct Reader {
  src : StringView
  mut i : Int32
}

///|
fn is_space(c : Int32) -> Bool {
  c == ' '.to_int() ||
  c == '\t'.to_int() ||
  c == '\u{0B}'.to_int() ||
  c == '\u{0C}'.to_int()
}

///|
fn is_break(c : Int32) -> Bool {
  c == '\n'.to_int() || c == '\r'.to_int()
}

///|
fn Reader::at(self : Reader, index : Int32) -> Int32 {
  if index < self.src.length() {
    self.src.at(index).to_int()
  } else {
    -1
  }
}

///|
fn Reader::here(self : Reader) -> Int32 {
  self.at(self.i)
}

///|
fn Reader::spot(self : Reader, index : Int32) -> At {
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
fn Reader::skip_space(self : Reader) -> Unit {
  while is_space(self.here()) {
    self.i += 1
  }
}

///|
/// Past the end of a line, whichever line ending this text uses.
fn Reader::skip_break(self : Reader) -> Unit {
  if self.here() == '\r'.to_int() && self.at(self.i + 1) == '\n'.to_int() {
    self.i += 2
    return
  }
  if is_break(self.here()) {
    self.i += 1
  }
}

///|
fn Reader::to_eol(self : Reader) -> Unit {
  while self.here() != -1 && !is_break(self.here()) {
    self.i += 1
  }
}

///|
/// One escape in a double-quoted value: the character, and the width.
fn escape_at(text : StringView, index : Int32) -> (Char, Int32) {
  let c = if index < text.length() { text.at(index).to_int() } else { -1 }
  match c {
    0x6E => ('\n', 2)
    0x74 => ('\t', 2)
    0x72 => ('\r', 2)
    0x61 => ('\u{07}', 2)
    0x62 => ('\u{08}', 2)
    0x66 => ('\u{0C}', 2)
    0x76 => ('\u{0B}', 2)
    0x5C => ('\\', 2)
    0x22 => ('"', 2)
    0x27 => ('\'', 2)
    _ => ('\\', 1)
  }
}

///|
/// The name at the current position: `[^=#\s]+`, or a single-quoted key.
fn Reader::name(self : Reader) -> String? {
  if self.here() == '\''.to_int() {
    let start = self.i
    self.i += 1
    while self.here() != -1 &&
          !is_break(self.here()) &&
          self.here() != '\''.to_int() {
      self.i += 1
    }
    if self.here() != '\''.to_int() {
      self.i = start
      return None
    }
    let key = self.src[start + 1:self.i].to_owned()
    self.i += 1
    return Some(key)
  }
  let start = self.i
  while self.here() != -1 &&
        !is_break(self.here()) &&
        self.here() != '='.to_int() &&
        self.here() != '#'.to_int() &&
        !is_space(self.here()) {
    self.i += 1
  }
  if self.i == start {
    return None
  }
  Some(self.src[start:self.i].to_owned())
}

///|
/// The value at the current position, after `=` and its spaces.
///
/// Nothing means the value was a quote that never closed, which makes the line
/// not a binding at all rather than a binding with a strange value.
fn Reader::value(self : Reader) -> String? {
  let c = self.here()
  if c == '\''.to_int() {
    return self.single_quoted()
  }
  if c == '"'.to_int() {
    return self.double_quoted()
  }
  if c == -1 || is_break(c) {
    return Some("")
  }
  // Unquoted: the rest of the line, minus a comment that whitespace starts, and
  // minus the spaces at the end.
  let from = self.i
  self.to_eol()
  let mut end = self.i
  while end > from && is_space(self.at(end - 1)) {
    end -= 1
  }
  // ` #…` starts a comment; `#…` right after a character does not.
  let mut i = from
  while i < end {
    if self.at(i) == '#'.to_int() && i > from && is_space(self.at(i - 1)) {
      end = i
      while end > from && is_space(self.at(end - 1)) {
        end -= 1
      }
      break
    }
    i += 1
  }
  Some(self.src[from:end].to_owned())
}

///|
/// A single-quoted value: `\'` and `\\` are the only escapes, and the value may
/// span lines.
fn Reader::single_quoted(self : Reader) -> String? {
  let start = self.i
  self.i += 1
  let out = StringBuilder()
  while self.here() != -1 && self.here() != '\''.to_int() {
    if self.here() == '\\'.to_int() {
      let next = self.at(self.i + 1)
      if next == '\\'.to_int() || next == '\''.to_int() {
        out.write_char(next.unsafe_to_char())
        self.i += 2
        continue
      }
      out.write_char('\\')
      self.i += 1
      continue
    }
    out.write_char(self.here().unsafe_to_char())
    self.i += 1
  }
  if self.here() != '\''.to_int() {
    self.i = start
    return None
  }
  self.i += 1
  Some(out.to_string())
}

///|
/// A double-quoted value: `\n`, `\t`, `\r`, `\a`, `\b`, `\f`, `\v`, `\\`,
/// `\'` and `\"` are the escapes, and the value may span lines.
fn Reader::double_quoted(self : Reader) -> String? {
  let start = self.i
  self.i += 1
  let out = StringBuilder()
  while self.here() != -1 && self.here() != '"'.to_int() {
    let c = self.here()
    if c == '\\'.to_int() {
      let (decoded, width) = escape_at(self.src, self.i + 1)
      if width == 2 {
        out.write_char(decoded)
        self.i += 2
        continue
      }
      out.write_char('\\')
      self.i += 1
      continue
    }
    if is_break(c) {
      // The newline a quoted value spans is kept, as a single line ending.
      if c == '\r'.to_int() && self.at(self.i + 1) == '\n'.to_int() {
        self.i += 2
      } else {
        self.i += 1
      }
      out.write_char('\n')
      continue
    }
    out.write_char(c.unsafe_to_char())
    self.i += 1
  }
  if self.here() != '"'.to_int() {
    self.i = start
    return None
  }
  self.i += 1
  Some(out.to_string())
}

///|
/// Read a `.env` text into its assignments, in file order.
///
/// The grammar is the one `.env` files share in the wild:
///
/// - `KEY=VALUE`, with an optional `export` in front and optional spaces around
///   the sign; `KEY` alone names a variable without giving it a value.
/// - A key may be quoted, for a name with a space in it.
/// - `#` at the start of a line, or after whitespace, starts a comment. A `#`
///   with a character before it is part of the value.
/// - Single quotes take a value literally apart from `\'` and `\\`; double
///   quotes decode `\n`, `\t`, `\r`, `\a`, `\b`, `\f`, `\v`, `\\`, `\'` and
///   `\"`; either may span lines.
/// - A line that is none of those is kept in [`Doc::skipped`], not made into an
///   error, so one stray line does not cost a deployment its configuration.
///
/// References are not resolved here: [`load`] does that, because a reference
/// needs the entries above it.
pub fn parse(text : StringView, source~ : String = "") -> Doc raise Refused {
  ignore(source)
  if text.length() > limit {
    raise TooLarge(at={ at: 0, line: 1, column: 1, }, limit~)
  }
  let reader : Reader = { src: text, i: 0, }
  // A byte-order mark is not part of the first name.
  if reader.here() == 0xFEFF {
    reader.i += 1
  }
  let entries = []
  let skipped = []
  while reader.i < text.length() {
    reader.skip_space()
    if reader.here() == -1 {
      break
    }
    if is_break(reader.here()) {
      reader.skip_break()
      continue
    }
    if reader.here() == '#' {
      reader.to_eol()
      reader.skip_break()
      continue
    }
    let start = reader.i
    // `export` followed by whitespace is a prefix, not a name.
    if reader.here() == 'e'.to_int() &&
      reader.starts("export") &&
      is_space(reader.at(reader.i + 6)) {
      reader.i += 6
      reader.skip_space()
    }
    let key = match reader.name() {
      Some(key) => key
      None => {
        reader.to_eol()
        let text = reader.src[start:reader.i].to_owned()
        skipped.push({ text, at: reader.spot(start), })
        reader.skip_break()
        continue
      }
    }
    reader.skip_space()
    let mut value : String? = None
    if reader.here() == '='.to_int() {
      reader.i += 1
      let spaces = reader.i
      reader.skip_space()
      if reader.i > spaces && reader.here() == '#' {
        // `KEY= # note`: the value is empty and the rest is a comment.
        value = Some("")
      } else {
        match reader.value() {
          Some(parsed) => value = Some(parsed)
          None => {
            reader.to_eol()
            let text = reader.src[start:reader.i].to_owned()
            skipped.push({ text, at: reader.spot(start), })
            reader.skip_break()
            continue
          }
        }
      }
    }
    // Whatever follows the value must be a comment or the end of the line.
    reader.skip_space()
    if reader.here() == '#'.to_int() {
      reader.to_eol()
    }
    if reader.here() != -1 && !is_break(reader.here()) {
      // A quoted value followed by something else is not a binding.
      reader.to_eol()
      let text = reader.src[start:reader.i].to_owned()
      skipped.push({ text, at: reader.spot(start), })
      reader.skip_break()
      continue
    }
    entries.push({ key, value, at: reader.spot(start), })
    reader.skip_break()
  }
  { entries, skipped, }
}

///|
/// Whether `text` stands at the current position, without consuming it.
fn Reader::starts(self : Reader, text : String) -> Bool {
  let view = text[:]
  let mut i = 0
  while i < view.length() {
    if self.at(self.i + i) != view.at(i).to_int() {
      return false
    }
    i += 1
  }
  true
}

///|
/// Resolve `${A}` and `${A:-b}` in a value.
///
/// Only those two forms: a `.env` file is not a shell script, and a reader that
/// expanded `$A` too would rewrite values that were meant literally. A form the
/// grammar does not recognise stays as written.
fn resolve(value : String, env : Map[String, String]) -> String {
  let view = value[:]
  let out = StringBuilder()
  let mut i = 0
  while i < view.length() {
    let c = view.at(i).to_int()
    if c != '$'.to_int() ||
      i + 1 >= view.length() ||
      view.at(i + 1).to_int() != '{'.to_int() {
      out.write_char(c.unsafe_to_char())
      i += 1
      continue
    }
    let mut cursor = i + 2
    let name_from = cursor
    while cursor < view.length() &&
          view.at(cursor).to_int() != '}'.to_int() &&
          view.at(cursor).to_int() != ':'.to_int() {
      cursor += 1
    }
    if cursor >= view.length() {
      // No closing brace: the text is not a reference, and stays as written.
      out.write_char('$')
      i += 1
      continue
    }
    let name = view[name_from:cursor].to_owned()
    let mut default : String? = None
    if view.at(cursor).to_int() == ':'.to_int() {
      if cursor + 1 >= view.length() ||
        view.at(cursor + 1).to_int() != '-'.to_int() {
        out.write_char('$')
        i += 1
        continue
      }
      let default_from = cursor + 2
      let mut end = default_from
      while end < view.length() && view.at(end).to_int() != '}'.to_int() {
        end += 1
      }
      if end >= view.length() {
        out.write_char('$')
        i += 1
        continue
      }
      default = Some(view[default_from:end].to_owned())
      cursor = end
    }
    if cursor >= view.length() || view.at(cursor).to_int() != '}'.to_int() {
      out.write_char('$')
      i += 1
      continue
    }
    match env.get(name) {
      Some(text) => out.write_string(text)
      None =>
        match default {
          Some(text) => out.write_string(text)
          None => ()
        }
    }
    i = cursor + 1
  }
  out.to_string()
}

///|
/// The variables a `.env` text sets, with references resolved against the
/// entries above them.
///
/// A later assignment wins over an earlier one, and a reference sees the value
/// the name had at the point it was written. A name with no value sets nothing:
/// it is a declaration, not an assignment.
pub fn load(
  text : StringView,
  vars? : Map[String, String],
  knobs? : Knobs,
  source~ : String = "",
) -> Map[String, String] raise Refused {
  let knobs = knobs.unwrap_or(interpolated)
  let doc = parse(text, source~)
  let table : Map[String, String] = Map([])
  match vars {
    Some(vars) =>
      for pair in vars {
        table.set(pair.0, pair.1)
      }
    None => ()
  }
  for entry in doc.entries {
    match entry.value {
      None => ()
      Some(raw) =>
        if knobs.interpolate {
          table.set(entry.key, resolve(raw, table))
        } else {
          table.set(entry.key, raw)
        }
    }
  }
  table
}

///|
/// The file as the shared tree: one mapping of names to values, resolved as
/// [`load`] resolves them.
pub fn tree(
  text : StringView,
  vars? : Map[String, String],
  knobs? : Knobs,
  source~ : String = "",
) -> @moonconf.Node raise Refused {
  let variables = load(text, vars?, knobs?, source~)
  let table = @moonconf.Table::new()
  for pair in variables {
    table.set(pair.0, @moonconf.Node::str(pair.1, source))
  }
  @moonconf.Node::new(@moonconf.Value::Map(table), source, @moonconf.start)
}

///|
/// Write the entries back as a `.env` text.
///
/// A value that a reader would otherwise split, quote or comment is quoted; a
/// value that holds nothing special is written bare, because a file a person
/// reads is the point of the format. An entry with no value is written as the
/// bare name it was.
pub fn dumps(entries : Array[Entry]) -> String {
  let out = StringBuilder()
  for entry in entries {
    match entry.value {
      None => out.write_string(quote_key(entry.key))
      Some(value) => {
        out.write_string(quote_key(entry.key))
        out.write_char('=')
        out.write_string(quote(value))
      }
    }
    out.write_char('\n')
  }
  out.to_string()
}

///|
/// A name as a line carries it.
fn quote_key(key : String) -> String {
  let view = key[:]
  let mut plain = view.length() > 0
  let mut i = 0
  while i < view.length() {
    if is_space(view.at(i).to_int()) || view.at(i).to_int() == '='.to_int() {
      plain = false
    }
    i += 1
  }
  if plain {
    key
  } else {
    "'" + key + "'"
  }
}

///|
/// A value as `.env` should carry it.
fn quote(value : String) -> String {
  let view = value[:]
  let mut plain = view.length() > 0
  let mut i = 0
  while i < view.length() {
    let c = view.at(i).to_int()
    let ok = (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
      (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
      (c >= '0'.to_int() && c <= '9'.to_int()) ||
      c == '_'.to_int() ||
      c == '.'.to_int() ||
      c == '/'.to_int() ||
      c == ':'.to_int() ||
      c == '-'.to_int() ||
      c == '@'.to_int() ||
      c == '+'.to_int() ||
      c == ','.to_int()
    if !ok {
      plain = false
    }
    i += 1
  }
  if plain {
    return value
  }
  let out = StringBuilder()
  out.write_char('"')
  for c in value {
    match c {
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      _ => out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}
