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
    
    -- 1. このノードが「開いているべき」状態かを、我々の state から判断する
    local should_be_expanded = state.explicitly_opened_nodes and state.explicitly_opened_nodes[node:get_id()] == true

    -- 2. node:is_expanded() の代わりに、我々の判断結果 `should_be_expanded` を使ってアイコンを決定する
    if should_be_expanded then
      -- 「開いているべき」場合のアイコンロジック
      if node.loaded and not node:has_children() then
        -- データが読み込み済みで、子がいない場合 -> 「空で開いているフォルダ」アイコン
        icon.text = config.folder_empty_open or "󰷏"
      else
        -- 子がいる、またはまだ読み込んでいない場合 -> 通常の「開いているフォルダ」アイコン
        icon.text = config.folder_open or ""
      end
    else
      -- 「閉じているべき」場合のアイコンロジック
      if node.loaded and not node:has_children() then
        -- データが読み込み済みで、子がいない場合 -> 「空で閉じているフォルダ」アイコン
        icon.text = config.folder_empty or "󰉖"
      else
        -- 子がいる、またはまだ読み込んでいない場合 -> 通常の「閉じているフォルダ」アイコン
        icon.text = config.folder_closed or ""
      end
    end
  end

  if config.provider then
    icon = config.provider(icon, node, state) or icon
  end

  icon.text = icon.text .. " "

  return icon
end

-- 共通コンポーネントと我々のカスタムコンポーネントをマージして返す
return vim.tbl_deep_extend("force", common_components, M)
