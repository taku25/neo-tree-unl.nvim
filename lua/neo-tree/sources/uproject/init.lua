-- lua/neo-tree/sources/uproject/init.lua
--
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
--                   最終確定版
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
--
-- このファイルは、以下の問題を解決するための全てのロジックを含んでいます。
-- 1. UCMによるファイル操作後、UIが自動で更新される。
-- 2. UI更新時に、ユーザーが展開していたディレクトリの状態が復元される。
-- 3. 数万ファイルを含む大規模プロジェクトでも遅延読み込みによって軽快に動作する。
-- 4. neo-treeの内部キャッシュによって更新がスキップされる問題を回避する。
-- 5. 全ての更新フロー（初回表示、:UEP tree、UCMイベント）が一貫した安定したコードパスを辿る。
--
local M = {}
M.name = "uproject"
M.display_name = "uproject"

local state_manager = require("neo-tree.sources.uproject.state")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")

-- このソースが現在データ取得中かどうかを管理する唯一の状態変数
local is_fetching = false

----------------------------------------------------------------------
-- 状態保存と復元のためのヘルパー関数
----------------------------------------------------------------------

---
-- 現在のツリーで展開されている全てのノードIDをリストとして取得する。
-- @param state neotree.State
-- @return table 展開済みノードIDの文字列リスト
local function save_expanded_state(state)
  local expanded_nodes = {}
  -- state.tree.nodes.by_id が存在する、というあなたの発見が核心です
  if not (state and state.tree and state.tree.nodes and state.tree.nodes.by_id) then
    return {}
  end
  for id, node in pairs(state.tree.nodes.by_id) do
    if node:is_expanded() then
      table.insert(expanded_nodes, id)
    end
  end
  require("neo-tree.log").trace("Saved %d expanded node IDs.", #expanded_nodes)
  return expanded_nodes
end

---
-- tree_modelを受け取り、展開が必要なノードの children を事前に設定（ハイドレーション）する。
-- これにより、neo-treeは遅延読み込みなしで初期表示時に子ノードを描画できる。
-- @param nodes table: tree_model のノードリスト
-- @param expanded_ids_set table: 展開すべきノードIDのセット (高速検索用)
local function hydrate_tree_model(nodes, expanded_ids_set)
  if not (nodes and #nodes > 0 and expanded_ids_set and next(expanded_ids_set)) then
    return
  end
  for _, node in ipairs(nodes) do
    if expanded_ids_set[node.id] then
      if node.extra and node.extra.hierarchy then
        node.children = vim.deepcopy(node.extra.hierarchy)
        -- 子孫も展開される可能性があるので、再帰的に処理する
        hydrate_tree_model(node.children, expanded_ids_set)
      end
    end
  end
end

----------------------------------------------------------------------
-- データ取得とレンダリングのコアロジック
----------------------------------------------------------------------

---
-- UEPプロバイダーから非同期でツリーモデルを取得する。
-- この関数は、結果をコールバックで返すことだけに責任を持つ。
-- @param state neotree.State
-- @param on_complete fun(tree_model_result: table|nil)
local function fetch_data(state, on_complete)
  if is_fetching then return end
  is_fetching = true

  -- ローディングメッセージだけは即座に表示する
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
      all_deps = request_opts.all_deps or false,
      target_module = request_opts.target_module,
      logger_name = "neo-tree-uproject",
    })

    is_fetching = false
    
    -- ★★★ 鉄の契約: 成功しても失敗しても、必ずコールバックを呼ぶ ★★★
    if on_complete then
      if not req_ok then
        on_complete(nil, "Waiting for UEP.nvim...")
      elseif not result then
        on_complete(nil, "No data. Please run :UEP refresh")
      else
        on_complete(result) -- 成功した場合、結果を渡す
      end
    end
  end)
end


---
-- このソースのメインエントリーポイント。レンダリングに関する全ての交通整理を行う。
-- どの経路で呼び出されても、常に一貫した描画フローを保証する。
function M.navigate(state, path)
  local log = require("neo-tree.log")
  log.trace("Navigate called.")

  -- 1. まず、現在のツリーがクリアされる前に、展開状態を記憶する
  local expanded_nodes_to_restore = save_expanded_state(state)

  -- 2. データ取得を開始し、完了後にレンダリングを行うコールバックを渡す
  fetch_data(state, function(tree_model_result, err_msg)
    -- --- このコールバック内が、データ取得後の唯一の処理場所 ---
    if not tree_model_result then
      -- データ取得に失敗した場合
      local final_err_msg = err_msg or "Failed to fetch data."
      renderer.show_nodes({{ id = "_error_", name = " " .. final_err_msg, type = "message" }}, state)
      return
    end

    -- 3. 状態復元ロジックを実行
    if #expanded_nodes_to_restore > 0 then
      state.default_expanded_nodes = expanded_nodes_to_restore
      
      local expanded_set = {}
      for _, id in ipairs(expanded_nodes_to_restore) do expanded_set[id] = true end
      hydrate_tree_model(tree_model_result, expanded_set)
    end

    -- 4. 準備が整った最終的なツリーを描画
    renderer.show_nodes(tree_model_result, state)
  end)
end

----------------------------------------------------------------------
-- セットアップとイベントリスナー
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

  ---
  -- データソースが外部で変更された（可能性のある）場合に呼ばれる、唯一のトリガー。
  -- この関数は、状態をリセットし、公式のrefresh APIを呼び出すことだけに責任を持つ。
  local function on_data_changed(payload)
    state_manager.set_last_request(payload)
    local state = manager.get_state(M.name)
    if state and state.winid and vim.api.nvim_win_is_valid(state.winid) then
      -- ★★★ neo-treeに「何か変わったぞ」と知らせるためにrefreshを呼び出す。
      -- これにより、我々のnavigate関数が安全に呼び出されることが保証される。


      -- state.dirty = false 
      vim.cmd("Neotree source=uproject")
      -- manager.refresh(M.name)
      -- renderer.redraw(state)
    end
  end

  -- :UEP tree コマンドが実行された時
  unl_events.subscribe(unl_event_types.ON_REQUEST_UPROJECT_TREE_VIEW, on_data_changed)
  
  -- UCMでファイルが変更され、UEPの軽量キャッシュ更新が完了した時
  unl_events.subscribe(unl_event_types.ON_AFTER_UEP_LIGHTWEIGHT_REFRESH, on_data_changed)
  
  -- UEPが後からロードされた時に、エラー表示を更新する
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
