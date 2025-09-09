return {
  function_icon = "󰊕",
  logger = {
    name = "NeoTreeUProject",
    cache = { dirname = "URPOJECT_UNL" },
    logging = { level = "info", file = { enable = true, filename = "neo-tree-uproject.log" } },
  },
  renderers = {
    directory = { { "indent" }, { "icon" }, { "container", content = { { "name" } } } },
    file = { { "indent" }, { "icon" }, { "name" } },
    func = { { "indent" }, { "icon" }, { "name" } },
    message = { { "indent", with_markers = false }, { "name", highlight = "NeoTreeMessage" } },
  },


  logging = {
    level = "info",
    echo = { level = "warn" },
    notify = { level = "error", prefix = "[neo-tree-insights]" },
    file = { enable = true, max_kb = 512, rotate = 3, filename = "unl.log" },
    perf = { enabled = false, patterns = { "^refresh" }, level = "trace" },
    debug = { enable = true, },
  },

  cache = { dirname = "neo-tree-insights" },
}
