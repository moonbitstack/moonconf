// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in the text a name or a value was written.
pub(all) struct At {
  /// The offset in UTF-16 code units from the start.
  at : Int32
  /// The line, counting from one.
  line : Int32
  /// The column, counting from one.
  column : Int32
} derive(Eq, Debug)

///|
pub extend At with Eq::{equal, not_equal}

///|
pub extend At with Debug::{to_repr}

///|
/// Why an INI text was refused.
pub(all) suberror Refused {
  /// An option outside any section. A file whose first line is `key=value` is
  /// missing its `[section]`, and saying so beats inventing one.
  MissingSection(at~ : At)
  /// A section header with no `]`, or with text after it.
  BadSection(at~ : At, got~ : String)
  /// A section header written twice, under the policy that refuses that.
  DuplicateSection(at~ : At, name~ : String)
  /// A name written twice in one section, under the policy that refuses that.
  DuplicateOption(at~ : At, name~ : String)
  /// A line that is neither a section, an option, nor a continuation.
  BadLine(at~ : At, got~ : String)
  /// A lookup in a section that is not in the document.
  NoSection(section~ : String)
  /// A lookup of a name that is in neither the section nor the defaults.
  NoOption(section~ : String, option~ : String)
  /// `%` or `${` that does not make sense, or a name it refers to that is not
  /// there.
  Interpolation(why~ : String, at~ : At)
  /// Nesting past the limit.
  TooDeep(at~ : At, limit~ : Int32)
}

///|
fn Refused::message(self : Refused) -> String {
  match self {
    MissingSection(at~) =>
      "line " + at.line.to_string() + ": an option before any [section]"
    BadSection(at~, got~) =>
      "line " + at.line.to_string() + ": `" + got + "` is not a section header"
    DuplicateSection(at~, name~) =>
      "line " +
      at.line.to_string() +
      ": section [" +
      name +
      "] is written twice"
    DuplicateOption(at~, name~) =>
      "line " + at.line.to_string() + ": " + name + " is written twice"
    BadLine(at~, got~) =>
      "line " + at.line.to_string() + ": `" + got + "` is not an option"
    NoSection(section~) => "no section [" + section + "]"
    NoOption(section~, option~) => "no " + option + " in [" + section + "]"
    Interpolation(why~, at~) => "line " + at.line.to_string() + ": " + why
    TooDeep(at~, limit~) =>
      "line " +
      at.line.to_string() +
      ": nested deeper than " +
      limit.to_string()
  }
}

///|
pub impl Show for Refused with fn to_string(self) {
  self.message()
}

///|
pub extend Refused with Show::{to_string, output}
