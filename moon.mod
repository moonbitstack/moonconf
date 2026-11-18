name = "moonbitstack/moonconf"

version = "0.2.1"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonconf"

license = "Apache-2.0"

keywords = [
  "config",
  "configuration",
  "ini",
  "properties",
  "java-properties",
  "dotenv",
  "env",
  "hocon",
  "hcl",
  "variable-expansion",
  "interpolation",
  "layering",
  "binding",
  "settings",
  "moonbit",
]

description = "Configuration files, their expansion, their layering and their binding to a typed model."

source = "src"

import {
  "moonbitstack/moonmodel@0.2.1",
  "moonbitstack/moonyaml@0.2.1",
  "moonbitstack/moontoml@0.2.1",
  "moonbitstack/moonjson@0.5.1",
  "moonbitstack/moonknob@0.2.1",
}
