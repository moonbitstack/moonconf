// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in a document a value was written.
///
/// The offset is in UTF-16 code units from the start of the source, which is
/// what a [`StringView`] indexes by. Line and column are one-based, because
/// that is how an editor counts, and an error a reader cannot find in their file
/// is half an error.
///
/// A source that does not report positions — the JSON, YAML and TOML readers
/// this package borrows keep the tree but not the offsets — fills in
/// `{ at: 0, line: 1, column: 1 }`, and says so where it matters.
pub(all) struct At {
  /// The offset in UTF-16 code units from the start of the source.
  at : Int32
  /// The line the offset is on, counting from one.
  line : Int32
  /// The column the offset is at, counting from one.
  column : Int32
} derive(Eq, Debug)

///|
/// The first position in a source: what to use when nothing better is known.
pub let start : At = { at: 0, line: 1, column: 1, }

///|
/// The position of `offset` in `text`, counted only when something has already
/// gone wrong.
pub fn At::of(text : StringView, offset : Int32) -> At {
  let mut line = 1
  let mut column = 1
  let mut i = 0
  while i < offset && i < text.length() {
    if text.at(i) == '\n' {
      line += 1
      column = 1
    } else {
      column += 1
    }
    i += 1
  }
  { at: offset, line, column, }
}

///|
pub extend At with Eq::{equal, not_equal}

///|
pub extend At with Debug::{to_repr}
