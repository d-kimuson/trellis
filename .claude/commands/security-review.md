---
description: 'セキュリティ観点でコードをレビューし docs/tmp に報告書を出力する'
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash(find), Bash(wc), Bash(date)
---

あなたはmacOSネイティブアプリ・ターミナルエミュレータのセキュリティに精通した上級セキュリティエンジニアです。このプロジェクトをセキュリティ観点でレビューし、脆弱性・リスクを洗い出してください。

## レビュー観点

### 1. プロセス実行・シェルインジェクション
- ユーザー入力をコマンド引数・シェルに渡す箇所
- `Process`/`NSTask` の引数サニタイズ漏れ
- エスケープ不足によるコマンドインジェクションリスク

### 2. ファイルシステムアクセス
- 任意パスへの読み書きを許す処理
- シンボリックリンク・パストラバーサル
- 一時ファイルの安全な作成（`mktemp` 等）

### 3. ネットワーク・IPC
- 外部通信（URLSession, WebSocket）の証明書検証
- ローカルソケット・XPC の認証・認可
- サードパーティライブラリの通信

### 4. 権限・エンタイトルメント
- `Entitlements.plist` の過剰権限
- Sandbox エスケープのリスク
- TCC (Accessibility, Full Disk Access) の適切な取得フロー

### 5. 機密情報の取り扱い
- ハードコードされたシークレット・API キー
- ログへの機密情報出力
- Keychain 非使用のパスワード・トークン保存

### 6. メモリ安全性
- unsafe ポインタ操作・バッファオーバーフローリスク
- libghostty C API 境界でのメモリ管理
- Use-after-free、ダングリングポインタのリスク

### 7. その他
上記以外で気になるセキュリティ上の問題を全て列挙してください。

## 作業手順

1. `CLAUDE.md` を読んでプロジェクト構造を把握する
2. `Resources/Entitlements.plist`（存在すれば）を確認する
3. `Sources/Trellis/` 配下を全て読んで実装を理解する
4. 上記観点でレビューし、問題を重大度（Critical / High / Medium / Low）で分類する

## 出力

`docs/tmp/security-review-{date}.md`（`date` は `date +%Y%m%d` の結果）に出力してください。

```markdown
# Security Review — {date}

## Executive Summary
(3〜5行で全体評価)

## Critical
### [脆弱性タイトル]
- **場所**: ファイルパス:行番号
- **問題**: 何が問題か（攻撃シナリオを含む）
- **影響**: 悪用された場合の被害
- **改善案**: 具体的な修正方針

## High
...

## Medium
...

## Low
...

## セキュリティチェックリスト
- [ ] 項目 — 補足
...
```
