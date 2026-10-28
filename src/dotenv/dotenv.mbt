// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One assignment, with the place it was written.
pub(all) struct Entry {
  /// The name.
  key : String
  /// The value, with quotes removed and escapes decoded.
  value : String
  /// Whether the value was written in single quotes, and so is taken exactly as
  /// written: no escapes, no expansion.
  quoted : Bool
  /// Where the name starts.
  at : At
} derive(Eq, Debug)

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend Entry with Debug::{to_repr}

///|
/// How to read a `.env` file.
pub(all) struct Knobs {
  /// Whether `${A}` and `$A` inside a value are expanded against the entries
  /// above them. A bootstrap file for a program that reads its own variables
  /// wants this off.
  interpolate : Bool
} derive(Eq, Debug)

///|
pub extend Knobs with Eq::{equal, not_equal}

///|
pub extend Knobs with Debug::{to_repr}

///|
/// Values are expanded as the file is read.
pub let interpolated : Knobs = { interpolate: true, }

///|
/// Values are taken as written.
pub let verbatim : Knobs = { interpolate: false, }

///|
/// The longest text this reader accepts. A `.env` file is not a document, and a
/// limit keeps a runaway input from being walked twice.
pub let limit : Int32 = 1_048_576

///|
priv struct Reader {
  src : StringView
  mut i : Int32
}

///|
fn is_space(c : Int32) -> Bool {
  c == ' '.to_int() || c == '\t'.to_int()
}

///|
fn is_newline(c : Int32) -> Bool {
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
  if is_newline(self.here()) {
    self.i += 1
  }
}

///|
fn Reader::to_eol(self : Reader) -> Unit {
  while self.here() != -1 && !is_newline(self.here()) {
    self.i += 1
  }
}

///|
/// The index just past the name that starts at `from`.
fn Reader::name_end(self : Reader, from : Int32) -> Int32 {
  let mut i = from
  while i < self.src.length() {
    let c = self.src.at(i).to_int()
    if c == '='.to_int() || is_space(c) || is_newline(c) {
      return i
    }
    i += 1
  }
  i
}

