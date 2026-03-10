# セッション引き継ぎ (2026-03-10)

## 完了したこと

### libghostty ビルド環境の構築
- Ghostty v1.2.1 をクローンし、macOS で直接 `libghostty.a` をビルドできるようにした
- **2つのパッチ** を `patches/libghostty-macos-static.patch` に保存:
  1. `build.zig` の Darwin ガードを外して `.a` を直接インストール可能に
  2. xcframework 初期化を `emit_xcframework` フラグでガード (iOS SDK 不要に)
- `build.zig.zon` の iterm2_themes URL を更新 (旧リリースが404)

### Nix 環境の問題解決
- **DEVELOPER_DIR 問題**: Nix stdenv が `DEVELOPER_DIR` を自前の apple-sdk に上書きし、`/usr/bin/xcrun` が `metal` を見つけられなくなる → `shellHook` で Xcode パスに再設定
- **Swift SDK 不一致**: Nix の apple-sdk (Swift 5.10) とシステム swiftc (6.2.1) が非互換 → `/usr/bin/xcrun -sdk macosx swiftc` を使用
- **Metal コンパイラ**: `metal` は Apple プロプライエタリで nixpkgs に存在しない。Xcode + MetalToolchain が必要 (`xcodebuild -downloadComponent MetalToolchain`)

### SwiftUI アプリの PoC
- サイドバー (NavigationSplitView) + 再帰的分割パネル
- libghostty surface を NSViewRepresentable で埋め込み
- アプリは起動し、ターミナルが動作する状態まで確認済み

## ビルド方法
```bash
# 前提: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c make setup  # 初回のみ
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer nix develop -c make run
```

## 決定済みの方針
- **GUI**: SwiftUI (macOS)。将来 Linux 対応時は GTK フロントエンドを別途追加
- **コアロジック**: SessionStore, PanelNode 等を GUI 非依存に切り出す設計にする
- **タスク管理**: bd (beads) をセットアップ済み。次セッションで理想形を議論しタスク登録
- **クロスプラットフォーム**: libghostty 自体がプラットフォーム別フロントエンド前提なので、GUI フレームワーク統一では解決しない。プラットフォーム別に薄い GUI 層を書く戦略

## 次セッションの TODO
1. 理想形 (欲しい機能・UX) を議論して固める
2. bd にエピック/タスクとして登録
3. 自走で実装を進める
