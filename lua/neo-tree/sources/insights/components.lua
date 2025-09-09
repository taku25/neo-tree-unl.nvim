local common_components = require("neo-tree.sources.common.components")
local highlights = require("neo-tree.ui.highlights")
local utils = require("neo-tree.utils") -- truncate_string用に追加

local M = {}

M.icon = function(config, node, state)
  local icon = {
    text = config.default or " ",
    highlight = config.highlight or highlights.FILE_ICON,
  }

  -- typeとextの両方をチェック
  local node_type = node.type
  local node_ext = node.item_type

  if node_type == "directory" or node_ext == "directory" then
    icon.highlight = highlights.DIRECTORY_ICON
    local should_be_expanded = state.explicitly_opened_nodes and 
                             state.explicitly_opened_nodes[node:get_id()] == true

    if should_be_expanded then
      if node.loaded and not node:has_children() then
        icon.text = config.folder_empty_open or "󰷏"
      else
        icon.text = config.folder_open or ""
      end
    else
      if node.loaded and not node:has_children() then
        icon.text = config.folder_empty or "󰉖"
      else
        icon.text = config.folder_closed or ""
      end
    end
  elseif node_type == "file" then
    icon.text = config.function_icon or "󰊕"  -- 関数用のアイコン
    icon.highlight = "Function" -- 関数用のハイライト
  end

  icon.text = icon.text .. " "
  return icon
end

M.name = function(config, node, state)
  local name = node.name
  local highlight = config.highlight or highlights.FILE_NAME
  
  if not name then 
    return nil
  end

  -- truncate_stringがutilsにあることを確認
  if config.truncate_length and utils.truncate_string then
    name = utils.truncate_string(name, config.truncate_length)
  end

  return {
    text = name,
    highlight = highlight
  }
end

-- ★★★ ここからが修正の核心です ★★★
-- 詳細表示で使われるが、私たちのソースには不要なコンポーネントを、
-- 「何も表示しない」空のコンポーネントとして明示的に定義します。
local empty_component = function()
  return { text = "" }
end

M.size = empty_component
M.last_modified = empty_component
M.git_status = empty_component
M.diagnostics = empty_component
M.modified = empty_component
M.bufnr = empty_component

return vim.tbl_deep_extend("force", common_components, M)
