# 自動レビュー

`git push` をトリガーに、複数の AI エージェントが並列でコードレビューを実行し、結果を Issue にコメントする。

## 仕組み

```
git push
  │
  ▼
lefthook pre-push hook
  │
  ▼
ブランチ名から issue 番号を抽出
（例: feature-123 → feature-123）
  │
  ▼
review.sh review feature-123
  │
  ├──→ Claude (primary/fallback)  ─┐
  ├──→ Gemini (primary/fallback)  ─┤ 並列実行
  └──→ Codex  (primary/fallback)  ─┘ ← agents.codex: true 時のみ
                                    │
                                    ▼
                              結果を統合
                                    │
                                    ▼
                          Issue にコメント
                          （comment: true 時のみ）
                                    │
                                    ▼
                            LGTM → push 成功
                            要修正 → push ブロック
```

### ポイント

- エージェントの有効/無効は `.config/review.yml` で設定
- 各エージェントは primary モデル → fallback モデルの順で試行
- 1エージェントでも成功すればレビュー結果を出力（全失敗時のみエラー）
- 2回目以降は前回指摘の対応状況を追跡
- ブロック対象の深刻度は `.config/review.yml` で設定可能

## セットアップ

### 1. ファイルを配置

プロジェクトルートに以下のファイルをコピーする。

```
your-project/
├── .config/
│   ├── project.yml               # プロジェクト設定
│   ├── review.yml                # レビュー設定
│   └── ai-models.yml             # AIモデル設定
├── dev-tools/
│   ├── config.sh                 # 設定読み込みヘルパー
│   ├── review/
│   │   ├── review.sh             # メインスクリプト
│   │   ├── perspectives.md       # レビュー観点（必須）
│   │   ├── additional_perspectives/  # 追加観点（オプション）
│   │   │   └── .gitkeep
│   │   └── agents/
│   │       ├── run-claude.sh
│   │       ├── run-gemini.sh
│   │       └── run-codex.sh
│   └── issue-tracker/
│       ├── loader.sh             # プロバイダー解決・読み込み
│       ├── github.sh             # GitHub プロバイダー
│       └── youtrack.sh           # YouTrack プロバイダー
└── lefthook.yml
```

### 2. `.config/project.yml` を編集

```yaml
# Issue トラッカー（github または youtrack）
issue_tracker: github

# YouTrack 設定（issue_tracker: youtrack の場合）
# youtrack:
#   base_url: https://your-instance.youtrack.cloud

# リポジトリ情報
repository:
  owner: your-org
  name: your-repo
  full_name: your-org/your-repo
  base_branch: main
  # ブランチプレフィックス（配列で複数指定可能）
  branch_prefix:
    - feature
```

### 3. `.config/review.yml` を編集

```yaml
# 有効化
enabled: true

# issueへのコメント
comment: true

# エージェント
agents:
  claude: true
  gemini: true
  codex: false

# ブロック対象
block:
  critical: true
  high: true
  medium: true
  low: false

# タイムアウト（秒）
timeout: 600
timeout_with_codex: 900
```

| 設定 | 説明 |
|------|------|
| `enabled` | `false` でレビュー全体を無効化 |
| `comment` | `false` で Issue へのコメント投稿を無効化 |
| `agents.*` | 各エージェントの有効/無効 |
| `block.*` | 各深刻度でpushをブロックするか |
| `timeout` | タイムアウト秒数 |
| `timeout_with_codex` | Codex有効時のタイムアウト秒数 |

### 4. `.config/ai-models.yml` を編集

```yaml
claude:
  primary: opus
  fallback: sonnet

gemini:
  primary: gemini-3-pro-preview
  fallback: gemini-3-flash-preview

codex:
  primary: gpt-5.3-codex
  fallback: gpt-5.2
```

各エージェントは primary → fallback の順で試行する。

### 5. `lefthook.yml` を設定

```yaml
pre-push:
  commands:
    review:
      run: |
        export CONFIG_DIR="$(pwd)/.config"
        BRANCH=$(git rev-parse --abbrev-ref HEAD)

        # branch_prefix を config から取得（配列対応）
        PREFIXES=$(yq -r '.repository.branch_prefix[]' "$CONFIG_DIR/project.yml" 2>/dev/null || yq -r '.repository.branch_prefix' "$CONFIG_DIR/project.yml" 2>/dev/null)

        ISSUE_NUMBER=""
        for prefix in $PREFIXES; do
          if [[ "$BRANCH" =~ ^(${prefix}-[0-9]+)(-[0-9]+)?$ ]]; then
            ISSUE_NUMBER="${BASH_REMATCH[1]}"
            break
          fi
        done

        if [ -n "$ISSUE_NUMBER" ]; then
          ./dev-tools/review/review.sh review "$ISSUE_NUMBER"
        fi
```

`branch_prefix` をプロジェクトのブランチ命名規約に合わせて変更する。

| ブランチ命名例 | branch_prefix |
|-------------|---------------|
| `feature-123` | `feature` |
| `issue-123` | `issue` |
| `navi_ota-123` | `navi_ota` |

パターンにマッチしないブランチ（`main`, `develop` 等）では自動レビューは実行されない。

### 6. Lefthook をインストール・有効化

```bash
brew install lefthook
lefthook install
```

### 7. `.gitignore` に追加

