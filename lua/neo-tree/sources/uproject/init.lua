-- lua/neo-tree/sources/uproject/init.lua
local M = {}
M.name = "uproject"
M.display_name = "uproject"

-- lua/neo-tree/sources/uproject/init.lua

local state_manager = require("neo-tree.sources.uproject.state")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")

-- 状態変数をシンプルに
local tree_model = nil -- 成功した結果か、表示すべきメッセージノードのどちらかが入る
local is_fetching = false -- is_buildingから改名

-- ★ データ取得のコアロジック
local function fetch_data()
  if is_fetching then return end
  is_fetching = true
   local state = manager.get_state(M.name)
  tree_model = {{ id = "_loading_", name = " Loading project data...", type = "message" }}
  renderer.show_nodes(tree_model, state)

  vim.schedule(function()
    local request_opts = state_manager.get_last_request() or {}
    -- request_optsが空でも、finderがcwdから探してくれる
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
        tree_model = {{ id = "_error_", name = " Not an Unreal Engine project.", type = "message" }}
        is_fetching = false
        renderer.show_nodes(tree_model, state)
        return
    end

    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if not unl_api_ok then
        tree_model = {{ id = "_error_", name = " UNL.api not available.", type = "message" }}
    else
      local req_ok, result = unl_api.provider.request("uep.build_tree_model", {
        capability = "uep.build_tree_model", -- ★ この行を追加！
        project_root = request_opts.project_root,
        engine_root = request_opts.engine_root,
        all_deps = request_opts.all_deps or false, 
        target_module = request_opts.target_module,
        logger_name = "neo-tree-uproject",
      })
      if not req_ok then
        tree_model = {{ id = "_error_", name = " Waiting for UEP.nvim...", type = "message" }}
      elseif not result then
        tree_model = {{ id = "_error_", name = " No data. Please run :UEP refresh", type = "message" }}
      else
        tree_model = result -- 成功した結果を格納
      end
    end
    
    is_fetching = false
    renderer.show_nodes(tree_model, state)
  end)
end

M.navigate = function(state, path)
  if tree_model then
    -- 表示すべきモデル（成功結果 or メッセージ）があれば表示
    renderer.show_nodes(tree_model, state)
  else
    -- 何もなければ（初回起動時）、データ取得を開始
    fetch_data()
  end
end

M.setup = function(config, global_config)

  local unl_log_ok, unl_log = pcall(require, "UNL.logging")
  if unl_log_ok then
    unl_log.setup("neo-tree-uproject", config)
  end

  local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
  if not unl_events_ok then return end
  local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
  if not unl_types_ok then return end


  -- UEPが後からロードされた時
  unl_events.subscribe(unl_event_types.ON_PLUGIN_AFTER_SETUP, function(payload)
    if payload and payload.name == "UEP" and tree_model and tree_model[1].id == "_error_" then
      fetch_data()
    end
  end)

  -- データが外部で更新された時
  local function on_data_changed()
    -- tree_modelをnilにして、次回navigate時に再取得するようにする
    tree_model = nil
    -- もしツリーが表示中なら、リフレッシュをかける
    local current_state = manager.get_state(M.name)
    if current_state and current_state.winid and vim.api.nvim_win_is_valid(current_state.winid) then
      fetch_data()
        -- manager.refresh(M.name)
    end
  end
  -- :UEP tree などで明示的に表示要求が来た時
  unl_events.subscribe(unl_event_types.ON_REQUEST_UPROJECT_TREE_VIEW, function(payload)
    state_manager.set_last_request(payload)
    fetch_data()
  end)
  unl_events.subscribe(unl_event_types.ON_AFTER_FILE_CACHE_SAVE, on_data_changed)
  unl_events.subscribe(unl_event_types.ON_AFTER_PROJECT_CACHE_SAVE, on_data_changed)
  unl_events.subscribe(unl_event_types.ON_AFTER_CHANGE_DIRECTORY, on_data_changed)
end

return M
