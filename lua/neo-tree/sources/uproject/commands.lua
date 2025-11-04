-- lua/neo-tree/sources/uproject/commands.lua (遅延読み込み対応版)
local fs_actions = require("neo-tree.sources.filesystem.lib.fs_actions")
local cc = require("neo-tree.sources.common.commands")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local unl_finder = require("UNL.finder")
local utils = require("neo-tree.utils")
local unl_events = require("UNL.event.events")
local unl_event_types =require("UNL.event.types")
local log = require("neo-tree.log") -- [!] ログ用に

---@class neotree.sources.Uproject.Commands : neotree.sources.Common.Commands
local M = {}


local refresh = function(state)
  manager.refresh(state.name)
end


local function modify_directory(type_name, dir_name)
  local module = unl_finder.module.find_module(dir_name)
  if module then
    unl_events.publish(unl_event_types.ON_AFTER_MODIFY_DIRECTORY,
      {
        status = "success",
        type=type_name,
        module=module
      })
  end
end

M.add_directory = function(state, callback)
  cc.add_directory(state, function(destination)
    if callback then
      callback(destination)
    end
    modify_directory("add", destination)
  end)
end
M.add = function(state)
  local log = require("neo-tree.log")
  local node = state.tree:get_node()
  if not node then
    log.info("uproject: No node selected.")
    return
  end
  local target_dir = nil
  if node.type == "directory" then
    target_dir = node.id
  else
    local parent_id = node:get_parent_id()
    if parent_id then
      local parent_node = state.tree:get_node(parent_id)
      if parent_node then target_dir = parent_node.id end
    end
  end
  if not target_dir then
    log.warn("Could not determine target directory for: " .. node.name)
    return
  end
  local unl_api_ok, unl_api = pcall(require, "UNL.api")
  if not unl_api_ok then
    return log.warn("UNL.api module could not be loaded.")
  end
  unl_api.provider.request("ucm.class.new", {
    target_dir = target_dir,
    logger_name = "neo-tree-uproject",
  })
end
M.refresh = refresh
M.delete = function(state)
  local log = require("neo-tree.log")
  local node = state.tree:get_node()
  if not node then
    log.info("uproject: No node selected to delete.")
    return
  end
  if node.type == "file" then
    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if not unl_api_ok then
      return log.warn("UNL.api module could not be loaded.")
    end
    unl_api.provider.request("ucm.class.delete", {
      file_path = node.id,
      logger_name = "neo-tree-uproject",
    })
  elseif node.type == "directory" then
    log.debug("Node is a directory, dispatching to common neo-tree delete command")
    local delete_target = node.id
    cc.delete(state, function(destination)
      if callback then
        callback(destination)
      end
      modify_directory("delete", delete_target)
    end)
  else
    log.debug("Delete command ignored for node type: " .. node.type)
  end
end
M.delete_visual = function(state, selected_nodes, callback)
  local delete_target = selected_nodes.id
  cc.delete_visual(state, selected_nodes, function(destination)
    if callback then
      callback(destination)
    end
    modify_directory("delete", delete_target)
  end)
end
M.rename = function(state, callback)
  local log = require("neo-tree.log")
  local node = state.tree:get_node()
  if not node then return end
  if node.type == "file" then
    log.debug("Node is a file, dispatching to UCM provider for rename")
    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if not unl_api_ok then
      return log.warn("UNL.api module could not be loaded.")
    end
    unl_api.provider.request("ucm.class.rename", {
      file_path = node.id,
      logger_name = "neo-tree-uproject",
    })
  elseif node.type == "directory" then
    log.debug("Node is a directory, dispatching to common neo-tree rename command")
    local neo_tree_path = node.id
    neo_tree_path = neo_tree_path:gsub("/", "\\")
    fs_actions.rename_node(neo_tree_path, function(path, destination)
        if callback then
          callback(path, destination)
        end
        modify_directory("rename", path)
    end)
  end
end
M.move = function(state, callback)
  local log = require("neo-tree.log")
  local node = state.tree:get_node()
  if not node then return end
  if node.type == "file" then
    log.debug("Node is a file, dispatching to UCM provider for move")
    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if not unl_api_ok then
      return log.warn("UNL.api module could not be loaded.")
    end
    unl_api.provider.request("ucm.class.move", {
      file_path = node.id,
      logger_name = "neo-tree-uproject",
    })
  elseif node.type == "directory" then
    log.debug("Node is a directory, using standard neo-tree move (cut/paste)")
    local neo_tree_path = node.id
    neo_tree_path = neo_tree_path:gsub("/", "\\")
    local function move_callback(source, dest)
      if callback then
        callback(source, dest)
      end
      modify_directory("move", dest)
    end
    fs_actions.move_node(neo_tree_path, nil, move_callback, neo_tree_path)
  end
end


local function uproject_toggle_directory(state, node)
  if not node then return end

  local uep_type = (node.extra and node.extra.uep_type) or "fs"
  
  -- 1. :UEP tree のノード ("category" または "fs") の場合
  --    (これがあなたの「完璧に動作している」カスタムロジック)
  if uep_type == "category" or uep_type == "fs" then
    if node.type == "directory" and node.loaded == false then
      log.debug("uproject (:UEP tree): Node '%s' is not loaded. Calling load_children.", node.name)
      local Source_Module = require("neo-tree.sources.uproject")
      if not Source_Module then
        log.error("uproject: Source_Module is nil! Require failed.")
        return
      end
      
      local children_data = Source_Module.load_children(state, node)
      local new_level = (node.level or 0) + 1
      
      if children_data and #children_data > 0 then
        local children_nodes = {}
        local num_children = #children_data
        for i, child_table in ipairs(children_data) do
          child_table.level = new_level
          child_table.is_last_child = (i == num_children)
          table.insert(children_nodes, 
            state.tree.Node(child_table, child_table.children)
          )
        end
        state.tree:set_nodes(children_nodes, node:get_id())
        node.loaded = true
      else
        log.warn("uproject: load_children returned no children for '%s'", node.name)
        node.loaded = true
      end
    end
  end

  -- 2. 常に neo-tree 標準の cc.toggle_node を呼び出す
  --    (:UEP module_tree のノード ("module_root") は 'loaded = true' で
  --    子も NuiTree.Node なので、cc.toggle_node が正しく処理できる)
  if utils.is_expandable(node) and node:has_children() then
    if node:is_expanded() then
      node:collapse()
    else
      node:expand()
    end
    renderer.redraw(state)
  elseif node.type == "directory" and node.loaded == true and not node:has_children() then
    if node:is_expanded() then
      node:collapse()
    else
      node:expand()
    end
    renderer.redraw(state)
  end
end

M.toggle_node = function(state)
  uproject_toggle_directory(state, state.tree:get_node())
end

M.open = function(state)
  local node = state.tree:get_node()
  if not node then return end

  if node.type == "directory" then
    uproject_toggle_directory(state, node)
  else
    cc.open(state) 
  end
end

cc._add_common_commands(M)

return M
