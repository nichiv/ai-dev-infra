# tm - tmuxセッション管理コマンド

tmuxセッションを簡単に管理するCLIツール。

リポジトリ同梱の `tmux.conf` と組み合わせると、WSLが落ちたりPCを再起動してもtmuxセッションのレイアウトとプロセスが自動復元される。

## セットアップ

### PATHに追加

```bash
# シンボリックリンク作成
ln -s /path/to/ai-dev-infra/bin/tm ~/bin/tm

# または PATH に追加
export PATH="/path/to/ai-dev-infra/bin:$PATH"
```

### tmux設定（任意・推奨）

セッションの自動保存・復元を有効にする：

```bash
# 既存の~/.tmux.confをバックアップ
[ -f ~/.tmux.conf ] && cp ~/.tmux.conf ~/.tmux.conf.bak

# リポジトリの設定をリンク
ln -sf /path/to/ai-dev-infra/tmux.conf ~/.tmux.conf

# TPM (tmux plugin manager) を導入
git clone --depth=1 https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# tmuxを起動してプラグインをインストール
tmux new-session -d -s _setup
~/.tmux/plugins/tpm/bin/install_plugins
tmux kill-session -t _setup
```

これで以下が有効になる：

- **tmux-resurrect**: セッション状態（ウィンドウ・ペイン構成、cwd、実行中プロセス）を保存・復元
- **tmux-continuum**: 15分おきに自動保存、tmuxサーバ起動時に自動復元
- **tmux-sensible**: ESCキー遅延の解消、history-limitの拡張など

#### 手動操作（prefix = `Ctrl+b`）

| キー | 動作 |
|---|---|
| `prefix + Ctrl+s` | 即時保存 |
| `prefix + Ctrl+r` | 即時復元 |

#### 復元対象のプロセス

`@resurrect-processes` で指定された以下のコマンドが復元時に再起動される：

- `ssh`, `psql`, `mysql`, `sqlite3`
- `node`, `python`, `python3`
- `docker`, `docker-compose`
- `claude`

未指定のコマンドはペインのcwdのみ保持され、シェルに戻る。Claude Codeの会話履歴は復元されないため、復元後に `claude --continue` で引き継ぐ。

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

`tmux.conf` を導入している場合は、tmuxサーバ停止に加えて `~/.tmux/resurrect/last` も削除する。これがないと、次回 `tm -c` 実行時にcontinuumの自動復元で削除したはずのセッションが蘇る。タイムスタンプ付きの過去スナップショットは `~/.tmux/resurrect/` に残るため、必要なら手動で復元可能。

## 前提条件

- tmux

### 任意（自動保存・復元を使う場合）

- TPM (tmux plugin manager)
- tmux-resurrect, tmux-continuum, tmux-sensible（TPM経由でインストール）
