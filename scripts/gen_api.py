#!/usr/bin/env python3
"""Write `docs/api.html` from the packages' interfaces and their doc comments.

The interface of a MoonBit package is `pkg.generated.mbti`, which `moon info`
writes from the source; the prose is the `///` block above each declaration.
This script joins the two: every public value, type, field and method, grouped
by package, each with the sentence its author wrote about it.

It refuses to write a page with a hole in it. A public item without a doc
comment is a bug in the source, not something to render as an empty paragraph,
so the script names the item and exits non-zero. CI runs it and compares the
result with what is committed, which is what keeps the page honest:

    python scripts/gen_api.py
    git diff --exit-code docs/api.html
"""

import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The order the guide reads in: the tree and its rules, the formats, then the
# two configuration languages.
PACKAGES = [
    ("moonconf", "src"),
    ("moonconf/ini", "src/ini"),
    ("moonconf/props", "src/props"),
    ("moonconf/dotenv", "src/dotenv"),
    ("moonconf/expand", "src/expand"),
    ("moonconf/hocon", "src/hocon"),
    ("moonconf/hcl", "src/hcl"),
]

# Methods a `derive` writes. They are part of the interface and not part of what
# an author wrote, so the page names them once under the type instead of
# pretending to explain `not_equal` seven times.
DERIVED = {"equal", "not_equal", "to_repr", "to_string", "output"}

GEAR = (
    "M26.20 16.00 L26.16 16.90 L29.07 17.82 L28.95 18.58 L28.77 19.34 L28.55 "
    "20.08 L25.70 19.15 L24.78 21.19 L24.25 22.00 L23.69 22.70 L25.51 25.16 "
    "L24.96 25.70 L24.37 26.21 L23.76 26.68 L22.00 24.25 L20.05 25.36 L19.15 "
    "25.70 L18.29 25.94 L18.31 29.00 L17.54 29.11 L16.77 29.18 L16.00 29.20 "
    "L16.00 26.20 L13.77 25.95 L12.85 25.70 L12.01 25.39 L10.23 27.87 L9.54 "
    "27.51 L8.88 27.12 L8.24 26.68 L10.00 24.25 L8.35 22.75 L7.75 22.00 L7.25 "
    "21.25 L4.35 22.21 L4.01 21.52 L3.71 20.81 L3.45 20.08 L6.30 19.15 L5.85 "
    "16.96 L5.80 16.00 L5.84 15.10 L2.93 14.18 L3.05 13.42 L3.23 12.66 L3.45 "
    "11.92 L6.30 12.85 L7.22 10.81 L7.75 10.00 L8.31 9.30 L6.49 6.84 L7.04 "
    "6.30 L7.63 5.79 L8.24 5.32 L10.00 7.75 L11.95 6.64 L12.85 6.30 L13.71 "
    "6.06 L13.69 3.00 L14.46 2.89 L15.23 2.82 L16.00 2.80 L16.00 5.80 L18.23 "
    "6.05 L19.15 6.30 L19.99 6.61 L21.77 4.13 L22.46 4.49 L23.12 4.88 L23.76 "
    "5.32 L22.00 7.75 L23.65 9.25 L24.25 10.00 L24.75 10.75 L27.65 9.79 L27.99 "
    "10.48 L28.29 11.19 L28.55 11.92 L25.70 12.85 L26.15 15.04 Z M16.00 12.00 "
    "A4 4 0 1 0 16.00 20.00 A4 4 0 1 0 16.00 12.00 Z"
)


class Failure(Exception):
    pass


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def strip_marker(lines):
    """A doc block, without the `///|` marker that opens one."""
    out = []
    for line in lines:
        text = line[3:].lstrip()
        if text in ("|", ""):
            out.append("")
        else:
            out.append(text)
    while out and out[0] == "":
        out.pop(0)
    while out and out[-1] == "":
        out.pop()
    return out


def parse_interface(path):
    """The public items of a package, in the order the interface file has them.

    A type owns its fields or variants, and the methods called on it.
    """
    items = []
    current = None
    for raw in read(path).splitlines():
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        match = re.match(r"pub\s*(?:\(all\)\s*)?(suberror|enum|struct) (\w+)", line)
        if match:
            kind = {"suberror": "error", "enum": "enum", "struct": "struct"}[
                match.group(1)
            ]
            current = {
                "kind": kind,
                "name": match.group(2),
                "sig": line.rstrip(" {"),
                "members": [],
                "methods": [],
            }
            items.append(current)
            continue
        if line.startswith("}"):
            current = None
            continue
        if current is not None and current["kind"] in ("enum", "error"):
            match = re.match(r"([A-Z]\w*)(.*)", line)
            if match:
                current["members"].append(
                    {"name": match.group(1), "sig": line.rstrip(","), "kind": "variant"}
                )
                continue
        if current is not None and current["kind"] == "struct":
            match = re.match(r"(\w+)\s*:\s*(.+)", line)
            if match:
                current["members"].append(
                    {
                        "name": match.group(1),
                        "sig": "%s : %s" % (match.group(1), match.group(2)),
                        "kind": "field",
                    }
                )
                continue
        match = re.match(r"pub (fn|let) (\w+)(::\w+)?(.*)", line)
        if match:
            what, name, method, _rest = match.groups()
            entry = {
                "kind": what,
                "name": method[2:] if method else name,
                "owner": name if method else "",
                "sig": line,
                "members": [],
                "methods": [],
            }
            if method:
                for item in items:
                    if item["name"] == name and "members" in item:
                        item["methods"].append(entry)
                        break
            else:
                items.append(entry)
            continue
    return items


