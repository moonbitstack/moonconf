// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0
//
// Generate the HCL vectors with hashicorp/hcl v2.24.0, the format's reference
// implementation. Every case is parsed and evaluated by it, and the values it
// ends up with become assertions in `src/hcl/vectors_test.mbt`. A case the
// reference refuses is asserted to be refused here too.
//
// The cases are the examples of the language specification, plus the shapes a
// Terraform-shaped configuration actually uses: templates, for expressions,
// splats, blocks with labels, and the functions this library provides.
//
// Run from the repository root:
//   cd scripts/vectors/hcl && go run .
//
// The module beside this file pins the reference implementation.

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/zclconf/go-cty/cty"
	"github.com/zclconf/go-cty/cty/function"
	"github.com/zclconf/go-cty/cty/function/stdlib"
	ctyjson "github.com/zclconf/go-cty/cty/json"
)

type testCase struct {
	label   string
	text    string
	context map[string]string // name -> JSON the name is bound to
	refuse  bool
}

var cases []testCase

func add(label, text string) {
	cases = append(cases, testCase{label: label, text: text})
}

func addWith(label, text string, context map[string]string) {
	cases = append(cases, testCase{label: label, text: text, context: context})
}

func addBad(label, text string) {
	cases = append(cases, testCase{label: label, text: text, refuse: true})
}

func addBadWith(label, text string, context map[string]string) {
	cases = append(cases, testCase{label: label, text: text, context: context, refuse: true})
}

func main() {
	// Values.
	add("plain", "a = 1\nb = 1.5\nc = true\nd = null\ne = \"x\"\n")
	add("negative numbers", "a = -1\nb = -2.5\nc = 1e3\n")
	add("list", "a = [1, 2, 3]\n")
	add("object", "a = { x = 1, y = 2 }\n")
	add("nested collections", "a = [{ b = [1, { c = 2 }] }]\n")
	add("comments", "# one\n// two\na = 1 # three\n")
	add("string escapes", "a = \"one\\ttwo\\nthree \\\"q\\\" \\\\\"\n")
	add("unicode escape", "a = \"caf\\u00e9\"\n")
	add("escaped template opener", "a = \"$${not a reference}\"\n")

	// Operators.
	add("arithmetic", "a = 1 + 2 * 3\nb = 7 / 2\nc = 7 % 2\nd = 2 - 5\n")
	add("unary", "a = -3\nb = !true\n")
	add("comparison", "a = 3 > 2\nb = 3 <= 2\nc = 1 == 1\nd = 1 != 2\n")
	add("logic", "a = true && false\nb = true || false\n")
	add("conditional", "a = 3 > 2 ? \"yes\" : \"no\"\n")
	add("parentheses", "a = (1 + 2) * 3\n")

	// Templates.
	addWith(
		"interpolation",
		"a = \"http://${host}:8080\"\n",
		map[string]string{"host": `"web"`},
	)
	add("template if", "a = \"%{ if true }yes%{ else }no%{ endif }\"\n")
	add("template for", "a = \"%{ for x in [1, 2] }<${x}>%{ endfor }\"\n")
	add("template strip markers", "a = <<EOF\none\n%{~ if true ~}\ntwo\n%{ endif }\nEOF\n")
	add("heredoc", "a = <<EOF\nhello\nbye\nEOF\n")
	add("indented heredoc", "a = <<-EOF\n    one\n      two\n    EOF\n")
	add("heredoc interpolates", "a = <<EOF\n${1 + 1}\nEOF\n")

	// for expressions and splats.
	add("for list", "a = [for x in [1, 2, 3] : x * 2]\n")
	add("for list with a filter", "a = [for x in [1, 2, 3] : x if x % 2 == 0]\n")
	add("for with an index", "a = [for i, x in [\"a\", \"b\"] : \"${i}${x}\"]\n")
	add("for object", "a = { for k, v in { x = 1, y = 2 } : k => v + 1 }\n")
	add("for object grouping", "a = { for x in [1, 1, 2] : \"k${x}\" => x... }\n")
	add("splat", "a = [{ n = 1 }, { n = 2 }][*].n\n")
	addWith(
		"attribute splat",
		"b = var.a.xs[*].n\n",
		map[string]string{"var": `{"a": {"xs": [{"n": 1}, {"n": 2}]}}`},
	)

	// Names from the context.
	addWith(
		"names and indexing",
		"a = var.region\nb = var.tags[\"env\"]\n",
		map[string]string{"var": `{"region": "eu-west-1", "tags": {"env": "prod"}}`},
	)
	addWith(
		"a list from the context",
		"a = var.hosts[1]\nb = length(var.hosts)\n",
		map[string]string{"var": `{"hosts": ["one", "two"]}`},
	)

	// Blocks.
	add("block with a label", "server \"web\" {\n  port = 80\n}\n")
	add("block with two labels", "resource \"aws_instance\" \"web\" {\n  ami = \"abc\"\n}\n")
	add("nested blocks", "outer {\n  inner {\n    a = 1\n  }\n}\n")
	add("repeated blocks", "server \"a\" {\n  port = 1\n}\nserver \"b\" {\n  port = 2\n}\n")
	add("attribute and block side by side", "name = \"web\"\nserver \"a\" {\n  port = 1\n}\n")
	add("empty block", "server \"a\" {\n}\n")

	// Functions this library provides.
	add("upper and lower", "a = upper(\"web\")\nb = lower(\"WEB\")\n")
	add("trim", "a = trim(\"  x  \")\n")
	add("length", "a = length(\"abc\")\nb = length([1, 2])\n")
	add("join", "a = join(\",\", [\"x\", \"y\"])\n")
	add("concat", "a = concat([1], [2, 3])\n")
	add("coalesce", "a = coalesce(null, \"b\")\n")

	// Refusals.
	addBad("a name nothing defines", "a = var.nope\n")
	addBad("a function nothing defines", "a = nope(1)\n")
	addBad("the wrong number of arguments", "a = upper(\"x\", \"y\")\n")
	addBad("an unclosed body", "a = 1\nb {\n")
	addBad("an unclosed string", "a = \"x\n")
	addBad("arithmetic on text", "a = \"x\" * 2\n")
	addBad("an unknown step into a value", "a = true.nope\n")

	emit()
}

