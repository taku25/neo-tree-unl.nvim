-- lua/neo-tree/sources/uproject/commands.lua (遅延読み込み対応版)

local cc = require("neo-tree.sources.common.commands")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")

---@class neotree.sources.Uproject.Commands : neotree.sources.Common.Commands
local M = {}

-- uproject_source の初期化は不要になったため、init関数を削除または空にしてもOKです
function M.init(source_module)
  -- このモジュールはもはやinit.luaの関数を直接呼び出す必要がありません
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
          -- この子ノードがさらに子階層を持っているかチェック
          if child_node.extra and child_node.extra.hierarchy and #child_node.extra.hierarchy > 0 then
            child_node.children = {}
            child_node.loaded = false -- neo-treeに子がいることを示す
          else
            -- 子階層を持たない空のディレクトリ
            child_node.loaded = true
          end
        else
          child_node.loaded = true
        end
        table.insert(children_for_display, child_node)
      end
      
      renderer.show_nodes(children_for_display, state, node:get_id())
    end
    
    -- 自身のノードを「読み込み済み」に更新
    node.extra.is_loaded = true
    
    -- neo-tree の内部状態も更新しておく
    node.loaded = true 

    if not node:is_expanded() then node:expand() end
    state.explicitly_opened_nodes[node:get_id()] = true
    renderer.redraw(state)

  -- 2. 既に読み込み済みで、子を持つノードの場合
  elseif node:has_children() then
    if node:is_expanded() then
      node:collapse()
      state.explicitly_opened_nodes[node:get_id()] = false
    else
      node:expand()
      state.explicitly_opened_nodes[node:get_id()] = true
    end
    renderer.redraw(state)
  end
  -- ▲▲▲ 変更ここまで ▲▲▲
end


M.refresh = function(state)
  manager.refresh(state.name)
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
  
  local ucm_ok, ucm_api  = pcall(require, "UCM.api")
  if ucm_ok then
    ucm_api.new_class({ target_dir = target_dir })
  else
    log.warn("UCM.api module could not be loaded.")
  end
end

-- (以降の delete, rename, move などのコマンドは変更の必要なし)
M.delete = function(state)
  local log = require("neo-tree.log")
  local node = state.tree:get_node()

  if not node then
    log.info("uproject: No node selected to delete.")
    return
  end
  
  if node.type == "file" then
    log.debug("Node is a file, dispatching to UCM.api.delete_class")
    local ucm_ok, ucm_api = pcall(require, "UCM.api")
    if ucm_ok then
      ucm_api.delete_class({ file_path = node.id })
    else
      log.warn("UCM.api module could not be loaded.")
    end

  elseif node.type == "directory" then
    log.debug("Node is a directory, dispatching to common neo-tree delete command")
    cc.delete(state)

  else
    log.debug("Delete command ignored for node type: " .. node.type)
  end
end

M.rename = function(state)
  local log = require("neo-tree.log")
  local node = state.tree:get_node()
  if not node then return end

  if node.type == "file" then
    log.debug("Node is a file, dispatching to UCM.api.rename_class")
    local ucm_ok, ucm_api = pcall(require, "UCM.api")
    if not ucm_ok then
      return log.warn("UCM.api module could not be loaded.")
    end
    
    local old_name = vim.fn.fnamemodify(node.id, ":t:r")
    vim.ui.input({ prompt = "Enter New Class Name:", default = old_name }, function(new_name)
      if not new_name or new_name == "" or new_name == old_name then
        return log.info("Rename canceled.")
      end
      ucm_api.rename_class({ file_path = node.id, new_class_name = new_name })
    end)

  elseif node.type == "directory" then
    log.debug("Node is a directory, dispatching to common neo-tree rename command")
    cc.rename(state)
  end
end

M.move = function(state)
  local log = require("neo-tree.log")
  local node = state.tree:get_node()
  if not node then return end

  if node.type == "file" then
    log.debug("Node is a file, dispatching to UCM.api.move_class")
    local ucm_ok, ucm_api = pcall(require, "UCM.api")
    if not ucm_ok then return log.warn("UCM.api module could not be loaded.") end

    ucm_api.move_class({ file_path = node.id })

  elseif node.type == "directory" then
    log.debug("Node is a directory, using standard neo-tree move (cut/paste)")
    cc.cut(state)
    vim.notify("Directory cut. Navigate to destination and press 'p' to paste.", vim.log.levels.INFO)
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