def parse_docs(directory):
    """What each declaration's `///` block says, by name.

    A field or a variant is named `Type.member`; a method is named
    `Type::method`; everything else by its own name. Only the first doc block
    for a name counts, because a name declared twice is a mistake the interface
    file would already have shown.
    """
    docs = {}

    def remember(key, block):
        docs.setdefault(key, strip_marker(block) if block else [])

    for name in sorted(os.listdir(directory)):
        if not name.endswith(".mbt") or name.endswith("_test.mbt"):
            continue
        block = []
        owner = None
        for raw in read(os.path.join(directory, name)).splitlines():
            line = raw.strip()
            if line.startswith("///"):
                block.append(line)
                continue
            if not line:
                continue
            if owner is not None:
                if line.startswith("}"):
                    owner = None
                else:
                    member = re.match(r"(\w+)\s*:|([A-Z]\w*)\s*(?:[\(,]|$)", line)
                    if member:
                        remember(
                            "%s.%s" % (owner, member.group(1) or member.group(2)),
                            block,
                        )
                block = []
                continue
            match = re.match(
                r"pub\s*(?:\(all\)\s*)?(suberror|enum|struct|fn|let)\s+(\w+(?:::\w+)?)",
                line,
            )
            if match:
                key = match.group(2)
                if key in ("equal", "not_equal", "to_repr", "to_string"):
                    block = []
                    continue
                remember(key, block)
                if match.group(1) in ("suberror", "enum", "struct"):
                    owner = key
                block = []
                continue
            block = []
    return docs


def package_summary(directory):
    """The sentence that says what a package is for, from its `moon.pkg`."""
    paragraphs = []
    current = []
    for line in read(os.path.join(directory, "moon.pkg")).splitlines():
        if not line.startswith("//"):
            break
        text = line[2:].strip()
        if not text:
            if current:
                paragraphs.append(" ".join(current))
                current = []
            continue
        current.append(text)
    if current:
        paragraphs.append(" ".join(current))
    return paragraphs[0] if paragraphs else ""


def inline(text):
    """Escape, then put back the marks the doc comments use."""
    out = html.escape(text, quote=False)
    out = re.sub(r"\[`([^`]+)`\]", r"<code>\1</code>", out)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    return out


def prose(lines):
    """A doc block as HTML: paragraphs, lists, tables and code fences."""
    out = []
    block = []
    index = 0

    def flush():
        if not block:
            return
        out.append("<p>%s</p>" % inline(" ".join(block)))
        block.clear()

    while index < len(lines):
        stripped = lines[index].strip()
        if stripped.startswith("```"):
            flush()
            language = stripped[3:].strip() or "mbt"
            index += 1
            code = []
            while index < len(lines) and not lines[index].strip().startswith("```"):
                code.append(lines[index])
                index += 1
            index += 1
            out.append(
                '<div class="code-card"><div class="bar"><span class="lang">%s</span>'
                '<span class="spacer"></span></div><pre>%s</pre></div>'
                % (html.escape(language), html.escape("\n".join(code)))
            )
            continue
        if not stripped:
            flush()
            index += 1
            continue
        if stripped.startswith("|"):
            flush()
            rows = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                rows.append(lines[index].strip())
                index += 1
            out.append(table(rows))
            continue
        if stripped.startswith("- "):
            flush()
            items = []
            while index < len(lines) and lines[index].strip().startswith("- "):
                items.append(lines[index].strip()[2:])
                index += 1
            out.append(
                "<ul>%s</ul>" % "".join("<li>%s</li>" % inline(item) for item in items)
            )
            continue
        block.append(stripped)
        index += 1
    flush()
    return "\n".join(out)


