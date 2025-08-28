-- UEP-integration/neo-tree/uproject/init.lua
-- Unreal Engineプロジェクトの論理ビューを表示するための、自己完結型neo-treeソース。
--
-- このソースは、UEP.nvim のことを一切知りません。
-- UNLのグローバルイベントのみに依存して動作します。

local M = {}

M.name = "uproject"
M.display_name = "UProject Explorer"

local modules = {
  renderer = nil,
  unl_events = nil,
  unl_event_types = nil,
  unl_log = nil,
}

local function load_modules()
  if not modules.renderer then pcall(function() modules.renderer = require("neo-tree.ui.renderer") end) end
  if not modules.unl_events then pcall(function() modules.unl_events = require("UNL.event.events") end) end
  if not modules.unl_event_types then pcall(function() modules.unl_event_types = require("UNL.event.types") end) end
  if not modules.unl_log then pcall(function() modules.unl_log = require("UNL.logging") end) end
  return modules.renderer and modules.unl_events and modules.unl_event_types and modules.unl_log
end

local current_nodes = nil

M.navigate = function(state, path)
  if not load_modules() then return end
  local renderer = modules.renderer

  if current_nodes then
    renderer.show_nodes(current_nodes, state)
  else
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
  local LOGGER_NAME = "NeoTreeUProject" -- 衝突を避けるため、より明確な名前に
  unl_log.setup(LOGGER_NAME, {

    cache = { dirname = "URPOJECT_UNL" },
    logging = {
      level = "info",
      file = { enable = true, filename = "neo-tree-uproject.log" },
    },
  }, {})
  local log = unl_log.get(LOGGER_NAME)

  local unl_events = modules.unl_events
  local unl_event_types = modules.unl_event_types
  local ok_manager, manager = pcall(require, "neo-tree.sources.manager")

  log.info("Setting up event listeners...")

  -- 1. UProjectツリー更新イベントを購読する
  unl_events.subscribe(unl_event_types.ON_UPROJECT_TREE_UPDATE, function(nodes_from_event)
    log.info("Received new tree data from 'ON_UPROJECT_TREE_UPDATE' event.")
    current_nodes = nodes_from_event
    if ok_manager then
      manager.refresh(M.name)
    else
      log.warn("Could not get neo-tree manager to refresh the view.")
    end
  end)
  
  -- ★★★ 2. 購読設定が完了した直後に、自身のセットアップ完了を通知する ★★★
  log.info("Publishing 'ON_PLUGIN_AFTER_SETUP' event for self.")
  unl_events.publish(unl_event_types.ON_PLUGIN_AFTER_SETUP, { name = "neo-tree-uproject" })

  is_subscribed = true
end

return M
