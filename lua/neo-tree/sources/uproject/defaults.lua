return {
  logger = {
    name = "NeoTreeUProject",
    cache = { dirname = "URPOJECT_UNL" },
    logging = { level = "info", file = { enable = true, filename = "neo-tree-uproject.log" } },
  },
  renderers = {
    directory = { { "indent" }, { "icon" }, { "container", content = { { "name" } } } },
    file = { { "indent" }, { "icon" }, { "name" } },
    message = { { "indent", with_markers = false }, { "name", highlight = "NeoTreeMessage" } },
  },
  
}
