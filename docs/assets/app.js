// moonconf site shell: theme, code highlighting, copy buttons, the table of
// contents that follows the scroll. No dependencies.
(function () {
  "use strict";

  var root = document.documentElement;
  var STORE = "moonconf-theme";

  // --- theme ---------------------------------------------------------------

  function stored() {
    try {
      return localStorage.getItem(STORE);
    } catch (error) {
      return null;
    }
  }

  function apply(theme) {
    root.setAttribute("data-theme", theme);
    var button = document.querySelector("[data-theme-toggle]");
    if (button) {
      button.setAttribute(
        "aria-label",
        theme === "dark" ? "Switch to the light theme" : "Switch to the dark theme"
      );
    }
  }

  document.addEventListener("click", function (event) {
    var toggle = event.target.closest("[data-theme-toggle]");
    if (!toggle) {
      return;
    }
    var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    apply(next);
    try {
      localStorage.setItem(STORE, next);
    } catch (error) {
      /* a reader who refuses storage keeps this theme for the page */
    }
  });

  // --- copy ----------------------------------------------------------------

  function flash(button, text) {
    var original = button.getAttribute("data-label") || button.textContent;
    button.setAttribute("data-label", original);
    button.textContent = text;
    window.setTimeout(function () {
      button.textContent = original;
    }, 1400);
  }

  function write(text, button) {
    var done = function () {
      flash(button, "copied");
    };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(done, function () {
        fallback();
      });
      return;
    }
    fallback();

    function fallback() {
      var area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.left = "-9999px";
      document.body.appendChild(area);
      area.select();
      try {
        document.execCommand("copy");
        done();
      } catch (error) {
        flash(button, "select and copy");
      }
      document.body.removeChild(area);
    }
  }

  document.addEventListener("click", function (event) {
    var button = event.target.closest("[data-copy]");
    if (!button) {
      return;
    }
    var selector = button.getAttribute("data-copy");
    var target = selector ? document.querySelector(selector) : null;
    if (target) {
      write(target.textContent, button);
    }
  });

  // --- highlighting --------------------------------------------------------

  var KEYWORDS =
    "fn let mut pub priv match if else for in while return raise guard try catch " +
    "test struct enum derive type trait impl extern as is const true false noraise";
  var TYPES =
    "Int Int32 Int64 Double Bool Char Byte String StringView Array ArrayView Map " +
    "Bytes BytesView StringBuilder Unit Json Node Value Table Source Tier Clash";

  function escape(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function moonbit(source) {
    var out = "";
    var index = 0;
    var words = new RegExp("\\b(" + KEYWORDS.split(" ").join("|") + ")\\b", "g");
    var types = new RegExp("\\b(" + TYPES.split(" ").join("|") + ")\\b", "g");

    function plain(text) {
      return escape(text)
        .replace(words, '<span class="tok-key">$1</span>')
        .replace(types, '<span class="tok-type">$1</span>');
    }

    var pattern =
      /(\/\/[^\n]*)|("(?:\\.|[^"\\])*")|('(?:\\.|[^'\\])*')|\b(\d+(?:\.\d+)?)\b/g;
    var match;
    while ((match = pattern.exec(source)) !== null) {
      out += plain(source.slice(index, match.index));
      if (match[1]) {
        out += '<span class="tok-com">' + escape(match[1]) + "</span>";
      } else if (match[2] || match[3]) {
        out += '<span class="tok-str">' + escape(match[2] || match[3]) + "</span>";
      } else {
        out += '<span class="tok-num">' + escape(match[4]) + "</span>";
      }
      index = pattern.lastIndex;
    }
    out += plain(source.slice(index));
    return out;
  }

  // INI, .env, properties, HOCON, HCL: comments, quoted text and numbers. The
  // shape of these files is the point of the page, so colour stays quiet.
  // Comments are found before escaping, because after it a `#` inside a span is
  // indistinguishable from one in the text.
  function config(source, language) {
    var hashComments = language === "ini" || language === "dotenv" || language === "props";
    var lines = source.split("\n");
    return lines
      .map(function (line) {
        var cut = commentAt(line, hashComments);
        var code = cut < 0 ? line : line.slice(0, cut);
        var tail = cut < 0 ? "" : line.slice(cut);
        return paint(code) + (tail ? '<span class="tok-com">' + escape(tail) + "</span>" : "");
      })
      .join("\n");
  }

  // Where a comment starts in a line, or -1. A `#` after whitespace starts one in
  // the formats that use it, and inside a quote it never does.
  function commentAt(line, hashOnly) {
    var quote = null;
    for (var i = 0; i < line.length; i += 1) {
      var c = line[i];
      if (quote) {
        if (c === "\\") {
          i += 1;
        } else if (c === quote) {
          quote = null;
        }
        continue;
      }
      if (c === '"' || c === "'") {
        quote = c;
        continue;
      }
      if (c === "#" || (c === ";" && hashOnly)) {
        if (i === 0 || /\s/.test(line[i - 1]) || !hashOnly) {
          return i;
        }
      }
      if (!hashOnly && c === "/" && line[i + 1] === "/") {
        return i;
      }
    }
    return -1;
  }

  function paint(text) {
    var out = "";
    var index = 0;
    var pattern = /("(?:\\.|[^"\\])*")|('(?:\\.|[^'\\])*')|\b(\d+(?:\.\d+)?)\b/g;
    var match;
    while ((match = pattern.exec(text)) !== null) {
      out += escape(text.slice(index, match.index));
      if (match[1] || match[2]) {
        out += '<span class="tok-str">' + escape(match[1] || match[2]) + "</span>";
      } else {
        out += '<span class="tok-num">' + escape(match[3]) + "</span>";
      }
      index = pattern.lastIndex;
    }
    out += escape(text.slice(index));
    return out;
  }

  function highlight(block) {
    var language = block.getAttribute("data-lang") || "";
    if (!language || block.dataset.highlighted === "yes") {
      return;
    }
    var source = block.textContent;
    block.dataset.highlighted = "yes";
    if (language === "moonbit") {
      block.innerHTML = moonbit(source);
    } else if (["ini", "dotenv", "props", "hocon", "hcl", "json", "toml", "yaml"].indexOf(language) !== -1) {
      block.innerHTML = config(source, language);
    }
  }

  // --- table of contents ---------------------------------------------------

  function contents() {
    var toc = document.querySelector(".docs-toc");
    if (!toc) {
      return;
    }
    var links = Array.prototype.slice.call(toc.querySelectorAll('a[href^="#"]'));
    var targets = links
      .map(function (link) {
        var id = link.getAttribute("href").slice(1);
        return document.getElementById(id);
      })
      .filter(Boolean);
    if (!targets.length) {
      return;
    }
    var watching = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) {
            return;
          }
          links.forEach(function (link) {
            link.setAttribute(
              "aria-current",
              link.getAttribute("href") === "#" + entry.target.id ? "true" : "false"
            );
          });
        });
      },
      { rootMargin: "-88px 0px -70% 0px", threshold: 0 }
    );
    targets.forEach(function (target) {
      watching.observe(target);
    });
  }

  // --- boot ----------------------------------------------------------------

  function boot() {
    apply(stored() || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"));
    Array.prototype.forEach.call(
      document.querySelectorAll("pre[data-lang]"),
      highlight
    );
    document.querySelectorAll(".code-card").forEach(function (card) {
      var pre = card.querySelector("pre");
      var bar = card.querySelector(".bar");
      if (!pre || !bar || bar.querySelector("[data-copy]")) {
        return;
      }
      var button = document.createElement("button");
      button.type = "button";
      button.textContent = "copy";
      button.setAttribute("data-copy", "");
      button.addEventListener("click", function () {
        write(pre.textContent, button);
      });
      bar.appendChild(button);
    });
    contents();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