def table(rows):
    """A pipe table from a doc comment; the first row is the head."""

    def cells(row):
        return [cell.strip() for cell in row.strip("|").split("|")]

    head = cells(rows[0])
    body = [row for row in rows[1:] if not re.match(r"^\|[\s:|-]+\|$", row)]
    out = ['<div class="table-card"><table><thead><tr>']
    out.extend("<th>%s</th>" % inline(cell) for cell in head)
    out.append("</tr></thead><tbody>")
    for row in body:
        out.append(
            "<tr>%s</tr>" % "".join("<td>%s</td>" % inline(cell) for cell in cells(row))
        )
    out.append("</tbody></table></div>")
    return "".join(out)


def derived_note(name):
    """The sentence for a method nobody wrote by hand."""
    return {
        "to_repr": "Written by `derive(Debug)`.",
        "output": "Written by the `Show` implementation.",
    }.get(name, "Written by `derive(Eq)`.")


def anchor(package, name):
    slug = package.replace("moonconf/", "").replace("moonconf", "root")
    return "%s-%s" % (slug, name.replace("::", "-").lower())


def signature(text):
    return '<code class="api-signature">%s</code>' % html.escape(text, quote=False)


def render_package(package, directory):
    interface = os.path.join(directory, "pkg.generated.mbti")
    if not os.path.exists(interface):
        raise Failure("%s has no pkg.generated.mbti" % directory)
    items = parse_interface(interface)
    docs = parse_docs(directory)
    missing = []

    values = [item for item in items if item["kind"] in ("fn", "let")]
    types = [item for item in items if item["kind"] in ("struct", "enum")]
    errors = [item for item in items if item["kind"] == "error"]

    def describe(item):
        doc = docs.get(item["name"])
        if not doc:
            missing.append(item["name"])
            doc = []
        return prose(doc)

    def item_html(item):
        body = [signature(item["sig"]), describe(item)]
        if item["members"]:
            label = "Fields" if item["kind"] == "struct" else "Variants"
            members = []
            for member in item["members"]:
                key = "%s.%s" % (item["name"], member["name"])
                member_doc = docs.get(key)
                if not member_doc:
                    missing.append(key)
                    member_doc = []
                members.append(
                    '<li><span class="api-member">%s</span>%s</li>'
                    % (signature(member["sig"]), prose(member_doc))
                )
            body.append(
                '<div class="api-members"><div class="api-label">%s</div>'
                "<ul>%s</ul></div>" % (label, "".join(members))
            )
        if item["methods"]:
            methods = []
            for method in sorted(item["methods"], key=lambda entry: entry["name"]):
                key = "%s::%s" % (item["name"], method["name"])
                method_doc = docs.get(key)
                if not method_doc and method["name"] in DERIVED:
                    method_doc = [derived_note(method["name"])]
                if not method_doc:
                    missing.append(key)
                    method_doc = []
                methods.append(
                    '<li><span class="api-member">%s</span>%s</li>'
                    % (signature(method["sig"]), prose(method_doc))
                )
            body.append(
                '<div class="api-members"><div class="api-label">Methods</div>'
                "<ul>%s</ul></div>" % "".join(methods)
            )
        return (
            '<article class="api-item" id="%s"><h3>%s</h3>%s</article>'
            % (anchor(package, item["name"]), html.escape(item["name"]), "".join(body))
        )

    groups = []
    for label, group in (
        ("Values", sorted(values, key=lambda entry: entry["name"])),
        ("Types", sorted(types, key=lambda entry: entry["name"])),
        ("Errors", sorted(errors, key=lambda entry: entry["name"])),
    ):
        if not group:
            continue
        chunks = "".join(item_html(item) for item in group)
        groups.append(
            '<div class="api-group"><div class="api-group-label">%s</div>%s</div>'
            % (label.lower(), chunks)
        )

    jump = "".join(
        '<a href="#%s">%s</a>' % (anchor(package, item["name"]), html.escape(item["name"]))
        for item in sorted(values + types + errors, key=lambda entry: entry["name"])
    )
    if not groups:
        raise Failure("%s has no public items" % package)
    return {
        "name": package,
        "summary": package_summary(directory),
        "body": '<div class="api-jump">%s</div>%s' % (jump, "".join(groups)),
        "missing": missing,
        "items": items,
    }


def page(packages):
    toc = "".join(
        '<a href="#%s">%s</a>'
        % (package["name"].replace("moonconf/", "").replace("moonconf", "root"),
           html.escape(package["name"].replace("moonconf", "moonconf")))
        for package in packages
    )
    sections = []
    for package in packages:
        slug = package["name"].replace("moonconf/", "").replace("moonconf", "root")
        sections.append(
            '<section class="api-package" id="%s">'
            '<div class="section-head" style="margin-bottom: 18px">'
            '<div><h2 style="font-size: 34px">%s</h2></div>'
            '<div class="aside">%d items</div>'
            "<p>%s</p></div>"
            '<div class="api-body">%s</div></section>'
            % (
                slug,
                html.escape(package["name"]),
                len(package["items"]),
                inline(package["summary"]),
                package["body"],
            )
        )
    return (
        TEMPLATE.replace("{{TOC}}", toc)
        .replace("{{SECTIONS}}", "".join(sections))
        .replace("{{GEAR}}", GEAR)
    )