// standardFunctions are the functions the library provides, mapped onto the ones
// the reference implementation ships.
func standardFunctions() map[string]function.Function {
	return map[string]function.Function{
		"upper":    stdlib.UpperFunc,
		"lower":    stdlib.LowerFunc,
		"trim":     stdlib.TrimSpaceFunc,
		"length":   lengthFunc(),
		"join":     stdlib.JoinFunc,
		"concat":   stdlib.ConcatFunc,
		"coalesce": stdlib.CoalesceFunc,
	}
}

// lengthFunc answers the number of members of a list, a mapping or a string,
// which is the one `length` this library provides. The reference's own `length`
// is the string-only `strlen`, so the case list would otherwise be comparing two
// different questions.
func lengthFunc() function.Function {
	return function.New(&function.Spec{
		Params: []function.Parameter{{
			Name:             "value",
			Type:             cty.DynamicPseudoType,
			AllowDynamicType: true,
			AllowNull:        true,
		}},
		Type: func(args []cty.Value) (cty.Type, error) { return cty.Number, nil },
		Impl: func(args []cty.Value, retType cty.Type) (cty.Value, error) {
			value := args[0]
			if value.IsNull() {
				return cty.NilVal, fmt.Errorf("nothing has no length")
			}
			switch {
			case value.Type() == cty.String:
				return cty.NumberIntVal(int64(len(value.AsString()))), nil
			case value.Type().IsTupleType(), value.Type().IsListType(),
				value.Type().IsSetType(), value.Type().IsMapType(),
				value.Type().IsObjectType():
				return cty.NumberIntVal(int64(value.LengthInt())), nil
			}
			return cty.NilVal, fmt.Errorf("a %s has no length", value.Type().FriendlyName())
		},
	})
}

