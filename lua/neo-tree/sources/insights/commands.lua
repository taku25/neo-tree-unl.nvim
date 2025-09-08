local cc = require("neo-tree.sources.common.commands")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager") -- ★ 追加
local util = require("neo-tree.utils") -- ★ 追加

local M = {}

local insights_source = nil
function M.init(source_module)
  insights_source = source_module
end

-- ★ 追加
M.refresh = function(state)
  manager.refresh(state.name)
end

local function toggle_node_logic(state, node)
  if not node then return end
  
  if node.loaded == false then
    if not insights_source then return end
    
    -- 一度に処理する子ノードの数を制限
    local BATCH_SIZE = 100
    local all_children = {}
    
    if node.extra and node.extra.ulg_event and node.extra.ulg_event.children then
      for i, child_event in ipairs(node.extra.ulg_event.children) do
        if i > BATCH_SIZE then
          -- 警告を表示
          vim.notify(string.format("Showing first %d children only. Node has %d total children.", 
            BATCH_SIZE, #node.extra.ulg_event.children), vim.log.levels.WARN)
          break
        end
        
        if type(child_event) == "table" and child_event.s and child_event.tid then
          local child_node = insights_source.event_to_node(child_event)
          if child_node.has_children then
            child_node.children = {}
            child_node.loaded = false
          end
          table.insert(all_children, child_node)
        end
      end
    end
    
    renderer.show_nodes(all_children, state, node:get_id())
    node.loaded = true
    if not node:is_expanded() then node:expand() end
    renderer.redraw(state)
  elseif node:has_children() then
    if node:is_expanded() then node:collapse() else node:expand() end
    renderer.redraw(state)
  end
end

M.toggle_node = function(state)
  toggle_node_logic(state, state.tree:get_node())
end

M.open = function(state)
  local node = state.tree:get_node()

  if (node.type == "function" or node.ext == "function") and 
     node.extra and node.extra.ulg_event then
    local event = node.extra.ulg_event
    if event.file and event.line then
      util.open_file(state, event.file)
      return
    end
  end
  
  toggle_node_logic(state, node)
end

cc._add_common_commands(M)


return M
