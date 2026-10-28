// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The names of the sections, in the order they were written.
///
/// The default section is not among them: it is where every section falls back
/// to, not a section a program reads on its own.
pub fn Doc::sections(self : Doc) -> Array[String] {
  let out = []
  for section in self.sections {
    if section.name != self.knobs.default_section {
      out.push(section.name)
    }
  }
  out
}

///|
/// Whether the document has that section.
pub fn Doc::has_section(self : Doc, name : String) -> Bool {
  self.index_of(name) is Some(_)
}

///|
/// The names a section answers to, in the order they were written: its own
/// options, then the defaults it inherits and does not override.
///
/// The defaults are in the list because they are what a lookup finds; a reader
/// that listed only the lines under the header would hide half the settings a
/// program can read.
pub fn Doc::options(
  self : Doc,
  section : String,
) -> Array[String] raise Refused {
  match self.index_of(section) {
    Some(index) => {
      let out = []
      for option in self.sections[index].options {
        out.push(option.name)
      }
      match self.index_of(self.knobs.default_section) {
        Some(defaults) =>
          for option in self.sections[defaults].options {
            if !out.contains(option.name) {
              out.push(option.name)
            }
          }
        None => ()
      }
      out
    }
    None => raise NoSection(section~)
  }
}

///|
/// The value as written, without interpolation.
pub fn Doc::raw(
  self : Doc,
  section : String,
  option : String,
) -> String? raise Refused {
  let name = folded(option, self.knobs)
  let index = match self.index_of(section) {
    Some(index) => index
    None => raise NoSection(section~)
  }
  match entry_index(self.sections[index].options, name) {
    Some(found) => Some(self.sections[index].options[found].value)
    None =>
      match self.index_of(self.knobs.default_section) {
        Some(defaults) =>
          match entry_index(self.sections[defaults].options, name) {
            Some(found) => Some(self.sections[defaults].options[found].value)
            None => None
          }
        None => None
      }
  }
}

///|
/// The value, with its references resolved.
///
/// The lookup order is the one every INI reader shares: the section named, then
/// the default section. A name in neither is [`NoOption`], and a reference to a
/// name in neither is an [`Interpolation`] refusal naming the reference, because
/// the two mistakes are different: one is a setting that was never written, the
/// other is a setting written in a way that points at nothing.
pub fn Doc::get(
  self : Doc,
  section : String,
  option : String,
) -> String raise Refused {
  let name = folded(option, self.knobs)
  if self.index_of(section) is None {
    raise NoSection(section~)
  }
  match self.raw(section, name) {
    Some(value) => self.resolve(section, value, 0)
    None => raise NoOption(section~, option=name)
  }
}

///|
/// The value, with a fallback for a name that is not there.
pub fn Doc::get_or(
  self : Doc,
  section : String,
  option : String,
  default : String,
) -> String raise Refused {
  match self.raw(section, option) {
    Some(value) => self.resolve(section, value, 0)
    None => default
  }
}

///|
/// Whether the name has a value, in the section or in the defaults.
pub fn Doc::has_option(self : Doc, section : String, option : String) -> Bool {
  let name = folded(option, self.knobs)
  match self.index_of(section) {
    Some(index) =>
      if entry_index(self.sections[index].options, name) is Some(_) {
        true
      } else {
        match self.index_of(self.knobs.default_section) {
          Some(defaults) =>
            entry_index(self.sections[defaults].options, name) is Some(_)
          None => false
        }
      }
    None => false
  }
}

///|
/// One value with its references resolved.
fn Doc::resolve(
  self : Doc,
  section : String,
  value : String,
  level : Int32,
) -> String raise Refused {
  if level > depth {
    raise TooDeep(at={ at: 0, line: 1, column: 1, }, limit=depth)
  }
  match self.knobs.interp {
    None_ => value
    Basic => self.basic(section, value, level)
    Extended => self.extended(section, value, level)
  }
}

