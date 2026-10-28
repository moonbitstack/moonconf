// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Hand the entry points to the page. Every one of them is this library,
/// compiled with the JavaScript backend: the page shows what the packages
/// answer, not a second implementation of the same idea.
///
/// Build it with
///
///     moon build --target js --release src/examples/browser
///
/// and the page calls `globalThis.moonconf.assemble(request)` and friends.
extern "js" fn expose(
  assemble : (String) -> String,
  bind : (String) -> String,
  check : (String) -> String,
  expand : (String, String, String) -> String,
) -> Unit = "function(assemble, bind, check, expand){ globalThis.moonconf = { assemble: assemble, bind: bind, check: check, expand: expand }; }"

///|
/// The name a tier answers to on the page.
fn tier_of(text : String) -> @moonconf.Tier {
  match text {
    "file" => @moonconf.File
    "env" => @moonconf.Env
    "override" => @moonconf.Override
    _ => @moonconf.Default
  }
}

///|
/// The name a tier answers to in a reply.
fn tier_name(tier : @moonconf.Tier) -> String {
  match tier {
    @moonconf.Default => "default"
    @moonconf.File => "file"
    @moonconf.Env => "env"
    @moonconf.Override => "override"
  }
}

///|
/// A member of an object, or nothing.
fn field_of(json : Json, name : String) -> Json? {
  match json {
    Object(map) => map.get(name)
    _ => None
  }
}

///|
/// A member that is text, or the empty string.
fn as_text(json : Json, name : String) -> String {
  match field_of(json, name) {
    Some(String(text)) => text
    _ => ""
  }
}

///|
/// A refusal the page can read.
fn failed(message : String) -> String {
  let out : Map[String, Json] = Map([])
  out["ok"] = Json::boolean(false)
  out["text"] = Json::string(message)
  Json::object(out).stringify()
}

///|
/// Read one source in the format the request names.
fn read_source(
  text : StringView,
  format : String,
  name : String,
) -> @moonconf.Node raise @moonconf.Refused {
  match format {
    "ini" =>
      @ini.parse(text).tree(source=name) catch {
        error => raise @moonconf.Format(why=error.to_string(), at=None)
      }
    "props" =>
      @props.parse(text).tree(source=name) catch {
        error => raise @moonconf.Format(why=error.to_string(), at=None)
      }
    "dotenv" =>
      @dotenv.tree(text, source=name) catch {
        error => raise @moonconf.Format(why=error.to_string(), at=None)
      }
    "hocon" =>
      @hocon.parse(text, knobs=@hocon.plain, source=name) catch {
        error => raise @moonconf.Format(why=error.to_string(), at=None)
      }
    "hcl" =>
      @hcl.parse(text, source=name).tree(name) catch {
        error => raise @moonconf.Format(why=error.to_string(), at=None)
      }
    "yaml" =>
      @moonconf.of_yaml(text, source=name) catch {
        error => raise @moonconf.Format(why=error.to_string(), at=None)
      }
    "toml" =>
      @moonconf.of_toml(text, source=name) catch {
        error => raise @moonconf.Format(why=error.to_string(), at=None)
      }
    _ =>
      @moonconf.of_json(text, source=name) catch {
        error => raise @moonconf.Format(why=error.to_string(), at=None)
      }
  }
}

///|
/// The request as a value, or a refusal naming the JSON mistake.
fn request_of(text : String) -> Json raise @moonconf.Refused {
  @json.parse(text) catch {
    error => raise @moonconf.Format(why=error.to_string(), at=None)
  }
}

///|
/// The layers a request carries, weakest first as written.
fn sources_of(
  request : Json,
) -> Array[@moonconf.Source] raise @moonconf.Refused {
  let sources : Array[@moonconf.Source] = []
  match field_of(request, "sources") {
    Some(Array(items)) =>
      for item in items {
        let name = as_text(item, "name")
        let format = as_text(item, "format")
        let text = as_text(item, "text")
        sources.push(
          @moonconf.Source::new(
            tier_of(as_text(item, "tier")),
            name,
            read_source(text[:], format, name),
          ),
        )
      }
    _ => ()
  }
  sources
}

///|
/// The merge switches a request names.
fn knobs_of(request : Json) -> @moonconf.Knobs {
  let clash = match as_text(request, "clash") {
    "first" => @moonconf.First
    "refuse" => @moonconf.Refuse
    _ => @moonconf.Last
  }
  let wins = match field_of(request, "wins") {
    Some(Array(items)) => {
      let tiers : Array[@moonconf.Tier] = []
      for item in items {
        match item {
          String(text) => tiers.push(tier_of(text))
          _ => ()
        }
      }
      tiers
    }
    _ => @moonconf.layered.wins
  }
  { wins, clash, }
}

///|
/// Record where each leaf of the tree came from: the path the page colours by.
fn origins_of(
  node : @moonconf.Node,
  path : String,
  tiers : Map[String, String],
  out : Map[String, Json],
) -> Unit {
  match node.value {
    @moonconf.Value::Map(table) =>
      if table.length() == 0 {
        record(node, path, tiers, out)
      } else {
        for pair in table.items() {
          let child = if path == "" { pair.0 } else { path + "." + pair.0 }
          origins_of(pair.1, child, tiers, out)
        }
      }
    @moonconf.Value::List(items) =>
      if items.length() == 0 {
        record(node, path, tiers, out)
      } else {
        let mut index = 0
        for item in items {
          origins_of(item, path + "[" + index.to_string() + "]", tiers, out)
          index += 1
        }
      }
    _ => record(node, path, tiers, out)
  }
}

