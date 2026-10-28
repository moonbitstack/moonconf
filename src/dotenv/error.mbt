// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in the text an entry was written.
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
/// Why a `.env` text was refused.
pub(all) suberror Refused {
  /// A quoted value that never ends.
  Unclosed(at~ : At)
  /// A line with something after the value that is not a comment.
  Trailing(at~ : At, got~ : String)
  /// A name that is empty or holds something a name cannot hold.
  BadName(at~ : At, got~ : String)
  /// A reference in a value that the expansion policy refused.
  Expand(why~ : String, at~ : At)
  /// Nesting past the limit, or a text too large to be one.
  TooDeep(at~ : At, limit~ : Int32)
}

///|
fn Refused::message(self : Refused) -> String {
  match self {
    Unclosed(at~) => "line " + at.line.to_string() + ": a quote is never closed"
    Trailing(at~, got~) =>
      "line " + at.line.to_string() + ": `" + got + "` after the value"
    BadName(at~, got~) =>
      "line " + at.line.to_string() + ": `" + got + "` is not a name"
    Expand(why~, at~) => "line " + at.line.to_string() + ": " + why
    TooDeep(at~, limit~) =>
      "line " +
      at.line.to_string() +
      ": longer than " +
      limit.to_string() +
      " characters"
  }
}

///|
pub impl Show for Refused with fn to_string(self) {
  self.message()
}

///|
pub extend Refused with Show::{to_string, output}
