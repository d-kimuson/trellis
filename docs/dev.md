# Development Setup

## Requirements

開発環境は Nix Flakes + direnv で管理している。`direnv allow` すればビルドに必要なツール (Zig, SwiftLint, make, pkg-config) が自動で PATH に入る。

唯一の例外は **Xcode**。nixpkgs では管理できないため、手動でのインストールが必要。libghostty が Metal シェーダコンパイラ (`metal`) を使うため、Command Line Tools だけでは不足し Xcode.app 本体が必要。

## Setup

### 1. Xcode

Mac App Store から Xcode をインストールし、`xcode-select` を向ける:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Metal コンパイラが利用可能か確認:

```bash
xcrun -sdk macosx -f metal
```

### 2. direnv

リポジトリの `.envrc` を許可:

```bash
direnv allow
```

### 3. Build libghostty

初回セットアップ — ghostty ソースの clone、パッチ適用、static library のビルド:

```bash
make setup
```

初回は Zig が ghostty をソースからコンパイルするため数分かかる。

### 4. Build & Run

```bash
make build   # Compile the app
make app     # Create .app bundle
make run     # Build + launch Trellis.app
```

### 5. Quality checks

```bash
make lint    # SwiftLint
make test    # XCTest via xcodebuild
make check   # Run all checks on changed files
```
