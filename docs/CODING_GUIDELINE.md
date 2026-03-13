# Trellis Coding Guideline

> アーキテクトによる方針。AI エージェントを含む全実装担当者が従うこと。

---

## 1. アーキテクチャ原則

### レイヤー構成

```
┌──────────────────────────────────────────────────────────┐
│ View layer   SwiftUI Views / NSViewRepresentable         │
│              ContentView, SidebarView, PanelView, ...    │
├──────────────────────────────────────────────────────────┤
│ Store layer  @Observable @MainActor                      │
│              WorkspaceStore, NotificationStore           │
├──────────────────────────────────────────────────────────┤
│ Model layer  struct / enum (value types)                 │
│              Workspace, Area, Tab, LayoutNode            │
│              TerminalSession, FileTreeState, BrowserState│
├──────────────────────────────────────────────────────────┤
│ Infra layer  libghostty / AppKit / FSEvent               │
│              GhosttyAppWrapper, GhosttyNSView            │
├──────────────────────────────────────────────────────────┤
│ Persistence  SnapshotStore, BookmarkStore, AppSettings   │
└──────────────────────────────────────────────────────────┘
```

### 依存方向のルール

- **上位レイヤーは下位レイヤーに依存してよい。逆は禁止。**
- Model 層は Infra・Persistence を直接呼ばない。
  - ❌ `FileTreeState.changeRoot` から `BookmarkStore.save` を直接呼ぶ
  - ✅ コールバック `onRootChanged: ((URL) -> Void)?` を通じて Store 側で保存する
- Model 層は GUI フレームワーク（AppKit/SwiftUI）をインポートしない。
  - ❌ `import AppKit` in `Workspace.swift`
  - ✅ `import Foundation` のみ

### GUI 独立性（将来の Linux/GTK 移植）

`Sources/Trellis/Models/` 配下のファイルは macOS 固有 API を直接使わない。
プラットフォーム依存のフィールドはプロトコルで抽象化する。

```swift
// ✅ プロトコルで抽象化
protocol TerminalSurfaceView { var nsView: NSView { get } }

// ❌ Model に platform-specific type を持たせる
var surface: UnsafeMutableRawPointer?  // ghostty_surface_t
```

---

## 2. 状態管理

### @Observable の使い方

- **Store（WorkspaceStore 等）**: `@Observable @MainActor final class`
- **クラスを要するモデル（TerminalSession, FileTreeState 等）**: `@Observable final class`
- **純粋データ（Workspace, Area, Tab, LayoutNode 等）**: `struct` / `enum`

```swift
// ✅ 正しいパターン
@Observable
public final class TerminalSession: Identifiable { ... }

// ❌ ObservableObject は使わない（@Observable への統一が完了済み）
class Foo: ObservableObject { @Published var bar = 0 }
```

### @ObservationIgnored の使いどころ

SwiftUI の細粒度トラッキングを活かすため、「変更しても再レンダリングが不要なプロパティ」に付ける。

- ✅ C API ポインタ（`surface`, `surfaceView`）
- ✅ クローズャー（`onFocused`, `onProcessExited`）
- ✅ バックグラウンドタスク参照（`gitProcess`, `reloadTask`）
- ❌ UI に表示されるデータ（`title`, `pwd`, `gitBranch`）

### 状態イベント伝達パターン

NSView → SwiftUI View への通知に `pendingAction?: ActionType` パターンを使う場合、**同一フレームで複数 dispatch すると後者が前者を上書きする**。

新規実装では `actions: [ActionType]` キューまたは `AsyncStream` を優先すること。

```swift
// ❌ 単一 pending フィールド — 複数イベントを失う可能性がある
var pendingAction: MyAction?

// ✅ キュー — 複数イベントを安全に処理できる
var pendingActions: [MyAction] = []

// ✅ AsyncStream — リアクティブに処理できる
var actionStream: AsyncStream<MyAction>
```

既存の `pendingUIAction` は単発アクション専用として維持し、複数 dispatch が必要な箇所ではキュー化すること。

---

## 3. 非同期処理

### @MainActor コンテキスト内での非同期パターン

```swift
// ✅ @MainActor コンテキスト内では Task { @MainActor in } を使う
@MainActor
func updateUI() {
    Task { @MainActor in
        self.title = await fetchTitle()
    }
}

// ❌ @MainActor 内で DispatchQueue.main.async は冗長（かつ混乱を招く）
@MainActor
func updateUI() {
    DispatchQueue.main.async {  // 不要：すでに MainActor にいる
        self.title = "new"
    }
}
```

**例外**: `Process.terminationHandler` はバックグラウンドキューで呼ばれる。この場合は `DispatchQueue.main.async` または `Task { @MainActor in }` が必要。その意図をコメントで明記すること。

```swift
process.terminationHandler = { [weak self] proc in
    // terminationHandler はバックグラウンドスレッドで呼ばれるため main queue に dispatch
    DispatchQueue.main.async { ... }
}
```

### Task.detached の使いどころ

ファイル I/O・git コマンド実行など、メインスレッドをブロックする可能性のある処理は `Task.detached` で実行し、結果を `await MainActor.run { ... }` で反映する。

```swift
// ✅ ファイル I/O はバックグラウンドで
reloadTask = Task.detached { [weak self] in
    let tree = FileNode.buildTree(at: path, ...)
    await MainActor.run { self?.rootNode = tree }
}
```

### timing hack は NG

