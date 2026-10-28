// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in the text something went wrong.
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
/// Why a text was refused.
pub(all) suberror Refused {
  /// A `${` with no `}`.
  Unclosed(at~ : At)
  /// A name that is not a name: `${}`, `${1x}`, `${a-b}` outside an operator.
  BadName(at~ : At, got~ : String)
  /// An operator this reader does not know, such as the substring form.
  BadOperator(at~ : At, got~ : String)
  /// A variable with no value, under the policy that refuses those.
  Undefined(name~ : String, at~ : At)
  /// `${A:=b}` with nowhere to write the assignment.
  ReadOnly(name~ : String, at~ : At)
  /// `${A:?}` when `A` is unset or empty.
  Required(name~ : String, why~ : String, at~ : At)
  /// Nesting past the limit.
  TooDeep(at~ : At, limit~ : Int32)
}

///|
fn Refused::message(self : Refused) -> String {
  match self {
    Unclosed(at~) =>
      "line " + at.line.to_string() + ": a reference is never closed"
    BadName(at~, got~) =>
      "line " + at.line.to_string() + ": `" + got + "` is not a name"
    BadOperator(at~, got~) =>
      "line " + at.line.to_string() + ": `" + got + "` is not an operator"
    Undefined(name~, at~) =>
      "line " + at.line.to_string() + ": " + name + " is not set"
    ReadOnly(name~, at~) =>
      "line " + at.line.to_string() + ": " + name + " cannot be assigned here"
    Required(name~, why~, at~) =>
      "line " +
      at.line.to_string() +
      ": " +
      name +
      " is required" +
      (if why == "" { "" } else { ": " + why })
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
