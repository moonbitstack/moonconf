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
/// A quoted string: its escapes decoded, then its `${…}` and `%{…}` forms
/// expanded.
fn P::quoted(self : P) -> String raise Refused {
  let start = self.i
  self.i += 1
  let raw = StringBuilder()
  while true {
    let c = self.here()
    if c == -1 || c == '\n'.to_int() {
      raise Unclosed(at=self.spot(start), got="\"")
    }
    if c == '"'.to_int() {
      self.i += 1
      return expand_template(
        raw.to_string(),
        self.ctx,
        self.source,
        self.spot(start),
      )
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
      raw.write_char(decoded)
      self.i += 2
      continue
    }
    raw.write_char(c.unsafe_to_char())
    self.i += 1
  }
  raw.to_string()
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
    "==" => @moonconf.Node::flag(left.value == right.value, "", at=root_at(at))
    "!=" => @moonconf.Node::flag(left.value != right.value, "", at=root_at(at))
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
  let mut splatting = false
  while true {
    self.space()
    if self.here() == '['.to_int() &&
      self.at(self.i + 1) == '*'.to_int() &&
      self.at(self.i + 2) == ']'.to_int() {
      // `xs[*]` is every member of `xs`; what follows is asked of each in turn.
      self.i += 3
      value = spread(value, self.source)
      splatting = true
      continue
    }
    if self.here() == '.'.to_int() {
      self.i += 1
      self.space()
      if self.here() == '*'.to_int() {
        // `xs.*` is the older spelling of the same thing.
        self.i += 1
        value = spread(value, self.source)
        splatting = true
        continue
      }
      let name = self.name()
      value = if splatting {
        project(value, name, self.spot(self.i))
      } else {
        get_member(value, name, self.spot(self.i))
      }
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
      value = if splatting {
        project_index(value, index, self.spot(self.i))
      } else {
        index_into(value, index, self.spot(self.i))
      }
      continue
    }
    return value
  }
  value
}

///|
/// Every member of a list, or the values of a mapping, as a list.
fn spread(value : @moonconf.Node, source : String) -> @moonconf.Node {
  match value.value {
    @moonconf.Value::List(_) => value
    @moonconf.Value::Map(table) => {
      let out = []
      for pair in table.items() {
        out.push(pair.1)
      }
      @moonconf.Node::seq(out, source)
    }
    _ => @moonconf.Node::seq([value], source)
  }
}

///|
/// `xs[*].name`: the member asked of every member of `xs`.
fn project(
  value : @moonconf.Node,
  name : String,
  at : At,
) -> @moonconf.Node raise Refused {
  match value.value {
    @moonconf.Value::List(items) => {
      let out = []
      for item in items {
        out.push(get_member(item, name, at))
      }
      @moonconf.Node::seq(out, "")
    }
    _ => get_member(value, name, at)
  }
}

