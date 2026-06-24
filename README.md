# ModelViewer

D言語と OpenGL 3.3 で動作する **Geo XML** 3D ビューアです。

## 機能

- 独自フォーマット `geo.xml`（`<Geo>` ルート）の読み込みと描画
- Arcball カメラ操作
  - 左ドラッグ: 回転
  - 右ドラッグ: パン
  - ホイール: ズーム
  - Shift + ドラッグ: 高速パン
- DlangUI パネル（ファイルパス入力、Load、モデル情報、操作説明）
- `R`: カメラリセット、`Esc`: 終了

## 依存ライブラリ

| 用途 | パッケージ |
|------|-----------|
| GUI | dlangui |
| OpenGL | bindbc-opengl（dlangui 経由） |
| ベクトル | gl3n |
| XML | dxml |

## ビルド要件（Linux）

- LDC 1.42+ と dub
- `libsdl2-dev`, `libfreetype6-dev`, `libfontconfig1-dev`
- `libgl1-mesa-dev`

## セットアップとビルド

```bash
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
  app.d           メインアプリ（DlangUI + OpenGL）
  geo_parser.d    Geo XML パーサ（dxml）
  geo_model.d     モデルデータ
  mesh.d          VAO/VBO 描画
  shader.d        シェーダ
  camera.d        Arcball カメラ
data/
  cube.geo.xml    サンプルモデル
```

## 備考

- GUI には [DlangUI](https://github.com/buggins/dlangui) を使用しています。Linux では SDL2 バックエンドで動作します。
- 3D ビューポートは DlangUI の `OpenGLDrawable` で描画し、コントロールパネルは通常の DlangUI ウィジェットで構成しています。
