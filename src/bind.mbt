// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What to do with a member no field of the model describes.
pub(all) enum Extra {
  /// Carry it through. The default, because a configuration often has more in
  /// it than one model describes: shared settings, another program's section.
  Allow
  /// Refuse it. For a deployment where a misspelled key is a bug that must be
  /// caught at startup, not a typo that silently does nothing.
  Refuse
} derive(Eq, Debug)

///|
/// How to bind.
pub(all) struct Bind {
  /// What an undescribed member means.
  extra : Extra
} derive(Eq, Debug)

///|
/// Bind the members the model describes and carry the rest through.
pub let open : Bind = { extra: Allow, }

///|
/// Bind the members the model describes and refuse the rest.
pub let closed : Bind = { extra: Refuse, }

///|
/// Refuse a value whose shape is not the one the model asks for.
fn wrong(node : Node, want : String, path : String) -> Json raise Refused {
  raise Type(want~, got=node.kind(), path~, source=node.source, at=node.at)
}

///|
/// The model a reference names, if the caller supplied it.
fn resolve(known : Array[@moonmodel.Model], name : String) -> @moonmodel.Model? {
  for model in known {
    if model.name == name {
      return Some(model)
    }
  }
  None
}

///|
/// Text that means a boolean, in the spellings every configuration file uses.
fn as_bool(text : String) -> Bool? {
  match text.to_lower() {
    "true" | "yes" | "on" | "1" => Some(true)
    "false" | "no" | "off" | "0" => Some(false)
    _ => None
  }
}

///|
/// The tree as JSON, keeping the shape and dropping the provenance.
pub fn native(node : Node) -> Json {
  match node.value {
    Null => Json::null()
    Bool(flag) => Json::boolean(flag)
    Int(n) => Json::number(n.to_double(), repr=n.to_string())
    Real(x) => Json::number(x)
    Text(text) => Json::string(text)
    List(items) => Json::array(items.map(fn(item) { native(item) }))
    Map(table) => {
      let out : Map[String, Json] = Map([])
      for entry in table.entries {
        out.set(entry.0, native(entry.1))
      }
      Json::object(out)
    }
  }
}

///|
/// One value, checked against one type of the model, as JSON.
///
/// Text is read as the number or the boolean it spells: an environment variable
/// is always text, and a model that says `Int` should not force every caller to
/// convert before merging. Text that does not spell the type is a refusal, not a
/// guess.
fn as_json(
  node : Node,
  kind : @moonmodel.Type,
  known : Array[@moonmodel.Model],
  path : String,
  knobs : Bind,
) -> Json raise Refused {
  match kind {
    @moonmodel.Bool =>
      match node.value {
        Bool(flag) => Json::boolean(flag)
        Text(text) =>
          match as_bool(text) {
            Some(flag) => Json::boolean(flag)
            None => wrong(node, "boolean", path)
          }
        _ => wrong(node, "boolean", path)
      }
    @moonmodel.Int | @moonmodel.Big =>
      match node.value {
        Int(n) => Json::number(n.to_double(), repr=n.to_string())
        Real(x) =>
          if x == x.trunc() {
            Json::number(x, repr=x.to_int64().to_string())
          } else {
            wrong(node, "integer", path)
          }
        Text(text) => {
          let parsed = @string.parse_int64(text[:]) catch {
            _ =>
              raise Type(
                want="integer",
                got=node.kind(),
                path~,
                source=node.source,
                at=node.at,
              )
          }
          Json::number(parsed.to_double(), repr=parsed.to_string())
        }
        _ => wrong(node, "integer", path)
      }
    @moonmodel.Real =>
      match node.value {
        Real(x) => Json::number(x)
        Int(n) => Json::number(n.to_double())
        Text(text) => {
          let parsed = @string.parse_double(text[:]) catch {
            _ =>
              raise Type(
                want="real",
                got=node.kind(),
                path~,
                source=node.source,
                at=node.at,
              )
          }
          Json::number(parsed)
        }
        _ => wrong(node, "real", path)
      }
    @moonmodel.Text | @moonmodel.Bytes | @moonmodel.Stamp =>
      match node.value {
        Text(text) => Json::string(text)
        Int(n) => Json::string(n.to_string())
        Real(x) => Json::string(x.to_string())
        Bool(flag) => Json::string(flag.to_string())
        _ => wrong(node, "text", path)
      }
    @moonmodel.List(element) => {
      let items = node.list()
      let out = []
      let mut i = 0
      for item in items {
        let child = if path == "" {
          i.to_string()
        } else {
          path + "." + i.to_string()
        }
        out.push(as_json(item, element, known, child, knobs))
        i += 1
      }
      Json::array(out)
    }
    @moonmodel.Dict(element) => {
      let table = node.table()
      let out : Map[String, Json] = Map([])
      for entry in table.entries {
        let child = if path == "" { entry.0 } else { path + "." + entry.0 }
        out.set(entry.0, as_json(entry.1, element, known, child, knobs))
      }
      Json::object(out)
    }
    @moonmodel.Ref(name) =>
      match resolve(known, name) {
        Some(model) =>
          as_json(node, @moonmodel.Type::Nest(model), known, path, knobs)
        None => native(node)
      }
    @moonmodel.Nest(model) => {
      let table = node.table()
      described(table, model, known, path, knobs)
    }
    @moonmodel.Raw(fixed) =>
      if native(node) == fixed {
        fixed
      } else {
        wrong(node, "the value the model fixes", path)
      }
    @moonmodel.Any => native(node)
  }
}

