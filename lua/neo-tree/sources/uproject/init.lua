
local M = {}

M.name = "uproject"
M.display_name = "UProject Explorer"

local current_nodes = nil -- このソースが管理するデータ

-- ヘルパー：UEPからのデータをneo-tree形式に変換
local function normalize_nodes_for_neo_tree(nodes, parent_path)
  if not nodes then return nil end
  local normalized = {}
  for _, node in ipairs(nodes) do
    local node_path = node.id
    local new_node = {
      id = node.id, name = node.name, type = node.type or "directory",
      path = node_path, parent_path = parent_path, extra = node.extra or {},
      loaded = true, is_link = false, link_to = nil, ext = nil, filtered_by = nil,
    }
    if new_node.type == "file" then new_node.ext = node_path:match("%.([^.]+)$") end
    if node.children and #node.children > 0 then
      new_node.children = normalize_nodes_for_neo_tree(node.children, node_path)
    end
    table.insert(normalized, new_node)
  end
  return normalized
end

--- ★★★ 新規追加: commands.lua から呼ばれる関数 ★★★
-- current_nodes の中から、指定されたIDのノードを再帰的に探す
-- @param node_id string 探すノードのID
-- @return table|nil 見つかったノードのデータ、またはnil
function M.get_full_node_data(node_id)
  if not current_nodes then return nil end

  local function find_recursive(nodes_to_search)
    for _, node in ipairs(nodes_to_search) do
      if node.id == node_id then
        return node
      end
      if node.children and #node.children > 0 then
        local found = find_recursive(node.children)
        if found then return found end
      end
    end
    return nil
  end

  -- current_nodes はトップレベルのノードのリストなので、そこから探し始める
  return find_recursive(current_nodes)
end

-- navigate は必須
M.navigate = function(state, path)
  local renderer = require("neo-tree.ui.renderer")
  if current_nodes then
    -- current_nodes は既に正規化済みなので、そのまま渡す
    renderer.show_nodes(current_nodes, state)
  else
    renderer.show_nodes({{
      id = "uproject_info_message", name = "Waiting for data from UEP.nvim...",
      type = "message",
    }}, state)
  end
end

-- setup は必須
M.setup = function(config, global_config)
  local ok_unl, unl_events = pcall(require, "UNL.event.events")
  if not ok_unl then return end 

  local unl_event_types = require("UNL.event.types")
  local manager = require("neo-tree.sources.manager")
  
  unl_events.subscribe(unl_event_types.ON_UPROJECT_TREE_UPDATE, function(nodes_from_event)
    
    -- 1. 正規化されたデータを current_nodes に保存
    current_nodes = normalize_nodes_for_neo_tree(nodes_from_event, nil)
    
    -- 2. 現在アクティブなタブページの uproject ソースの state を取得する
    local current_tab = vim.api.nvim_get_current_tabpage()
    local state = manager.get_state(M.name, current_tab)

    -- 3. その state を使って、navigate を直接呼び出す
    --    これにより、即座にUIが更新される
    if state and state.winid and vim.api.nvim_win_is_valid(state.winid) then
        M.navigate(state)
    end
  end)

  -- ON_PLUGIN_AFTER_SETUP は、一度だけ発行すれば良い
  -- (この setup 関数が複数回呼ばれることを考慮すると、is_subscribed フラグは有用)
  local is_subscribed
  if not is_subscribed then
      unl_events.publish(unl_event_types.ON_PLUGIN_AFTER_SETUP, { name = "neo-tree-uproject" })
      is_subscribed = true
  end
end

return M
