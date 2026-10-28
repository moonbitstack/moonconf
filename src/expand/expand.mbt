// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a reference to a variable that has no value means.
pub(all) enum Unset {
  /// A reference to nothing is an error. The default, and what `set -u` does:
  /// a missing setting is nearly always the bug, and a diagnostic at the point
  /// of use beats an empty string threaded through the program.
  Fail
  /// A missing variable reads as the empty string. What a shell does without
  /// `set -u`, and what most configuration loaders do.
  Empty
  /// A missing variable leaves the reference as written, `${A}`, so a later
  /// stage can fill it in.
  Keep
} derive(Eq, Debug)

///|
pub extend Unset with Eq::{equal, not_equal}

///|
pub extend Unset with Debug::{to_repr}

///|
/// How far to expand.
pub(all) struct Knobs {
  /// What a reference to a variable with no value means.
  unset : Unset
} derive(Eq, Debug)

///|
pub extend Knobs with Eq::{equal, not_equal}

///|
pub extend Knobs with Debug::{to_repr}

///|
/// A reference to an unset variable is an error.
pub let strict : Knobs = { unset: Fail, }

///|
/// A reference to an unset variable reads as empty.
pub let lenient : Knobs = { unset: Empty, }

///|
/// A reference to an unset variable is left as written.
pub let deferred : Knobs = { unset: Keep, }

///|
/// The limit on nested forms. `${A:-${B:-${C}}}` is three; a text that nests
/// itself a thousand times is a mistake, and the recursion has to stop
/// somewhere short of the stack.
pub let depth : Int32 = 32

///|
/// The variables a text may refer to, and where `${A:=b}` writes.
///
/// Reading is one function and writing is another rather than a map, because
/// the thing a caller has is usually not a map: the process environment cannot
/// be written, a layered configuration writes to its override layer, and a test
/// writes to a small table. A `Vars` with no `set` is read-only, and an
/// assignment through it is refused rather than dropped.
pub(all) struct Vars {
  /// The value of a variable, or nothing when it has none.
  get : (String) -> String?
  /// Where an assignment goes, when there is anywhere to put it.
  set : ((String, String) -> Unit)?
}

///|
/// The variables of a function, which cannot be assigned to.
pub fn Vars::of(get : (String) -> String?) -> Vars {
  { get, set: None, }
}

///|
/// The variables of a function, which an assignment also updates.
pub fn Vars::writing(
  get : (String) -> String?,
  set : (String, String) -> Unit,
) -> Vars {
  { get, set: Some(set), }
}

///|
/// The entries of a map, which an assignment updates.
pub fn Vars::of_map(entries : Map[String, String]) -> Vars {
  {
    get: fn(name) { entries.get(name) },
    set: Some(fn(name, value) { entries.set(name, value) }),
  }
}

///|
/// The value of `name`, or nothing.
pub fn Vars::lookup(self : Vars, name : String) -> String? {
  (self.get)(name)
}

///|
/// Write `name`, answering whether there was anywhere to write it.
pub fn Vars::write(self : Vars, name : String, value : String) -> Bool {
  match self.set {
    Some(write) => {
      write(name, value)
      true
    }
    None => false
  }
}

///|
/// No variables at all.
pub fn Vars::none() -> Vars {
  { get: fn(_) { None }, set: None, }
}

///|
priv struct Reader {
  src : StringView
  vars : Vars
  knobs : Knobs
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
/// Whether `c` can start a name.
fn starts_name(c : Int32) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  c == '_'.to_int()
}

///|
/// Whether `c` can continue a name.
fn continues_name(c : Int32) -> Bool {
  starts_name(c) || (c >= '0'.to_int() && c <= '9'.to_int())
}

///|
/// A name is a letter or an underscore followed by letters, digits, underscores.
fn is_name(name : String) -> Bool {
  let view = name[:]
  if view.length() == 0 || !starts_name(view.at(0).to_int()) {
    return false
  }
  let mut i = 1
  while i < view.length() {
    if !continues_name(view.at(i).to_int()) {
      return false
    }
    i += 1
  }
  true
}

