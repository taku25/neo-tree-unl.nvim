-- From: neo-tree-unl.nvim/lua/neo-tree/sources/uproject/init.lua
-- (vim.api.nvim.is_valid のタイポを修正)

local M = {}
M.name = "uproject"
M.display_name = "uproject"

local state_manager = require("neo-tree.sources.uproject.state")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local log = require("neo-tree.log") 
local events = require("neo-tree.events") -- [!] 1. neo-treeのイベントを require
local is_fetching = false

----------------------------------------------------------------------
-- 状態保存 (変更なし)
----------------------------------------------------------------------
local function save_expanded_state(state)
  local expanded_nodes = {}
  if not (state and state.tree and state.tree.nodes and state.tree.nodes.by_id) then
    log.trace("save_expanded_state: No tree found in state, returning empty.")
    return {}
  end
  for id, node in pairs(state.tree.nodes.by_id) do
    if node:is_expanded() then
      table.insert(expanded_nodes, id)
    end
  end
  log.trace("Saved %d expanded node IDs.", #expanded_nodes)
  return expanded_nodes
end

----------------------------------------------------------------------
-- データ取得とレンダリングのコアロジック
----------------------------------------------------------------------

-- (fetch_data 関数は変更なし)
local function fetch_data(state, on_complete)
  if is_fetching then return end
  is_fetching = true
  renderer.show_nodes({ { id = "_loading_", name = " Loading project data...", type = "message" } }, state)
  vim.schedule(function()
    local request_opts = state_manager.get_last_request() or {}
    if not request_opts.project_root then
      local unl_finder_ok, unl_finder = pcall(require, "UNL.finder")
      if unl_finder_ok then
          local proj_info = unl_finder.project.find_project(vim.loop.cwd())
          local engine_root = proj_info and unl_finder.engine.find_engine_root(proj_info.uproject, {})
          request_opts.project_root = proj_info and proj_info.root or nil
          request_opts.engine_root = engine_root
      end
    end
    if not request_opts.project_root then
        is_fetching = false
        if on_complete then on_complete(nil, "Not an Unreal Engine project.") end
        return
    end
    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if not unl_api_ok then
        is_fetching = false
        if on_complete then on_complete(nil, "UNL.api not available.") end
        return
    end
    local req_ok, result = unl_api.provider.request("uep.build_tree_model", {
      capability = "uep.build_tree_model",
      project_root = request_opts.project_root,
      engine_root = request_opts.engine_root,
      scope = request_opts.scope,
      deps_flag = request_opts.deps_flag,
      target_module = request_opts.target_module,
      logger_name = "neo-tree-uproject",
    })
    is_fetching = false
    if on_complete then
      if not req_ok then
        on_complete(nil, "Waiting for UEP.nvim...")
      elseif not result then
        on_complete(nil, "No data. Please run :UEP refresh")
      else
        on_complete(result)
      end
    end
  end)
end

-- (load_children 関数は変更なし)
function M.load_children(state, node)
  log.trace("load_children called for node: %s", node.id)
  local unl_api_ok, unl_api = pcall(require, "UNL.api")
  if not unl_api_ok then
    log.error("UNL.api not available for load_children.")
    return nil
  end
  local req_ok, children_nodes = unl_api.provider.request("uep.load_tree_children", {
    capability = "uep.load_tree_children",
    node = node,
    logger_name = "neo-tree-uproject",
  })
  if not req_ok or not children_nodes then
    log.error("Failed to fetch children for node: %s", node.id)
    return nil
  end
  log.trace("Successfully fetched %d children for node: %s", #children_nodes, node.id)
  return children_nodes
end

-- (M.navigate 関数は変更なし)
function M.navigate(state, path, expanded_nodes_to_restore)
  log.trace("Navigate called.")
  
  fetch_data(state, function(tree_model_result, err_msg)
    if not tree_model_result then
      local final_err_msg = err_msg or "Failed to fetch data."
      renderer.show_nodes({{ id = "_error_", name = " " .. final_err_msg, type = "message" }}, state)
      return
    end

    if expanded_nodes_to_restore and #expanded_nodes_to_restore > 0 then
      log.debug("Restoring %d expanded nodes.", #expanded_nodes_to_restore)
      state.default_expanded_nodes = expanded_nodes_to_restore
    else
      log.debug("No expanded nodes to restore.")
      state.default_expanded_nodes = {} -- クリア
    end

    renderer.show_nodes(tree_model_result, state)
  end)
end

----------------------------------------------------------------------
-- セットアップとイベントリスナー (★ ここの typo が原因でした)
----------------------------------------------------------------------

M.setup = function(config, global_config)
  local unl_log_ok, unl_log = pcall(require, "UNL.logging")
  if unl_log_ok then
    unl_log.setup("neo-tree-uproject", config)
  end
  local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
  if not unl_events_ok then return end
  local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
  if not unl_types_ok then return end
  local log = require("neo-tree.log") 

  ---
  -- Handler 1: :UEP tree などの「ツリー表示設定」の変更用
  ---
  local function on_tree_request_changed(payload)
    log.trace("on_tree_request_changed triggered")
    state_manager.set_last_request(payload)
    log.debug("Calling manager.refresh() for new tree request.")
    manager.refresh(M.name)
  end

  ---
  -- Handler 2: UCM によるファイル変更などの「軽量リフレッシュ」用
  ---
  local function on_lightweight_refresh(payload)
    log.trace("on_lightweight_refresh triggered for module: %s", payload.updated_module or "unknown")

    local state = manager.get_state(M.name)
    
    -- ▼▼▼ 修正: `vim.api.nvim.is_valid` -> `vim.api.nvim_win_is_valid` ▼▼▼
    if state and state.winid and vim.api.nvim_win_is_valid(state.winid) then
    -- ▲▲▲ ここがL164です ▲▲▲
      log.debug("uproject source is visible, saving state and calling M.navigate().")
      local expanded_state = save_expanded_state(state)
      M.navigate(state, nil, expanded_state)
    elseif state then
      log.debug("uproject source is not visible, marking as dirty.")
      state.dirty = true
    end
  end
  
  -- [!] イベントを正しいハンドラに紐付ける
  unl_events.subscribe(unl_event_types.ON_REQUEST_UPROJECT_TREE_VIEW, on_tree_request_changed)
  unl_events.subscribe(unl_event_types.ON_AFTER_UEP_LIGHTWEIGHT_REFRESH, on_lightweight_refresh)
  
-- ▼▼▼ 2. ここに修正を追加 ▼▼▼
  -- neo-tree のグローバル設定 (enable_modified_markers) に従って、
  -- ファイル変更イベントの監視を有効化します。
  if global_config.enable_modified_markers then
    manager.subscribe(M.name, {
      event = events.VIM_BUFFER_MODIFIED_SET,
      handler = function(args)
        -- 'manager.opened_buffers_changed' は neo-tree が提供する
        -- 汎用の「バッファ変更ハンドラ」です
        manager.opened_buffers_changed(M.name, args)
      end
    })
  end
  -- ▲▲▲ 修正完了 ▲▲▲
  unl_events.subscribe(unl_event_types.ON_PLUGIN_AFTER_SETUP, function(payload)
    if payload and payload.name == "UEP" then
      local state = manager.get_state(M.name)
      if state and state.tree and state.tree:get_node("_error_") then
        manager.refresh(M.name)
      end
    end
  end)
end

return M