// evaluated is the tree the reference reads out of a body: attributes under
// their names, and blocks under theirs, a repeated block name collecting a list.
func evaluated(body *hclsyntax.Body, ctx *hcl.EvalContext) (map[string]any, error) {
	out := map[string]any{}
	names := make([]string, 0, len(body.Attributes))
	for name := range body.Attributes {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		value, diags := body.Attributes[name].Expr.Value(ctx)
		if diags.HasErrors() {
			return nil, fmt.Errorf("%s: %s", name, diags.Error())
		}
		text, err := toJSON(value)
		if err != nil {
			return nil, err
		}
		out[name] = text
	}
	kinds := []string{}
	seen := map[string]bool{}
	for _, block := range body.Blocks {
		if !seen[block.Type] {
			seen[block.Type] = true
			kinds = append(kinds, block.Type)
		}
	}
	sort.Strings(kinds)
	for _, kind := range kinds {
		ones := []any{}
		for _, block := range body.Blocks {
			if block.Type != kind {
				continue
			}
			inner, err := evaluated(block.Body, ctx)
			if err != nil {
				return nil, err
			}
			ones = append(ones, inner)
		}
		if len(ones) == 1 {
			out[kind] = ones[0]
		} else {
			out[kind] = ones
		}
	}
	return out, nil
}

func labels(body *hclsyntax.Body) map[string][]string {
	out := map[string][]string{}
	for _, block := range body.Blocks {
		out[block.Type] = append(out[block.Type], strings.Join(block.Labels, "/"))
	}
	return out
}

// toJSON reads a value into the same shapes `encoding/json` produces, so that
// one walk can print both.
func toJSON(value cty.Value) (any, error) {
	if !value.IsKnown() || value.IsNull() {
		return nil, nil
	}
	encoded, err := ctyjson.Marshal(value, value.Type())
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(strings.NewReader(string(encoded)))
	decoder.UseNumber()
	var out any
	if err := decoder.Decode(&out); err != nil {
		return nil, err
	}
	return out, nil
}

func emit() {
	path := filepath.Join("..", "..", "..", "src", "hcl", "vectors_test.mbt")
	var out strings.Builder
	out.WriteString("// Copyright 2026 Leo Cheng\n")
	out.WriteString("// SPDX-License-Identifier: Apache-2.0\n\n")
	out.WriteString("// Generated by scripts/vectors/hcl from hashicorp/hcl v2.24.0.\n")
	out.WriteString("// Do not edit by hand: the answers below are what that reader produced.\n\n")

	for _, one := range cases {
		body, diags := hclsyntax.ParseConfig([]byte(one.text), "main.hcl", hcl.Pos{Line: 1, Column: 1})
		var readErr error
		var tree map[string]any
		var bodyLabels map[string][]string
		if diags.HasErrors() {
			readErr = fmt.Errorf("%s", diags.Error())
		} else {
			ctx := &hcl.EvalContext{Variables: map[string]cty.Value{}, Functions: standardFunctions()}
			for name, json := range one.context {
				var value cty.Value
				value, readErr = parseJSONValue(json)
				if readErr != nil {
					break
				}
				ctx.Variables[name] = value
			}
			if readErr == nil {
				parsed := body.Body.(*hclsyntax.Body)
				tree, readErr = evaluated(parsed, ctx)
				bodyLabels = labels(parsed)
			}
		}
		if one.refuse {
			if readErr == nil {
				panic("case `" + one.label + "` was expected to be refused, and was read")
			}
			out.WriteString("///|\n")
			out.WriteString("test \"hashicorp hcl: " + one.label + " refused\" {\n")
			out.WriteString("  let refused = Ok(" + readCall(one) + ") catch { error => Err(error) }\n")
			out.WriteString("  match refused {\n    Err(_) => ()\n")
			out.WriteString("    Ok(_) => fail(\"this document should be refused\")\n  }\n}\n\n")
			continue
		}
		if readErr != nil {
			panic("case `" + one.label + "` was expected to read: " + readErr.Error())
		}
		out.WriteString("///|\n")
		out.WriteString("test \"hashicorp hcl: " + one.label + "\" {\n")
		out.WriteString("  let body = " + readCall(one) + "\n")
		out.WriteString("  let tree = body.tree(\"main.hcl\")\n")
		for _, line := range flatten(tree) {
			out.WriteString("  " + line + "\n")
		}
		kinds := make([]string, 0, len(bodyLabels))
		for kind := range bodyLabels {
			kinds = append(kinds, kind)
		}
		sort.Strings(kinds)
		for _, kind := range kinds {
			quoted := make([]string, 0, len(bodyLabels[kind]))
			for _, one := range bodyLabels[kind] {
				quoted = append(quoted, quote(one))
			}
			out.WriteString("  assert_eq(body.blocks_of(" + quote(kind) + ").map(fn(b) { b.labels.join(\"/\") }), [" +
				strings.Join(quoted, ", ") + "])\n")
		}
		out.WriteString("}\n\n")
	}

	if err := os.WriteFile(path, []byte(out.String()), 0o644); err != nil {
		panic(err)
	}
	fmt.Printf("wrote %s (%d cases)\n", path, len(cases))
}