///|
/// The index of the `}` that closes the expansion opened just before `from`,
/// or nothing when the text ends first.
fn Reader::close_of(self : Reader, from : Int32, to : Int32) -> Int32? {
  let mut open_count = 1
  let mut i = from
  while i < to {
    let c = self.src.at(i).to_int()
    if c == '$'.to_int() &&
      i + 1 < to &&
      self.src.at(i + 1).to_int() == '{'.to_int() {
      open_count += 1
      i += 2
      continue
    }
    if c == '}'.to_int() {
      open_count -= 1
      if open_count == 0 {
        return Some(i)
      }
    }
    i += 1
  }
  None
}

///|
/// The value of a variable, or what the policy says to do about its absence.
fn Reader::value_or(
  self : Reader,
  name : String,
  open : Int32,
  close : Int32,
  out : StringBuilder,
) -> String? raise Refused {
  match self.vars.lookup(name) {
    Some(value) => Some(value)
    None =>
      match self.knobs.unset {
        Fail => raise Undefined(name~, at=self.spot(open))
        Empty => Some("")
        Keep => {
          out.write_string(self.src[open:close].to_owned())
          None
        }
      }
  }
}

///|
/// Expand `text[from:to]` into `out`.
fn Reader::run(
  self : Reader,
  from : Int32,
  to : Int32,
  level : Int32,
  out : StringBuilder,
) -> Unit raise Refused {
  if level > depth {
    raise TooDeep(at=self.spot(from), limit=depth)
  }
  let mut i = from
  while i < to {
    let c = self.src.at(i).to_int()
    if c == '\\'.to_int() {
      if i + 1 < to {
        let next = self.src.at(i + 1).to_int()
        if next == '$'.to_int() ||
          next == '\\'.to_int() ||
          next == '"'.to_int() ||
          next == '`'.to_int() {
          out.write_char(next.unsafe_to_char())
          i += 2
          continue
        }
      }
      out.write_char('\\')
      i += 1
      continue
    }
    if c != '$'.to_int() {
      out.write_char(c.unsafe_to_char())
      i += 1
      continue
    }
    if i + 1 >= to {
      out.write_char('$')
      i += 1
      continue
    }
    let next = self.src.at(i + 1).to_int()
    if next == '{'.to_int() {
      let close = match self.close_of(i + 2, to) {
        Some(index) => index
        None => raise Unclosed(at=self.spot(i))
      }
      self.brace(i, i + 2, close, level, out)
      i = close + 1
      continue
    }
    if starts_name(next) {
      let mut end = i + 1
      while end < to && continues_name(self.src.at(end).to_int()) {
        end += 1
      }
      let name = self.src[i + 1:end].to_owned()
      match self.value_or(name, i, end, out) {
        Some(value) => out.write_string(value)
        None => ()
      }
      i = end
      continue
    }
    out.write_char('$')
    i += 1
  }
}

///|
/// One `${…}` form, from the `$` at `open` to the body in `[from:to)`.
fn Reader::brace(
  self : Reader,
  open : Int32,
  from : Int32,
  to : Int32,
  level : Int32,
  out : StringBuilder,
) -> Unit raise Refused {
  if from >= to {
    raise BadName(at=self.spot(open), got="")
  }
  // `${#A}` is the length of the value.
  if self.src.at(from).to_int() == '#'.to_int() {
    let name = self.src[from + 1:to].to_owned()
    if !is_name(name) {
      raise BadName(at=self.spot(from), got=name)
    }
    match self.value_or(name, open, to + 1, out) {
      Some(value) => out.write_string(value.length().to_string())
      None => ()
    }
    return
  }
  let mut end = from
  while end < to && continues_name(self.src.at(end).to_int()) {
    end += 1
  }
  let name = self.src[from:end].to_owned()
  if !is_name(name) {
    raise BadName(at=self.spot(from), got=name)
  }
  if end == to {
    match self.value_or(name, open, to + 1, out) {
      Some(value) => out.write_string(value)
      None => ()
    }
    return
  }
  // `:` before an operator means "unset or empty".
  let colon = self.src.at(end).to_int() == ':'.to_int()
  let at = if colon { end + 1 } else { end }
  if at >= to {
    raise BadOperator(at=self.spot(end), got=self.src[end:to].to_owned())
  }
  let word_from = at + 1
  match self.src.at(at).to_int() {
    '-' => self.defaulted(name, open, word_from, to, level, out, colon, false)
    '=' => self.defaulted(name, open, word_from, to, level, out, colon, true)
    '?' => self.required(name, open, word_from, to, level, out, colon)
    '+' => self.alternate(name, word_from, to, level, out, colon)
    _ => raise BadOperator(at=self.spot(at), got=self.src[at:to].to_owned())
  }
}