///|
/// One leaf: the source it was written in, the tier that source belongs to, and
/// the line it sits on.
fn record(
  node : @moonconf.Node,
  path : String,
  tiers : Map[String, String],
  out : Map[String, Json],
) -> Unit {
  if path == "" {
    return
  }
  let entry : Map[String, Json] = Map([])
  entry["tier"] = Json::string(
    match tiers.get(node.source) {
      Some(tier) => tier
      None => ""
    },
  )
  entry["name"] = Json::string(node.source)
  entry["line"] = Json::number(node.at.line.to_double())
  out[path] = Json::object(entry)
}

///|
/// The merged tree, plus where each of its leaves came from.
fn snapshot(request : String) -> Json raise @moonconf.Refused {
  let parsed = request_of(request)
  let sources = sources_of(parsed)
  let tiers : Map[String, String] = Map([])
  for source in sources {
    tiers[source.name] = tier_name(source.tier)
  }
  let merged = @moonconf.merge(sources, knobs=knobs_of(parsed))
  let origins : Map[String, Json] = Map([])
  origins_of(merged, "", tiers, origins)
  let shape : Map[String, Json] = Map([])
  shape["ok"] = Json::boolean(true)
  shape["tree"] = @moonconf.native(merged)
  shape["origins"] = Json::object(origins)
  Json::object(shape)
}

///|
/// The model the bench binds to: what a database section has to say.
fn database() -> @moonmodel.Model {
  @moonmodel.Model::new("Db", [
    @moonmodel.Field::new("host", @moonmodel.Type::Text, required=true),
    @moonmodel.Field::new("port", @moonmodel.Type::Int, required=true),
    @moonmodel.Field::new(
      "pool",
      @moonmodel.Type::Int,
      default=Json::number(4.0),
    ),
    @moonmodel.Field::new(
      "tls",
      @moonmodel.Type::Bool,
      default=Json::boolean(false),
    ),
  ])
}

///|
/// The section a request binds or checks.
fn section_of(request : Json) -> String {
  let path = as_text(request, "path")
  if path == "" {
    "db"
  } else {
    path
  }
}

///|
/// `assemble(request)` — read every layer, merge them, and say where each value
/// came from.
fn assemble(request : String) -> String {
  let outcome = Ok(snapshot(request)) catch { error => Err(error.to_string()) }
  match outcome {
    Ok(reply) => reply.stringify()
    Err(why) => failed(why)
  }
}

///|
/// `bind(request)` — the merged section as the model describes it, with the
/// defaults filled in and every value typed.
fn bind(request : String) -> String {
  let outcome = Ok(
    {
      let parsed = request_of(request)
      let sources = sources_of(parsed)
      let merged = @moonconf.merge(sources, knobs=knobs_of(parsed))
      @moonconf.bind(merged.need(section_of(parsed)), database())
    },
  ) catch {
    error => Err(error.to_string())
  }
  match outcome {
    Ok(record) => {
      let out : Map[String, Json] = Map([])
      out["ok"] = Json::boolean(true)
      out["tree"] = record
      Json::object(out).stringify()
    }
    Err(why) => failed(why)
  }
}

///|
/// `check(request)` — every reason the section is not what the model describes,
/// rather than the first one.
fn check(request : String) -> String {
  let outcome = Ok(
    {
      let parsed = request_of(request)
      let sources = sources_of(parsed)
      let merged = @moonconf.merge(sources, knobs=knobs_of(parsed))
      @moonconf.validate(merged.need(section_of(parsed)), database())
    },
  ) catch {
    error => Err(error.to_string())
  }
  match outcome {
    Ok(problems) => {
      let list : Array[Json] = []
      for problem in problems {
        list.push(Json::string(problem.to_string()))
      }
      let out : Map[String, Json] = Map([])
      out["ok"] = Json::boolean(true)
      out["problems"] = Json::array(list)
      Json::object(out).stringify()
    }
    Err(why) => failed(why)
  }
}

///|
/// `expand(text, vars, mode)` — POSIX parameter expansion over the variables
/// the page supplies.
fn expand(text : String, vars_json : String, mode : String) -> String {
  let outcome = Ok(
    {
      let vars : Map[String, String] = Map([])
      match @json.parse(vars_json) {
        Object(map) =>
          for pair in map {
            match pair.1 {
              String(value) => vars[pair.0] = value
              _ => ()
            }
          }
        _ => ()
      }
      let knobs = match mode {
        "strict" => @expand.strict
        "deferred" => @expand.deferred
        _ => @expand.lenient
      }
      @expand.expand(text[:], @expand.Vars::of_map(vars), knobs~)
    },
  ) catch {
    error => Err(error.to_string())
  }
  match outcome {
    Ok(result) => {
      let out : Map[String, Json] = Map([])
      out["ok"] = Json::boolean(true)
      out["text"] = Json::string(result)
      Json::object(out).stringify()
    }
    Err(why) => failed(why)
  }
}

///|
fn main {
  expose(assemble, bind, check, expand)
}
