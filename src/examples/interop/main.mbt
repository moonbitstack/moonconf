// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The documents this library writes, printed for another reader to read back.
///
/// Each one is printed as a line `@@ name` followed by the document itself, so
/// that `scripts/interop/read_back.py` can hand it to a reader of the same
/// format that was written by somebody else. What this program prints is the
/// answer: whether a reader on the other side accepts it is the point.
///
///     moon run src/examples/interop
#coverage.skip
fn main raise {
  let ini = @ini.parse("[db]\nhost = localhost\nport = 5432\n")
  println("@@ ini")
  println(@ini.dumps(ini))

  let props = @props.parse("db.host=localhost\ndb.port=5432\n")
  println("@@ props")
  println(@props.dumps(props))

  let env = @dotenv.parse("HOST=localhost\nDSN=postgres://localhost/app\n")
  println("@@ dotenv")
  println(@dotenv.dumps(env.entries))

  let hocon = @hocon.parse("db { host = localhost, port = 5432 }\n")
  println("@@ hocon")
  println(@moonconf.native(hocon).stringify())
}