func parseJSONValue(text string) (cty.Value, error) {
	decoder := json.NewDecoder(strings.NewReader(text))
	decoder.UseNumber()
	var anyValue any
	if err := decoder.Decode(&anyValue); err != nil {
		return cty.NilVal, err
	}
	return toCty(anyValue)
}

func toCty(value any) (cty.Value, error) {
	switch one := value.(type) {
	case nil:
		return cty.NullVal(cty.DynamicPseudoType), nil
	case bool:
		return cty.BoolVal(one), nil
	case string:
		return cty.StringVal(one), nil
	case json.Number:
		if strings.ContainsAny(one.String(), ".eE") {
			f, err := one.Float64()
			if err != nil {
				return cty.NilVal, err
			}
			return cty.NumberFloatVal(f), nil
		}
		i, err := one.Int64()
		if err != nil {
			return cty.NilVal, err
		}
		return cty.NumberIntVal(i), nil
	case []any:
		items := make([]cty.Value, 0, len(one))
		for _, item := range one {
			value, err := toCty(item)
			if err != nil {
				return cty.NilVal, err
			}
			items = append(items, value)
		}
		return cty.TupleVal(items), nil
	case map[string]any:
		names := make([]string, 0, len(one))
		for name := range one {
			names = append(names, name)
		}
		sort.Strings(names)
		members := map[string]cty.Value{}
		for _, name := range names {
			value, err := toCty(one[name])
			if err != nil {
				return cty.NilVal, err
			}
			members[name] = value
		}
		return cty.ObjectVal(members), nil
	}
	return cty.NilVal, fmt.Errorf("unexpected value %T", value)
}

// readCall writes the call that reads a case. The reference always has the
// standard functions in scope, so the call passes the same set.
func readCall(one testCase) string {
	call := "@hcl.parse(" + quote(one.text)
	call += ",\n    context=" + contextCall(one.context)
	return call + ")"
}

func contextCall(context map[string]string) string {
	names := make([]string, 0, len(context))
	for name := range context {
		names = append(names, name)
	}
	sort.Strings(names)
	call := "@hcl.standard()"
	for _, name := range names {
		call += ".bind(" + quote(name) + ", " + nodeCall(context[name], "vars") + ")"
	}
	return call
}

// nodeCall writes the MoonBit that builds the same value.
func nodeCall(text string, source string) string {
	decoder := json.NewDecoder(strings.NewReader(text))
	decoder.UseNumber()
	var value any
	if err := decoder.Decode(&value); err != nil {
		panic(err)
	}
	return nodeValue(value, source)
}

