---
name: beads
description: このプロジェクトの bd (beads) タスク管理のコンセプト・ルール・ワークフロー全体を定義する
disable-model-invocation: false
user-invocable: false
---

このプロジェクトの bd (beads) タスク管理の共通知識。

## ロールモデル

| ロール | 担い手 | 責務 |
|--------|--------|------|
| pdm | AI | タスク管理・分解・AC設定・依存設計 |
| dev | AI | 実装・テスト・コミット |
| architect | AI | 設計判断・レビュー |
| po / user | kimuson | 要件定義・AC合意・動作確認 |

## Issue の型 (type)

すべての issue は同じ ID 体系 (`<prefix>-xxx`) を持つ。

| type | 用途 |
|------|------|
| task | 作業全般（機能追加・バグ以外） |
| bug | バグ修正 |
| feature | ユーザーに見える新機能 |
| epic | 複数 issue をまとめる親 |
| chore | メンテナンス・依存更新・ドキュメント等 |
| gate | 実装後の確認チェックポイント |
| merge-request | PR に対応する issue |

`molecule / agent / role / convoy / event` は bd 内部構造用。通常の開発では使わない。

## Assignee ルール

| assignee | 意味 |
|----------|------|
| なし (unassigned) | dev (AI) が `bd ready --unassigned` で自動取得・実装 |
| `kimuson` | kimuson 専任。AI はスキップする |

## Issue の必須メタデータ

`gate` を除くすべての issue (task / bug / feature) には以下が必要:

**description:**
```
## AC (Acceptance Criteria)
- [ ] <具体的な完了条件>
```

**ラベル:** `gate:required` または `gate:not-required` を付与する。
`gate:required` の場合は description に確認観点も記載する。

**gate 要否の判断基準:**

| 条件 | gate |
|------|------|
| ユーザーに見える挙動の変更（機能追加・UI変更・外部挙動に変わるバグ修正） | required |
| 内部実装のみ・テストで担保可能（リファクタ・型修正・内部バグ修正） | not-required |

## AC の決め方

- **PdM が決めてよい**: 実装詳細・内部構造・テスト戦略
- **kimuson と合意が必要**: ユーザーに見える機能で設計選択肢が複数あるもの

→ kimuson 合意が必要な場合は **AC合意タスク → 本体** の依存構造にする:

```bash
# AC合意タスク (kimuson 専任)
AC_ID=$(bd q --title="[AC合意] <本体タイトル>" --type=task --assignee=kimuson \
  --description="<選択肢と決めるべきこと>")

# 本体
MAIN_ID=$(bd q --title="<本体タイトル>" --type=feature \
  --labels "gate:required" ...)

# 本体が AC合意タスクに依存（AC合意が終わるまで本体は ready に出ない）
bd dep add "$MAIN_ID" "$AC_ID"
```

## ワークフロー概要

```
1. [pdm]       teams:pdm           → issue 起票・AC設定・依存設計
2. [dev]       teams:dev-auto|colab → bd ready --unassigned から実装
3. [dev]       実装完了              → gate:required なら gate issue 作成
4. [po]        teams:gates-review   → kimuson が動作確認し結果を返す
5. [pdm]       teams:gates-review   → OK なら close、NG なら note + タスク open に戻す
6. [architect] teams:architect      → 定期レビュー → pdm が issue 化
```

## コマンド一覧

| コマンド | 用途 |
|----------|------|
| `teams:pdm` | issue 起票・整理・依存設計 |
| `teams:dev-auto` | 自律実装。ユーザー確認なし |
| `teams:dev-colab` | 協働実装。kimuson に確認しながら進む |
| `teams:gates-review` | gate 確認サマリー出力 + kimuson の結果処理 |
| `teams:architect` | アーキテクチャレビュー + CODING_GUIDELINE.md + Lint更新 |
