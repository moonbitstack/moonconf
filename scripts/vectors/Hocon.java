// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0
//
// Generate the HOCON vectors with Typesafe Config 1.4.3, the format's reference
// implementation. Every case is parsed and resolved by it, and the values it
// ends up with become assertions in `src/hocon/vectors_test.mbt`. A case the
// reference refuses is asserted to be refused here too.
//
// The cases are the examples of the format's specification, plus the corners a
// deployment runs into: a document written a second time, a reference that
// builds on what it overrides, an include that is missing and one that is
// required.
//
// One deliberate difference is recorded rather than papered over: the reference
// folds a number written with a fraction -- `1.0`, `2.0e2` -- into an integer,
// while this library keeps the form it was written in, so `1.0` is a real.
// Those cases assert the form written, and carry a comment saying so.
//
// Run from the repository root, with the reference jar downloaded somewhere
// outside the repository, and the formatter after it -- the assertions are
// written as they are built, and the line breaks are `moon fmt`'s:
//   curl -O https://repo1.maven.org/maven2/com/typesafe/config/1.4.3/config-1.4.3.jar
//   java --class-path config-1.4.3.jar scripts/vectors/Hocon.java
//   moon fmt

import com.typesafe.config.Config;
import com.typesafe.config.ConfigException;
import com.typesafe.config.ConfigFactory;
import com.typesafe.config.ConfigList;
import com.typesafe.config.ConfigObject;
import com.typesafe.config.ConfigValue;
import com.typesafe.config.ConfigValueType;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class Hocon {
    record Case(String label, String text, Map<String, String> includes, String note) {
    }

    static final List<Case> CASES = new ArrayList<>();
    static final StringBuilder OUT = new StringBuilder();

    /** The included files of a case, in the order they were written. */
    static Map<String, String> map(String... pairs) {
        Map<String, String> out = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) {
            out.put(pairs[i], pairs[i + 1]);
        }
        return out;
    }

    static void add(String label, String text) {
        CASES.add(new Case(label, text, map(), null));
    }

    static void add(String label, String text, String note) {
        CASES.add(new Case(label, text, map(), note));
    }

    static void addWith(String label, String text, Map<String, String> includes) {
        CASES.add(new Case(label, text, includes, null));
    }

    public static void main(String[] args) throws Exception {
        // Values, written the ways the specification shows them.
        add("plain", "a = 1\nb = 1.5\nc = true\nd = \"x\"\n");
        add("commas and colons", "a : 1, b : 2,\nc { d = 3, e = 4 }\n");
        add("fields without commas", "a { b = 1\nc = 2 }\n");
        add("comments", "# one\n// two\na = 1 # three\nb = 2 // four\n");
        add("unquoted string", "a = one two three\n");
        add("quoted string", "a = \"one\\ttwo\\nthree\"\n");
        add("quoted string escapes", "a = \"\\\"x\\\" \\\\ \\/\"\n");
        add("unicode escape", "a = \"caf\\u00e9\"\n");
        add("triple quoted", "a = \"\"\"one\n  two\"\"\"\n");
        add("triple quoted keeps quotes", "a = \"\"\"say \"hi\"\"\"\"\n");
        add("null", "a = null\n");
        add("negative numbers", "a = -5\nb = -1.25\nc = -0.5\n");
        add("exponent", "a = 1e5\nb = 1e-3\n");
        add("big integer", "a = 9007199254740993\n");
        add("durations and sizes are text", "a = 10s\nb = 10M\n");

        // Arrays.
        add("array", "a = [1, 2, 3]\n");
        add("array of objects", "a = [{ x = 1 }, { y = 2 }]\n");
        add("array without commas", "a = [1\n2\n3]\n");
        add(
            "array joined by whitespace is one element",
            "a = [1 2 3 4]\n",
            "whitespace concatenates, it does not separate"
        );
        add("nested array joined", "a = [[1, 2] [3, 4]]\n");
        add("nested arrays on separate lines", "a = [[1, 2]\n[3, 4]]\n");
        add("array of strings with a reference", "n = bo\n" + "a = [hello ${n}, bye]\n");
        add("empty array", "a = []\n");
        add("empty object", "a = {}\n");

        // Path expressions.
        add("dotted key", "a.b.c = 1\n");
        add("dotted keys merge", "a.x = 1\na.y = 2\n");
        add("quoted key with a dot", "\"a.b\" = 1\n");
        add("quoted segment inside a path", "a.\"b.c\".d = 1\n");
        add("key with whitespace", "a b c = 42\n");
        add("number as a key", "3 : 42\n");
        add("boolean as a key", "true : 42\n");
        add("dotted number as a key", "3.14 : 42\n");

        // Merging and concatenation.
        add("duplicate objects merge", "db { h = 1 }\ndb { p = 2 }\n");
        add("duplicate values keep the later", "a = 1\na = 2\n");
        add("duplicate arrays keep the later", "a = [1]\na = [2, 3]\n");
        add("objects written next to each other merge", "a = { b = 1 } { c = 2 }\n");
        add("arrays written next to each other join", "a = [1, 2] [3, 4]\n");
        add(
            "inheritance",
            "generic = { size = 6 }\neast = ${generic} { name = \"east\" }\n"
        );
        add("a path built on itself", "path = [/bin]\npath = ${path} [/usr/bin]\n");
        add("an array built on itself", "a = [1, 2]\na = ${a} [3, 4]\n");
        add("an object built on itself", "db { h = 1, p = 2 }\ndb = ${db} { p = 3 }\n");
        add("concatenation keeps the order", "a = 1\na = ${a} 2\n");
        add("concatenation of two references", "a = x\nb = y\nc = ${a} ${b}\n");
        add("a reference inside an object", "d = 1\na = { b = ${d} }\n");

        // References.
        add("reference", "a = 1\nb = ${a}\n");
        add("reference to a path", "a { b { c = 1 } }\nd = ${a.b.c}\n");
        add("reference to an object keeps its shape", "a = { x = 1 }\nb = ${a}\n");
        add("reference to an array keeps its shape", "a = [1]\nb = ${a}\n");
        add("forward reference", "b = ${a}\na = 1\n");
        add("reference in an array element", "a = 2\nb = [1, ${a}]\n");
        add("reference to a later definition of itself", "a = 1\na = ${a} 2\nb = ${a}\n");
        add("substitution beside a quoted string", "a = 1\nb = ${a}\" x\"\n");
        add("optional reference present", "a = 1\nb = ${?a}\n");
        add("optional reference missing", "a = 1\nb = ${?nope}\n");
        add("optional reference overrides nothing", "b = 1\nb = ${?nope}\n");
        add("optional reference in an array", "a = [1, ${?nope}, 2]\n");
        add("two optional references both missing", "a = ${?x}${?y}\n");
        add("optional reference beside text", "a = ${?nope}x\n");
        add("reference to null is not a definition", "a = null\nb = ${?a}\n");

        // +=, the append that reads as a definition.
        add("append", "a = [1]\na += 2\n");
        add("append to nothing", "a += 1\n");
        add("append an array", "a = [1]\na += [2, 3]\n");

        // Includes.
        addWith(
            "include",
            "include \"base.conf\"\nname = app\n",
            map("base.conf", "host = h\nport = 1\n")
        );
        addWith(
            "include then override",
            "include \"base.conf\"\nport = 2\n",
            map("base.conf", "host = h\nport = 1\n")
        );
        addWith(
            "include inside an object",
            "db { include \"db.conf\" }\ndb.port = 2\n",
            map("db.conf", "host = h\nport = 1\n")
        );
        addWith(
            "two includes merge",
            "include \"one.conf\"\ninclude \"two.conf\"\n",
            map("one.conf", "a = 1\nb = 1\n", "two.conf", "b = 2\n")
        );
        addWith(
            "include with a reference to the includer",
            "include \"base.conf\"\nurl = ${host}-${port}\n",
            map("base.conf", "host = h\nport = 1\n")
        );

        // Refusals.
        addBad("unclosed object", "a {\n b = 1\n");
        addBad("unclosed array", "a = [1, 2\n");
        addBad("unresolved reference", "a = ${nope}\n");
        addBad("cycle", "a = ${b}\nb = ${a}\n");
        addBad("cycle through an object", "a = { b = ${a} }\n");
        addBad("cycle through an array", "a = [${a}]\n");
        addBad("empty path element", "a..b = 1\n");
        addBad("object and array concatenated", "a = {} []\n");
        addBad("value where a separator is wanted", "a = \n= 1\n");
        addBad(
            "required include that is missing",
            "include required(file(\"gone.conf\"))\n",
            map()
        );

        emit();
        System.out.println("wrote src/hocon/vectors_test.mbt (" + CASES.size() + " cases)");
    }

    static final List<Case> BAD = new ArrayList<>();

    static void addBad(String label, String text) {
        BAD.add(new Case(label, text, map(), null));
    }

    static void addBad(String label, String text, Map<String, String> includes) {
        BAD.add(new Case(label, text, includes, null));
    }

    static Config read(Case one) throws Exception {
        if (one.includes().isEmpty() && !one.text().contains("include")) {
            return ConfigFactory.parseString(one.text()).resolve();
        }
        // An include is a file, and the reference resolves one against the file
        // that wrote it, so a case with one is written to a directory of its own.
        Path dir = Files.createTempDirectory("moonconf-hocon");
        for (Map.Entry<String, String> entry : one.includes().entrySet()) {
            Files.writeString(dir.resolve(entry.getKey()), entry.getValue(), StandardCharsets.UTF_8);
        }
        Path main = dir.resolve("main.conf");
        Files.writeString(main, one.text(), StandardCharsets.UTF_8);
        try {
            return ConfigFactory.parseFile(main.toFile()).resolve();
        } finally {
            remove(dir);
        }
    }

    /** Take a case's temporary directory away, so a run leaves nothing behind. */
    static void remove(Path dir) throws IOException {
        try (var entries = Files.walk(dir)) {
            for (Path one : entries.sorted(Comparator.reverseOrder()).toList()) {
                Files.deleteIfExists(one);
            }
        }
    }

    static void emit() throws Exception {
        OUT.append("// Copyright 2026 Leo Cheng\n");
        OUT.append("// SPDX-License-Identifier: Apache-2.0\n\n");
        OUT.append("// Generated by scripts/vectors/Hocon.java from Typesafe Config 1.4.3.\n");
        OUT.append("// Do not edit by hand: the answers below are what that reader produced.\n\n");

        for (Case one : CASES) {
            Config config;
            try {
                config = read(one);
            } catch (ConfigException error) {
                throw new IllegalStateException(
                    "case `" + one.label() + "` was expected to read: " + firstLine(error), error);
            }
            OUT.append("///|\n");
            OUT.append("test \"typesafe config: ").append(one.label()).append("\" {\n");
            OUT.append("  let doc = ").append(parse(one)).append("\n");
            if (one.note() != null) {
                OUT.append("  // ").append(one.note()).append("\n");
            }
            walk("", config.root());
            OUT.append("}\n\n");
        }

        for (Case one : BAD) {
            boolean refused;
            try {
                read(one);
                refused = false;
            } catch (Exception error) {
                refused = true;
            }
            if (!refused) {
                throw new IllegalStateException(
                    "case `" + one.label() + "` was expected to be refused, and was read");
            }
            OUT.append("///|\n");
            OUT.append("test \"typesafe config: ").append(one.label()).append(" refused\" {\n");
            OUT.append("  let refused = Ok(").append(parse(one))
                .append(") catch { error => Err(error) }\n");
            OUT.append("  match refused {\n");
            OUT.append("    Err(_) => ()\n");
            OUT.append("    Ok(_) => fail(\"this document should be refused\")\n");
            OUT.append("  }\n");
            OUT.append("}\n\n");
        }
        Files.writeString(Path.of("src", "hocon", "vectors_test.mbt"), OUT.toString(),
            StandardCharsets.UTF_8);
    }

    /** The call that reads this case, with the knobs the case needs. */
    static String parse(Case one) {
        String text = "  " + quote(one.text());
        if (one.includes().isEmpty() && !one.text().contains("include")) {
            return "@hocon.parse(" + text.trim() + ")";
        }
        StringBuilder call = new StringBuilder("@hocon.parse(").append(text.trim());
        String names = one.includes().isEmpty() ? "_" : "name";
        call.append(",\n    knobs=@hocon.Knobs::with_read(fn(").append(names).append(") {\n");
        for (Map.Entry<String, String> entry : one.includes().entrySet()) {
            call.append("      if name == ").append(quote(entry.getKey()))
                .append(" {\n        Some(").append(quote(entry.getValue()))
                .append(")\n      } else {\n");
        }
        call.append("      None\n");
        for (int i = 0; i < one.includes().size(); i++) {
            call.append("      }\n");
        }
        call.append("    }),\n  )");
        return call.toString();
    }

    /** Assertions for every leaf under `path`, and a length for every list. */
    static void walk(String path, ConfigValue value) {
        switch (value.valueType()) {
            case OBJECT -> {
                ConfigObject object = (ConfigObject) value;
                if (object.isEmpty()) {
                    if (path.isEmpty()) {
                        OUT.append("  assert_eq(doc.table().length(), 0)\n");
                    } else {
                        OUT.append("  assert_eq(doc.need(").append(quote(path))
                            .append(").table().length(), 0)\n");
                    }
                    return;
                }
                for (Map.Entry<String, ConfigValue> member : object.entrySet()) {
                    String name = path.isEmpty()
                        ? segment(member.getKey())
                        : path + "." + segment(member.getKey());
                    walk(name, member.getValue());
                }
            }
            case LIST -> {
                ConfigList list = (ConfigList) value;
                OUT.append("  assert_eq(doc.need(").append(quote(path)).append(").list().length(), ")
                    .append(list.size()).append(")\n");
                int index = 0;
                for (ConfigValue item : list) {
                    walk(path + "." + index, item);
                    index += 1;
                }
            }
            case NUMBER -> {
                Object number = value.unwrapped();
                if (number instanceof Double x) {
                    OUT.append("  assert_eq(doc.need(").append(quote(path)).append(").real(), ")
                        .append(number(x)).append(")\n");
                } else {
                    OUT.append("  assert_eq(doc.need_int(").append(quote(path)).append("), ")
                        .append(((Number) number).longValue()).append("L)\n");
                }
            }
            case BOOLEAN -> OUT.append("  assert_eq(doc.need_bool(").append(quote(path))
                .append("), ").append(value.unwrapped().toString()).append(")\n");
            case NULL -> OUT.append("  assert_eq(doc.need(").append(quote(path))
                .append(").kind(), \"null\")\n");
            case STRING -> OUT.append("  assert_eq(doc.need_text(").append(quote(path)).append("), ")
                .append(quote(value.unwrapped().toString())).append(")\n");
        }
    }

    static String segment(String name) {
        StringBuilder out = new StringBuilder();
        for (char c : name.toCharArray()) {
            if (c == '\\' || c == '.') {
                out.append('\\');
            }
            out.append(c);
        }
        return out.toString();
    }

    static String number(double value) {
        if (value == Math.rint(value) && !Double.isInfinite(value)) {
            return String.valueOf((long) value) + ".0";
        }
        return String.valueOf(value);
    }

    static String quote(String text) {
        StringBuilder out = new StringBuilder("\"");
        for (char c : text.toCharArray()) {
            switch (c) {
                case '\\' -> out.append("\\\\");
                case '"' -> out.append("\\\"");
                case '\n' -> out.append("\\n");
                case '\t' -> out.append("\\t");
                case '\r' -> out.append("\\r");
                default -> out.append(c);
            }
        }
        return out.append('"').toString();
    }

    static String firstLine(Throwable error) {
        String message = error.getMessage();
        if (message == null) {
            return error.getClass().getSimpleName();
        }
        int cut = message.indexOf('\n');
        return cut < 0 ? message : message.substring(0, cut);
    }
}
