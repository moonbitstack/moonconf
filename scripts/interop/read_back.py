#!/usr/bin/env python3
"""Read this library's own output with readers written by somebody else.

The vectors check one direction: another implementation writes a document, this
library reads it. This checks the other: this library writes a document, and
another reader of the same format reads it back to the same values.

The documents come from `src/examples/interop`, which prints them:

    moon run src/examples/interop > interop.txt
    python scripts/interop/read_back.py interop.txt

Each format is read by a reader that has nothing to do with this repository:
INI by Python's `configparser`, Java properties by `java.util.Properties`, `.env`
by `python-dotenv`, and the tree a HOCON document reads to by `pyhocon` — JSON is
HOCON, so what this library prints as JSON is a document that reader accepts.

`moonconf/hcl` has nothing to read back: it evaluates a document against a
context, and the format has no form this library writes.

A document that the other reader refuses, or reads differently, fails the run.
"""

import configparser
import io
import os
import subprocess
import sys
import tempfile

# The values the documents in src/examples/interop hold. A change there is a
# change here, which is the point: what is compared is the value, not the text.
VALUES = {
    "ini": {"db": {"host": "localhost", "port": "5432"}},
    "props": {"db.host": "localhost", "db.port": "5432"},
    "dotenv": {"HOST": "localhost", "DSN": "postgres://localhost/app"},
    "hocon": {"db": {"host": "localhost", "port": 5432}},
}

PROPERTIES_READER = """
import java.io.FileInputStream;
import java.util.Properties;
import java.util.TreeMap;

public class ReadProperties {
  public static void main(String[] args) throws Exception {
    Properties properties = new Properties();
    try (FileInputStream stream = new FileInputStream(args[0])) {
      properties.load(stream);
    }
    TreeMap<String, String> sorted = new TreeMap<>();
    for (String key : properties.stringPropertyNames()) {
      sorted.put(key, properties.getProperty(key));
    }
    for (var entry : sorted.entrySet()) {
      System.out.println(entry.getKey() + "=" + entry.getValue());
    }
  }
}
"""


def split(text):
    """The documents the example printed, by name."""
    out = {}
    name = None
    body = []
    for line in text.split("\n"):
        if line.startswith("@@ "):
            if name is not None:
                out[name] = "\n".join(body).strip("\n")
            name = line[3:].strip()
            body = []
            continue
        body.append(line)
    if name is not None:
        out[name] = "\n".join(body).strip("\n")
    return out


def check_ini(text):
    reader = configparser.ConfigParser()
    reader.read_string(text)
    want = VALUES["ini"]
    if reader.sections() != list(want):
        return f"configparser reads sections {reader.sections()}, not {list(want)}"
    for section, options in want.items():
        if reader.options(section) != list(options):
            return f"configparser reads {reader.options(section)} in {section}"
        for name, value in options.items():
            if reader.get(section, name) != value:
                return f"configparser reads {name} as {reader.get(section, name)!r}"
    return None


def check_props(text):
    with tempfile.TemporaryDirectory() as directory:
        source = os.path.join(directory, "ReadProperties.java")
        with open(source, "w", encoding="utf-8") as handle:
            handle.write(PROPERTIES_READER)
        properties = os.path.join(directory, "app.properties")
        with open(properties, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        outcome = subprocess.run(
            ["java", source, properties], capture_output=True, text=True, check=False
        )
    if outcome.returncode != 0:
        return "java.util.Properties refuses it: " + outcome.stderr.strip().split("\n")[0]
    found = dict(
        line.split("=", 1) for line in outcome.stdout.strip().split("\n") if "=" in line
    )
    if found != VALUES["props"]:
        return f"java.util.Properties reads {found!r}"
    return None


def check_dotenv(text):
    from dotenv import dotenv_values

    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, "app.env")
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        found = {key: value for key, value in dotenv_values(path).items()}
    if found != VALUES["dotenv"]:
        return f"python-dotenv reads {found!r}"
    return None


def check_hocon(text):
    from pyhocon import ConfigFactory

    try:
        found = ConfigFactory.parse_string(text).as_plain_ordered_dict()
    except Exception as error:
        return "pyhocon refuses it: " + str(error).split("\n")[0]
    if found != VALUES["hocon"]:
        return f"pyhocon reads {found!r}"
    return None


CHECKERS = {
    "ini": check_ini,
    "props": check_props,
    "dotenv": check_dotenv,
    "hocon": check_hocon,
}


def main():
    if len(sys.argv) != 2:
        print("usage: read_back.py <the output of src/examples/interop>", file=sys.stderr)
        return 2
    documents = split(open(sys.argv[1], encoding="utf-8").read())
    failed = False
    for name, check in CHECKERS.items():
        if name not in documents:
            print(f"missing   {name}: the example did not print it")
            failed = True
            continue
        problem = check(documents[name])
        if problem is None:
            print(f"read back {name}")
        else:
            print(f"differs   {name}: {problem}")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
