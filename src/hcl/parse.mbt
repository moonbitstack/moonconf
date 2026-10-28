// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
priv struct P {
  src : StringView
  ctx : Context
  source : String
  depth : Int32
  mut i : Int32
}

///|
fn is_space(c : Int32) -> Bool {
  c == ' '.to_int() ||
  c == '\t'.to_int() ||
  c == '\r'.to_int() ||
  c == '\n'.to_int()
}

///|
fn is_name_start(c : Int32) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  c == '_'.to_int()
}

///|
fn is_name_part(c : Int32) -> Bool {
  is_name_start(c) ||
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  c == '-'.to_int()
}

///|
fn P::at(self : P, index : Int32) -> Int32 {
  if index < self.src.length() {
    self.src.at(index).to_int()
  } else {
    -1
  }
}

///|
fn P::here(self : P) -> Int32 {
  self.at(self.i)
}

///|
fn P::spot(self : P, index : Int32) -> At {
  let mut line = 1
  let mut column = 1
  let mut i = 0
  while i < index && i < self.src.length() {
    if self.src.at(i).to_int() == 0x0A {
      line += 1
      column = 1
    } else {
      column += 1
    }
    i += 1
  }
  { at: index, line, column, }
}

///|
fn P::error(self : P, index : Int32) -> Refused {
  let c = self.at(index)
  if c == -1 {
    Unclosed(at=self.spot(index), got="the text")
  } else {
    Unexpected(at=self.spot(index), got=c.unsafe_to_char().to_string())
  }
}

///|
/// Past whitespace and comments.
fn P::space(self : P) -> Unit {
  while true {
    if is_space(self.here()) {
      self.i += 1
      continue
    }
    if self.here() == '#'.to_int() ||
      (self.here() == '/'.to_int() && self.at(self.i + 1) == '/'.to_int()) {
      while self.here() != -1 && self.here() != '\n'.to_int() {
        self.i += 1
      }
      continue
    }
    if self.here() == '/'.to_int() && self.at(self.i + 1) == '*'.to_int() {
      self.i += 2
      while self.here() != -1 &&
            !(self.here() == '*'.to_int() && self.at(self.i + 1) == '/'.to_int()) {
        self.i += 1
      }
      self.i += 2
      continue
    }
    return
  }
}

///|
fn P::name(self : P) -> String raise Refused {
  let from = self.i
  if !is_name_start(self.here()) {
    raise self.error(self.i)
  }
  self.i += 1
  while is_name_part(self.here()) {
    self.i += 1
  }
  self.src[from:self.i].to_owned()
}

///|
fn P::word(self : P, text : String) -> Bool {
  let mut i = 0
  while i < text.length() {
    if self.at(self.i + i) != text.at(i).to_int() {
      return false
    }
    i += 1
  }
  if is_name_part(self.at(self.i + text.length())) {
    return false
  }
  self.i += text.length()
  true
}

///|
/// A body: attributes and blocks, up to the closing brace or the end of the text.
fn P::body(self : P, braced : Bool) -> Body raise Refused {
  if self.depth > 64 {
    raise TooDeep(at=self.spot(self.i), limit=64)
  }
  let attributes : Array[(String, @moonconf.Node)] = []
  let blocks : Array[Block] = []
  while true {
    self.space()
    let c = self.here()
    if c == -1 {
      if braced {
        raise Unclosed(at=self.spot(self.i), got="{")
      }
      return { attributes, blocks, }
    }
    if c == '}'.to_int() {
      if !braced {
        raise Unexpected(at=self.spot(self.i), got="}")
      }
      self.i += 1
      return { attributes, blocks, }
    }
    let at = self.spot(self.i)
    if !is_name_start(c) {
      raise BadBody(at~, got=c.unsafe_to_char().to_string())
    }
    let key = self.name()
    self.space()
    if self.here() == '='.to_int() {
      self.i += 1
      let value = self.expression()
      attributes.push((key, value))
      continue
    }
    let labels : Array[String] = []
    while true {
      self.space()
      if self.here() == '"'.to_int() {
        labels.push(self.quoted())
        continue
      }
      if is_name_start(self.here()) {
        labels.push(self.name())
        continue
      }
      break
    }
    self.space()
    if self.here() != '{'.to_int() {
      raise BadBody(at~, got=self.describe(self.i))
    }
    self.i += 1
    let inner = self.body(true)
    blocks.push({ kind: key, labels, body: inner, at, })
  }
  { attributes, blocks, }
}

///|
fn P::describe(self : P, index : Int32) -> String {
  let c = self.at(index)
  if c == -1 {
    "the end"
  } else {
    c.unsafe_to_char().to_string()
  }
}