///|
/// The word `[from:to)`, expanded, as a string of its own.
fn Reader::word(
  self : Reader,
  from : Int32,
  to : Int32,
  level : Int32,
) -> String raise Refused {
  let out = StringBuilder()
  self.run(from, to, level + 1, out)
  out.to_string()
}

///|
/// `${A-word}` and `${A:-word}`: the word when unset (or empty), the value
/// otherwise. `${A:=word}` also writes the word back.
fn Reader::defaulted(
  self : Reader,
  name : String,
  open : Int32,
  word_from : Int32,
  to : Int32,
  level : Int32,
  out : StringBuilder,
  colon : Bool,
  assign : Bool,
) -> Unit raise Refused {
  let absent = match self.vars.lookup(name) {
    None => true
    Some(value) => colon && value == ""
  }
  if !absent {
    out.write_string(self.vars.lookup(name).unwrap())
    return
  }
  let filled = self.word(word_from, to, level)
  if assign && !self.vars.write(name, filled) {
    raise ReadOnly(name~, at=self.spot(open))
  }
  out.write_string(filled)
}

///|
/// `${A:?msg}`: a message when unset (or empty), the value otherwise.
fn Reader::required(
  self : Reader,
  name : String,
  open : Int32,
  word_from : Int32,
  to : Int32,
  level : Int32,
  out : StringBuilder,
  colon : Bool,
) -> Unit raise Refused {
  let present = match self.vars.lookup(name) {
    None => false
    Some(value) => !(colon && value == "")
  }
  if present {
    out.write_string(self.vars.lookup(name).unwrap())
    return
  }
  let why = self.word(word_from, to, level) catch {
    _ => self.src[word_from:to].to_owned()
  }
  raise Required(name~, why~, at=self.spot(open))
}

///|
/// `${A:+word}`: the word when set (and not empty), nothing otherwise.
fn Reader::alternate(
  self : Reader,
  name : String,
  word_from : Int32,
  to : Int32,
  level : Int32,
  out : StringBuilder,
  colon : Bool,
) -> Unit raise Refused {
  let present = match self.vars.lookup(name) {
    None => false
    Some(value) => !(colon && value == "")
  }
  if present {
    out.write_string(self.word(word_from, to, level))
  }
}

///|
/// Expand a text in the POSIX shell's parameter syntax.
///
/// `${A}`, `$A`, `${A:-b}`, `${A-b}`, `${A:=b}`, `${A=b}`, `${A:?msg}`, `${A?msg}`,
/// `${A:+b}`, `${A+b}` and `${#A}`, with `\` escaping `$`, `\`, `"` and a
/// backtick, and the word inside any of the forms expanded in turn. The colon
/// forms also treat an empty value as missing, as the shell does.
///
/// A variable with no value is an error by default: a caller who knows an empty
/// string is meant asks for [`lenient`], and one that expands in two passes asks
/// for `{ unset: Keep }`.
pub fn expand(
  text : StringView,
  vars : Vars,
  knobs? : Knobs,
) -> String raise Refused {
  let reader = { src: text, vars, knobs: knobs.unwrap_or(strict), }
  let out = StringBuilder()
  reader.run(0, text.length(), 0, out)
  out.to_string()
}
