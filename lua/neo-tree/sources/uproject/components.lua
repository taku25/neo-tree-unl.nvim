local common_components = require("neo-tree.sources.common.components")
local highlights = require("neo-tree.ui.highlights")

local M = {}

M.icon = function(config, node, state)
  local icon = {
    text = config.default or " ",
    highlight = config.highlight or highlights.FILE_ICON,
  }

  if node.type == "directory" then
    icon.highlight = highlights.DIRECTORY_ICON
    -- 2. node:is_expanded() の代わりに、我々の判断結果 `should_be_expanded` を使ってアイコンを決定する
    if node:is_expanded() then
      icon.text = config.folder_open or ""
    else
      icon.text = config.folder_closed or ""
    end
  else
    if node.id:match("%.uproject$") then
      icon.text = config.uproject_icon or ""
      icon.highlight = highlights.FILE_ICON
    elseif node.id:match("%.uplugin$") then
      icon.text = config.uplugin_icon or ""
      icon.highlight = highlights.FILE_ICON
    else

      if config.provider then
        icon = config.provider(icon, node, state) or icon
      end
    end
  end

  icon.text = icon.text .. " "

  return icon
end

-- 共通コンポーネントと我々のカスタムコンポーネントをマージして返す
return vim.tbl_deep_extend("force", common_components, M)
