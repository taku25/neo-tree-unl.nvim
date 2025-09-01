
local cc = require("neo-tree.sources.common.commands")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")

---@class neotree.sources.Uproject.Commands : neotree.sources.Common.Commands
local M = {}

-- このソースの init.lua を保持するための変数
-- neo-tree が setup 時に M.init を呼び出してくれる
local uproject_source = nil
function M.init(source_module)
  uproject_source = source_module
end




---
-- ユーザーのキー操作に対応する、展開/折りたたみのメインロジック
-- @param state neotree.State
-- @param node NuiTree.Node 対象ノード
local function toggle_directory(state, node)
  if not node then return end

  state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}
  
  -- 1. まだ読み込んでいないノードの場合 (遅延読み込み)
  if node.loaded == false then
    if not uproject_source then
      require("neo-tree.log").warn("uproject source module is not initialized in commands.lua")
      return
    end
    -- init.lua から完全なノードデータを取得
    local full_node_data = uproject_source.get_full_node_data(node.id)
    if full_node_data and full_node_data.children then
      -- 描画用に子ノードのリストを準備
      local children_for_display = {}
      for _, child_data in ipairs(full_node_data.children) do
        local child_copy = vim.deepcopy(child_data)
        if child_copy.children and #child_copy.children > 0 then
          child_copy.children = {}
          child_copy.loaded = false
        else
          child_copy.loaded = true
        end
        table.insert(children_for_display, child_copy)
      end
      
      renderer.show_nodes(children_for_display, state, node:get_id())
      node.loaded = true
      if not node:is_expanded() then node:expand() end
      
      -- 展開したことを記録
      state.explicitly_opened_nodes[node:get_id()] = true
      renderer.redraw(state) -- 子を追加した後に再描画
    end
  -- 2. 既に読み込み済みで、子を持つノードの場合
  elseif node:has_children() then
    if node:is_expanded() then
      node:collapse()
      state.explicitly_opened_nodes[node:get_id()] = false
    else
      node:expand()
      state.explicitly_opened_nodes[node:get_id()] = true
    end
    -- UIの状態変更を反映するために再描画
    renderer.redraw(state)
  end
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

-- 'd' キーに割り当てられたカスタム削除コマンド
-- 選択されたノードのタイプに応じて振る舞いを変更する
M.delete = function(state)
  local log = require("neo-tree.log")
  local node = state.tree:get_node()

  if not node then
    log.info("uproject: No node selected to delete.")
    return
  end
  
  -- 1. 選択されたノードが「ファイル」の場合
  if node.type == "file" then
    log.debug("Node is a file, dispatching to UCM.api.delete_class")
    local ucm_ok, ucm_api = pcall(require, "UCM.api")
    if ucm_ok then
      -- UCM APIは .h と .cpp をペアで賢く削除してくれる
      ucm_api.delete_class({ file_path = node.id })
    else
      log.warn("UCM.api module could not be loaded.")
    end

  -- 2. 選択されたノードが「ディレクトリ」の場合
  elseif node.type == "directory" then
    log.debug("Node is a directory, dispatching to common neo-tree delete command")
    -- neo-treeの標準の削除コマンドを呼び出す
    cc.delete(state)

  -- 3. その他の場合 (メッセージノードなど)
  else
    log.debug("Delete command ignored for node type: " .. node.type)
    -- 何もしない
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

    -- UCMの対話的UIを再利用する
    ucm_api.move_class({ file_path = node.id })

  elseif node.type == "directory" then
    log.debug("Node is a directory, using standard neo-tree move (cut/paste)")
    -- 標準の'cut'コマンドを呼び出す
    cc.cut(state)
    vim.notify("Directory cut. Navigate to destination and press 'p' to paste.", vim.log.levels.INFO)
  end
end
-- neo-tree の標準コマンドをカスタムロジックでオーバーライド
M.toggle_node = function(state)
  toggle_directory(state, state.tree:get_node())
end

M.open = function(state)
  cc.open(state, function(node) toggle_directory(state, node) end)
end

-- 共通コマンドを継承
cc._add_common_commands(M)

return M

