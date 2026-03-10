# Design Decisions (Phase 1)

## 1. Model Structure: Value Types vs Reference Types

**Decision**: Workspace, Area, Tab は struct（値型）。TerminalSession は class のまま（ghostty surface のライフサイクル管理が必要）。

**Rationale**: CLAUDE.md の "Prefer value types" に従う。TerminalSession は ghostty C ポインタの所有権を持つため参照型が適切。

## 2. PanelContent enum

**Decision**: Panel の種類を enum で表現。Phase 1 では `.terminal(TerminalSession)` のみ。

```swift
public enum PanelContent {
    case terminal(TerminalSession)
    // Future phases: .browser(URL), .fileTree(path), .gitClient(path)
}
```

**Rationale**: 将来のパネル種別追加を見据えた拡張ポイント。

## 3. LayoutNode: PanelNode の後継

**Decision**: PanelNode を LayoutNode にリネーム・再設計。リーフノードは個別ターミナルではなく Area（タブを持つ矩形領域）。

```
LayoutNode
  ├── .leaf(Area)           ← Area はタブリストを保持
  └── .split(direction, first, second, ratio)
```

**Rationale**: 要件の「エリアがタブバーを持ち、複数パネルをタブ切替で表示」に対応。PanelNode は terminal を直接保持していたが、新モデルではエリア→タブ→パネルの階層を導入。

## 4. WorkspaceStore: SessionStore の後継

**Decision**: SessionStore を WorkspaceStore に置き換え。ワークスペース単位の管理に移行。

**API**:
- `workspaces: [Workspace]`
- `activeWorkspaceId: UUID?`
- `activeWorkspace: Workspace?` (computed)
- ワークスペース CRUD
- エリア分割・統合
- タブ追加・削除・切替

## 5. 既存コードの扱い

**Decision**: PanelNode.swift と SessionStore.swift は新モデルで完全に置き換え、削除する。PanelNodeTests も新テストで置き換え。

**Rationale**: 旧モデルを残すと混乱するだけ。

## 6. GUI への影響（8kd スコープ）

**Decision**: 8kd ではモデル＋既存 GUI の最低限の接続変更まで行う。ビルドが通る状態を維持する。

- ContentView: WorkspaceStore を使うよう変更
- SidebarView: 最低限のワークスペースリスト表示（詳細は 004 タスク）
- PanelView → AreaLayoutView: LayoutNode を描画
- TerminalPanelWrapper: タブバーの仮表示（詳細は 3ur タスク）

## Open Questions (相談事項)

### Q1: ワークスペース永続化
Phase 1 ではワークスペースのメモリ内管理のみ。永続化（アプリ再起動時の復元）は Phase 1 スコープ外とする。必要であれば別タスクとして追加。

### Q2: デフォルトワークスペース
アプリ起動時に「Workspace 1」を1つ自動作成。空のエリア（ターミナルタブ1つ）を持つ。

### Q3: パネルの ID 管理
Tab.id は UUID で自動生成。TerminalSession.id とは別物（1 Tab = 1 Panel = 1 Session の関係だが、ID は独立）。
