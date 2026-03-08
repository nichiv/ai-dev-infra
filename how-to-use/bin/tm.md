# tm - tmuxセッション管理コマンド

tmuxセッションを簡単に管理するCLIツール。

## セットアップ

### PATHに追加

```bash
# シンボリックリンク作成
ln -s /path/to/ai-dev-infra/bin/tm ~/bin/tm

# または PATH に追加
export PATH="/path/to/ai-dev-infra/bin:$PATH"
```

## コマンド

### tm -c \<name\>

セッションを作成、または既存セッションにアタッチ。

```bash
tm -c main
```

**処理内容:**
- 指定名のセッションが存在しなければ新規作成
- 存在すればアタッチ

### tm ls

セッション一覧を表示。

```bash
tm ls
```

**出力例:**

```
main: 1 windows (created Sun Mar  8 21:00:00 2026)
dev: 2 windows (created Sun Mar  8 21:30:00 2026)
```

### tm -r \<name\>

指定セッションを削除。

```bash
tm -r main
```

### tm -r --all

全セッションを削除。

```bash
tm -r --all
```

## 前提条件

- tmux
