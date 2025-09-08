local M = {}

M.name = "uproject"
M.display_name = "UProject Explorer"

local state_manager = require("neo-tree.sources.uproject.state")

local last_active_state_id = nil
local active_listeners = {}

-------------------------------------------------
-- ツリーモデル構築ヘルパー関数
-------------------------------------------------
local function build_fs_tree_from_flat_list(file_list, root_path)
  local root = {}
  for _, file_path in ipairs(file_list) do
    local current_level = root
    local relative_path = file_path:sub(#root_path + 2)
    local parts = vim.split(relative_path, "[/]")
    for i, part in ipairs(parts) do
      if not current_level[part] then current_level[part] = {} end
      current_level = current_level[part]
    end
  end
  local function table_to_nodes(tbl, current_path)
    local nodes = {}
    for name, content in pairs(tbl) do
      local new_path = vim.fs.joinpath(current_path, name)
      local node_type = "file"
      local children_nodes = nil
      if next(content) then
        node_type = "directory"
        children_nodes = table_to_nodes(content, new_path)
      end
      table.insert(nodes, {
        id = new_path, name = name, path = new_path, type = node_type,
        children = children_nodes,
      })
    end
    table.sort(nodes, function(a, b) return a.name < b.name end)
    return nodes
  end
  return table_to_nodes(root, root_path)
end

local function build_hierarchy_nodes(modules_meta, files_by_module)
  local root_nodes = {
    Game = { id = "category_Game", name = "Game", type = "directory", extra = { uep_type = "category" }, children = {} },
    Plugins = { id = "category_Plugins", name = "Plugins", type = "directory", extra = { uep_type = "category" }, children = {} },
    Engine = { id = "category_Engine", name = "Engine", type = "directory", extra = { uep_type = "category" }, children = {} },
  }
  local plugin_nodes = {}
  for name, meta in pairs(modules_meta) do
    if meta.module_root then
      local module_files = files_by_module[name] or {}
      local file_tree = build_fs_tree_from_flat_list(module_files, meta.module_root)
      local node = { id = meta.module_root, name = name, path = meta.module_root, type = "directory", extra = { uep_type = "module" }, children = file_tree }
      
      if meta.location == "in_plugins" then
        local plugin_name = meta.module_root:match("[/\\]Plugins[/\\]([^/\\]+)")
        if plugin_name then
          local plugin_path = meta.module_root:match("(.+[/\\]Plugins[/\\][^/\\]+)")
          if not plugin_nodes[plugin_name] then
            plugin_nodes[plugin_name] = { id = plugin_path, name = plugin_name, path = plugin_path, type = "directory", extra = { uep_type = "plugin" }, children = {} }
          end
          table.insert(plugin_nodes[plugin_name].children, node)
        else
          table.insert(root_nodes.Plugins.children, node)
        end
      elseif meta.location == "in_source" then
        local category_key = meta.category or "Game"
        if root_nodes[category_key] then
          table.insert(root_nodes[category_key].children, node)
        end
      end
    end
  end
  for _, plugin_node in pairs(plugin_nodes) do table.insert(root_nodes.Plugins.children, plugin_node) end
  
  local final_nodes = {}
  for _, category_name in ipairs({ "Game", "Engine", "Plugins" }) do
    local category_node = root_nodes[category_name]
    if category_node and #category_node.children > 0 then
      category_node.path = category_node.id
      table.insert(final_nodes, category_node)
    end
  end
  return final_nodes
end

local cached_tree_model = nil
local is_building = false
--- ★★★ 変更点: 最後に有効だったstateを保持する変数 ★★★
local last_known_active_state = nil

-------------------------------------------------
-- navigate: メインの処理関数
-------------------------------------------------
M.navigate = function(state, path)
  local renderer = require("neo-tree.ui.renderer")

  --- ★★★ 変更点: 常に最新の有効なstateを記録 ★★★
  last_known_active_state = state

  if cached_tree_model then
    renderer.show_nodes(cached_tree_model, state)
    return
  end
  
  -- (あなたの修正を反映した、正しいloading_node)
  local loading_node = {{
    id = "_loading_node_", name = " Loading project data...", type = "directory", children = {},
  }}

  if is_building then
    renderer.show_nodes(loading_node, state)
    return
  end

  is_building = true
  renderer.show_nodes(loading_node, state)

  vim.defer_fn(function()
    -- (非同期のデータ構築ロジックは変更なし)
    local request = state_manager.get_last_request()
    if not request then
      local unl_finder = require("UNL.finder")
      local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
      if not project_root then is_building = false; return end
      local proj_info = unl_finder.project.find_project(project_root)
      request = { project_root = project_root, engine_root = proj_info and unl_finder.engine.find_engine_root(proj_info.uproject, {}), all_depth = false, target_module = nil }
    end
    
    local uep_project_cache = require("UEP.cache.project")
    local uep_files_cache = require("UEP.cache.files")
    local game_data = uep_project_cache.load(request.project_root)
    if not game_data then
      cached_tree_model = {{ id = "_error_node_", name = "Project data not found. Run ':UEP refresh'.", type = "message"}}
    else
      local engine_data = request.engine_root and uep_project_cache.load(request.engine_root)
      local game_files = uep_files_cache.load(request.project_root) or { files_by_module = {} }
      local engine_files = engine_data and uep_files_cache.load(engine_data.root) or { files_by_module = {} }
      local all_modules = vim.tbl_deep_extend("force", engine_data and engine_data.modules or {}, game_data.modules or {})
      local all_files = vim.tbl_deep_extend("force", engine_files.files_by_module or {}, game_files.files_by_module or {})
      local hierarchy = build_hierarchy_nodes(all_modules, all_files)
      local project_name = vim.fn.fnamemodify(game_data.uproject_path, ":t:r")
      cached_tree_model = {{
        id = request.project_root, name = project_name, path = request.project_root, type = "directory",
        extra = { uep_type = "project_root" },
        children = hierarchy,
      }}
    end
    is_building = false
    
    if require("neo-tree.sources.manager").get_state(M.name) then
      vim.cmd("Neotree action=focus source=uproject")
    end
  end, 10)
end

-------------------------------------------------
-- setup: イベントを購読し、安全なリフレッシュをトリガーする
-------------------------------------------------
M.setup = function(config, global_config)
  local unl_events = require("UNL.event.events")
  local unl_event_types = require("UNL.event.types")

  local function request_refresh()
    cached_tree_model = nil -- キャッシュを無効化
    
    --- ★★★ 変更点: 即時ローディング表示 ★★★
    if last_known_active_state and vim.api.nvim_win_is_valid(last_known_active_state.winid) then
      local renderer = require("neo-tree.ui.renderer")
      local loading_node = {{
        id = "_loading_node_", name = " Refreshing project data...", type = "directory", children = {},
      }}
      -- 最後の有効なstateを使って、即座にUIを上書き
      renderer.show_nodes(loading_node, last_known_active_state)
    end

    -- その後、正式なリフレッシュプロセスをトリガー
    if require("neo-tree.sources.manager").get_state(M.name) then
      vim.cmd("Neotree action=focus source=uproject")
    end
  end

  unl_events.subscribe(unl_event_types.ON_REQUEST_UPROJECT_TREE_VIEW, function(payload)
    state_manager.set_last_request(payload)
    request_refresh()
  end)
  
  unl_events.subscribe(unl_event_types.ON_AFTER_FILE_CACHE_SAVE, request_refresh)
  unl_events.subscribe(unl_event_types.ON_AFTER_PROJECT_CACHE_SAVE, request_refresh)

  unl_events.subscribe(unl_event_types.ON_AFTER_CHANGE_DIRECTORY, function(ev)
    if ev.status == "success" then
      state_manager.set_last_request(nil)
      request_refresh()
    end
  end)

  unl_events.publish(unl_event_types.ON_PLUGIN_AFTER_SETUP, { name = "neo-tree-unl-uproject" })
end

return M
