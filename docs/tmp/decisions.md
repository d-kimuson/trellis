# Implementation Decisions & Notes

Date: 2026-03-11 (overnight session)

## Completed

### 1. SplitContainer drag @State local ratio (HIGH)
- `localRatio: Double?` を追加、ドラッグ中はローカル更新のみ、onEnded で Store にコミット
- 全ペインのフレーム毎再評価を解消

### 2. Git branch detection cancellation (MED)
- `waitUntilExit()` → `terminationHandler` 方式に変更
- `gitProcess` プロパティで前回プロセスをキャンセル可能に
- `close()`/`deinit` でもクリーンアップ

### 3. nextTerminalNumber monotonic counter (LOW)
- `allSessions.count + 1` → `nextTerminalCounter` 単調増加カウンタ

### 4. closeTerminalSession workspace-switching hack 解消 (MED)
- `closeTab(in:at:workspaceIndex:)` private オーバーロード追加
- `closeTerminalSession` から直接呼び出し、activeWorkspaceIndex の一時切替を廃止

### 5. 起動時ターミナル不要 (User request)
- 空の Area で起動するよう変更

### 6. Cmd+Shift+/- フォントサイズ変更 (User request)
- `GhosttyFontSizeChange` enum + `ghostty_surface_binding_action` で実装
- View メニューに Cmd+Shift+=, Cmd+Shift+-, Cmd+0 を追加
- `performKeyEquivalent` の menuKeys に =/-/0 を追加

### 7. 非ターミナルタブの条件付きレンダリング (LOW)
- Terminal: opacity パターン維持、Browser/FileTree: `if isActive` で条件付き描画

### 8. Unmanaged ポインタ安全性 (MED)
- `surfaceSessions: [UnsafeRawPointer: TerminalSession]` lookup table を導入
- C コールバックから Unmanaged で直接 session を取得する代わりに lookup で検証
- surface 作成時に register、destroy 時に unregister

## Deferred / Needs Discussion

### @Observable migration (HIGH priority but HIGH complexity)
- macOS 14+ なので技術的には可能
- WorkspaceStore を `@Observable` に移行すると:
  - `@Published` → 通常プロパティ
  - `@ObservedObject` → `@Environment` or `@Bindable`
  - 全 View のプロパティラッパーを書き換える必要がある
  - テストで `@Published` sink してる箇所も影響
- **判断**: 大規模リファクタの割に動作が壊れるリスクが高い。起きてるときに相談してからが良い

### URL click suggest (User request, HIGH complexity)
- ghostty が OSC 8 (hyperlinks) をサポートしているか確認が必要
- VSCode 風の「Open URL」suggest は ghostty の action callback に依存
- GHOSTTY_ACTION_OPEN_URL のようなアクションがあるか、またはマウスイベントから URL 検出が必要
- **判断**: ghostty の API 調査が先。スキップ

### 60fps tick timer optimization (LOW)
- ghostty の wakeup_cb は on-demand ticking 用だが、現状 timer も併用
- timer を止めると描画が止まるリスク
- **判断**: バッテリー最適化は後回し。wakeup_cb のみで動作するか実機テストが必要

### BrowserState.pendingAction one-shot pattern (MED)
- SwiftUI の updateNSView タイミングに依存する脆弱なパターン
- Combine publisher 方式がベター
- **判断**: Browser panel 自体がまだ実験的。後回し