///|
/// A quoted string, with its escapes decoded and its `${…}` interpolated.
fn P::quoted(self : P) -> String raise Refused {
  let start = self.i
  self.i += 1
  let out = StringBuilder()
  while true {
    let c = self.here()
    if c == -1 || c == '\n'.to_int() {
      raise Unclosed(at=self.spot(start), got="\"")
    }
    if c == '"'.to_int() {
      self.i += 1
      return out.to_string()
    }
    if c == '\\'.to_int() {
      let next = self.at(self.i + 1)
      let decoded = match next {
        0x6E => '\n'
        0x74 => '\t'
        0x72 => '\r'
        0x22 => '"'
        0x5C => '\\'
        0x24 => '$'
        _ => next.unsafe_to_char()
      }
      out.write_char(decoded)
      self.i += 2
      continue
    }
    if c == '$'.to_int() && self.at(self.i + 1) == '{'.to_int() {
      self.i += 2
      let value = self.expression()
      self.space()
      if self.here() != '}'.to_int() {
        raise Unclosed(at=self.spot(self.i), got="${")
      }
      self.i += 1
      out.write_string(render(value))
      continue
    }
    out.write_char(c.unsafe_to_char())
    self.i += 1
  }
  out.to_string()
}

///|
/// A value as the text it stands for, which is what interpolation inserts.
fn render(node : @moonconf.Node) -> String {
  match node.value {
    @moonconf.Value::Null => ""
    @moonconf.Value::Bool(flag) => flag.to_string()
    @moonconf.Value::Int(n) => n.to_string()
    @moonconf.Value::Real(x) => x.to_string()
    @moonconf.Value::Text(text) => text
    @moonconf.Value::List(items) => {
      let parts = items.map(fn(item) { render(item) })
      "[" + parts.join(", ") + "]"
    }
    @moonconf.Value::Map(_) => "{…}"
  }
}

///|
/// One expression, evaluated as it is read.
fn P::expression(self : P) -> @moonconf.Node raise Refused {
  let condition = self.binary(0)
  self.space()
  if self.here() == '?'.to_int() {
    self.i += 1
    let yes = self.expression()
    self.space()
    if self.here() != ':'.to_int() {
      raise self.error(self.i)
    }
    self.i += 1
    let no = self.expression()
    return if truth(condition) { yes } else { no }
  }
  condition
}

///|
fn truth(node : @moonconf.Node) -> Bool {
  match node.value {
    @moonconf.Value::Bool(flag) => flag
    @moonconf.Value::Null => false
    @moonconf.Value::Int(n) => n != 0L
    @moonconf.Value::Real(x) => x != 0.0
    @moonconf.Value::Text(text) => text != ""
    @moonconf.Value::List(items) => items.length() > 0
    @moonconf.Value::Map(_) => true
  }
}

///|
/// The operators, weakest first: `||`, `&&`, equality, comparison, `+ -`, `* / %`.
fn P::binary(self : P, level : Int32) -> @moonconf.Node raise Refused {
  if level >= 6 {
    return self.unary()
  }
  let mut left = self.binary(level + 1)
  while true {
    self.space()
    let op = self.operator(level)
    if op == "" {
      return left
    }
    let right = self.binary(level + 1)
    left = apply(op, left, right, self.spot(self.i))
  }
  left
}

///|
/// The operator of `level` at the current position, consumed, or "".
fn P::operator(self : P, level : Int32) -> String {
  let pairs = match level {
    0 => [("||", "||")]
    1 => [("&&", "&&")]
    2 => [("==", "=="), ("!=", "!=")]
    3 => [("<=", "<="), (">=", ">="), ("<", "<"), (">", ">")]
    4 => [("+", "+"), ("-", "-")]
    _ => [("*", "*"), ("/", "/"), ("%", "%")]
  }
  for pair in pairs {
    let text = pair.0
    let mut matches = true
    let mut i = 0
    while i < text.length() {
      if self.at(self.i + i) != text.at(i).to_int() {
        matches = false
      }
      i += 1
    }
    if matches {
      // `=` or `>` after a single-character operator would be another operator.
      if text.length() == 1 {
        let next = self.at(self.i + 1)
        if next == '='.to_int() || next == '>'.to_int() {
          matches = false
        }
      }
      if matches {
        self.i += text.length()
        return pair.1
      }
    }
  }
  ""
}

