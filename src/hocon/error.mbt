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
/// Why a HOCON text was refused.
pub(all) suberror Refused {
  /// A character that cannot appear where it does.
  Unexpected(at~ : At, got~ : String)
  /// A string, an array or an object that never closes.
  Unclosed(at~ : At, got~ : String)
  /// A key with no value after it.
  MissingValue(at~ : At, got~ : String)
  /// A reference to a path that is not in the document.
  Unresolved(path~ : String, at~ : At)
  /// A reference that reaches itself.
  Cycle(path~ : String)
  /// An include the caller could not supply, when it was marked required.
  MissingInclude(name~ : String, at~ : At)
  /// Values that cannot be joined: an object and a string, say.
  Concat(at~ : At, got~ : String)
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
    MissingValue(at~, got~) =>
      "line " + at.line.to_string() + ": " + got + " has no value"
    Unresolved(path~, at~) =>
      "line " + at.line.to_string() + ": " + path + " is not in the document"
    Cycle(path~) => path + " refers to itself"
    MissingInclude(name~, at~) =>
      "line " + at.line.to_string() + ": include " + name + " was not found"
    Concat(at~, got~) => "line " + at.line.to_string() + ": cannot join " + got
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
