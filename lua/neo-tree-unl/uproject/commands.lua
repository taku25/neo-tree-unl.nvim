-- C:\Users\taku3\Documents\git\neo-tree-unl.nvim\lua\neo-tree-unl\uproject\commands.lua

local cc = require("neo-tree.sources.common.commands")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local utils = require("neo-tree.utils")

---@class neotree.sources.Uproject.Commands : neotree.sources.Common.Commands
local M = {}

-- init.lua から渡されるモジュールテーブルを保持するための変数
local uproject_source = nil

--- init.lua から呼び出されるセットアップ関数
function M.setup(source_module)
  uproject_source = source_module
end

-- 展開/折りたたみのカスタムロジック
local function toggle_directory(state, node)
  if not node then
    node = state.tree:get_node()
  end
  if not node then return end
  
  if not uproject_source then
    require("neo-tree.log").warn("uproject source module is not initialized in commands.lua")
    return
  end

  -- 展開状態を保存するためのテーブルを初期化
  state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}

  -- ノードが「未読み込み」の場合、子ノードを読み込んで表示する
  if node.loaded == false then
    -- uproject_source 経由で、init.luaの関数を呼び出す
    local full_node_data = uproject_source.get_full_node_data(node.id)

    if full_node_data and full_node_data.children then
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
      node.loaded = true -- 読み込み済みに変更
      if not node:is_expanded() then
        node:expand() -- ノードを展開状態にする
      end
      -- ユーザーが展開したことを記録
      state.explicitly_opened_nodes[node:get_id()] = true
      renderer.redraw(state)
    end
  elseif node:has_children() then
    -- 既に読み込み済みの場合は、単純に展開/折りたたみを切り替える
    if node:is_expanded() then
      node:collapse()
      -- ユーザーが閉じたことを記録
      state.explicitly_opened_nodes[node:get_id()] = false
    else
      node:expand()
      -- ユーザーが展開したことを記録
      state.explicitly_opened_nodes[node:get_id()] = true
    end
    renderer.redraw(state)
  end
end

-- toggle_node コマンドをオーバーライド
M.toggle_node = function(state)
  toggle_directory(state, state.tree:get_node())
end

-- open コマンドも、ディレクトリの場合はカスタムの toggle_directory を使うようにする
M.open = function(state)
  -- cc.open はファイルの場合はファイルを開き、ディレクトリの場合は第二引数の関数を実行する
  cc.open(state, function(node) toggle_directory(state, node) end)
end

-- refresh コマンドを定義
M.refresh = function(state)
  if not uproject_source then
    require("neo-tree.log").warn("uproject source module is not initialized for refresh")
    return
  end
  manager.refresh(uproject_source.name)
end

-- 他の必要なコマンドを common_components から継承
cc._add_common_commands(M)

return M