///|
/// Whether `text` is a name a shell would accept.
fn is_name(text : String) -> Bool {
  let view = text[:]
  if view.length() == 0 {
    return false
  }
  let first = view.at(0).to_int()
  let starts = (first >= 'a'.to_int() && first <= 'z'.to_int()) ||
    (first >= 'A'.to_int() && first <= 'Z'.to_int()) ||
    first == '_'.to_int()
  if !starts {
    return false
  }
  let mut i = 1
  while i < view.length() {
    let c = view.at(i).to_int()
    let ok = (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
      (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
      (c >= '0'.to_int() && c <= '9'.to_int()) ||
      c == '_'.to_int()
    if !ok {
      return false
    }
    i += 1
  }
  true
}

///|
/// The body of a single-quoted value: nothing is decoded, nothing is expanded.
fn Reader::single_quoted(self : Reader) -> String raise Refused {
  let out = StringBuilder()
  let start = self.i
  let mut i = self.i + 1
  while true {
    if i >= self.src.length() {
      raise Unclosed(at=self.spot(start))
    }
    let c = self.src.at(i).to_int()
    if c == '\''.to_int() {
      self.i = i + 1
      return out.to_string()
    }
    out.write_char(c.unsafe_to_char())
    i += 1
  }
  out.to_string()
}

///|
/// The body of a double-quoted value, up to and including the closing quote.
///
/// The escapes are decoded here and expansion is not: `\$` is left as `\$` on
/// purpose, so that the expansion pass — which understands that escape — is the
/// only thing that has to know what a dollar means. A trace of the escape in the
/// value would otherwise expand twice.
fn Reader::double_quoted(self : Reader) -> String raise Refused {
  let out = StringBuilder()
  let start = self.i
  let mut i = self.i + 1
  while true {
    if i >= self.src.length() {
      raise Unclosed(at=self.spot(start))
    }
    let c = self.src.at(i).to_int()
    if c == '"'.to_int() {
      self.i = i + 1
      return out.to_string()
    }
    if c == '\\'.to_int() {
      let next = if i + 1 < self.src.length() {
        self.src.at(i + 1).to_int()
      } else {
        -1
      }
      match next {
        0x6E => out.write_char('\n') // n
        0x72 => out.write_char('\r') // r
        0x74 => out.write_char('\t') // t
        0x61 => out.write_char('\u{07}') // a
        0x62 => out.write_char('\u{08}') // b
        0x66 => out.write_char('\u{0C}') // f
        0x76 => out.write_char('\u{0B}') // v
        0x5C => out.write_char('\\') // backslash
        0x22 => out.write_char('"') // "
        0x27 => out.write_char('\'') // '
        -1 => raise Unclosed(at=self.spot(start))
        _ => {
          // `\$` stays escaped for the expansion pass; anything else keeps both
          // characters, because a backslash the file did not mean as an escape
          // is part of the value.
          out.write_char('\\')
          out.write_char(next.unsafe_to_char())
        }
      }
      i += 2
      continue
    }
    out.write_char(c.unsafe_to_char())
    i += 1
  }
  out.to_string()
}

///|
/// After a value: only spaces, then a comment or the end of the line.
fn Reader::tail(self : Reader) -> Unit raise Refused {
  self.skip_space()
  let c = self.here()
  if c == '#'.to_int() {
    self.to_eol()
    return
  }
  if c == -1 || is_newline(c) {
    return
  }
  let start = self.i
  self.to_eol()
  raise Trailing(at=self.spot(start), got=self.src[start:self.i].to_owned())
}

///|
/// Read a `.env` text into its assignments, in file order.
///
/// The grammar is the one every `.env` reader shares: `KEY=VALUE`, an optional
/// `export` in front, `#` starting a comment on its own line, single quotes for
/// a value taken exactly as written, double quotes for one whose escapes are
/// decoded, and a quoted value that may run over several lines. A name with no
/// `=` is an empty value, as it is in the shell. `#` inside an unquoted value is
/// part of the value, also as it is in the shell.
///
/// Values come back as written, apart from quotes and escapes. Expansion is
/// [`load`]'s job, because it needs the entries above the one it is reading.
pub fn parse(
  text : StringView,
  source~ : String = "",
) -> Array[Entry] raise Refused {
  ignore(source)
  if text.length() > limit {
    raise TooDeep(at={ at: 0, line: 1, column: 1, }, limit~)
  }
  let reader : Reader = { src: text, i: 0, }
  let out = []
  let mut first = true
  while reader.i < text.length() {
    // A byte-order mark at the very start is not part of the first name.
    if first && reader.here() == 0xFEFF {
      reader.i += 1
    }
    first = false
    reader.skip_space()
    if reader.here() == -1 {
      break
    }
    if is_newline(reader.here()) {
      reader.skip_break()
      continue
    }
    if reader.here() == '#'.to_int() {
      reader.to_eol()
      reader.skip_break()
      continue
    }
    let start = reader.i
    // `export FOO=1` and `export<TAB>FOO=1` mean the same as `FOO=1`.
    if reader.at(reader.i) == 'e'.to_int() &&
      reader.at(reader.i + 1) == 'x'.to_int() &&
      reader.at(reader.i + 2) == 'p'.to_int() &&
      reader.at(reader.i + 3) == 'o'.to_int() &&
      reader.at(reader.i + 4) == 'r'.to_int() &&
      reader.at(reader.i + 5) == 't'.to_int() &&
      is_space(reader.at(reader.i + 6)) {
      reader.i += 6
      reader.skip_space()
    }
    let name_from = reader.i
    let name_to = reader.name_end(name_from)
    let key = reader.src[name_from:name_to].to_owned()
    if !is_name(key) {
      raise BadName(at=reader.spot(name_from), got=key)
    }
    reader.i = name_to
    reader.skip_space()
    let mut value = ""
    let mut quoted = false
    if reader.here() == '='.to_int() {
      reader.i += 1
      reader.skip_space()
      match reader.here() {
        0x27 => {
          value = reader.single_quoted()
          quoted = true
          reader.tail()
        }
        0x22 => {
          value = reader.double_quoted()
          reader.tail()
        }
        _ => {
          let from = reader.i
          reader.to_eol()
          let mut to = reader.i
          // Unquoted values lose the spaces before the line ending, and keep
          // everything else, `#` included.
          while to > from && is_space(reader.at(to - 1)) {
            to -= 1
          }
          value = reader.src[from:to].to_owned()
        }
      }
    } else if reader.here() != -1 && !is_newline(reader.here()) {
      // A name followed by something that is neither `=` nor the end of the
      // line: the shell would try to run it, and this reader says so.
      let from = reader.i
      reader.to_eol()
      raise Trailing(
        at=reader.spot(from),
        got=reader.src[from:reader.i].to_owned(),
      )
    }
    out.push({ key, value, quoted, at: reader.spot(start), })
    reader.skip_space()
    if reader.here() == '#'.to_int() {
      reader.to_eol()
    }
    reader.skip_break()
  }
  out
}

///|
/// Read a `.env` text into the variables it sets, expanding references against
/// the entries above them.
///
/// A later assignment wins over an earlier one, and a reference sees the value
/// the name had at the point it was written — the order in the file is the order
/// of evaluation, which is what makes `PATH=${PATH}:/opt/bin` work.
///
/// A single-quoted value is taken exactly as written, so it is neither expanded
/// nor escaped; that is the way to keep a `${…}` for something else to fill in.
pub fn load(
  text : StringView,
  vars? : @expand.Vars,
  knobs? : Knobs,
  source~ : String = "",
) -> Map[String, String] raise Refused {
  let knobs = knobs.unwrap_or(interpolated)
  let entries = parse(text, source~)
  let table : Map[String, String] = Map([])
  let vars = vars.unwrap_or(@expand.Vars::of_map(table))
  for entry in entries {
    let value = if knobs.interpolate && !entry.quoted {
      @expand.expand(entry.value[:], vars, knobs=@expand.lenient) catch {
        refused => raise Expand(why=refused.to_string(), at=entry.at)
      }
    } else {
      entry.value
    }
    table.set(entry.key, value)
    vars.write(entry.key, value) |> ignore
  }
  table
}

///|
/// Write the entries back as a `.env` text.
///
/// A value that a reader would otherwise split or decode is quoted; a value that
/// holds nothing special is written bare, because a file a person reads is the
/// point of the format.
pub fn dumps(entries : Array[Entry]) -> String {
  let out = StringBuilder()
  for entry in entries {
    out.write_string(entry.key)
    out.write_char('=')
    out.write_string(quote(entry.value))
    out.write_char('\n')
  }
  out.to_string()
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
      '$' => out.write_string("\\$")
      _ => out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// The file as the shared tree: one mapping of names to values, with references
/// resolved as [`load`] resolves them.
pub fn tree(
  text : StringView,
  vars? : @expand.Vars,
  knobs? : Knobs,
  source~ : String = "",
) -> @moonconf.Node raise Refused {
  let entries = parse(text, source~)
  let table = @moonconf.Table::new()
  let vars = vars.unwrap_or(@expand.Vars::of_map(Map([])))
  for entry in entries {
    let value = if knobs.unwrap_or(interpolated).interpolate && !entry.quoted {
      @expand.expand(entry.value[:], vars, knobs=@expand.lenient) catch {
        refused => raise Expand(why=refused.to_string(), at=entry.at)
      }
    } else {
      entry.value
    }
    vars.write(entry.key, value) |> ignore
    table.set(entry.key, @moonconf.Node::str(value, source))
  }
  @moonconf.Node::new(@moonconf.Value::Map(table), source, @moonconf.start)
}