///|
/// `%(name)s`, taken from the section then the defaults, and `%%` for a percent
/// sign.
fn Doc::basic(
  self : Doc,
  section : String,
  value : String,
  level : Int32,
) -> String raise Refused {
  let out = StringBuilder()
  let view = value[:]
  let mut i = 0
  while i < view.length() {
    let c = view.at(i).to_int()
    if c != '%'.to_int() {
      out.write_char(c.unsafe_to_char())
      i += 1
      continue
    }
    if i + 1 < view.length() && view.at(i + 1).to_int() == '%'.to_int() {
      out.write_char('%')
      i += 2
      continue
    }
    if i + 1 < view.length() && view.at(i + 1).to_int() == '('.to_int() {
      let mut end = i + 2
      while end < view.length() && view.at(end).to_int() != ')'.to_int() {
        end += 1
      }
      if end + 1 < view.length() && view.at(end + 1).to_int() == 's'.to_int() {
        let name = view[i + 2:end].to_owned()
        match self.raw(section, name) {
          Some(inner) =>
            out.write_string(self.resolve(section, inner, level + 1))
          None =>
            raise Interpolation(why="no " + name + " in [" + section + "]", at={
              at: 0,
              line: 1,
              column: 1,
            })
        }
        i = end + 2
        continue
      }
    }
    raise Interpolation(why="a % must be %% or %(name)s", at={
      at: 0,
      line: 1,
      column: 1,
    })
  }
  out.to_string()
}

///|
/// `${name}` and `${section:name}`, and `$$` for a dollar sign.
fn Doc::extended(
  self : Doc,
  section : String,
  value : String,
  level : Int32,
) -> String raise Refused {
  let out = StringBuilder()
  let view = value[:]
  let mut i = 0
  while i < view.length() {
    let c = view.at(i).to_int()
    if c != '$'.to_int() {
      out.write_char(c.unsafe_to_char())
      i += 1
      continue
    }
    if i + 1 < view.length() && view.at(i + 1).to_int() == '$'.to_int() {
      out.write_char('$')
      i += 2
      continue
    }
    if i + 1 < view.length() && view.at(i + 1).to_int() == '{'.to_int() {
      let mut end = i + 2
      while end < view.length() && view.at(end).to_int() != '}'.to_int() {
        end += 1
      }
      if end >= view.length() {
        raise Interpolation(why="a ${ is never closed", at={
          at: 0,
          line: 1,
          column: 1,
        })
      }
      let body = view[i + 2:end].to_owned()
      let (from, name) = match body[:].find(":") {
        Some(colon) => (body[:colon].to_owned(), body[colon + 1:].to_owned())
        None => (section, body)
      }
      match self.raw(from, name) {
        Some(inner) => out.write_string(self.resolve(from, inner, level + 1))
        None =>
          raise Interpolation(why="no " + name + " in [" + from + "]", at={
            at: 0,
            line: 1,
            column: 1,
          })
      }
      i = end + 1
      continue
    }
    raise Interpolation(why="a $ must be $$ or ${name}", at={
      at: 0,
      line: 1,
      column: 1,
    })
  }
  out.to_string()
}

///|
/// Write the document back.
///
/// Values are written as they were read, so a file that is parsed and written
/// again keeps the references it had: interpolation belongs to reading, and a
/// writer that resolved it would turn a file a person can follow into one whose
/// lines no longer say where a value came from.
pub fn dumps(doc : Doc) -> String {
  let out = StringBuilder()
  let mut first = true
  for section in doc.sections {
    if !first {
      out.write_char('\n')
    }
    first = false
    out.write_char('[')
    out.write_string(section.name)
    out.write_string("]\n")
    for option in section.options {
      out.write_string(option.name)
      out.write_string(" = ")
      out.write_string(option.value)
      out.write_char('\n')
    }
  }
  out.to_string()
}

///|
/// The document as the shared tree: one mapping per section, with the defaults
/// folded into every section that does not override them.
///
/// The values are interpolated, because a caller taking the tree is taking the
/// answers rather than the lines. A file that refers to another value is a file
/// that means the value it refers to.
pub fn Doc::tree(
  self : Doc,
  source~ : String = "",
) -> @moonconf.Node raise Refused {
  let root = @moonconf.Table::new()
  for name in self.sections() {
    let section = @moonconf.Table::new()
    for option in self.options(name) {
      section.set(option, @moonconf.Node::str(self.get(name, option), source))
    }
    root.set(
      name,
      @moonconf.Node::new(
        @moonconf.Value::Map(section),
        source,
        @moonconf.start,
      ),
    )
  }
  @moonconf.Node::new(@moonconf.Value::Map(root), source, @moonconf.start)
}
