// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a configuration was refused, and where.
///
/// One error type for the whole repository's root package: reading a borrowed
/// format, merging layers, looking a path up, binding to a model. A caller
/// catches one thing and reads one message. The message names the source and
/// the position when the value came from text, and names the field path — `db.pool.size` —
/// whenever the refusal is about a place in the tree, because a message that
/// says "expected an integer" without saying where is a message that sends the
/// reader looking through the whole file.
pub(all) suberror Refused {
  /// A value has the wrong shape. `path` is empty when the refusal is about a
  /// value asked for on its own, with no place in the tree to name.
  Type(
    want~ : String,
    got~ : String,
    path~ : String,
    source~ : String,
    at~ : At
  )
  /// A field the model requires was nowhere in the sources.
  Missing(path~ : String, want~ : String)
  /// A member no field of the model describes, under a closed binding.
  Unknown(path~ : String, got~ : String)
  /// Two layers carried the same scalar and the clash policy refused both.
  Clash(path~ : String, first~ : String, second~ : String)
  /// A path that does not parse: an empty segment, a stray dot.
  Path(got~ : String, at~ : Int32)
  /// A borrowed reader refused the document, or a value it produced could not
  /// be carried into the tree. `at` is the position the reader reported, when
  /// it reported one.
  Format(why~ : String, at~ : At?)
  /// Nesting past the limit. A document of ten thousand opens must not take the
  /// stack down with it.
  TooDeep(at~ : At, limit~ : Int32)
}

///|
/// The refusal as a person reads it: what was wanted, what was there, and where.
///
/// The path comes first because that is what a person greps for; the source and
/// position follow, because that is where they look next.
fn Refused::message(self : Refused) -> String {
  match self {
    Type(want~, got~, path~, source~, at~) => {
      let site = if path == "" {
        spot(source, at)
      } else {
        path + " (" + spot(source, at) + ")"
      }
      site + ": want " + want + ", got " + got
    }
    Missing(path~, want~) => path + ": want " + want + ", got nothing"
    Unknown(path~, got~) => path + ": no field describes this " + got
    Clash(path~, first~, second~) =>
      path + ": written twice, at " + first + " and " + second
    Path(got~, at~) => "path " + got + ": empty segment at " + at.to_string()
    Format(why~, at~) =>
      match at {
        Some(at) => spot("", at) + ": " + why
        None => why
      }
    TooDeep(at~, limit~) =>
      spot("", at) + ": nested deeper than " + limit.to_string()
  }
}

///|
pub impl Show for Refused with fn to_string(self) {
  self.message()
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// The source and position part of a refusal, rendered as `name@line:column`.
pub fn spot(source : String, at : At) -> String {
  let name = if source == "" { "<input>" } else { source }
  name + "@" + at.line.to_string() + ":" + at.column.to_string()
}
