// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What happens to the case of an option name.
///
/// Section names keep theirs, because two sections that differ only in case are
/// two sections; option names are folded by default, because `Port` and `port`
/// in one section are the same setting written twice, and a reader that treats
/// them as two silently keeps a value nobody can find.
pub(all) enum Case {
  /// Fold to lower case. The default.
  Lower
  /// Leave as written.
  Preserve
  /// Fold to upper case.
  Upper
} derive(Eq, Debug)

///|
pub extend Case with Eq::{equal, not_equal}

///|
pub extend Case with Debug::{to_repr}

///|
/// How a value refers to another value.
pub(all) enum Interp {
  /// A value is a value.
  None_
  /// `%(name)s`, taken from the same section, then from the defaults, and `%%`
  /// for a literal percent sign. The default, because it is what the oldest
  /// files in the wild use.
  Basic
  /// `${name}`, or `${section:name}`, and `$$` for a literal dollar sign.
  Extended
} derive(Eq, Debug)

///|
pub extend Interp with Eq::{equal, not_equal}

///|
pub extend Interp with Debug::{to_repr}

///|
/// How to read an INI text.
///
/// The defaults are the ones a file in the wild is written for: `=` and `:` both
/// separate, `#` and `;` start a comment line, option names are folded to lower
/// case, a repeated name is an error, and `%(name)s` is interpolated. Every one
/// of those is a switch because the format never had a specification, and a
/// reader that cannot be told what a file means is a reader that cannot read
/// half of them.
pub(all) struct Knobs {
  /// The characters that separate a name from its value.
  delimiters : String
  /// The characters that start a comment line.
  comment : String
  /// The characters that start a comment after a value, once whitespace comes
  /// before them. Empty by default: `value ; note` is a value with a semicolon
  /// in it unless the reader is told otherwise.
  inline_comment : String
  /// What happens to the case of an option name.
  case : Case
  /// Whether a repeated section or option is an error.
  strict : Bool
  /// Whether a name with no value at all is allowed, as in a file of flags.
  allow_no_value : Bool
  /// Whether a blank line inside an indented block belongs to the value.
  empty_lines_in_values : Bool
  /// How a value refers to another value.
  interp : Interp
  /// The section whose values every other section falls back to.
  default_section : String
} derive(Eq, Debug)

///|
pub extend Knobs with Eq::{equal, not_equal}

///|
pub extend Knobs with Debug::{to_repr}

///|
/// The usual file: `=` and `:`, `#` and `;`, lower-case names, strict, no bare
/// names, `%(name)s` interpolation.
pub let standard : Knobs = {
  delimiters: "=:",
  comment: "#;",
  inline_comment: "",
  case: Lower,
  strict: true,
  allow_no_value: false,
  empty_lines_in_values: true,
  interp: Basic,
  default_section: "DEFAULT",
}

///|
/// A file with `${section:name}` references instead of `%(name)s`.
pub let extended : Knobs = { ..standard, interp: Extended, }

///|
/// A file where a value is a value, and a name may stand alone.
pub let literal : Knobs = { ..standard, interp: None_, allow_no_value: true, }

///|
/// The limit on interpolation chains. `a = ${b}` and `b = ${a}` is a cycle, and
/// a chain of a thousand is a mistake.
pub let depth : Int32 = 32

///|
/// One name and its value, as written.
pub(all) struct Entry {
  /// The name, with its case folded as the knobs ask.
  name : String
  /// The value, as written: continuation lines joined with newlines, and no
  /// interpolation applied.
  value : String
  /// Where the name was written.
  at : At
} derive(Eq, Debug)

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend Entry with Debug::{to_repr}

///|
/// One section, in the order its options were written.
pub(all) struct Section {
  /// The name between the brackets.
  name : String
  /// The options, in the order they were written.
  options : Array[Entry]
  /// Where the header was written.
  at : At
} derive(Eq, Debug)

///|
pub extend Section with Eq::{equal, not_equal}

///|
pub extend Section with Debug::{to_repr}

///|
/// A whole document: its sections, in the order they were written.
pub(all) struct Doc {
  /// The sections, the default one first when it is there.
  sections : Array[Section]
  /// The knobs the document was read with, which its lookups need.
  knobs : Knobs
} derive(Eq, Debug)

///|
pub extend Doc with Eq::{equal, not_equal}

///|
pub extend Doc with Debug::{to_repr}
