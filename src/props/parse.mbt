// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The pairs in the order they were read, with a repeated name kept once, at the
/// position it first held and with the value that won.
fn Doc::distinct(self : Doc) -> Array[Pair] {
  let out : Array[Pair] = []
  for pair in self.pairs {
    let mut at = -1
    let mut i = 0
    while i < out.length() {
      if out[i].key == pair.key {
        at = i
      }
      i += 1
    }
    if at >= 0 {
      out[at] = { ..pair, at: out[at].at, }
    } else {
      out.push(pair)
    }
  }
  out
}

///|
/// The value of `key`, or nothing.
pub fn Doc::get(self : Doc, key : String) -> String? {
  let mut found = None
  for pair in self.pairs {
    if pair.key == key {
      found = Some(pair.value)
    }
  }
  found
}

///|
/// Whether `key` is in the file.
pub fn Doc::has(self : Doc, key : String) -> Bool {
  self.get(key) is Some(_)
}

///|
/// The names, once each, in the order they first appear.
pub fn Doc::keys(self : Doc) -> Array[String] {
  self.distinct().map(fn(pair) { pair.key })
}

///|
/// The pairs as a reader would see them: once each, later value winning.
pub fn Doc::items(self : Doc) -> Array[(String, String)] {
  self.distinct().map(fn(pair) { (pair.key, pair.value) })
}

///|
fn is_space(c : Int32) -> Bool {
  c == ' '.to_int() ||
  c == '\t'.to_int() ||
  c == '\f'.to_int() ||
  c == '\n'.to_int() ||
  c == '\r'.to_int()
}

///|
fn is_break(c : Int32) -> Bool {
  c == '\n'.to_int() || c == '\r'.to_int()
}

