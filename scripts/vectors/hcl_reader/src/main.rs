// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0
//
// Read one HCL document and print the tree it evaluates to, as JSON.
//
// This is the second reader `scripts/vectors/hcl_crosscheck.py` compares the
// vectors against. It reads a document from standard input and prints
//
//   {"tree": { ... }, "labels": {"kind": ["label/label", ...]}}
//
// or, when the document cannot be read or evaluated, writes the reason to
// standard error and exits non-zero.

use std::collections::BTreeMap;
use std::io::{self, Read};

use hcl::eval::{Context, Evaluate};
use serde_json::{Map, Value as Json};

fn main() {
    let mut text = String::new();
    if let Err(error) = io::stdin().read_to_string(&mut text) {
        eprintln!("cannot read the document: {error}");
        std::process::exit(2);
    }
    match read(&text) {
        Ok(answer) => println!("{answer}"),
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(1);
        }
    }
}

fn read(text: &str) -> Result<String, String> {
    let body: hcl::Body = hcl::from_str(text).map_err(|error| error.to_string())?;
    let context = Context::new();
    let mut labels = Map::new();
    let tree = body_value(&body, &context, &mut labels)?;
    let mut answer = Map::new();
    answer.insert("tree".to_owned(), tree);
    answer.insert("labels".to_owned(), Json::Object(labels));
    Ok(Json::Object(answer).to_string())
}

fn body_value(
    body: &hcl::Body,
    context: &Context,
    labels: &mut Map<String, Json>,
) -> Result<Json, String> {
    let mut out = Map::new();
    for attribute in body.attributes() {
        let value = attribute
            .expr
            .evaluate(context)
            .map_err(|error| format!("{}: {error}", attribute.key.as_str()))?;
        out.insert(attribute.key.as_str().to_owned(), value_json(&value));
    }
    let mut kinds: Vec<String> = Vec::new();
    for block in body.blocks() {
        let kind = block.identifier().to_owned();
        if !kinds.contains(&kind) {
            kinds.push(kind.clone());
        }
        let joined = block
            .labels()
            .iter()
            .map(|label| label.as_str().to_owned())
            .collect::<Vec<_>>()
            .join("/");
        labels
            .entry(kind.clone())
            .or_insert_with(|| Json::Array(Vec::new()))
            .as_array_mut()
            .expect("a list of labels")
            .push(Json::String(joined));
    }
    for kind in kinds {
        let mut ones = Vec::new();
        for block in body.blocks().filter(|one| one.identifier() == kind) {
            ones.push(body_value(block.body(), context, labels)?);
        }
        if ones.len() == 1 {
            out.insert(kind.clone(), ones.pop().expect("one body"));
        } else {
            out.insert(kind.clone(), Json::Array(ones));
        }
    }
    Ok(Json::Object(out))
}

fn value_json(value: &hcl::Value) -> Json {
    match value {
        hcl::Value::Null => Json::Null,
        hcl::Value::Bool(flag) => Json::Bool(*flag),
        hcl::Value::Number(number) => match number.as_i64() {
            Some(whole) => Json::from(whole),
            None => Json::from(number.as_f64()),
        },
        hcl::Value::String(text) => Json::String(text.clone()),
        hcl::Value::Array(items) => Json::Array(items.iter().map(value_json).collect()),
        hcl::Value::Object(members) => {
            let mut out = BTreeMap::new();
            for (name, item) in members.iter() {
                out.insert(name.clone(), value_json(item));
            }
            Json::Object(out.into_iter().collect())
        }
    }
}