///|
/// The members of `table` as the model describes them.
///
/// A field that is absent takes its default; a field with neither a default nor
/// a value is [`Missing`] when the model requires it, and left out otherwise.
fn described(
  table : Table,
  model : @moonmodel.Model,
  known : Array[@moonmodel.Model],
  path : String,
  knobs : Bind,
) -> Json raise Refused {
  let out : Map[String, Json] = Map([])
  for field in model.fields {
    let child = if path == "" { field.name } else { path + "." + field.name }
    match table.get(field.name) {
      Some(node) =>
        match (node.value, field.nullable) {
          (Null, true) => out.set(field.name, Json::null())
          (Null, false) =>
            if field.required {
              wrong(node, "a value", child) |> ignore
            }
          _ =>
            out.set(field.name, as_json(node, field.kind, known, child, knobs))
        }
      None =>
        match field.default {
          Some(fixed) => out.set(field.name, fixed)
          None =>
            if field.required {
              raise Missing(path=child, want=shape(field.kind, known))
            }
        }
    }
  }
  if knobs.extra == Refuse {
    for entry in table.entries {
      if model.field(entry.0) is None {
        let child = if path == "" { entry.0 } else { path + "." + entry.0 }
        raise Unknown(path=child, got=entry.1.kind())
      }
    }
  }
  Json::object(out)
}

///|
/// The name of a type, as a person would say it.
fn shape(kind : @moonmodel.Type, known : Array[@moonmodel.Model]) -> String {
  match kind {
    @moonmodel.Bool => "boolean"
    @moonmodel.Int => "integer"
    @moonmodel.Big => "integer"
    @moonmodel.Real => "real"
    @moonmodel.Text => "text"
    @moonmodel.Bytes => "bytes"
    @moonmodel.Stamp => "timestamp"
    @moonmodel.List(element) => "list of " + shape(element, known)
    @moonmodel.Dict(element) => "mapping of " + shape(element, known)
    @moonmodel.Ref(name) => name
    @moonmodel.Nest(model) => model.name
    @moonmodel.Any => "any value"
    @moonmodel.Raw(_) => "the value the model fixes"
  }
}

///|
/// Check a tree against a model and hand back the bound values as JSON, with
/// defaults filled in and text read as the type it spells.
///
/// The JSON is the shape the model describes, so `@json.from_json` turns it into
/// a struct of the caller's own. `known` resolves `Ref` fields by model name; a
/// reference nothing resolves is carried through unchecked rather than guessed
/// at.
pub fn bind(
  node : Node,
  model : @moonmodel.Model,
  known? : Array[@moonmodel.Model],
  knobs? : Bind,
) -> Json raise Refused {
  let table = node.table()
  described(table, model, known.unwrap_or([]), "", knobs.unwrap_or(open))
}

