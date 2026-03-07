# wt - Git Worktree管理コマンド

Git worktreeを簡単に管理するCLIツール。

## セットアップ

### 1. PATHに追加

```bash
# シンボリックリンク作成
ln -s /path/to/ai-dev-infra/bin/wt ~/bin/wt

# または PATH に追加
export PATH="/path/to/ai-dev-infra/bin:$PATH"
```

### 2. 環境変数設定

`.bashrc` / `.zshrc` に追加:

```bash
export WORKTREE_DIR="$HOME/worktrees"    # worktree格納ディレクトリ
export PROJECT_DIR="$HOME/projects"       # プロジェクト検索ディレクトリ
```

### 3. シェル関数の有効化（推奨）

`wt cd` で直接移動するために必要:

```bash
# .bashrc / .zshrc に追加
eval "$(wt init)"
```

## コマンド

### wt --create / wt -c

新規worktreeを作成。

```bash
wt --create <repository_name> <branch_name> [base_branch]
```

**例:**

```bash
# デフォルトブランチ（main/master）から作成
wt --create my-app feature-123

# 指定ブランチから作成
wt --create my-app feature-123 develop
```

**処理内容:**
1. `$PROJECT_DIR/<repository_name>` を検出
2. リモートから最新情報を取得
3. `$WORKTREE_DIR/<repository_name>-<branch_name>` にworktree作成
4. 新規ブランチを作成（既存の場合は確認）

### wt cd

worktreeディレクトリへ直接移動。

```bash
wt cd <branch_name>
```

**例:**

```bash
wt cd feature-123
```

複数のリポジトリで同じブランチ名がある場合は対話形式で選択。

**注意:** `eval "$(wt init)"` を実行済みである必要がある。

### wt --list / wt -l

worktree一覧を表示。

```bash
wt --list
```

**出力例:**

```
=== Worktree一覧 ===
ディレクトリ: /home/user/worktrees

my-app-feature-123
  パス: /home/user/worktrees/my-app-feature-123
  ブランチ: feature-123

合計: 1 件
```

### wt --remove / wt -r

マージ済みPRのworktreeを自動削除。

```bash
wt --remove
```

**処理内容:**
1. `$WORKTREE_DIR` 内のworktreeを検索
2. GitHub CLI (`gh`) でPRのマージ状況を確認
3. マージ済みのworktreeとローカルブランチを削除

**注意:** 未マージのworktreeは削除されない。

### wt init

シェル関数定義を出力。`wt cd` を有効にするために必要。

```bash
eval "$(wt init)"
```

`.bashrc` / `.zshrc` に追加しておくと、シェル起動時に自動で有効になる。

## 前提条件

- Git
- GitHub CLI (`gh`) - `--remove` で使用

## ディレクトリ構成例

```
$PROJECT_DIR/
  my-app/           # git リポジトリ
  another-repo/     # git リポジトリ

$WORKTREE_DIR/
  my-app-feature-123/       # worktree
  another-repo-bugfix-456/  # worktree
```
