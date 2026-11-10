// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which layer of a configuration a source belongs to.
///
/// The tiers are here rather than as a number the caller assigns because the
/// order almost everybody wants — defaults, then files, then the environment,
/// then whatever the command line said — is a fact about deployment, not about
/// this repository, and naming it means a caller who wants the usual thing does
/// not write it out.
#derive(Eq, Debug)
pub(all) enum Tier {
  /// Values the program carries with it, used when nothing overrides them.
  Default
  /// A file the deployment shipped, or the one named on the command line.
  File
  /// The process environment.
  Env
  /// Whatever the caller declares last: flags, a test fixture, an override.
  Override
}

///|
/// How to merge: the order of the tiers, and what two layers that disagree mean.
///
/// `order` runs from the weakest tier to the strongest, and a tier left out of
/// it sorts below every tier in it, in the order the sources were given.
/// Putting the tiers in a different order is how a caller reverses the whole
/// stack, an overlay read after the base file say, without touching any parser.
pub(all) struct Knobs {
  /// Tiers from weakest to strongest: the last one wins.
  order : Array[Tier]
  /// What a value set differently by two layers means to the program: taken
  /// from the stronger layer silently or with a warning, aborted on, or decided
  /// by the caller's function. `moonknob`'s, as in every library of the family.
  clash : @moonknob.OnClash[Node]
  /// Whether such a value is an error in the configuration itself, raised as
  /// `Clash` with both positions, for a deployment where an accidental override
  /// is a bug. Checked before `clash`.
  strict : Bool
}

///|
/// Defaults below files below the environment below explicit overrides, with
/// the stronger layer winning silently.
pub let layered : Knobs = {
  order: [Default, File, Env, Override],
  clash: Ignore,
  strict: false,
}

///|
/// One layer of a configuration: a tree, the tier it belongs to, and the name
/// that goes into error messages.
#derive(Eq, Debug)
pub(all) struct Source {
  /// Which layer this is.
  tier : Tier
  /// The name the caller wants to see in an error: a file name, `env`.
  name : String
  /// The tree this layer contributes.
  node : Node
}

///|
/// A source whose name is taken from the tree it carries.
pub fn Source::new(tier : Tier, name : String, node : Node) -> Source {
  { tier, name, node, }
}

///|
/// The rank of a tier under `knobs`, lowest first.
fn rank(tier : Tier, knobs : Knobs) -> Int32 {
  let mut i = 0
  while i < knobs.order.length() {
    if knobs.order[i] == tier {
      return i
    }
    i += 1
  }
  -1
}

///|
/// Merge two trees. `over` is the stronger one; `strict` and `clash` decide
/// what happens where they disagree, as in [`Knobs`].
///
/// Mappings merge member by member, so a later file that sets one key under
/// `db` keeps the rest of the earlier file's `db`. Lists replace rather than
/// concatenate: a list in a configuration is nearly always one decision,
/// which hosts or which plugins, and appending two decisions gives a value
/// nobody wrote.
pub fn Node::merge(
  self : Node,
  over : Node,
  clash~ : @moonknob.OnClash[Node] = Ignore,
  strict~ : Bool = false,
  path~ : String = "",
) -> Node raise Refused {
  let base = self
  match (base.value, over.value) {
    (Map(left), Map(right)) => {
      let out = left.copy()
      for entry in right.entries {
        let key = entry.0
        let child = if path == "" { key } else { path + "." + key }
        match out.get(key) {
          Some(before) =>
            out.set(key, before.merge(entry.1, clash~, strict~, path=child))
          None => out.set(key, entry.1.copy())
        }
      }
      { value: Map(out), source: over.source, at: over.at, }
    }
    (_, _) => {
      if base.value == over.value {
        return base
      }
      let first = spot(base.source, base.at)
      let second = spot(over.source, over.at)
      if strict {
        raise Clash(path~, first~, second~)
      }
      clash.settle(base, over, [path], "moonconf: \{first} and \{second}")
    }
  }
}

///|
/// Merge a whole stack, weakest first, in the order `knobs` asks for.
///
/// Sources of the same tier keep the order they were given, so `Source` order is
/// the tie-break and a caller never has to number anything.
pub fn merge(sources : Array[Source], knobs? : Knobs) -> Node raise Refused {
  let knobs = knobs.unwrap_or(layered)
  let ranked = []
  let mut index = 0
  for source in sources {
    ranked.push((rank(source.tier, knobs), index, source))
    index += 1
  }
  // A stable insertion sort: the stack is a handful of layers, and the tie-break
  // has to be the caller's order rather than whatever the sort happens to do.
  let mut i = 1
  while i < ranked.length() {
    let item = ranked[i]
    let mut j = i
    while j > 0 && ranked[j - 1].0 > item.0 {
      ranked[j] = ranked[j - 1]
      j -= 1
    }
    ranked[j] = item
    i += 1
  }
  let empty = { value: Map(Table::new()), source: "", at: start, }
  let mut acc = empty
  for entry in ranked {
    acc = acc.merge(entry.2.node, clash=knobs.clash, strict=knobs.strict)
  }
  acc
}

///|
pub extend Tier with Eq::{equal, not_equal}

///|
pub extend Tier with Debug::{to_repr}

///|
pub extend Source with Eq::{equal, not_equal}

///|
pub extend Source with Debug::{to_repr}
