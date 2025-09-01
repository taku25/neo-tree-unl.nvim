return {
  logger = {
    name = "NeoTreeUProject",
    cache = { dirname = "URPOJECT_UNL" },
    logging = { level = "info", file = { enable = true, filename = "neo-tree-uproject.log" } },
  },
  renderers = {
    directory = { { "indent" }, { "icon" }, { "container", content = { { "name" } } } },
    file = { { "indent" }, { "icon" }, { "name" } },
    message = { { "indent", with_markers = false }, { "name", highlight = "NeoTreeMessage" } },
  },
  
  window = {
    mappings = {
      -- ★★★ ここからが修正箇所 ★★★

      -- 'a' キーを、我々のカスタムコマンド 'publish_node_info' に割り当てる
      ["a"] = "publish_node_info",
      
      -- 'A' キー (デフォルトでは 'add_directory') を明示的に無効化する
      ["A"] = "noop",

      -- 【念のため】'add' という名前のコマンド自体を無効化するマッピングを追加
      -- これにより、もし何らかの理由で 'a' のマッピングが neo-tree のデフォルト
      -- ({ "add", ... }) に上書きされそうになっても、その 'add' が何もしないようにする
      ["add"] = "noop",
      ["add_directory"] = "noop",
      
      -- ★★★ 修正ここまで ★★★
    }
  }
}
