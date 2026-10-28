name = "moonbitstack/moonconf"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonconf"

license = "Apache-2.0"

keywords = [
  "config",
  "ini",
  "properties",
  "dotenv",
  "hocon",
  "hcl",
  "moonbit",
]

description = "Configuration files, their expansion, their layering and their binding to a typed model."

source = "src"

import {
  "moonbitstack/moonmodel@0.1.0",
  "moonbitstack/moonyaml@0.1.2",
  "moonbitstack/moontoml@0.1.0",
  "moonbitstack/moonjson@0.4.1",
}
