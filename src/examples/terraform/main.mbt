// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An HCL body, evaluated against a context the caller fills.
///
///     moon run src/examples/terraform
#coverage.skip
fn main raise {
  let variables = @moonconf.Node::map(
    [("region", @moonconf.Node::str("eu-west-1", "vars"))],
    "vars",
  )
  let context = @hcl.standard().bind("var", variables)
  let text = "region = var.region\n" +
    "name   = upper(\"web\")\n" +
    "ports  = [80, 443]\n" +
    "server \"web\" {\n" +
    "  port = 80 + 1\n" +
    "}\n"
  let body = @hcl.parse(text[:], context~)
  println("region -> \{body.get("region").unwrap().text()}")
  println("name   -> \{body.get("name").unwrap().text()}")
  let server = body.blocks_of("server")[0]
  println("port   -> \{server.body.get("port").unwrap().int()}")
}
