
# neo-tree-unl.nvim

# Unreal Engine Logical Tree 💓 Neovim

<table>
  <tr>
   <td><div align=center><img width="100%" alt="neo-tree-unl" src="https://raw.githubusercontent.com/taku25/neo-tree-unl.nvim/images/assets/main-image.png" /></div></td>
  </tr>
</table>

`neo-tree-unl.nvim`は、[UEP.nvim](https://github.com/taku25/UEP.nvim) によって解析されたUnreal Engineのプロジェクト構造を、[neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) 上にIDEのソリューションエクスプローラーのように表示するための、neo-tree.vnim のカスタムSourceです。

ファイルシステムの物理的な階層ではなく、「Game」「Plugins」「Engine」といった論理的なカテゴリや、モジュール単位でプロジェクトを把握することを可能にします。

共有ライブラリとして [UNL.nvim](https://github.com/taku25/UNL.nvim) に依存しています。

その他、Unreal Engine開発を強化するためのプラグイン群 ([`UEP.nvim`](https://github.com/taku25/UEP.nvim), [`UCM.nvim`](https://github.com/taku25/UCM.nvim)) 
 ([`ULG.nvim`](https://github.com/taku25/ULG.nvim), [`UBT.nvim`](https://github.com/taku25/UBT.nvim)) があります。


[English](README.md) | [日本語 (Japanese)](README_ja.md)

-----

## ✨ 機能 (Features)

  * **IDEライクな論理ビュー**:
      * ファイルシステムではなく、プロジェクトの論理的な構造（Game, Plugins, Engine, Module）をツリー表示します。

  * **UEPプラグインコマンド**
      * UEPのキャッシュデータを表示するためにコマンドはすべてUEPから発行します
    * **シームレスなビュー切り替え**:
      * `:UEP tree`: プロジェクト全体の構造を俯瞰できます。
      * `:UEP module_tree`: 特定のモジュールのみにフォーカスした、集中モードに切り替えられます。
    * **疎結合なアーキテクチャ**:
      * `UEP.nvim` から完全に独立したUIレイヤーとして機能します。
      * `UNL.nvim` が提供するグローバルなイベントバスを通じて `UEP.nvim` と通信するため、互いに直接依存しません。

## 🔧 必要要件 (Requirements)

  * Neovim v0.8+
  * [**UNL.nvim**](https://github.com/taku25/UNL.nvim) (**必須**)
  * [**UEP.nvim**](https://github.com/taku25/UEP.nvim) (**必須ですが 依存関係はありません**)
  * [**neo-tree.nvim**](https://github.com/nvim-neo-tree/neo-tree.nvim) (**必須**)

## 🚀 インストール (Installation)

お好みのプラグインマネージャーでインストールしてください。`UEP.nvim` や `neo-tree.nvim` と一緒にインストールする必要があります。

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  -- UNLエコシステムの基盤
  { "taku25/UNL.nvim", lazy = false, priority = 1000 },

  { "taku25/UEP.nvim", dependencies = "taku25/UNL.nvim" },

  -- UIコンポーネント (このプラグイン)
  { 
    "taku25/neo-tree-unl.nvim",
    dependencies = {
      "taku25/UNL.nvim",
    }
  },

  -- neo-tree本体の設定
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- optional, for icons
      "MunifTanjim/nui.nvim",
      "taku25/neo-tree-unl.nvim", -- 必須
    },
    opts = {
      sources = {
        "filesystem",
        -- ★★★ このソースを有効化 ★★★
        "neo-tree.sources.uproject",
      },
      source_selector = {
        winbar = true,
        statusline = false,
        sources = {
          -- カスタムソース追加
          { source = "filesystem", display_name = "filesysetm" },
          { source = "uproject", display_name = "uproject" },
        },
      },
      -- ... その他のneo-tree設定
    }
  }
}
```

## ⚙️ 設定 (Configuration)

このプラグインは、追加の設定を必要としません。インストールし、`neo-tree.nvim` の `sources` に `"neo-tree-unl"` を追加するだけで有効になります。

## ⚡ 使い方 (Usage)

このソースは、`UEP.nvim` が提供するコマンドによって駆動されます。
詳しいUEP.nvimのコマンドは [UEP.nvim](https://github.com/taku25/UEP.nvim)を参照してください

```viml
" プロジェクト全体の論理ツリーを表示します。
:UEP tree [--all-deps](オプション:浅い参照 or 深い参照)

" 特定のモジュールの論理ツリーを表示します。
:UEP module_tree [ModuleName](オプション　引数なしの場合はPickerが起動します)
```

## 📜 ライセンス (License)

MIT License

Copyright (c) 2025 taku25

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