TEMPLATE = """<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>API — moonconf</title>
    <meta
      name="description"
      content="Every public package, type, value, field, method and error of moonconf, with the sentence its source wrote about it."
    />
    <link rel="stylesheet" href="assets/style.css?v=1" />
    <link
      rel="icon"
      href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='4' fill='%230e1012'/%3E%3Ccircle cx='16' cy='16' r='8' fill='none' stroke='%23e0a94a' stroke-width='4' stroke-dasharray='3 3'/%3E%3Ccircle cx='16' cy='16' r='2.6' fill='%23e0a94a'/%3E%3C/svg%3E"
    />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700&family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap"
      rel="stylesheet"
    />
    <script>
      (function () {
        try {
          var theme = localStorage.getItem("moonconf-theme");
        } catch (error) {
          theme = null;
        }
        if (!theme) {
          theme = window.matchMedia("(prefers-color-scheme: dark)").matches
            ? "dark"
            : "light";
        }
        document.documentElement.setAttribute("data-theme", theme);
      })();
    </script>
  </head>
  <body>
    <a class="skip" href="#main">Skip to content</a>

    <header class="site-header">
      <div class="inner">
        <a class="wordmark" href="index.html">
          <svg class="gear" viewBox="0 0 32 32" aria-hidden="true">
            <path fill="currentColor" fill-rule="evenodd" d="{{GEAR}}" />
          </svg>
          <span class="name">moonconf</span>
          <span class="dash" aria-hidden="true"></span>
          <span class="kind">configuration</span>
        </a>
        <nav class="site-nav" aria-label="Main">
          <a href="index.html">Home</a>
          <a href="guide.html">Guide</a>
          <a href="showcase.html">Showcase</a>
          <a href="api.html" aria-current="page">API</a>
        </nav>
        <div class="header-tools">
          <button class="icon-button" type="button" data-theme-toggle aria-label="Switch theme">
            <svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
              <circle cx="12" cy="12" r="4" />
              <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
            </svg>
            <svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
              <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
            </svg>
          </button>
          <a
            class="icon-button"
            href="https://github.com/moonbitstack/moonconf"
            aria-label="GitHub repository"
          >
            <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M12 .5a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.6-1.4-1.4-1.8-1.4-1.8-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.8-1.6-2.7-.3-5.5-1.3-5.5-6 0-1.2.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.2 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.6 1.7.2 2.9.1 3.2.8.8 1.2 1.9 1.2 3.1 0 4.7-2.8 5.7-5.5 6 .4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A12 12 0 0 0 12 .5z" />
            </svg>
          </a>
        </div>
      </div>
    </header>

    <main id="main" class="wrap">
      <div class="docs-layout">
        <aside class="docs-toc" aria-label="Packages">
          <div class="title">Packages</div>
          {{TOC}}
        </aside>

        <div class="docs-body">
          <div class="section-head" style="margin-bottom: 26px">
            <div>
              <div class="kicker">Reference</div>
              <h2 style="font-size: clamp(38px, 5vw, 56px)">Everything public.</h2>
            </div>
          </div>
          <p class="lead">
            One section per package, in the order the guide reads them. Each item
            is the declaration the compiler sees and the sentence the source wrote
            about it. Types list their fields or variants, then the methods called
            on them.
          </p>
          {{SECTIONS}}
        </div>
      </div>
    </main>

    <footer class="site-footer">
      <div class="inner">
        <span>moonconf — configuration for MoonBit, read once and layered. Apache-2.0.</span>
        <div class="links">
          <a href="guide.html">Guide</a>
          <a href="showcase.html">Showcase</a>
          <a href="api.html">API</a>
          <a href="https://mooncakes.io/docs/moonbitstack/moonconf">Mooncakes</a>
          <a href="https://github.com/moonbitstack/moonconf">GitHub</a>
        </div>
      </div>
    </footer>

    <script src="assets/app.js?v=1"></script>
  </body>
</html>
"""


def main():
    packages = []
    missing = []
    for name, directory in PACKAGES:
        package = render_package(name, os.path.join(ROOT, directory))
        packages.append(package)
        missing.extend("%s: %s" % (name, item) for item in package["missing"])
    if missing:
        for item in missing:
            print("no doc comment for", item, file=sys.stderr)
        print("%d public items have no description" % len(missing), file=sys.stderr)
        return 1
    target = os.path.join(ROOT, "docs", "api.html")
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page(packages))
    print(
        "api: %d packages, %d items"
        % (len(packages), sum(len(package["items"]) for package in packages))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