///|
fn spot(text : StringView, index : Int32) -> At {
  let mut line = 1
  let mut column = 1
  let mut i = 0
  while i < index && i < text.length() {
    if text.at(i).to_int() == 0x0A {
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
/// One escape, decoded: the character it stands for, and how many characters it
/// took.
fn decode(
  text : StringView,
  from : Int32,
  at : At,
) -> (Char, Int32) raise Refused {
  if from >= text.length() {
    raise BadEscape(at~, got="")
  }
  let c = text.at(from).to_int()
  match c {
    0x74 => ('\t', 2) // t
    0x6E => ('\n', 2) // n
    0x72 => ('\r', 2) // r
    0x66 => ('\u{0C}', 2) // f
    0x75 => {
      // u, then exactly four hex digits.
      let mut value = 0
      let mut i = 0
      while i < 4 {
        if from + 1 + i >= text.length() {
          raise BadEscape(at~, got=text[from:text.length()].to_owned())
        }
        let digit = match hex(text.at(from + 1 + i).to_int()) {
          Some(digit) => digit
          None =>
            raise BadEscape(at~, got=text[from:from + 1 + i + 1].to_owned())
        }
        value = value * 16 + digit
        i += 1
      }
      (value.unsafe_to_char(), 6)
    }
    _ => (c.unsafe_to_char(), 2)
  }
}

///|
/// A raw run of text with its escapes decoded.
fn unescape(raw : StringView, at : At) -> String raise Refused {
  let out = StringBuilder()
  let mut i = 0
  while i < raw.length() {
    let c = raw.at(i).to_int()
    if c != '\\'.to_int() {
      out.write_char(c.unsafe_to_char())
      i += 1
      continue
    }
    let (decoded, width) = decode(raw, i + 1, at)
    out.write_char(decoded)
    i += width
  }
  out.to_string()
}

///|
/// The number of backslashes at the end of `text[from:to)`.
fn trailing_backslashes(text : StringView, from : Int32, to : Int32) -> Int32 {
  let mut count = 0
  let mut i = to
  while i > from && text.at(i - 1).to_int() == '\\'.to_int() {
    count += 1
    i -= 1
  }
  count
}

///|
/// Read a properties text into its pairs.
///
/// The grammar is `java.util.Properties`': a key, a separator that may be `=`,
/// `:` or whitespace, and a value; `#` or `!` starting a comment line; a line
/// that ends in an odd number of backslashes continuing on the next; and
/// `\uXXXX` for a character the encoding cannot carry.
///
/// A continuation joins with no character between the halves, and the leading
/// whitespace of the continued line is dropped, which is what makes a long value
/// wrap without changing.
pub fn parse(text : StringView) -> Doc raise Refused {
  let pairs : Array[Pair] = []
  let mut i = 0
  let length = text.length()
  while i < length {
    let start = i
    // One natural line.
    while i < length && !is_break(text.at(i).to_int()) {
      i += 1
    }
    let line_to = i
    if i < length && text.at(i).to_int() == '\r'.to_int() {
      i += 1
      if i < length && text.at(i).to_int() == '\n'.to_int() {
        i += 1
      }
    } else if i < length {
      i += 1
    }
    // A logical line: continuation while the line ends in an odd number of
    // backslashes.
    let logical = StringBuilder()
    let mut first_from = start
    let mut first_to = line_to
    while trailing_backslashes(text, first_from, first_to) % 2 == 1 {
      logical.write_string(text[first_from:first_to - 1].to_owned())
      if i >= length {
        raise Truncated(at=spot(text, start))
      }
      let next_from = i
      while i < length && !is_break(text.at(i).to_int()) {
        i += 1
      }
      let next_to = i
      if i < length && text.at(i).to_int() == '\r'.to_int() {
        i += 1
        if i < length && text.at(i).to_int() == '\n'.to_int() {
          i += 1
        }
      } else if i < length {
        i += 1
      }
      // The whitespace at the front of a continued line is not part of the value.
      let mut from = next_from
      while from < next_to && is_space(text.at(from).to_int()) {
        from += 1
      }
      first_from = from
      first_to = next_to
    }
    logical.write_string(text[first_from:first_to].to_owned())
    let line = logical.to_string()
    let view = line[:]
    // A blank line, or a comment.
    let mut scan = 0
    while scan < view.length() && is_space(view.at(scan).to_int()) {
      scan += 1
    }
    if scan >= view.length() {
      continue
    }
    let lead = view.at(scan).to_int()
    if lead == '#'.to_int() || lead == '!'.to_int() {
      continue
    }
    // The key starts at the first character that is not whitespace: a line may
    // be indented, and the indent is not part of the name.
    let mut key_to = scan
    let mut separator = 0
    let mut stop = false
    while key_to < view.length() && !stop {
      let c = view.at(key_to).to_int()
      if c == '\\'.to_int() {
        key_to += 2
        continue
      }
      if c == '='.to_int() || c == ':'.to_int() || is_space(c) {
        separator = c
        stop = true
        continue
      }
      key_to += 1
    }
    if key_to > view.length() {
      key_to = view.length()
    }
    let at = spot(text, start)
    let key = unescape(view[scan:key_to], at)
    let mut value_from = key_to
    if stop {
      // Past the separator, then any whitespace, then a second `=` or `:` after
      // whitespace, then whitespace again.
      value_from += 1
      if is_space(separator) {
        while value_from < view.length() &&
              is_space(view.at(value_from).to_int()) {
          value_from += 1
        }
        if value_from < view.length() {
          let c = view.at(value_from).to_int()
          if c == '='.to_int() || c == ':'.to_int() {
            value_from += 1
          }
        }
      }
      while value_from < view.length() && is_space(view.at(value_from).to_int()) {
        value_from += 1
      }
    }
    let value = unescape(view[value_from:view.length()], at)
    pairs.push({ key, value, at, })
  }
  { pairs, }
}

///|
/// Read a properties file from bytes, as `load(InputStream)` does: ISO-8859-1,
/// one byte to one character, with `\uXXXX` for everything else.
pub fn load(bytes : BytesView) -> Doc raise Refused {
  let out = StringBuilder()
  let mut i = 0
  while i < bytes.length() {
    let byte = bytes.at(i).to_int() & 0xFF
    out.write_char(byte.unsafe_to_char())
    i += 1
  }
  parse(out.to_string()[:])
}

///|
/// Write the pairs back, as `store` does: one `key=value` per line, escapes for
/// everything outside printable ASCII, and a `#` comment first when there is one.
///
/// The pairs are written in the order they were read, once each, which is what a
/// person diffing two files wants; the writer this follows writes them in hash
/// order, which is not an order at all.
pub fn dumps(doc : Doc, comment? : String) -> String {
  let out = StringBuilder()
  match comment {
    Some(text) =>
      for line in text.split("\n") {
        out.write_char('#')
        out.write_stringview(line)
        out.write_char('\n')
      }
    None => ()
  }
  for pair in doc.distinct() {
    out.write_string(escape(pair.key, true))
    out.write_char('=')
    out.write_string(escape(pair.value, false))
    out.write_char('\n')
  }
  out.to_string()
}

///|
/// A name or a value as a properties file carries it.
fn escape(text : String, key : Bool) -> String {
  let out = StringBuilder()
  let view = text[:]
  let mut i = 0
  while i < view.length() {
    let code = view.at(i).to_int()
    let c = code.unsafe_to_char()
    if code == '\\'.to_int() {
      out.write_string("\\\\")
    } else if code == '\t'.to_int() {
      out.write_string("\\t")
    } else if code == '\n'.to_int() {
      out.write_string("\\n")
    } else if code == '\r'.to_int() {
      out.write_string("\\r")
    } else if code == '\u{0C}'.to_int() {
      out.write_string("\\f")
    } else if code == ' '.to_int() {
      if i == 0 || key {
        out.write_char('\\')
      }
      out.write_char(' '.to_int().unsafe_to_char())
    } else if code == '='.to_int() ||
      code == ':'.to_int() ||
      code == '#'.to_int() ||
      code == '!'.to_int() {
      out.write_char('\\')
      out.write_char(c)
    } else if code < 0x20 || code > 0x7E {
      out.write_string("\\u")
      let mut shift = 12
      while shift >= 0 {
        let digit = (code >> shift) & 0xF
        out.write_char(
          if digit < 10 {
            ('0'.to_int() + digit).unsafe_to_char()
          } else {
            ('A'.to_int() + digit - 10).unsafe_to_char()
          },
        )
        shift -= 4
      }
    } else {
      out.write_char(c)
    }
    i += 1
  }
  out.to_string()
}

///|
/// The file as the shared tree: one mapping of names to values.
///
/// Properties has no sections and no nesting of its own; a name with dots in it
/// is one name, not a path, because that is what the format says. A caller who
/// wants the dots read as nesting has a path to ask for in the layer above.
pub fn Doc::tree(self : Doc, source~ : String = "") -> @moonconf.Node {
  let table = @moonconf.Table::new()
  for pair in self.distinct() {
    table.set(pair.key, @moonconf.Node::str(pair.value, source))
  }
  @moonconf.Node::new(@moonconf.Value::Map(table), source, @moonconf.start)
}