///|
fn apply(
  op : String,
  left : @moonconf.Node,
  right : @moonconf.Node,
  at : At,
) -> @moonconf.Node raise Refused {
  match op {
    "||" =>
      @moonconf.Node::flag(truth(left) || truth(right), "", at=root_at(at))
    "&&" =>
      @moonconf.Node::flag(truth(left) && truth(right), "", at=root_at(at))
    "==" => @moonconf.Node::flag(left == right, "", at=root_at(at))
    "!=" => @moonconf.Node::flag(left != right, "", at=root_at(at))
    "<" | "<=" | ">" | ">=" => {
      let order = compare(left, right, at)
      let answer = match op {
        "<" => order < 0
        "<=" => order <= 0
        ">" => order > 0
        _ => order >= 0
      }
      @moonconf.Node::flag(answer, "", at=root_at(at))
    }
    "+" => arithmetic(left, right, at, "+")
    "-" => arithmetic(left, right, at, "-")
    "*" => arithmetic(left, right, at, "*")
    "/" => arithmetic(left, right, at, "/")
    _ => arithmetic(left, right, at, "%")
  }
}

///|
fn compare(
  left : @moonconf.Node,
  right : @moonconf.Node,
  at : At,
) -> Int32 raise Refused {
  match (left.value, right.value) {
    (@moonconf.Value::Text(a), @moonconf.Value::Text(b)) =>
      if a == b {
        0
      } else if a < b {
        -1
      } else {
        1
      }
    (_, _) => {
      let a = number(left, at)
      let b = number(right, at)
      if a == b {
        0
      } else if a < b {
        -1
      } else {
        1
      }
    }
  }
}

///|
fn number(node : @moonconf.Node, at : At) -> Double raise Refused {
  match node.value {
    @moonconf.Value::Int(n) => n.to_double()
    @moonconf.Value::Real(x) => x
    @moonconf.Value::Text(text) =>
      match @moonconf.decimal(text[:]) {
        Some(value) => value
        None => raise BadOperation(why="`" + text + "` is not a number", at~)
      }
    _ => raise BadOperation(why="a " + node.kind() + " is not a number", at~)
  }
}

///|
fn arithmetic(
  left : @moonconf.Node,
  right : @moonconf.Node,
  at : At,
  op : String,
) -> @moonconf.Node raise Refused {
  let whole = match (left.value, right.value) {
    (@moonconf.Value::Int(a), @moonconf.Value::Int(b)) => Some((a, b))
    _ => None
  }
  match whole {
    Some((a, b)) =>
      match op {
        "+" => @moonconf.Node::num(a + b, "", at=root_at(at))
        "-" => @moonconf.Node::num(a - b, "", at=root_at(at))
        "*" => @moonconf.Node::num(a * b, "", at=root_at(at))
        "/" =>
          if b == 0L {
            raise BadOperation(why="a division by zero", at~)
          } else {
            @moonconf.Node::num(a / b, "", at=root_at(at))
          }
        _ =>
          if b == 0L {
            raise BadOperation(why="a division by zero", at~)
          } else {
            @moonconf.Node::num(a % b, "", at=root_at(at))
          }
      }
    None => {
      let a = number(left, at)
      let b = number(right, at)
      match op {
        "+" => @moonconf.Node::of_real(a + b, "", at=root_at(at))
        "-" => @moonconf.Node::of_real(a - b, "", at=root_at(at))
        "*" => @moonconf.Node::of_real(a * b, "", at=root_at(at))
        "/" =>
          if b == 0.0 {
            raise BadOperation(why="a division by zero", at~)
          } else {
            @moonconf.Node::of_real(a / b, "", at=root_at(at))
          }
        _ =>
          if b == 0.0 {
            raise BadOperation(why="a division by zero", at~)
          } else {
            @moonconf.Node::of_real(a % b, "", at=root_at(at))
          }
      }
    }
  }
}

///|
fn P::unary(self : P) -> @moonconf.Node raise Refused {
  self.space()
  let c = self.here()
  if c == '!'.to_int() {
    let at = self.spot(self.i)
    self.i += 1
    return @moonconf.Node::flag(!truth(self.unary()), "", at=root_at(at))
  }
  if c == '-'.to_int() {
    let at = self.spot(self.i)
    self.i += 1
    let value = self.unary()
    return match value.value {
      @moonconf.Value::Int(n) => @moonconf.Node::num(-n, "", at=root_at(at))
      @moonconf.Value::Real(x) =>
        @moonconf.Node::of_real(-x, "", at=root_at(at))
      _ => @moonconf.Node::of_real(-number(value, at), "", at=root_at(at))
    }
  }
  self.postfix()
}

