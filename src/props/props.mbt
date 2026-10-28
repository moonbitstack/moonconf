// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in the text a pair was written.
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
/// Why a properties text was refused.
pub(all) suberror Refused {
  /// A `\u` escape with fewer than four hex digits, or digits that are not hex.
  BadEscape(at~ : At, got~ : String)
  /// A byte that is not ISO-8859-1, when the text arrived as bytes.
  BadByte(at~ : At, got~ : Int32)
  /// A line that ends inside a continuation and never continues.
  Truncated(at~ : At)
}

///|
fn Refused::message(self : Refused) -> String {
  match self {
    BadEscape(at~, got~) =>
      "line " + at.line.to_string() + ": `\\" + got + "` is not an escape"
    BadByte(at~, got~) =>
      "line " +
      at.line.to_string() +
      ": byte " +
      got.to_string() +
      " is not ISO-8859-1"
    Truncated(at~) =>
      "line " + at.line.to_string() + ": the text ends in a continuation"
  }
}

///|
pub impl Show for Refused with fn to_string(self) {
  self.message()
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// One name and its value.
pub(all) struct Pair {
  /// The name, with its escapes decoded.
  key : String
  /// The value, with its escapes decoded.
  value : String
  /// Where the pair was written.
  at : At
} derive(Eq, Debug)

///|
pub extend Pair with Eq::{equal, not_equal}

///|
pub extend Pair with Debug::{to_repr}

///|
/// A properties file: its pairs, in the order they were read.
///
/// A later pair with the same name wins, which is what a map does and what the
/// reader this follows does. The order is kept because a file written back with
/// its lines shuffled is a file nobody can diff.
pub(all) struct Doc {
  /// The pairs, in the order they were read, duplicates included.
  pairs : Array[Pair]
} derive(Eq, Debug)

///|
pub extend Doc with Eq::{equal, not_equal}

///|
pub extend Doc with Debug::{to_repr}

///|
/// A document made of pairs, for a caller that builds one instead of reading one.
pub fn Doc::new(pairs : Array[Pair]) -> Doc {
  { pairs, }
}

///|
/// A pair made of a name and a value, at a position the caller supplies.
pub fn Pair::new(key : String, value : String, at? : At) -> Pair {
  { key, value, at: at.unwrap_or({ at: 0, line: 1, column: 1, }), }
}