```swift
// ❌ 時間でロードを待つ
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { ... }

// ✅ コールバックや delegate で完了を検知する
func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ... }
```

---

## 4. SwiftUI / AppKit 混在

### NSViewRepresentable の使い方

- `makeNSView`: NSView のインスタンス生成のみ。副作用を持たせない。
- `updateNSView`: SwiftUI 側のプロパティ変更を NSView に反映。**全 updateNSView 呼び出しで高コスト処理を行わない**。変更検知（Coordinator キャッシュ等）でガードすること。
- `dismantleNSView`: NSView の外部リソース（モニター等）を解放。ただし SwiftUI がこれを呼ばない edge case に備え、`deinit` でも解放すること。

```swift
// ✅ Coordinator キャッシュで updateNSView をガード
func updateNSView(_ view: NSView, context: Context) {
    let coord = context.coordinator
    guard value != coord.cachedValue else { return }
    coord.cachedValue = value
    // 高コスト処理
}
```

### NSApp / NSWindow への直接アクセス

`NSApp.keyWindow` などへのアクセスは SwiftUI View 内に限定する（SwiftUI は暗黙的に MainActor）。Store や Model から呼ばない。

---

## 5. JavaScript インジェクション（SyntaxHighlightWebView）

WKWebView に文字列を注入する際は、**必ずすべての危険文字をエスケープ**すること。

```swift
// ✅ JS 文字列エスケープに </script> を含める
private func escapeJS(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "</script>", with: "<\\/script>")  // 必須
}
```

HTML を動的に生成する場合も `&`, `<`, `>`, `"` を HTML エスケープすること（`escapeHTML` を使う）。

---

## 6. Private API / undocumented API

WebKit の KVC private key など、非公開 API を使う場合は必ずコメントを付ける。

```swift
// ⚠️ Private WKWebView key — WebKit のバージョンアップで動作が変わる可能性がある。
// 代替: baseURL にファイル URL を渡す方法を試みること。
// 参照: https://bugs.webkit.org/...
config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
```

Private API は代替手段が存在する場合はそちらを優先する。

---

## 7. リソース管理

### close() / deinit パターン

外部リソース（ghostty surface、FSEvent stream、NSEvent monitor 等）を持つクラスは、`close()` または `stop()` メソッドを提供し、そこにクリーンアップを集約する。`deinit` はリークの検出（assertionFailure）のみとする。

```swift
// ✅ 正しいパターン
func close() {
    surface?.free()
    surface = nil
}

deinit {
    // close() が呼ばれずに解放された場合の検出
    assert(surface == nil, "close() was not called before dealloc")
}
```

### FSEventStream

FSEventStream のコールバックには必ず `weak` ラッパー（`FSEventContext` パターン）を使う。`Unmanaged.passRetained` で保持したオブジェクトは `stopWatching` で必ず `release` すること。コールバックが呼ばれる可能性がなくなった（`FSEventStreamRelease` 後）のを確認してから release する。

---

## 8. テスト

### MockGhosttyApp インジェクション

`WorkspaceStore` は `GhosttyAppProviding` プロトコルを受け取るため、テストでは `MockGhosttyApp` を注入する。`AppSettings.shared` の直接参照がある場合は、テスト用 `AppSettings(configURL: tempURL)` を渡す。

```swift
// ✅ テストでの DI
let mock = MockGhosttyApp()
let store = WorkspaceStore(ghosttyApp: mock, loadSnapshots: false)
```

### 非同期テストのパターン

`Task.detached` を使った非同期処理のテストには `awaitXxx()` メソッド（`awaitReload()`, `awaitSelectFile()` 等）を使う。`XCTestExpectation` ではなく `async/await` で書くこと。

```swift
// ✅ 非同期テスト
func testReload() async throws {
    state.reload()
    await state.awaitReload()
    XCTAssertNotNil(state.rootNode)
}
```

---

## 9. 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| Bool プロパティ | `is` / `has` / `can` プレフィックス | `isActive`, `hasMarkedText` |
| コールバッククロージャ | `on` プレフィックス | `onFocused`, `onProcessExited` |
| 非同期 pending 状態 | `pending` プレフィックス | `pendingURL`, `pendingUIAction` |
| キャッシュ変数 | `cached` プレフィックス | `cachedCode`, `cachedFontSize` |
| Store 操作メソッド | 動詞 + 名詞 | `addTerminalTab`, `closeArea`, `selectTab` |
| 純粋変換関数 | 現在分詞 | `removingTab(at:)`, `addingTab(_:)` |

---

## 10. よくあるアンチパターンと代替

| アンチパターン | 代替 |
|--------------|------|
| モデルから `BookmarkStore.save` を直接呼ぶ | コールバック `onRootChanged` を通じて Store で保存 |
| `DispatchQueue.main.async` in `@MainActor` メソッド | `Task { @MainActor in }` |
| `asyncAfter(deadline: .now() + N)` でロード完了を待つ | delegate / completionHandler で完了を検知 |
| `ObservableObject` + `@Published` | `@Observable` に移行（統一済み） |
| `NotificationCenter` for 1:1 in-process 通信 | `store.dispatch(_:)` または `@Observable` プロパティ |
| JS 文字列に `</script>` を含む可能性があるコードを直接埋め込む | `escapeJS` で `</script>` → `<\/script>` |
| `NSApp.keyWindow` を Store / Model から参照 | View 層でのみ使用する |
