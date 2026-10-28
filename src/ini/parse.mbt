// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A section while it is being read.
priv struct Build {
  name : String
  at : At
  options : Array[Entry]
}

///|
fn is_space(c : Int32) -> Bool {
  c == ' '.to_int() || c == '\t'.to_int()
}

///|
fn is_break(c : Int32) -> Bool {
  c == '\n'.to_int() || c == '\r'.to_int()
}

///|
fn contains(text : String, c : Int32) -> Bool {
  let view = text[:]
  let mut i = 0
  while i < view.length() {
    if view.at(i).to_int() == c {
      return true
    }
    i += 1
  }
  false
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
/// `text` without the spaces at either end.
fn trimmed(text : String) -> String {
  let view = text[:]
  let mut from = 0
  let mut to = view.length()
  while from < to && is_space(view.at(from).to_int()) {
    from += 1
  }
  while to > from && is_space(view.at(to - 1).to_int()) {
    to -= 1
  }
  view[from:to].to_owned()
}

///|
/// The name with its case folded as the knobs ask.
fn folded(name : String, knobs : Knobs) -> String {
  match knobs.case {
    Lower => name.to_lower()
    Upper => name.to_upper()
    Preserve => name
  }
}

///|
/// The index of the first of `chars` in `text[from:to)`, or nothing.
fn index_of(
  text : StringView,
  chars : String,
  from : Int32,
  to : Int32,
) -> Int32? {
  let mut i = from
  while i < to {
    if contains(chars, text.at(i).to_int()) {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// Cut an inline comment: the first character of `chars` that has whitespace
/// before it ends the value.
fn cut_comment(
  text : StringView,
  from : Int32,
  to : Int32,
  chars : String,
) -> Int32 {
  if chars == "" {
    return to
  }
  let mut i = from
  while i < to {
    if contains(chars, text.at(i).to_int()) &&
      i > from &&
      is_space(text.at(i - 1).to_int()) {
      return i
    }
    i += 1
  }
  to
}

///|
/// Find the section called `name`, or nothing.
fn Doc::index_of(self : Doc, name : String) -> Int32? {
  let mut i = 0
  while i < self.sections.length() {
    if self.sections[i].name == name {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// Read an INI text.
///
/// Section headers stand at the start of a line; an option is a name, a
/// delimiter, and a value; a line that starts with whitespace continues the
/// value above it, joined with a newline, which is how a value spans lines in
/// every file that has ever had a long one. A comment is a line of its own,
/// starting with `#` or `;`, and by default a `#` after a value is part of the
/// value.
///
/// Options before the first header are refused rather than collected into a
/// section nobody named: a file has a section, and a reader that invents one
/// hides the missing line.
pub fn parse(text : StringView, knobs? : Knobs) -> Doc raise Refused {
  let knobs = knobs.unwrap_or(standard)
  let builders : Array[Build] = []
  let mut i = 0
  let mut blanks = 0
  let length = text.length()
  // The index of the option a continuation line belongs to, if any.
  let mut last : (Int32, Int32)? = None
  while i < length {
    let from = i
    while i < length && !is_break(text.at(i).to_int()) {
      i += 1
    }
    let to = i
    // Past the line ending, whichever kind it is.
    if i < length && text.at(i).to_int() == '\r'.to_int() {
      i += 1
      if i < length && text.at(i).to_int() == '\n'.to_int() {
        i += 1
      }
    } else if i < length {
      i += 1
    }
    let line = text[from:to]
    let bare = trimmed(line.to_owned())
    let blank = bare == ""
    let indented = from < to && is_space(line.at(0).to_int())
    if blank {
      if knobs.empty_lines_in_values && last is Some(_) {
        blanks += 1
      } else {
        last = None
        blanks = 0
      }
      continue
    }
    if contains(knobs.comment, bare[:].at(0).to_int()) {
      // A comment line ends the value above it, but does not clear the option a
      // later indented line might continue: comments between continuation lines
      // are how a person annotates a long value.
      continue
    }
    if bare[:].at(0).to_int() == '['.to_int() && (!indented || last is None) {
      let close = index_of(line, "]", 0, to - from)
      let end = match close {
        Some(index) => index
        None => raise BadSection(at=spot(text, from), got=bare)
      }
      let name = trimmed(line[1:end].to_owned())
      if name == "" {
        raise BadSection(at=spot(text, from), got=bare)
      }
      let rest = trimmed(line[end + 1:].to_owned())
      if rest != "" && !contains(knobs.comment, rest[:].at(0).to_int()) {
        raise BadSection(at=spot(text, from), got=bare)
      }
      match section_index(builders, name) {
        Some(_) =>
          if knobs.strict {
            raise DuplicateSection(at=spot(text, from), name~)
          }
        None => builders.push({ name, at: spot(text, from), options: [], })
      }
      last = None
      blanks = 0
      continue
    }
    if builders.length() == 0 {
      raise MissingSection(at=spot(text, from))
    }
    // An indented line continues the option above it. An indented line with no
    // option above it is an option written with an indent, which is how half the
    // files in the wild are written.
    if indented && last is Some(_) {
      match last {
        None => ()
        Some((section, option)) => {
          let build = builders[section]
          let before = build.options[option]
          let value = StringBuilder()
          value.write_string(before.value)
          value.write_char('\n')
          let mut padding = 0
          while padding < blanks {
            value.write_char('\n')
            padding += 1
          }
          value.write_string(bare)
          build.options[option] = { ..before, value: value.to_string(), }
          blanks = 0
          continue
        }
      }
    }
    blanks = 0
    let section = builders.length() - 1
    let delimiter = index_of(line, knobs.delimiters, 0, to - from)
    let (name, value) = match delimiter {
      Some(index) => {
        let name = trimmed(line[0:index].to_owned())
        let width = to - from
        let mut value_to = cut_comment(
          line,
          index + 1,
          width,
          knobs.inline_comment,
        )
        while value_to > index + 1 && is_space(line.at(value_to - 1).to_int()) {
          value_to -= 1
        }
        let mut value_from = index + 1
        while value_from < value_to && is_space(line.at(value_from).to_int()) {
          value_from += 1
        }
        (name, line[value_from:value_to].to_owned())
      }
      None =>
        if knobs.allow_no_value {
          (bare, "")
        } else {
          raise BadLine(at=spot(text, from), got=bare)
        }
    }
    if name == "" {
      raise BadLine(at=spot(text, from), got=bare)
    }
    let option = { name: folded(name, knobs), value, at: spot(text, from), }
    let build = builders[section]
    match entry_index(build.options, option.name) {
      Some(index) =>
        if knobs.strict {
          raise DuplicateOption(at=spot(text, from), name=option.name)
        } else {
          build.options[index] = option
          last = Some((section, index))
        }
      None => {
        build.options.push(option)
        last = Some((section, build.options.length() - 1))
      }
    }
  }
  // The default section goes to the front so that a document written back keeps
  // the shape a person wrote.
  let sections : Array[Section] = []
  let mut defaults : Section? = None
  for build in builders {
    if build.name == knobs.default_section {
      defaults = Some({
        name: build.name,
        options: build.options,
        at: build.at,
      })
    } else {
      sections.push({ name: build.name, options: build.options, at: build.at, })
    }
  }
  let ordered = match defaults {
    Some(section) => {
      let out = [section]
      for section in sections {
        out.push(section)
      }
      out
    }
    None => sections
  }
  { sections: ordered, knobs, }
}

///|
fn section_index(builds : Array[Build], name : String) -> Int32? {
  let mut i = 0
  while i < builds.length() {
    if builds[i].name == name {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn entry_index(options : Array[Entry], name : String) -> Int32? {
  let mut i = 0
  while i < options.length() {
    if options[i].name == name {
      return Some(i)
    }
    i += 1
  }
  None
}
