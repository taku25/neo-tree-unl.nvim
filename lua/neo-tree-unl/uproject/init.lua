-- C:\Users\taku3\Documents\git\neo-tree-unl.nvim\lua\neo-tree-unl\uproject\init.lua

local utils = require("neo-tree.utils")
local M = {}

M.name = "uproject"
M.display_name = "UProject Explorer"

-- 依存モジュールを格納するテーブル
local modules = {
  renderer = nil,
  manager = nil,
  commands = nil,
  unl_events = nil,
  unl_event_types = nil,
  unl_log = nil,
}

-- 依存モジュールを遅延読み込みする関数
local function load_modules()
  if not modules.renderer then pcall(function() modules.renderer = require("neo-tree.ui.renderer") end) end
  if not modules.manager then pcall(function() modules.manager = require("neo-tree.sources.manager") end) end
  if not modules.commands then pcall(function() modules.commands = require("neo-tree-unl.uproject.commands") end) end
  if not modules.unl_events then pcall(function() modules.unl_events = require("UNL.event.events") end) end
  if not modules.unl_event_types then pcall(function() modules.unl_event_types = require("UNL.event.types") end) end
  if not modules.unl_log then pcall(function() modules.unl_log = require("UNL.logging") end) end
  return modules.renderer and modules.manager and modules.commands and modules.unl_events and modules.unl_event_types and modules.unl_log
end

-- UEP.nvimから受け取ったツリーデータを保持する変数
local full_tree_data = {} -- ノードIDをキーとして、完全なノード情報（子要素も含む）を格納するテーブル
local root_node_ids = {} -- ツリーの第一階層にあたるノードのIDを格納するリスト

---
-- commands.luaから完全なノードデータを取得するための公開関数
-- @param id string ノードのID
-- @return table|nil ノードデータ。見つからなければnil。
function M.get_full_node_data(id)
  return full_tree_data[id]
end

---
-- UEP.nvimから受け取ったノードリストを、高速にアクセスできる形式に変換する
-- @param nodes table UEP.nvimから渡されたノードのリスト
-- @param parent_id string|nil 親ノードのID
local function build_tree_lookup(nodes, parent_id)
  for _, node in ipairs(nodes) do
    node.parent_id = parent_id
    full_tree_data[node.id] = node
    if node.children and #node.children > 0 then
      build_tree_lookup(node.children, node.id)
    end
  end
end

---
-- 再帰的にノードを描画用に準備するヘルパー関数
-- stateに保存された展開状態を復元する
-- @param node_id string 処理対象のノードID
-- @param state table neo-treeの状態
-- @return table|nil 描画用のノードデータ
local function prepare_node_for_display_recursively(node_id, state)
  local node_data = full_tree_data[node_id]
  if not node_data then return nil end

  local node_copy = vim.deepcopy(node_data)
  
  -- このノードが展開されるべきかチェック
  local should_be_expanded = state.explicitly_opened_nodes and state.explicitly_opened_nodes[node_id]

  if node_copy.children and #node_copy.children > 0 then
    if should_be_expanded then
      -- 展開状態を復元する場合、子ノードも再帰的に準備する
      node_copy.loaded = true
      node_copy._is_expanded = true -- NuiTreeに展開状態で描画するよう指示するフラグ
      local children_for_display = {}
      for _, child_data in ipairs(node_copy.children) do
        local prepared_child = prepare_node_for_display_recursively(child_data.id, state)
        if prepared_child then
          table.insert(children_for_display, prepared_child)
        end
      end
      node_copy.children = children_for_display
    else
      -- 展開されていない場合は、子ノードは描画せず「未読み込み」とする
      node_copy.children = {}
      node_copy.loaded = false
    end
  else
    node_copy.loaded = true
  end
  
  return node_copy
end

---
-- neo-treeがツリーを描画または更新する際に呼び出すメイン関数
-- @param state table neo-treeの内部状態
-- @param path string? (このソースでは未使用)
M.navigate = function(state, path)
  if not load_modules() then return end
  local renderer = modules.renderer

  if #root_node_ids > 0 then
    -- 描画用データの準備
    local nodes_for_display = {}
    for _, id in ipairs(root_node_ids) do
      -- 新しく追加した再帰関数を使って、展開状態を復元しながらノードを準備する
      local prepared_node = prepare_node_for_display_recursively(id, state)
      if prepared_node then
        table.insert(nodes_for_display, prepared_node)
      end
    end

    utils.debounce("uproject_navigate",
      function()
        -- 準備したデータでツリーを描画
        renderer.show_nodes(nodes_for_display, state)
      end, 50, utils.debounce_strategy.CALL_LAST_ONLY)
  else
    -- UEP.nvimからデータがまだ来ていない場合のメッセージを表示
    renderer.show_nodes({{
      id = "uproject_info_message",
      name = "Waiting for data from UEP.nvim... Run ':UEP tree'",
      type = "message",
      highlight = "Comment",
    }}, state)
  end
end

local is_subscribed = false
M.setup = function(config, global_config)
  if is_subscribed then return end
  if not load_modules() then return end

  -- --- このソース専用のロガーをセットアップ ---
  local unl_log = modules.unl_log
  local LOGGER_NAME = "NeoTreeUProject"
  unl_log.setup(LOGGER_NAME, {
    cache = { dirname = "URPOJECT_UNL" },
    logging = {
      level = "info",
      file = { enable = true, filename = "neo-tree-uproject.log" },
    },
  }, {})
  local log = unl_log.get(LOGGER_NAME)

  -- commands モジュールに init.lua 自身のテーブル(M)を渡して初期化する
  modules.commands.setup(M)

  local unl_events = modules.unl_events
  local unl_event_types = modules.unl_event_types
  local manager = modules.manager

  log.info("Setting up event listeners for neo-tree-unl...")

  -- 1. UProjectツリー更新イベントを購読する
  unl_events.subscribe(unl_event_types.ON_UPROJECT_TREE_UPDATE, function(nodes_from_event)
    log.info("Received new tree data from 'ON_UPROJECT_TREE_UPDATE' event.")

    -- データを一旦リセット
    full_tree_data = {}
    root_node_ids = {}
    
    -- ルートノードのIDをリストアップ
    for _, node in ipairs(nodes_from_event or {}) do
        table.insert(root_node_ids, node.id)
    end
    -- 全ノードをIDで引けるようにルックアップテーブルを構築
    build_tree_lookup(nodes_from_event or {}, nil)

    -- neo-treeにビューの更新を要求
    if manager then
      manager.refresh(M.name)
    else
      log.warn("Could not get neo-tree manager to refresh the view.")
    end
  end)
  
  -- 2. 自身のセットアップ完了を通知する
  log.info("Publishing 'ON_PLUGIN_AFTER_SETUP' event for self.")
  unl_events.publish(unl_event_types.ON_PLUGIN_AFTER_SETUP, { name = "neo-tree-uproject" })

  is_subscribed = true
end

return M
