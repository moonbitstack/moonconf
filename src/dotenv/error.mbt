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
/// Why a `.env` text could not be read at all.
///
/// A line the grammar cannot parse is not one of these: it is kept in the
/// document's [`Skipped`] list, because a reader that refuses a whole file over
/// one bad line is a reader that leaves a deployment with no configuration at
/// all. A refusal here means the input is not text this package can even walk.
pub(all) suberror Refused {
  /// More text than a configuration file should ever be.
  TooLarge(at~ : At, limit~ : Int32)
}

///|
fn Refused::message(self : Refused) -> String {
  match self {
    TooLarge(at~, limit~) =>
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