```
tmp/
```

レビュー結果は `./tmp/review/` に出力される。

## 使い方

### レビュー実行

```bash
# 手動実行
./dev-tools/review/review.sh review feature-123

# Codex も含めてレビュー（CLI フラグ）
./dev-tools/review/review.sh review feature-123 --with-codex
```

### 自動実行

`git push` 時に lefthook が自動実行する。

```bash
git push  # → lefthook → review.sh review feature-123
```

### レビュー回数の追跡

レビュー結果は `combined-review-N.md` として保存され、回数が追跡される。

```
tmp/review/
├── combined-review-1.md    # 1回目のレビュー結果
├── combined-review-2.md    # 2回目のレビュー結果
├── combined-review-3.md    # 3回目のレビュー結果
└── ...
```

2回目以降のレビューでは、前回の指摘に対する対応状況も確認される。

### 出力ファイル

```
tmp/review/
├── claude-review.md          # Claude の個別結果
├── gemini-review.md          # Gemini の個別結果
├── codex-review.md           # Codex の個別結果
├── combined-review-N.md      # 統合結果（N=レビュー回数）
└── *.err                     # 各エージェントのエラーログ
```

## Issue Tracker 設定

`.config/project.yml` の `issue_tracker` で使用するプロバイダーを設定する。

### GitHub（デフォルト）

```yaml
issue_tracker: github
```

`gh` CLI が認証済みであること。

### YouTrack

```yaml
issue_tracker: youtrack

youtrack:
  base_url: https://your-instance.youtrack.cloud
```

環境変数 `YOUTRACK_TOKEN` に API トークンを設定すること。

```bash
export YOUTRACK_TOKEN="perm:xxx..."
```

プロジェクトルートの `.env` ファイルからも読み込み可能。

```
# .env
YOUTRACK_TOKEN=perm:xxx...
```

### プロバイダーの追加

全プロバイダーは以下の3関数を実装する:

| 関数 | 説明 |
|------|------|
| `tracker_get_issue $issue_number $repo` | Issue のタイトルと本文を取得 |
| `tracker_get_comments $issue_number $repo` | Issue のコメント一覧を取得 |
| `tracker_post_comment $issue_number $repo $body_file` | Issue にコメントを投稿 |

新しいプロバイダーを追加する手順:

1. `dev-tools/issue-tracker/<provider>.sh` を作成し、上記3関数を実装
2. `dev-tools/issue-tracker/loader.sh` の `case` 文にプロバイダーを追加
3. `.config/project.yml` に `issue_tracker: <provider>` を設定

## カスタマイズ

### レビュー観点（必須）

`dev-tools/review/perspectives.md` にレビュー観点を定義する。このファイルは必須。

```markdown
### 観点1: 要件充足 🔴
Issue で定義された要件を全て満たしているか。

### 観点2: セキュリティ 🔴
SQLインジェクション、XSS、認証バイパス...

### 観点3: テスト 🟡
新機能にテストがあるか...
```

深刻度アイコンの意味:

| アイコン | 深刻度 | 説明 |
|---------|--------|------|
| 🔴 | Critical | 必ず修正が必要 |
| 🟠 | High | 原則修正が必要 |
| 🟡 | Medium | 修正を推奨 |
| 🟢 | Low | 改善提案 |

### 追加観点（オプション）

`dev-tools/review/additional_perspectives/` に `.md` ファイルを配置すると、追加観点として自動的に読み込まれる。

```
dev-tools/review/additional_perspectives/
├── performance.md      # パフォーマンス観点
├── accessibility.md    # アクセシビリティ観点
└── i18n.md             # 国際化観点
```

### 設定ディレクトリの変更

`CONFIG_DIR` 環境変数で `.config/` 以外の場所を指定できる。

```bash
CONFIG_DIR=./settings ./dev-tools/review/review.sh review 123
```

## トラブルシューティング

### Claude Code のネスト禁止エラー

Claude Code セッション内から `git push` すると、`CLAUDECODE` 環境変数が子プロセスに継承されてネスト禁止になる。`review.sh` は `CLAUDECODE=` で明示的に unset しているため、通常は発生しない。

手動実行で発生する場合:

```bash
CLAUDECODE= ./dev-tools/review/review.sh review 123
```

### 特定のエージェントだけ失敗する

CLI がインストールされていない、または認証が切れている可能性がある。`tmp/review/*.err` でエラー内容を確認する。

```bash
cat tmp/review/gemini-review.err
```

1エージェントでも成功すればレビュー結果は出力されるため、全エージェントのインストールは必須ではない。

### Gemini の rate limit

Gemini は rate limit が厳しく、連続実行するとエラーになりやすい。rate limit が検出されると自動的に fallback モデルに切り替わる。両方 rate limit の場合はそのエージェントはスキップされる。

### push が毎回ブロックされる

レビュー結果にブロック対象の指摘が含まれていると push がブロックされる。`tmp/review/combined-review-N.md` で具体的な指摘内容を確認し、対応してから再度 push する。

ブロック対象の深刻度は `.config/review.yml` の `block` で設定できる。

レビューをスキップして push したい場合:

```bash
git push --no-verify
```

### レビューを一時的に無効化したい

`.config/review.yml` で `enabled: false` に設定する。

```yaml
enabled: false
```