///|
/// A primary value, then the members and indexes that follow it.
fn P::postfix(self : P) -> @moonconf.Node raise Refused {
  let mut value = self.primary()
  while true {
    self.space()
    if self.here() == '.'.to_int() {
      self.i += 1
      self.space()
      let name = self.name()
      value = get_member(value, name, self.spot(self.i))
      continue
    }
    if self.here() == '['.to_int() {
      self.i += 1
      let index = self.expression()
      self.space()
      if self.here() != ']'.to_int() {
        raise self.error(self.i)
      }
      self.i += 1
      value = index_into(value, index, self.spot(self.i))
      continue
    }
    return value
  }
  value
}

///|
fn get_member(
  value : @moonconf.Node,
  name : String,
  at : At,
) -> @moonconf.Node raise Refused {
  match value.value {
    @moonconf.Value::Map(table) =>
      match table.get(name) {
        Some(found) => found
        None => raise UnknownName(name~, at~)
      }
    _ =>
      raise BadOperation(
        why="a " + value.kind() + " has no member " + name,
        at~,
      )
  }
}

///|
fn index_into(
  value : @moonconf.Node,
  index : @moonconf.Node,
  at : At,
) -> @moonconf.Node raise Refused {
  match (value.value, index.value) {
    (@moonconf.Value::List(items), @moonconf.Value::Int(n)) => {
      let position = n.to_int()
      if position < 0 || position >= items.length() {
        raise BadOperation(
          why="index " + n.to_string() + " is outside the list",
          at~,
        )
      }
      items[position]
    }
    (@moonconf.Value::Map(table), @moonconf.Value::Text(key)) =>
      match table.get(key) {
        Some(found) => found
        None => raise UnknownName(name=key, at~)
      }
    _ =>
      raise BadOperation(
        why="a " + value.kind() + " is not indexed by a " + index.kind(),
        at~,
      )
  }
}

///|
fn P::primary(self : P) -> @moonconf.Node raise Refused {
  self.space()
  let start = self.i
  let c = self.here()
  if c == '"'.to_int() {
    return @moonconf.Node::str(
      self.quoted(),
      self.source,
      at=root_at(self.spot(start)),
    )
  }
  if c == '['.to_int() {
    self.i += 1
    let items = []
    while true {
      self.space()
      if self.here() == ']'.to_int() {
        self.i += 1
        return @moonconf.Node::seq(
          items,
          self.source,
          at=root_at(self.spot(start)),
        )
      }
      if self.here() == -1 {
        raise Unclosed(at=self.spot(start), got="[")
      }
      items.push(self.expression())
      self.space()
      if self.here() == ','.to_int() {
        self.i += 1
      }
    }
  }
  if c == '{'.to_int() {
    self.i += 1
    let table = @moonconf.Table::new()
    while true {
      self.space()
      if self.here() == '}'.to_int() {
        self.i += 1
        return @moonconf.Node::new(
          @moonconf.Value::Map(table),
          self.source,
          root_at(self.spot(start)),
        )
      }
      if self.here() == -1 {
        raise Unclosed(at=self.spot(start), got="{")
      }
      let key = if self.here() == '"'.to_int() {
        self.quoted()
      } else {
        self.name()
      }
      self.space()
      if self.here() == '='.to_int() || self.here() == ':'.to_int() {
        self.i += 1
      } else {
        raise self.error(self.i)
      }
      let value = self.expression()
      table.set(key, value)
      self.space()
      if self.here() == ','.to_int() {
        self.i += 1
      }
    }
  }
  if c == '('.to_int() {
    self.i += 1
    let value = self.expression()
    self.space()
    if self.here() != ')'.to_int() {
      raise self.error(self.i)
    }
    self.i += 1
    return value
  }
  if c == '-'.to_int() || (c >= '0'.to_int() && c <= '9'.to_int()) {
    return self.number()
  }
  if self.word("true") {
    return @moonconf.Node::flag(true, self.source, at=root_at(self.spot(start)))
  }
  if self.word("false") {
    return @moonconf.Node::flag(
      false,
      self.source,
      at=root_at(self.spot(start)),
    )
  }
  if self.word("null") {
    return @moonconf.Node::new(
      @moonconf.Value::Null,
      self.source,
      root_at(self.spot(start)),
    )
  }
  if is_name_start(c) {
    let name = self.name()
    self.space()
    if self.here() == '('.to_int() {
      return self.call(name, start)
    }
    return self.lookup(name, start)
  }
  raise self.error(self.i)
}

