-- lua/neo-tree/sources/insights/init.lua (renderers定義を追加した最終完成版)

local M = {}

M.name = "insights"
M.display_name = "ULG Insights"

local state_manager = require("neo-tree.sources.insights.state")
local manager = require("neo-tree.sources.manager")

function M.event_to_node(event)
  -- UUIDを生成するヘルパー関数
  local function generate_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
      local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
    end)
  end

  local duration_ms = (event.e - event.s) * 1000
  local has_children = event.children and #event.children > 0
  
  -- 完全にユニークなIDを生成
  local node_id = string.format("insight_event_%s_%s", 
    generate_uuid(),
    event.tid and tostring(event.tid) or "unknown"
  )
  -- ★★★ ここからが修正箇所です ★★★
  
  local node_type, item_type
  if has_children then
    node_type = "directory"
    item_type = "directory" 
  else
    node_type = "file"
    item_type = "func"
  end
  
  return {
    id = node_id,
    name = string.format("%s (%.3fms)", event.name or "Unknown", duration_ms),
    type = node_type,
    item_type = item_type,
    has_children = has_children,
    loaded = not has_children,
    extra = { 
      ulg_event = event,
      file = event.file,
      line = event.line
    },
  }
end

function M.navigate(state, path)
  local renderer = require("neo-tree.ui.renderer")
  local last_request = state_manager.get_last_request()
  
  if not (last_request and last_request.frame_data) then
    renderer.show_nodes({{
      id = "insights_no_frame",
      name = "No frame data.",
      type = "message",
      children = {},
    }}, state)
    return
  end

  local root_events = last_request.frame_data.events_tree
  if not root_events or #root_events == 0 then
    renderer.show_nodes({{
      id = "insights_no_events",
      name = "No events in this frame.",
      type = "message",
      children = {},
    }}, state)
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

function M.setup(config, global_config)
  local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
  if not unl_events_ok then return end
  local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
  if not unl_types_ok then return end

  unl_events.subscribe(unl_event_types.ON_REQUEST_TRACE_CALLEES_VIEW, function(payload)
    state_manager.set_last_request(payload)

    local insights_state = manager.get_state(M.name)
    if insights_state and insights_state.winid and vim.api.nvim_win_is_valid(insights_state.winid) then
      M.navigate(insights_state, nil)
      manager.refresh(M.name)
    else
      vim.cmd("Neotree action=focus source=" .. M.name)
    end
  end)

  M.commands = require("neo-tree.sources.insights.commands")
  -- M.components = require("neo-tree.sources.insights.components")
  M.commands.init(M)

  unl_events.publish(unl_event_types.ON_PLUGIN_AFTER_SETUP, { name = "neo-tree-unl-insights" })

end

return M
