# ModelViewer

D言語と OpenGL 3.3 で動作する **Geo XML** 3D ビューアです。

## 機能

- 独自フォーマット `geo.xml`（`<Geo>` ルート）の読み込みと描画
- Arcball カメラ操作
  - 左ドラッグ: 回転
  - 右ドラッグ: パン
  - ホイール: ズーム
  - Shift + ドラッグ: 高速パン
- ImGui パネル（ファイルパス入力、Load、モデル情報、操作説明）
- `R`: カメラリセット、`Esc`: 終了

## 依存ライブラリ

| 用途 | パッケージ |
|------|-----------|
| GUI | bindbc-imgui |
| ウィンドウ / 入力 | bindbc-glfw |
| OpenGL | bindbc-opengl |
| ベクトル | gl3n |
| XML | dxml |

## ビルド要件（Linux）

- LDC 1.42+ と dub
- `g++-13`, `libstdc++-13-dev`
- `libgl1-mesa-dev`, GLFW 3
- `libsdl2-dev`, `libfreetype6-dev`（bindbc-imgui 静的ビルド用）

## セットアップとビルド

```bash
# bindbc-imgui / cimgui の準備（初回のみ）
bash scripts/setup-bindbc-imgui.sh

# アプリケーション
dub build --config=application

# パーサのみのテスト
dub run --config=parser-test
```

## 実行

```bash
dub run --config=application -- data/cube.geo.xml
# または
./bin/modelviewer data/cube.geo.xml
```

引数を省略すると `data/cube.geo.xml` を読み込みます。

## プロジェクト構成

```
source/
  app.d           メインアプリ（GLFW + OpenGL + ImGui）
  geo_parser.d    Geo XML パーサ（dxml）
  geo_model.d     モデルデータ
  mesh.d          VAO/VBO 描画
  shader.d        シェーダ
  camera.d        Arcball カメラ
  imgui_input.d   GLFW → ImGui 入力ブリッジ
  imgui_ogl.d     ImGui OpenGL レンダラ
  imgui_helper.*  ImGuiIO アクセス用 C ヘルパ
data/
  cube.geo.xml    サンプルモデル
```

## 備考

- `bindbc-imgui` 0.7.0 は **静的リンク**（`static_dynamicCRT`）を使用しています。同梱の D バインディングと cimgui 1.79 の `ImGuiIO` レイアウトが一致しないため、ImGuiIO へのアクセスは `source/c/imgui_helper.cpp` 経由で行います。
- GLFW 用の `ImGui_ImplGlfw` は cimgui に含まれないため、マウス入力は手動でブリッジしています。
