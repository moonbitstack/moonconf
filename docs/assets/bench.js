// The benches: every reading on this page comes from moonconf compiled to
// JavaScript. This file only paints; the answers are the library's.
(function () {
  "use strict";

  var TIERS = ["default", "file", "env", "override"];

  var DEFAULT_SOURCES = [
    {
      tier: "default",
      name: "defaults.conf",
      format: "hocon",
      text: "db {\n  host = localhost\n  port = 5432\n  pool = 4\n}\n"
    },
    {
      tier: "file",
      name: "app.ini",
      format: "ini",
      text: "[db]\nhost = db.internal\npool = 8\n"
    },
    {
      tier: "env",
      name: "env",
      format: "json",
      text: '{ "db": { "port": "6432" } }\n'
    },
    {
      tier: "override",
      name: "flags",
      format: "hcl",
      text: "db {\n  pool = 16\n}\n"
    }
  ];

  var api = null;

  function lib() {
    if (!api) {
      api = window.moonconf || null;
    }
    return api;
  }

  function escape(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function tierOf(origin) {
    return (origin && origin.tier) || "default";
  }

  function badge(tier) {
    return '<i class="tier-dot" style="--tier: var(--tier-' + tier + ')"></i>';
  }

  // --- a tree as lines, each leaf coloured by the layer that won -------------

  function jsonLines(value, path, origins, indent, out, suffix, prefix) {
    var label = prefix || "";
    var end = suffix || "";
    if (Array.isArray(value)) {
      if (!value.length) {
        out.push(indent + label + '<span class="punct">[]</span>' + end);
        return out;
      }
      out.push(indent + label + '<span class="punct">[</span>');
      value.forEach(function (item, index) {
        jsonLines(
          item,
          path + "[" + index + "]",
          origins,
          indent + "  ",
          out,
          index < value.length - 1 ? '<span class="punct">,</span>' : "",
          ""
        );
      });
      out.push(indent + '<span class="punct">]</span>' + end);
      return out;
    }
    if (value && typeof value === "object") {
      var keys = Object.keys(value);
      if (!keys.length) {
        out.push(indent + label + '<span class="punct">{}</span>' + end);
        return out;
      }
      out.push(indent + label + '<span class="punct">{</span>');
      keys.forEach(function (key, index) {
        var child = path ? path + "." + key : key;
        var tick = index < keys.length - 1 ? '<span class="punct">,</span>' : "";
        jsonLines(
          value[key],
          child,
          origins,
          indent + "  ",
          out,
          tick,
          '<span class="key">"' +
            escape(key) +
            '"</span><span class="punct">: </span>'
        );
      });
      out.push(indent + '<span class="punct">}</span>' + end);
      return out;
    }
    var origin = origins && origins[path];
    var tier = tierOf(origin);
    var where = origin ? origin.name + " line " + origin.line : "";
    out.push(
      indent +
        label +
        '<span class="val t-' +
        tier +
        '" data-origin="' +
        escape(path) +
        '" data-where="' +
        escape(where) +
        '" data-tier="' +
        tier +
        '">' +
        scalar(value) +
        "</span>" +
        end
    );
    return out;
  }

  function scalar(value) {
    if (value === null) {
      return '<span class="punct">null</span>';
    }
    if (typeof value === "string") {
      return '<span class="punct">"</span>' + escape(value) + '<span class="punct">"</span>';
    }
    return escape(String(value));
  }

  function treeHtml(tree, origins) {
    var out = jsonLines(tree, "", origins || {}, "", [], "", "");
    return '<div class="jtree">' + out.join("\n") + "</div>";
  }

  function boundHtml(tree) {
    return "<pre>" + escape(JSON.stringify(tree, null, 2)) + "</pre>";
  }

  // --- the compact bench ----------------------------------------------------

  function mountBench(root) {
    var state = {
      sources: DEFAULT_SOURCES.map(function (source) {
        return Object.assign({}, source);
      }),
      on: [true, true, true, true],
      clash: "last",
      view: "tree"
    };

    var layers = root.querySelector('[data-role="layers"]');
    var screen = root.querySelector('[data-role="screen"]');
    var probe = root.querySelector('[data-role="probe"]');
    var status = root.querySelector('[data-role="status"]');

    function layerRows() {
      layers.innerHTML = state.sources
        .map(function (source, index) {
          return (
            '<button class="layer" type="button" data-index="' +
            index +
            '" aria-pressed="' +
            (state.on[index] ? "true" : "false") +
            '" style="--tier: var(--tier-' +
            source.tier +
            ')">' +
            '<span class="switch" aria-hidden="true"></span>' +
            '<span class="file"><span class="top"><span class="name">' +
            escape(source.name) +
            '</span><span class="tier">' +
            source.tier +
            '</span></span><span class="sample">' +
            escape(preview(source.text)) +
            "</span></span>" +
            '<span class="format">' +
            source.format +
            "</span>" +
            "</button>"
          );
        })
        .join("");
    }

    // A line or two that says what is in the plate, without the punctuation that
  // only a parser cares about.
  function preview(text) {
    var lines = text
      .split("\n")
      .map(function (line) {
        return line.trim();
      })
      .filter(function (line) {
        return (
          line &&
          line[0] !== "#" &&
          line[0] !== "[" &&
          line !== "{" &&
          line !== "}" &&
          line[line.length - 1] !== "{"
        );
      });
    return lines.slice(0, 2).join("  ·  ");
  }

  function request() {
      var body = {
        clash: state.clash,
        sources: state.sources
          .filter(function (source, index) {
            return state.on[index];
          })
          .map(function (source) {
            return {
              tier: source.tier,
              name: source.name,
              format: source.format,
              text: source.text
            };
          })
      };
      return JSON.stringify(body);
    }

    function show(answer, bound) {
      if (!answer.ok) {
        screen.innerHTML =
          '<div class="refusal"><span class="why">refused</span>' +
          escape(answer.text) +
          "</div>";
        status.textContent = "refused";
        return;
      }
      if (state.view === "bound") {
        if (!bound.ok) {
          screen.innerHTML =
            '<div class="refusal"><span class="why">refused</span>' +
            escape(bound.text) +
            "</div>";
          status.textContent = "refused";
          return;
        }
        screen.innerHTML = boundHtml(bound.tree);
        status.textContent = "bound";
        return;
      }
      screen.innerHTML = treeHtml(answer.tree, answer.origins);
      var count = Object.keys(answer.origins || {}).length;
      status.textContent = count + " values";
    }

    function run() {
      var library = lib();
      if (!library) {
        screen.innerHTML =
          '<div class="refusal"><span class="why">not built</span>' +
          "The bench runs the library compiled to JavaScript. Build it with " +
          "<code>moon build --target js --release src/examples/browser</code>.</div>";
        status.textContent = "offline";
        return;
      }
      var body = request();
      var answer;
      try {
        answer = JSON.parse(library.assemble(body));
      } catch (error) {
        screen.innerHTML =
          '<div class="refusal"><span class="why">error</span>' + escape(error.message) + "</div>";
        return;
      }
      var bound = { ok: false, text: "not asked" };
      if (state.view === "bound") {
        try {
          bound = JSON.parse(library.bind(body));
        } catch (error) {
          bound = { ok: false, text: error.message };
        }
      }
      show(answer, bound);
      probe.textContent = "Hover a value to see where it was written.";
    }

    root.addEventListener("click", function (event) {
      var layer = event.target.closest(".layer");
      if (layer) {
        var index = Number(layer.getAttribute("data-index"));
        state.on[index] = !state.on[index];
        layerRows();
        run();
        return;
      }
      var policy = event.target.closest("[data-policy]");
      if (policy) {
        state.clash = policy.getAttribute("data-policy");
        root.querySelectorAll("[data-policy]").forEach(function (button) {
          button.setAttribute("aria-pressed", String(button === policy));
        });
        run();
        return;
      }
      var tab = event.target.closest("[data-view]");
      if (tab) {
        state.view = tab.getAttribute("data-view");
        root.querySelectorAll("[data-view]").forEach(function (button) {
          button.setAttribute("aria-selected", String(button === tab));
        });
        run();
      }
    });

    root.addEventListener("mouseover", function (event) {
      var value = event.target.closest(".val");
      if (!value) {
        return;
      }
      probe.innerHTML =
        '<b style="color: var(--tier-' +
        value.getAttribute("data-tier") +
        ')">' +
        escape(value.getAttribute("data-origin")) +
        "</b> · " +
        escape(value.getAttribute("data-tier")) +
        " · " +
        escape(value.getAttribute("data-where"));
    });

    root.addEventListener("mouseout", function (event) {
      if (event.target.closest(".val")) {
        probe.textContent = "Hover a value to see where it was written.";
      }
    });

    layerRows();
    run();
  }

  // --- the lab on the showcase page ----------------------------------------

  function mountLab(root) {
    var state = {
      sources: DEFAULT_SOURCES.map(function (source) {
        return Object.assign({}, source);
      }),
      clash: "last",
      reversed: false,
      view: "tree",
      bound: null,
      problems: []
    };
    var FORMATS = ["hocon", "ini", "props", "dotenv", "hcl", "json", "yaml", "toml"];
    var screen = root.querySelector('[data-role="screen"]');
    var status = root.querySelector('[data-role="status"]');
    // The list of where each value came from sits under both panels, not inside
    // either of them.
    var table = document.querySelector('[data-role="wirelist"]');
    var editors = root.querySelector('[data-role="editors"]');

    function editorRows() {
      return state.sources
        .map(function (source, index) {
          return (
            '<div class="field" data-index="' +
            index +
            '" style="--tier: var(--tier-' +
            source.tier +
            ')">' +
            '<label class="label" for="lab-' +
            index +
            '">' +
            badge(source.tier) +
            "<span>" +
            source.tier +
            "</span>" +
            '<span style="margin-left:auto">' +
            escape(source.name) +
            "</span></label>" +
            '<select data-format="' +
            index +
            '" aria-label="Format of ' +
            escape(source.name) +
            '">' +
            FORMATS.map(function (format) {
              return (
                '<option value="' +
                format +
                '"' +
                (format === source.format ? " selected" : "") +
                ">" +
                format +
                "</option>"
              );
            }).join("") +
            "</select>" +
            '<textarea id="lab-' +
            index +
            '" data-text="' +
            index +
            '" spellcheck="false">' +
            escape(source.text) +
            "</textarea>" +
            "</div>"
          );
        })
        .join("");
    }

    // Repaint the editors and the switches from the state, after a sample has
    // replaced several of them at once.
    function paint() {
      editors.innerHTML = editorRows();
      root.querySelectorAll("[data-policy]").forEach(function (button) {
        button.setAttribute(
          "aria-pressed",
          String(button.getAttribute("data-policy") === state.clash)
        );
      });
      root.querySelectorAll("[data-direction]").forEach(function (button) {
        var reversed = button.getAttribute("data-direction") === "reversed";
        button.setAttribute("aria-pressed", String(reversed === state.reversed));
      });
      root.querySelectorAll("[data-view]").forEach(function (button) {
        button.setAttribute(
          "aria-selected",
          String(button.getAttribute("data-view") === state.view)
        );
      });
    }

    function request() {
      var wins = state.reversed
        ? TIERS.slice().reverse()
        : TIERS.slice();
      return JSON.stringify({
        clash: state.clash,
        wins: wins,
        sources: state.sources.map(function (source) {
          return {
            tier: source.tier,
            name: source.name,
            format: source.format,
            text: source.text
          };
        })
      });
    }

    function refusal(why) {
      return '<div class="refusal"><span class="why">refused</span>' + escape(why) + "</div>";
    }

    function wirelist(origins) {
      var keys = Object.keys(origins || {});
      if (!keys.length) {
        table.innerHTML = '<p class="hint" style="color: var(--ink-3)">Nothing to list.</p>';
        return;
      }
      table.innerHTML =
        '<table class="spec"><caption>where each value came from</caption>' +
        "<thead><tr><th>path</th><th>tier</th><th>written in</th><th>line</th></tr></thead><tbody>" +
        keys
          .map(function (key) {
            var origin = origins[key];
            return (
              "<tr><td><code>" +
              escape(key) +
              "</code></td><td>" +
              badge(origin.tier) +
              " " +
              escape(origin.tier) +
              "</td><td>" +
              escape(origin.name) +
              "</td><td>" +
              origin.line +
              "</td></tr>"
            );
          })
          .join("") +
        "</tbody></table>";
    }

    function run() {
      var library = lib();
      if (!library) {
        screen.innerHTML = refusal("the library is not built on this copy of the site");
        return;
      }
      var body = request();
      var merged;
      try {
        merged = JSON.parse(library.assemble(body));
      } catch (error) {
        screen.innerHTML = refusal(error.message);
        return;
      }
      if (!merged.ok) {
        screen.innerHTML = refusal(merged.text);
        status.textContent = "refused";
        table.innerHTML = "";
        return;
      }
      if (state.view === "bound") {
        var bound = JSON.parse(library.bind(body));
        screen.innerHTML = bound.ok ? boundHtml(bound.tree) : refusal(bound.text);
        status.textContent = bound.ok ? "bound" : "refused";
      } else if (state.view === "check") {
        var checked = JSON.parse(library.check(body));
        if (!checked.ok) {
          screen.innerHTML = refusal(checked.text);
        } else if (!checked.problems.length) {
          screen.innerHTML =
            '<p style="font-family: var(--font-mono); font-size: 12px; color: var(--moss)">' +
            "the section matches the model: host, port, pool, tls</p>";
        } else {
          screen.innerHTML = checked.problems
            .map(function (problem) {
              return refusal(problem);
            })
            .join("");
        }
        status.textContent = checked.ok ? checked.problems.length + " problems" : "refused";
      } else {
        screen.innerHTML = treeHtml(merged.tree, merged.origins);
        status.textContent = Object.keys(merged.origins || {}).length + " values";
      }
      wirelist(merged.origins);
    }

    editors.addEventListener("input", function (event) {
      var area = event.target.closest("[data-text]");
      if (!area) {
        return;
      }
      state.sources[Number(area.getAttribute("data-text"))].text = area.value;
      window.clearTimeout(root._timer);
      root._timer = window.setTimeout(run, 220);
    });

    editors.addEventListener("change", function (event) {
      var select = event.target.closest("[data-format]");
      if (!select) {
        return;
      }
      state.sources[Number(select.getAttribute("data-format"))].format = select.value;
      run();
    });

    root.addEventListener("click", function (event) {
      var policy = event.target.closest("[data-policy]");
      if (policy) {
        state.clash = policy.getAttribute("data-policy");
        root.querySelectorAll("[data-policy]").forEach(function (button) {
          button.setAttribute("aria-pressed", String(button === policy));
        });
        run();
        return;
      }
      var direction = event.target.closest("[data-direction]");
      if (direction) {
        state.reversed = direction.getAttribute("data-direction") === "reversed";
        root.querySelectorAll("[data-direction]").forEach(function (button) {
          button.setAttribute("aria-pressed", String(button === direction));
        });
        run();
        return;
      }
      var tab = event.target.closest("[data-view]");
      if (tab) {
        state.view = tab.getAttribute("data-view");
        root.querySelectorAll("[data-view]").forEach(function (button) {
          button.setAttribute("aria-selected", String(button === tab));
        });
        run();
        return;
      }
      var sample = event.target.closest("[data-sample]");
      if (sample) {
        load(sample.getAttribute("data-sample"));
      }
    });

    // A sample is a whole scenario, not a patch on whatever was on the bench:
    // four layers are cheaper to reset than to explain.
    function load(kind) {
      state.sources = DEFAULT_SOURCES.map(function (source) {
        return Object.assign({}, source);
      });
      state.clash = kind === "missing" ? "last" : "refuse";
      state.reversed = false;
      if (kind === "quote") {
        state.sources[1].format = "ini";
        state.sources[1].text = "[db\nhost = db.internal\n";
      }
      if (kind === "clash") {
        state.sources[1].format = "ini";
        state.sources[1].text = "[db]\npool = 99\n";
      }
      if (kind === "missing") {
        state.sources[0].format = "hcl";
        state.sources[0].text = 'db {\n  host = "db.internal"\n}\n';
        state.sources[2].format = "json";
        state.sources[2].text = "{}\n";
      }
      state.view = kind === "missing" ? "check" : "tree";
      paint();
      run();
    }

    paint();
    run();
  }

  // --- the expansion bench --------------------------------------------------

  function mountExpander(root) {
    var template = root.querySelector('[data-role="template"]');
    var vars = root.querySelector('[data-role="vars"]');
    var screen = root.querySelector('[data-role="screen"]');
    var status = root.querySelector('[data-role="status"]');
    var mode = "lenient";

    function run() {
      var library = lib();
      if (!library) {
        screen.innerHTML =
          '<div class="refusal"><span class="why">not built</span>the library is not built on this copy of the site</div>';
        return;
      }
      var table = {};
      vars.value.split("\n").forEach(function (line) {
        var at = line.indexOf("=");
        if (at > 0) {
          table[line.slice(0, at).trim()] = line.slice(at + 1).trim();
        }
      });
      var answer = JSON.parse(library.expand(template.value, JSON.stringify(table), mode));
      if (answer.ok) {
        screen.innerHTML = '<pre>' + escape(answer.text) + "</pre>";
        status.textContent = answer.text.length + " characters";
      } else {
        screen.innerHTML =
          '<div class="refusal"><span class="why">refused</span>' + escape(answer.text) + "</div>";
        status.textContent = "refused";
      }
    }

    root.addEventListener("input", function (event) {
      if (!event.target.closest("textarea")) {
        return;
      }
      window.clearTimeout(root._timer);
      root._timer = window.setTimeout(run, 200);
    });

    root.addEventListener("click", function (event) {
      var button = event.target.closest("[data-mode]");
      if (!button) {
        return;
      }
      mode = button.getAttribute("data-mode");
      root.querySelectorAll("[data-mode]").forEach(function (other) {
        other.setAttribute("aria-pressed", String(other === button));
      });
      run();
    });

    run();
  }

  function boot() {
    var bench = document.getElementById("bench");
    if (bench) {
      mountBench(bench);
    }
    var lab = document.getElementById("lab");
    if (lab) {
      mountLab(lab);
    }
    var expander = document.getElementById("expander");
    if (expander) {
      mountExpander(expander);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
