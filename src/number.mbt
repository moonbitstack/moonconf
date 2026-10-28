// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The whole number `text` spells, or nothing.
///
/// Configuration text is mostly digits that a program has to read as a number,
/// and the readers in this repository refuse rather than guess. Nothing is
/// trimmed here: a value with a space in it is not a number, and saying so is
/// better than quietly accepting it.
pub fn whole(text : StringView) -> Int64? {
  let parsed = @string.parse_int64(text) catch { _ => return None }
  Some(parsed)
}

///|
/// The real number `text` spells, or nothing.
pub fn decimal(text : StringView) -> Double? {
  let parsed = @string.parse_double(text) catch { _ => return None }
  Some(parsed)
}
