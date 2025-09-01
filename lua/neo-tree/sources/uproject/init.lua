local M = {}

M.name = "uproject"
M.display_name = "UProject Explorer"

-- このソースの状態を管理するモジュールをrequire
local state_manager = require("neo-tree.sources.uproject.state")
local manager = require("neo-tree.sources.manager")

-------------------------------------------------
-- ツリーモデル構築ヘルパー
-- (UEPから移動し、このファイル内で完結)
-------------------------------------------------
local function build_fs_tree_from_flat_list(file_list, root_path)
  local root = {}
  for _, file_path in ipairs(file_list) do
    local current_level = root
    local relative_path = file_path:sub(#root_path + 2) -- +2 for trailing slash
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
          if not plugin_nodes[plugin_name] then
            local plugin_path = meta.module_root:match("(.+[/\\]Plugins[/\\][^/\\]+)")
            plugin_nodes[plugin_name] = { id = plugin_path, name = plugin_name, path = plugin_path, type = "directory", extra = { uep_type = "plugin" }, children = {} }
          end
          table.insert(plugin_nodes[plugin_name].children, node)
        else
          table.insert(root_nodes.Plugins.children, node)
        end
      elseif meta.location == "in_source" then
        local category_key = meta.category or "Game" -- category should exist
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

-------------------------------------------------
-- navigate: ソースが表示されるたびに呼ばれる
-------------------------------------------------
M.navigate = function(state, path)
  local renderer = require("neo-tree.ui.renderer")
  
  -- 1. 表示リクエストのコンテキストを取得
  local request = state_manager.get_last_request()
  
  -- 2. リクエストがなければ、CWDからデフォルトコンテキストを作成
  if not request then
    local ok_finder, unl_finder = pcall(require, "UNL.finder")
    if not ok_finder then return renderer.show_nodes({{ name = "Error: UNL.nvim not available." }}, state) end
    
    local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
    if not project_root then
      return renderer.show_nodes({{ name = "Not in an Unreal Engine project." }}, state)
    end
    local proj_info = unl_finder.project.find_project(project_root)
    local engine_root = proj_info and unl_finder.engine.find_engine_root(proj_info.uproject, {})
    
    request = { project_root = project_root, engine_root = engine_root, all_depth = false, target_module = nil }
    state_manager.set_last_request(request) -- 次回のために保存
  end

  -- 3. UEPのキャッシュをロード
  local uep_project_cache = require("UEP.cache.project")
  local uep_files_cache = require("UEP.cache.files")

  local game_data = uep_project_cache.load(request.project_root)
  if not game_data then
    return renderer.show_nodes({{ name = "Project data not found. Run ':UEP refresh'." }}, state)
  end
  local engine_data = request.engine_root and uep_project_cache.load(request.engine_root)

  local game_files = uep_files_cache.load(request.project_root) or { files_by_module = {} }
  local engine_files = engine_data and uep_files_cache.load(engine_data.root) or { files_by_module = {} }

  -- 4. 全モジュールと全ファイルリストを準備
  local all_modules = vim.tbl_deep_extend("force", engine_data and engine_data.modules or {}, game_data.modules or {})
  local all_files = vim.tbl_deep_extend("force", engine_files.files_by_module, game_files.files_by_module)
  
  -- 5. モジュールを依存関係でフィルタリング (必要な場合)
  local deps_key = request.all_depth and "deep_dependencies" or "shallow_dependencies"
  local visible_modules = {}
  if request.target_module and all_modules[request.target_module] then
    -- 単一モジュール表示の場合
    visible_modules[request.target_module] = all_modules[request.target_module]
    for _, dep_name in ipairs(all_modules[request.target_module][deps_key] or {}) do
      if all_modules[dep_name] then visible_modules[dep_name] = all_modules[dep_name] end
    end
  else
    -- 全モジュール表示の場合
    visible_modules = all_modules
  end
  
  -- 6. ツリーモデルを構築
  local hierarchy = build_hierarchy_nodes(visible_modules, all_files)
  local project_name = vim.fn.fnamemodify(game_data.uproject_path, ":t:r")
  
  local tree_model_to_render = {{
    id = request.project_root, name = project_name, path = request.project_root, type = "directory",
    extra = { uep_type = "project_root" },
    children = hierarchy,
  }}

  -- 7. 描画
  renderer.show_nodes(tree_model_to_render, state)
end

-------------------------------------------------
-- setup: イベントを購読する
-------------------------------------------------
M.setup = function(config, global_config)
  local unl_events = require("UNL.event.events")
  local unl_event_types = require("UNL.event.types")

  local function request_ui_refresh()
    local state = manager.get_state(M.name, vim.api.nvim_get_current_tabpage())
    if state and state.winid and vim.api.nvim_win_is_valid(state.winid) then
      manager.refresh_source(M.name)
    end
  end
  
  -- UEPからのツリー表示リクエストを購読
  unl_events.subscribe(unl_event_types.ON_REQUEST_UPROJECT_TREE_VIEW, function(payload)
    state_manager.set_last_request(payload)
    request_ui_refresh()
  end)
  
  -- キャッシュ更新イベントを購読
  unl_events.subscribe(unl_event_types.ON_AFTER_FILE_CACHE_SAVE, request_ui_refresh)
  unl_events.subscribe(unl_event_types.ON_AFTER_PROJECT_CACHE_SAVE, request_ui_refresh)

  unl_events.subscribe(unl_event_types.ON_AFTER_CHANGE_DIRECTORY, function(ev)
    if ev.status == "success" then
      -- 状態をリセットする
      state_manager.set_last_request(nil)
      -- もしneo-treeが開いていたら、UIも更新する
      request_ui_refresh()
    end
  end)

  unl_events.publish(unl_event_types.ON_PLUGIN_AFTER_SETUP, { name = "neo-tree-unl" })
end

return M