///|
fn P::number(self : P) -> @moonconf.Node raise Refused {
  let start = self.i
  let out = StringBuilder()
  if self.here() == '-'.to_int() {
    out.write_char('-')
    self.i += 1
  }
  while true {
    let c = self.here()
    if (c >= '0'.to_int() && c <= '9'.to_int()) ||
      c == '.'.to_int() ||
      c == 'e'.to_int() ||
      c == 'E'.to_int() ||
      c == '+'.to_int() ||
      c == '-'.to_int() {
      out.write_char(c.unsafe_to_char())
      self.i += 1
      continue
    }
    break
  }
  let text = out.to_string()
  if text.contains(".") || text.contains("e") || text.contains("E") {
    match @moonconf.decimal(text[:]) {
      Some(value) =>
        @moonconf.Node::of_real(
          value,
          self.source,
          at=root_at(self.spot(start)),
        )
      None => raise self.error(start)
    }
  } else {
    match @moonconf.whole(text[:]) {
      Some(value) =>
        @moonconf.Node::num(value, self.source, at=root_at(self.spot(start)))
      None => raise self.error(start)
    }
  }
}

///|
/// A name, looked up in the context. A dotted name is a member of its first
/// segment, which is how `var.region` and `local.name` work.
fn P::lookup(
  self : P,
  name : String,
  start : Int32,
) -> @moonconf.Node raise Refused {
  match self.ctx.names.get(name) {
    Some(value) => value
    None => raise UnknownName(name~, at=self.spot(start))
  }
}

///|
fn P::call(
  self : P,
  name : String,
  start : Int32,
) -> @moonconf.Node raise Refused {
  self.i += 1
  let args = []
  while true {
    self.space()
    if self.here() == ')'.to_int() {
      self.i += 1
      break
    }
    args.push(self.expression())
    self.space()
    if self.here() == ','.to_int() {
      self.i += 1
      continue
    }
    if self.here() == ')'.to_int() {
      self.i += 1
      break
    }
    raise self.error(self.i)
  }
  match self.ctx.functions.get(name) {
    Some(body) => body(args)
    None => raise UnknownFunction(name~, at=self.spot(start))
  }
}

///|
/// Read an HCL body in the native syntax.
///
/// A body is a list of members: `name = expression` is an attribute, and `name
/// labels { … }` is a block. The expressions are evaluated as they are read,
/// against `context`: a name is looked up there, a call is answered by a function
/// there, and a string interpolates what an expression inside it evaluates to.
///
/// The syntax follows HCL 2's native form. Template directives (`%{ if }`),
/// heredocs and `for` expressions are not part of this reader.
pub fn parse(
  text : StringView,
  context? : Context,
  source~ : String = "",
) -> Body raise Refused {
  let parser : P = {
    src: text,
    ctx: context.unwrap_or(Context::new()),
    source,
    depth: 0,
    i: 0,
  }
  parser.body(false)
}

///|
/// Read an HCL body in the JSON syntax.
///
/// JSON has no way to say "this object is a block", so the reading is the one
/// every HCL tool settles on: an object whose members are all objects is a block,
/// and the member names are its labels; anything else is an attribute. A body is
/// then `{"resource": {"aws_instance": {"web": {…}}}}`, with `resource` the block
/// name and the two names inside it the labels.
pub fn parse_json(
  text : StringView,
  source~ : String = "",
) -> Body raise Refused {
  let root = @moonconf.of_json(text, source~) catch {
    refused => raise BadOperation(why=refused.to_string(), at=nowhere)
  }
  from_json(root, source)
}

///|
fn from_json(node : @moonconf.Node, source : String) -> Body raise Refused {
  let attributes : Array[(String, @moonconf.Node)] = []
  let blocks : Array[Block] = []
  match node.value {
    @moonconf.Value::Map(table) =>
      for pair in table.items() {
        match label_chain(pair.1) {
          Some((labels, inner)) =>
            blocks.push({
              kind: pair.0,
              labels,
              body: from_json(inner, source),
              at: here_at(pair.1.at),
            })
          None => attributes.push(pair)
        }
      }
    _ => raise BadOperation(why="a body must be an object", at=here_at(node.at))
  }
  { attributes, blocks, }
}

///|
/// The labels an object stands for, and the body under them: every member an
/// object means another label, until a member that is not an object.
fn label_chain(node : @moonconf.Node) -> (Array[String], @moonconf.Node)? {
  let labels : Array[String] = []
  let mut here = node
  while true {
    match here.value {
      @moonconf.Value::Map(table) =>
        if table.length() == 0 {
          return Some((labels, here))
        } else {
          let mut all_maps = true
          for pair in table.items() {
            if !pair.1.is_map() {
              all_maps = false
            }
          }
          if !all_maps {
            return Some((labels, here))
          }
          let first = table.items()[0]
          labels.push(first.0)
          here = first.1
        }
      _ => return None
    }
  }
  None
}
