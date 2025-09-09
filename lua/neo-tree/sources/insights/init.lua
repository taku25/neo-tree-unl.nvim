-- lua/neo-tree/sources/insights/init.lua (プロバイダー + イベントのハイブリッド版)

local M = {}
M.name = "insights"
M.display_name = "ULG Insights"

local state_manager = require("neo-tree.sources.insights.state")
local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")

-- (このヘルパー関数は変更の必要なし)
function M.event_to_node(event)
  local function generate_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
      local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
    end)
  end
  local duration_ms = (event.e - event.s) * 1000
  local has_children = event.children and #event.children > 0
  local node_id = string.format("insight_event_%s_%s", generate_uuid(), event.tid and tostring(event.tid) or "unknown")
  local node_type, item_type
  if has_children then
    node_type = "directory"; item_type = "directory" 
  else
    node_type = "file"; item_type = "func"
  end
  return {
    id = node_id,
    name = string.format("%s (%.3fms)", event.name or "Unknown", duration_ms),
    type = node_type, item_type = item_type,
    has_children = has_children,
    loaded = not has_children,
    extra = { ulg_event = event, file = event.file, line = event.line },
  }
end

M.navigate = function(state, path)
  -- 初回表示時に、ULGに保留中のリクエストがないか問い合わせる
  if not state.initial_provider_check_done then
    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if unl_api_ok then
      local req_ok, payload = unl_api.provider.request("ulg.get_pending_trace_request", {
          capability = "ulg.get_pending_trace_request", -- ★ この行を追加！
          consumer = "neo-tree-insights",
          logger_name = "neo-tree-insights" -- ロガー名を渡す
      })
      if req_ok and payload then
        state_manager.set_last_request(payload)
      end
    end
    state.initial_provider_check_done = true
  end

  local last_request = state_manager.get_last_request()
  
  if not last_request then
    renderer.show_nodes({{ id = "insights_no_data", name = "No trace data loaded. Run :ULG trace", type = "message" }}, state)
    return
  end
  
  -- last_requestからツリーを構築して表示する
  local root_events = last_request.frame_data.events_tree
  if not root_events or #root_events == 0 then
    renderer.show_nodes({{ id = "insights_no_events", name = "No events in this frame.", type = "message" }}, state)
    return
  end
  
  local root_nodes = {}
  for _, event in ipairs(root_events) do
    local node = M.event_to_node(event)
    if node.has_children then
      node.children = {}
      node.loaded = false
    end
    table.insert(root_nodes, node)
  end
  
  renderer.show_nodes(root_nodes, state)
end

M.setup = function(config, global_config)
  -- 自身のロガーをUNLに登録
  local unl_log_ok, unl_log = pcall(require, "UNL.logging")
  if unl_log_ok then
    unl_log.setup("neo-tree-insights", config) -- defaults.luaがないので空テーブルでOK
  end

  local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
  if not unl_events_ok then return end
  local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
  if not unl_types_ok then return end

  -- ULGからの更新通知イベントを購読
  unl_events.subscribe(unl_event_types.ON_REQUEST_TRACE_CALLEES_VIEW, function(payload)
    state_manager.set_last_request(payload)
    -- stateをリセットして、次回navigate時にプロバイダーを見に行くようにする
    local current_state = manager.get_state(M.name)
    if current_state then
        current_state.initial_provider_check_done = false
    end
    manager.refresh(M.name)
  end)
  
  -- ULGが後からロードされた場合にも対応
  unl_events.subscribe(unl_event_types.ON_PLUGIN_AFTER_SETUP, function(payload)
      if payload and payload.name == "ULG" then
          local current_state = manager.get_state(M.name)
          if current_state then
              current_state.initial_provider_check_done = false
              manager.refresh(M.name)
          end
      end
  end)

  M.commands = require("neo-tree.sources.insights.commands")
  M.commands.init(M)
end

return M