///|
/// Check one value, throwing the result away.
fn check_one(
  here : Node,
  kind : @moonmodel.Type,
  known : Array[@moonmodel.Model],
  path : String,
  knobs : Bind,
) -> Unit raise Refused {
  as_json(here, kind, known, path, knobs) |> ignore
}

///|
/// Walk one value, collecting every refusal below it.
fn collect(
  here : Node,
  kind : @moonmodel.Type,
  path : String,
  known : Array[@moonmodel.Model],
  knobs : Bind,
  out : Array[Refused],
) -> Unit {
  match kind {
    @moonmodel.Nest(inner) =>
      match here.value {
        Map(table) => {
          for field in inner.fields {
            let child = if path == "" {
              field.name
            } else {
              path + "." + field.name
            }
            match table.get(field.name) {
              Some(value) =>
                collect(value, field.kind, child, known, knobs, out)
              None =>
                if field.required && field.default is None {
                  out.push(Missing(path=child, want=shape(field.kind, known)))
                }
            }
          }
          if knobs.extra == Refuse {
            for entry in table.entries {
              if inner.field(entry.0) is None {
                let child = if path == "" {
                  entry.0
                } else {
                  path + "." + entry.0
                }
                out.push(Unknown(path=child, got=entry.1.kind()))
              }
            }
          }
        }
        _ =>
          out.push(
            Type(
              want=inner.name,
              got=here.kind(),
              path~,
              source=here.source,
              at=here.at,
            ),
          )
      }
    @moonmodel.List(element) =>
      match here.value {
        List(items) =>
          for item in items {
            collect(item, element, path, known, knobs, out)
          }
        _ =>
          out.push(
            Type(
              want="list",
              got=here.kind(),
              path~,
              source=here.source,
              at=here.at,
            ),
          )
      }
    @moonmodel.Dict(element) =>
      match here.value {
        Map(table) =>
          for entry in table.entries {
            let child = if path == "" { entry.0 } else { path + "." + entry.0 }
            collect(entry.1, element, child, known, knobs, out)
          }
        _ =>
          out.push(
            Type(
              want="mapping",
              got=here.kind(),
              path~,
              source=here.source,
              at=here.at,
            ),
          )
      }
    @moonmodel.Ref(name) =>
      match resolve(known, name) {
        Some(inner) =>
          collect(here, @moonmodel.Type::Nest(inner), path, known, knobs, out)
        None => ()
      }
    _ =>
      check_one(here, kind, known, path, knobs) catch {
        error => out.push(error)
      }
  }
}

///|
/// Every way `node` fails to be what `model` describes, in tree order.
///
/// Binding stops at the first refusal, because a caller who is going to fail
/// wants one clear message. A caller who wants to show a person everything wrong
/// with a file at once uses this: it walks the whole tree and collects.
pub fn validate(
  node : Node,
  model : @moonmodel.Model,
  known? : Array[@moonmodel.Model],
  knobs? : Bind,
) -> Array[Refused] {
  let out : Array[Refused] = []
  let known = known.unwrap_or([])
  let knobs = knobs.unwrap_or(open)
  match node.value {
    Map(table) => {
      for field in model.fields {
        let child = field.name
        match table.get(field.name) {
          Some(value) => collect(value, field.kind, child, known, knobs, out)
          None =>
            if field.required && field.default is None {
              out.push(Missing(path=child, want=shape(field.kind, known)))
            }
        }
      }
      if knobs.extra == Refuse {
        for entry in table.entries {
          if model.field(entry.0) is None {
            out.push(Unknown(path=entry.0, got=entry.1.kind()))
          }
        }
      }
    }
    _ =>
      out.push(
        Type(
          want=model.name,
          got=node.kind(),
          path="",
          source=node.source,
          at=node.at,
        ),
      )
  }
  out
}

///|
pub extend Extra with Eq::{equal, not_equal}

///|
pub extend Extra with Debug::{to_repr}

///|
pub extend Bind with Eq::{equal, not_equal}

///|
pub extend Bind with Debug::{to_repr}