func nodeValue(value any, source string) string {
	switch one := value.(type) {
	case nil:
		return "@moonconf.Node::new(@moonconf.Value::Null, " + quote(source) + ", @moonconf.start)"
	case bool:
		return "@moonconf.Node::flag(" + fmt.Sprintf("%t", one) + ", " + quote(source) + ")"
	case string:
		return "@moonconf.Node::str(" + quote(one) + ", " + quote(source) + ")"
	case json.Number:
		if strings.ContainsAny(one.String(), ".eE") {
			return "@moonconf.Node::of_real(" + one.String() + ", " + quote(source) + ")"
		}
		return "@moonconf.Node::num(" + one.String() + "L, " + quote(source) + ")"
	case []any:
		items := make([]string, 0, len(one))
		for _, item := range one {
			items = append(items, nodeValue(item, source))
		}
		return "@moonconf.Node::seq([" + strings.Join(items, ", ") + "], " + quote(source) + ")"
	case map[string]any:
		names := make([]string, 0, len(one))
		for name := range one {
			names = append(names, name)
		}
		sort.Strings(names)
		pairs := make([]string, 0, len(names))
		for _, name := range names {
			pairs = append(pairs, "("+quote(name)+", "+nodeValue(one[name], source)+")")
		}
		return "@moonconf.Node::map([" + strings.Join(pairs, ", ") + "], " + quote(source) + ")"
	}
	panic(fmt.Sprintf("unexpected value %T", value))
}

// flatten turns a tree into the assertions that read it back.
func flatten(tree map[string]any) []string {
	lines := []string{}
	var walk func(path string, value any)
	walk = func(path string, value any) {
		switch one := value.(type) {
		case map[string]any:
			if len(one) == 0 {
				if path == "" {
					lines = append(lines, "assert_eq(tree.table().length(), 0)")
				} else {
					lines = append(lines, "assert_eq(tree.need("+quote(path)+").table().length(), 0)")
				}
				return
			}
			names := make([]string, 0, len(one))
			for name := range one {
				names = append(names, name)
			}
			sort.Strings(names)
			for _, name := range names {
				next := name
				if path != "" {
					next = path + "." + segment(name)
				} else {
					next = segment(name)
				}
				walk(next, one[name])
			}
		case []any:
			lines = append(lines, fmt.Sprintf("assert_eq(tree.need(%s).list().length(), %d)", quote(path), len(one)))
			for index, item := range one {
				walk(fmt.Sprintf("%s.%d", path, index), item)
			}
		case string:
			lines = append(lines, "assert_eq(tree.need_text("+quote(path)+"), "+quote(one)+")")
		case bool:
			lines = append(lines, "assert_eq(tree.need_bool("+quote(path)+"), "+fmt.Sprintf("%t", one)+")")
		case json.Number:
			text := one.String()
			if strings.ContainsAny(text, ".eE") {
				lines = append(lines, "assert_eq(tree.need("+quote(path)+").real(), "+text+")")
			} else {
				lines = append(lines, "assert_eq(tree.need_int("+quote(path)+"), "+text+"L)")
			}
		case nil:
			lines = append(lines, "assert_eq(tree.need("+quote(path)+").kind(), \"null\")")
		}
	}
	names := make([]string, 0, len(tree))
	for name := range tree {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		walk(segment(name), tree[name])
	}
	return lines
}

func segment(name string) string {
	var out strings.Builder
	for _, c := range name {
		if c == '\\' || c == '.' {
			out.WriteByte('\\')
		}
		out.WriteRune(c)
	}
	return out.String()
}

func quote(text string) string {
	var out strings.Builder
	out.WriteByte('"')
	for _, c := range text {
		switch c {
		case '\\':
			out.WriteString("\\\\")
		case '"':
			out.WriteString("\\\"")
		case '\n':
			out.WriteString("\\n")
		case '\t':
			out.WriteString("\\t")
		case '\r':
			out.WriteString("\\r")
		default:
			out.WriteRune(c)
		}
	}
	out.WriteByte('"')
	return out.String()
}
