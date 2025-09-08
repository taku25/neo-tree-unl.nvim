
local config = {
  renderers = {
    directory = {
      { "indent" },
      { "icon" },
      { "name" },
    },
    file = {
      { "indent" },
      { "icon" },
      { "name" },
    },
    function = {  -- function用のレンダラーを追加
      { "indent" },
      { "icon" },
      { "name" },
    },
    message = {
      { "indent", with_markers = false },
      { "name", highlight = "NeoTreeMessage" },
    },
  },
  function_icon = "󰊕",
}

return config

