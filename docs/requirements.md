## Concept

CLI Agent に最適化されたターミナル — Claude Code 等の AI エージェントを複数並行で走らせながら、関連情報（ブラウザ・ファイルツリー・Git 状態）を一画面で把握できる統合環境。

## Terminology

| Term | Definition |
|------|-----------|
| Workspace | 1つの作業コンテキスト。複数のエリアで構成される。サイドバーに一覧表示 |
| Area | ワークスペース内の矩形領域。タブバーを持ち、複数パネルをタブ切替で表示 |
| Panel | エリア内の1タブに対応する実体。ターミナル・ブラウザ・ファイルツリー・Git クライアントのいずれか |
| Layout | ワークスペース内のエリア配置。水平/垂直分割の再帰的な木構造 |

## Core Features

### Terminal Panel
- libghostty ベースの PTY ターミナル（PoC 済み）
- 1パネル = 1シェルセッション
- ワークスペースごとに複数ターミナルを起動可能

### Workspace Management
- 複数ワークスペースの作成・削除・名前変更
- ワークスペースごとに独立したレイアウトとパネル群を保持
- サイドバーからワークスペースを切り替え
- 用途例: 「プロジェクトA作業用」「サーバー監視用」など作業コンテキストの分離

### Area and Tabs
- 各エリアはタブバーを持ち、「+」ボタンでパネルを追加（種類を選択）
- タブの閉じる・並び替え
- アクティブタブのパネルがエリア内に描画される

### Layout
- エリアの水平分割・垂直分割（再帰的。PoC の PanelNode 木構造を拡張）
- ドラッグ・アンド・ドロップによるレイアウト構築:
  - タブをエリア外にドラッグ → 新しいエリアとして分割配置
  - タブを既存エリアのタブバーにドロップ → そのエリアのタブとして合流
- エリア境界のドラッグでサイズ比率を調整
- サイドバーとメインエリア間の境界もドラッグでリサイズ可能

## UX Enhancement Panels

### Built-in Browser Panel
- WKWebView ベースの簡易ブラウザ
- URL バー、戻る/進む/リロード
- 用途: ドキュメント参照、プレビュー確認、AI エージェントの出力確認など
- ターミナルとの連携は初期スコープ外（将来的に URL 渡し等を検討）

### File Tree Panel
- 指定ディレクトリのツリー表示
- ファイル選択でパスをクリップボードにコピー、または関連ターミナルに送信
- .gitignore に準じたフィルタリング
- ファイルの変更監視（FSEvents）でリアルタイム更新

### Git Client Panel
- カレントブランチ表示、ブランチ切り替え
- ステージング状態の一覧（変更/追加/削除ファイル）
- diff ビューア
- 基本操作: stage / unstage / commit / push / pull
- 詳細な Git 操作はターミナルに委ねる（GUI で全機能をカバーしない）

## UI Structure

```
┌──────────────────────────────────────────────┐
│ [WS1] [WS2] [WS3]  │  Area 1         │ Area 2      │
│  (Sidebar)          │ [Tab1][Tab2][+] │ [Tab1][+]   │
│                     │                 │             │
│  Workspace list     │  Terminal       │  Browser    │
│                     │                 │             │
│                     ├─────────────────┤             │
│                     │  Area 3         │             │
│                     │ [Tab1][+]       │             │
│                     │  File Tree      │             │
│                     │                 │             │
└──────────────────────────────────────────────┘
       ↕ resize             ↔ resize
```

## Notifications

- デスクトップ通知（macOS UNUserNotificationCenter）
- 検知対象:
  - ターミナル出力の特定パターン（例: プロセス完了、エラー発生）
  - Claude Code 等のエージェントからの通知パターン（エスケープシーケンス、または特定の文字列パターンマッチ）
- アプリが非フォーカス時に通知を発火
- 通知クリックで該当ワークスペース/パネルにフォーカス移動

## Out of Scope (for now)

- キーバインドのカスタマイズ
- テーマ/カラースキーム設定
- リモート SSH 接続の特別対応（通常のターミナル経由で可能）
- プラグインシステム

## Phase Plan

| Phase | Content | Priority |
|-------|---------|----------|
| 1 | Workspace/Area/Tab model + Sidebar + Split + Resize | P0 (MVP) |
| 2 | D&D layout operations (tab move, area split, area merge) | P1 |
| 3 | Desktop notifications (foundation, pattern match, focus) | P2 |
| 4 | Additional panels (Browser, File Tree, Git) | P3 |