///|
/// `xs[*][0]`: the index asked of every member of `xs`.
fn project_index(
  value : @moonconf.Node,
  index : @moonconf.Node,
  at : At,
) -> @moonconf.Node raise Refused {
  match value.value {
    @moonconf.Value::List(items) => {
      let out = []
      for item in items {
        out.push(index_into(item, index, at))
      }
      @moonconf.Node::seq(out, "")
    }
    _ => index_into(value, index, at)
  }
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
    self.space()
    if self.starts("for") {
      return self.for_list(start)
    }
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
    self.space()
    if self.starts("for") {
      return self.for_object(start)
    }
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
  if c == '<'.to_int() && self.at(self.i + 1) == '<'.to_int() {
    return self.heredoc()
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

///|
/// Evaluate an expression written in a string of its own: a `${…}` inside a
/// template, or one half of a `for`.
fn eval_fragment(
  text : String,
  ctx : Context,
  source : String,
) -> @moonconf.Node raise Refused {
  let parser : P = { src: text[:], ctx, source, depth: 0, i: 0, }
  let value = parser.expression()
  parser.space()
  if parser.i < text.length() {
    raise Unexpected(at=parser.spot(parser.i), got=parser.describe(parser.i))
  }
  value
}

///|
/// Whether `word` stands at the current position as a whole word.
fn P::starts(self : P, word : String) -> Bool {
  let view = word[:]
  let mut i = 0
  while i < view.length() {
    if self.at(self.i + i) != view.at(i).to_int() {
      return false
    }
    i += 1
  }
  !is_name_part(self.at(self.i + view.length()))
}

///|
/// The index of `close` that matches the `open` just before `from`, or the end
/// of the text when nothing closes it.
fn P::matching(self : P, from : Int32, open : Int32, close : Int32) -> Int32 {
  let mut depth = 1
  let mut i = from
  while i < self.src.length() {
    let c = self.at(i)
    if c == '"'.to_int() {
      i += 1
      while i < self.src.length() && self.at(i) != '"'.to_int() {
        if self.at(i) == '\\'.to_int() {
          i += 1
        }
        i += 1
      }
      i += 1
      continue
    }
    if c == open {
      depth += 1
    } else if c == close {
      depth -= 1
      if depth == 0 {
        return i
      }
    }
    i += 1
  }
  self.src.length()
}

///|
/// The index of `stop` at bracket depth zero in `[from, to)`, or -1.
fn P::top_level(self : P, from : Int32, to : Int32, stop : Int32) -> Int32 {
  let mut depth = 0
  let mut i = from
  while i < to {
    let c = self.at(i)
    if c == '"'.to_int() {
      i += 1
      while i < to && self.at(i) != '"'.to_int() {
        if self.at(i) == '\\'.to_int() {
          i += 1
        }
        i += 1
      }
      i += 1
      continue
    }
    if c == '['.to_int() || c == '{'.to_int() || c == '('.to_int() {
      depth += 1
    } else if c == ']'.to_int() || c == '}'.to_int() || c == ')'.to_int() {
      depth -= 1
    } else if depth == 0 && c == stop {
      return i
    }
    i += 1
  }
  -1
}

///|
/// The index of the word ` if ` at depth zero in `[from, to)`, or -1.
fn P::top_level_if(self : P, from : Int32, to : Int32) -> Int32 {
  let mut depth = 0
  let mut i = from
  while i + 4 <= to {
    let c = self.at(i)
    if c == '"'.to_int() {
      i += 1
      while i < to && self.at(i) != '"'.to_int() {
        if self.at(i) == '\\'.to_int() {
          i += 1
        }
        i += 1
      }
      i += 1
      continue
    }
    if c == '['.to_int() || c == '{'.to_int() || c == '('.to_int() {
      depth += 1
    } else if c == ']'.to_int() || c == '}'.to_int() || c == ')'.to_int() {
      depth -= 1
    } else if depth == 0 &&
      is_blank(c) &&
      self.at(i + 1) == 'i'.to_int() &&
      self.at(i + 2) == 'f'.to_int() &&
      is_blank(self.at(i + 3)) {
      return i
    }
    i += 1
  }
  -1
}

///|
/// `<<EOF`, `<<-EOF`: a string that runs to a line of its own.
fn P::heredoc(self : P) -> @moonconf.Node raise Refused {
  let start = self.i
  self.i += 2
  let mut strip = false
  if self.here() == '-'.to_int() {
    strip = true
    self.i += 1
  }
  let marker = self.name()
  if marker == "" {
    raise self.error(start)
  }
  while self.here() != -1 && self.here() != '\n'.to_int() {
    self.i += 1
  }
  if self.here() == '\n'.to_int() {
    self.i += 1
  }
  let lines : Array[String] = []
  while true {
    if self.i >= self.src.length() {
      raise Unclosed(at=self.spot(start), got="<<")
    }
    let from = self.i
    while self.i < self.src.length() && self.here() != '\n'.to_int() {
      self.i += 1
    }
    let mut end = self.i
    if end > from && self.at(end - 1) == '\r'.to_int() {
      end -= 1
    }
    let line = self.src[from:end]
    if trimmed(line) == marker {
      if self.here() == '\n'.to_int() {
        self.i += 1
      }
      break
    }
    lines.push(line.to_owned())
    if self.here() == '\n'.to_int() {
      self.i += 1
    }
  }
  let body = if strip { dedented(lines) } else { lines.join("\n") }
  let text = if body == "" { body } else { body + "\n" }
  @moonconf.Node::str(
    expand_template(text, self.ctx, self.source, self.spot(start)),
    self.source,
    at=root_at(self.spot(start)),
  )
}

///|
/// The lines with the indentation they share taken away, for `<<-`.
fn dedented(lines : Array[String]) -> String {
  let mut least = -1
  for line in lines {
    let view = line[:]
    let mut indent = 0
    while indent < view.length() && is_blank(view.at(indent).to_int()) {
      indent += 1
    }
    if indent < view.length() {
      if least < 0 || indent < least {
        least = indent
      }
    }
  }
  let cut = if least < 0 { 0 } else { least }
  let out = []
  for line in lines {
    let view = line[:]
    let mut start = 0
    while start < cut &&
          start < view.length() &&
          is_blank(view.at(start).to_int()) {
      start += 1
    }
    out.push(view[start:].to_owned())
  }
  out.join("\n")
}

///|
/// `[for x in xs : expr]`, `[for i, x in xs : expr if cond]`.
fn P::for_list(self : P, start : Int32) -> @moonconf.Node raise Refused {
  self.i += 3
  self.space()
  let first = self.name()
  self.space()
  let mut second : String? = None
  if self.here() == ','.to_int() {
    self.i += 1
    self.space()
    second = Some(self.name())
    self.space()
  }
  if !self.starts("in") {
    raise self.error(self.i)
  }
  self.i += 2
  let from = self.i
  let close = self.matching(from + 1, '['.to_int(), ']'.to_int())
  let colon = self.top_level(from, close, ':'.to_int())
  if colon < 0 {
    raise self.error(from)
  }
  let collection = eval_fragment(
    self.src[from:colon].to_owned(),
    self.ctx,
    self.source,
  )
  let body_from = colon + 1
  let test_at = self.top_level_if(body_from, close)
  let body_to = if test_at < 0 { close } else { test_at }
  let body = self.src[body_from:body_to].to_owned()
  let filter = if test_at < 0 {
    ""
  } else {
    self.src[test_at + 4:close].to_owned()
  }
  self.i = close + 1
  let items : Array[@moonconf.Node] = []
  let each = fn(node : @moonconf.Node, index : Int32) -> Unit raise Refused {
    let scope = self.ctx
    match second {
      // Two names are the index and the member, in that order.
      Some(name) => {
        ignore(
          scope.bind(first, @moonconf.Node::num(index.to_int64(), self.source)),
        )
        ignore(scope.bind(name, node))
      }
      None => ignore(scope.bind(first, node))
    }
    if filter == "" || truth(eval_fragment(filter, scope, self.source)) {
      items.push(eval_fragment(body, scope, self.source))
    }
  }
  match collection.value {
    @moonconf.Value::List(entries) => {
      let mut index = 0
      for entry in entries {
        each(entry, index)
        index += 1
      }
    }
    @moonconf.Value::Map(table) => {
      let mut index = 0
      for pair in table.items() {
        match second {
          Some(_) => each(@moonconf.Node::str(pair.0, self.source), index)
          None => each(pair.1, index)
        }
        index += 1
      }
    }
    _ =>
      raise BadOperation(
        why="a for wants a list or a mapping",
        at=self.spot(start),
      )
  }
  @moonconf.Node::seq(items, self.source, at=root_at(self.spot(start)))
}

///|
/// `{for k, v in m : k => v}`.
fn P::for_object(self : P, start : Int32) -> @moonconf.Node raise Refused {
  self.i += 3
  self.space()
  let first = self.name()
  self.space()
  let mut second : String? = None
  if self.here() == ','.to_int() {
    self.i += 1
    self.space()
    second = Some(self.name())
    self.space()
  }
  if !self.starts("in") {
    raise self.error(self.i)
  }
  self.i += 2
  let from = self.i
  let close = self.matching(from + 1, '{'.to_int(), '}'.to_int())
  let colon = self.top_level(from, close, ':'.to_int())
  if colon < 0 {
    raise self.error(from)
  }
  let collection = eval_fragment(
    self.src[from:colon].to_owned(),
    self.ctx,
    self.source,
  )
  let arrow = self.top_level(colon + 1, close, '='.to_int())
  if arrow < 0 {
    raise self.error(colon + 1)
  }
  let key_src = self.src[colon + 1:arrow].to_owned()
  let value_src = self.src[arrow + 2:close].to_owned()
  self.i = close + 1
  let table = @moonconf.Table::new()
  let each = fn(key : String, value : @moonconf.Node) -> Unit raise Refused {
    let scope = self.ctx
    ignore(scope.bind(first, @moonconf.Node::str(key, self.source)))
    match second {
      Some(name) => ignore(scope.bind(name, value))
      None => ()
    }
    let made = render(eval_fragment(key_src, scope, self.source))
    table.set(made, eval_fragment(value_src, scope, self.source))
  }
  match collection.value {
    @moonconf.Value::List(entries) => {
      let mut index = 0
      for entry in entries {
        each(index.to_string(), entry)
        index += 1
      }
    }
    @moonconf.Value::Map(items) =>
      for pair in items.items() {
        each(pair.0, pair.1)
      }
    _ =>
      raise BadOperation(
        why="a for wants a list or a mapping",
        at=self.spot(start),
      )
  }
  @moonconf.Node::new(
    @moonconf.Value::Map(table),
    self.source,
    root_at(self.spot(start)),
  )
}
