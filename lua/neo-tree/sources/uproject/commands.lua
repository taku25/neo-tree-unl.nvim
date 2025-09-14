-- lua/neo-tree/sources/uproject/commands.lua (遅延読み込み対応版)
local fs_actions = require("neo-tree.sources.filesystem.lib.fs_actions")
local cc = require("neo-tree.sources.common.commands")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local unl_finder = require("UNL.finder")
local utils = require("neo-tree.utils")
local unl_events = require("UNL.event.events")
local unl_event_types =require("UNL.event.types")

---@class neotree.sources.Uproject.Commands : neotree.sources.Common.Commands
local M = {}

-- uproject_source の初期化は不要になったため、init関数を削除または空にしてもOKです
function M.init(source_module)
  -- このモジュールはもはやinit.luaの関数を直接呼び出す必要がありません
end

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

---
-- ユーザーのキー操作に対応する、展開/折りたたみのメインロジック (遅延読み込み対応)
-- @param state neotree.State
-- @param node NuiTree.Node 対象ノード
local function toggle_directory(state, node)
  if not node then return end

  state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}
  
  -- ▼▼▼ 変更点: 判定条件を node.extra.is_loaded に変更 ▼▼▼

  -- 1. まだ読み込んでいないノードの場合 (遅延読み込みの実行)
  -- node.loaded の代わりに、自分たちで定義した extra.is_loaded フラグを見る
  if node.extra and not node.extra.is_loaded then
    
    local children_data = node.extra.hierarchy
    if children_data and #children_data > 0 then
      
      local children_for_display = {}
      for _, child_data in ipairs(children_data) do
        local child_node = vim.deepcopy(child_data)
        
        if child_node.type == "directory" then
          if child_node.extra and child_node.extra.hierarchy and #child_node.extra.hierarchy > 0 then
            child_node.children = {}
            child_node.loaded = false -- neo-treeに子がいることを示す
          else
            child_node.loaded = true
          end
        else
          child_node.loaded = true
        end
        table.insert(children_for_display, child_node)
      end
      
      renderer.show_nodes(children_for_display, state, node:get_id())
    end
    node.extra.is_loaded = true
    node.loaded = true 
  else

    if node:has_children() then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
      end
      renderer.redraw(state)
    end
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
---
-- 'a' キーに割り当てられたカスタムコマンド
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

  -- プロバイダーにリクエストを投げる (Fire and Forget)
  -- on_completeコールバックは不要。UIの更新はイベント駆動で行われる。
  unl_api.provider.request("ucm.class.new", {
    target_dir = target_dir,
    logger_name = "neo-tree-uproject", -- ログを一元管理するためにロガー名を渡す
  })
end


M.refresh = refresh
-- (以降の delete, rename, move などのコマンドは変更の必要なし)
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
      logger_name = "neo-tree-uproject", -- ログを一元管理するためにロガー名を渡す
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
    -- ディレクトリのリネームはneo-treeの標準機能を使う
   
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

    -- UCMのプロバイダーを呼び出す。
    -- UCM側が移動先の選択UIを表示し、ファイルの移動とイベント発行を行う。
    -- on_completeは不要。
    unl_api.provider.request("ucm.class.move", {
      file_path = node.id,
      logger_name = "neo-tree-uproject",
    })

  elseif node.type == "directory" then
    log.debug("Node is a directory, using standard neo-tree move (cut/paste)")
    -- ディレクトリの移動はneo-treeの標準機能を使う
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

M.toggle_node = function(state)
  toggle_directory(state, state.tree:get_node())
end

M.open = function(state)
  cc.open(state, function(node) toggle_directory(state, node) end)
end

cc._add_common_commands(M)

return M
