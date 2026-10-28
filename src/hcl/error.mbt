// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in the text something was written.
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
/// The first position in a text: what a refusal about a whole document, rather
/// than one character, points at.
let nowhere : At = { at: 0, line: 1, column: 1, }

///|
/// Why an HCL text was refused.
pub(all) suberror Refused {
  /// A character that cannot appear where it does.
  Unexpected(at~ : At, got~ : String)
  /// A string, a list, an object or a body that never closes.
  Unclosed(at~ : At, got~ : String)
  /// A member of a body that is neither an attribute nor a block.
  BadBody(at~ : At, got~ : String)
  /// A name nothing defines.
  UnknownName(name~ : String, at~ : At)
  /// A function nothing defines.
  UnknownFunction(name~ : String, at~ : At)
  /// A function called with the wrong number of arguments.
  BadArity(name~ : String, want~ : String, got~ : Int32, at~ : At)
  /// An operation on values it does not take.
  BadOperation(why~ : String, at~ : At)
  /// Nesting past the limit.
  TooDeep(at~ : At, limit~ : Int32)
}

///|
fn Refused::message(self : Refused) -> String {
  match self {
    Unexpected(at~, got~) =>
      "line " + at.line.to_string() + ": `" + got + "` cannot appear here"
    Unclosed(at~, got~) =>
      "line " + at.line.to_string() + ": " + got + " is never closed"
    BadBody(at~, got~) =>
      "line " +
      at.line.to_string() +
      ": `" +
      got +
      "` is neither an attribute nor a block"
    UnknownName(name~, at~) =>
      "line " + at.line.to_string() + ": " + name + " is not defined"
    UnknownFunction(name~, at~) =>
      "line " + at.line.to_string() + ": no function called " + name
    BadArity(name~, want~, got~, at~) =>
      "line " +
      at.line.to_string() +
      ": " +
      name +
      " wants " +
      want +
      " arguments, got " +
      got.to_string()
    BadOperation(why~, at~) => "line " + at.line.to_string() + ": " + why
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
