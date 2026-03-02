# 開発スキル（Claude Code / Agents）

Issue 駆動の開発ワークフローを自動化する4つのスキル。計画 → 実装 → 中断 → 再開のライフサイクルを管理する。

## 概要

```
/dev-plan <issue_number>      計画作成
        │
        ▼
/dev-execute <issue_number>   実装実行
        │
        ├── 中断したい場合 ──→ /dev-pause
        │                           │
        │                           ▼
        │                    /dev-resume <issue_number>
        │                           │
        │ ◄─────────────────────────┘
        ▼
      PR 作成・レビュー
```

## スキル一覧

| スキル | コマンド | 説明 |
|--------|----------|------|
| dev-plan | `/dev-plan <N>` | Issue の要件整理・設計・実装計画を作成 |
| dev-execute | `/dev-execute <N>` | 承認済み計画に基づいて実装 |
| dev-pause | `/dev-pause` | 作業中断し、引き継ぎ情報を Issue に投稿 |
| dev-resume | `/dev-resume <N>` | 中断した作業を再開 |

## セットアップ

### 1. ファイルを配置

プロジェクトルートに以下をコピーする:

```
your-project/
├── .claude/
│   └── skills/
│       ├── dev-plan/SKILL.md
│       ├── dev-execute/SKILL.md
│       ├── dev-pause/SKILL.md
│       └── dev-resume/SKILL.md
└── .agents/                          # Claude Code 以外のエージェントも使う場合
    └── skills/
        ├── dev-plan/SKILL.md
        ├── dev-execute/SKILL.md
        ├── dev-pause/SKILL.md
        └── dev-resume/SKILL.md
```

### 2. プロジェクト固有の設定

スキルはプロジェクト非依存で書かれているため、以下の情報を CLAUDE.md に記載しておくと精度が上がる:

```markdown
## Conventions

- ブランチ名: `feature-{issue_number}`
- テストコマンド: `make test` / `npm test`
- Lint コマンド: `make lint` / `npm run lint`
```

スキル内の `<branch_prefix>` はプロジェクトの CLAUDE.md のブランチ命名規約を自動参照する。

### 3. 前提条件

- [GitHub CLI](https://cli.github.com/) (`gh`) — Issue の取得・更新・コメント投稿に使用
- `tmp/` ディレクトリを `.gitignore` に追加

## 使い方

### 計画 → 実装の基本フロー

```bash
# 1. Issue の計画を作成
/dev-plan 123

# 2. 計画が承認されたら実装
/dev-execute 123
```

### 中断 → 再開

```bash
# 作業を中断（ブランチ名から Issue 番号を自動取得）
/dev-pause

# 後日、作業を再開
/dev-resume 123
```

## 各スキルの詳細

### `/dev-plan` — 計画作成

**入力:** Issue 番号

**処理:**
1. Issue 情報と関連ドキュメントを調査
2. 要件整理（入力・出力・ビジネスルール・非機能要件）
3. 設計（DB・レイヤー・UI・アクセス制御）
4. テスト計画作成
5. `./tmp/plan-<N>.md` に計画ファイルを保存
6. ユーザー承認後、Issue にコメント投稿＆ body 更新

**出力:**
- `./tmp/plan-<N>.md` — 計画ファイル
- Issue コメント — 計画の意思決定ログ
- Issue body — やることチェックリスト

### `/dev-execute` — 実装

**入力:** Issue 番号

**処理:**
1. 計画ファイル読み込み
2. ブランチ確認
3. 計画に従って実装（フェーズ完了時に Issue チェックリスト更新）
4. テスト実行（全通過が必須ゲート）
5. Lint 実行
6. コミット・PR 作成

**ゲート:** テスト全通過 + Lint クリア → PR 作成。未通過ならユーザーに報告して停止。

### `/dev-pause` — 中断

**入力:** なし（ブランチ名から Issue 番号を自動取得）

**処理:**
1. 現在の進捗を `git diff` / `git status` で確認
2. Issue の「やること」チェックリストと照合
3. 引き継ぎ事項をまとめて Issue にコメント投稿
4. Issue body の引き継ぎセクションを更新

**出力:**
- Issue コメント — 引き継ぎ事項（完了/進行中/未着手/ブロッカー）
- Issue body — 引き継ぎセクション追記

### `/dev-resume` — 再開

**入力:** Issue 番号

**処理:**
1. ブランチチェックアウト
2. Issue body から計画・引き継ぎ情報を取得
3. 計画ファイルを復元（なければ Issue コメントから再構築）
4. 進捗サマリーを表示
5. 未完了タスクから実装を再開（`/dev-execute` と同じフロー）

## Issue body の構造

スキルが管理する Issue body の標準構造:

```markdown
## 概要
（機能の説明）

## Dependencies
- #42

## 対応
- **機能A**: 〜を追加
- **機能B**: 〜を変更

## やること
### Phase 1: DB・スキーマ
- [x] テーブル追加
- [ ] マイグレーション

### Phase 2: API実装
- [ ] Repository作成
- [ ] Service作成

## 計画書
- [実装計画](コメントURL) — YYYY-MM-DD

## 引き継ぎ
- [引き継ぎ事項](コメントURL) — YYYY-MM-DD
```

## カスタマイズ

### プロジェクト固有スキルの参照

`dev-plan` や `dev-execute` からプロジェクト固有のスキルを呼び出したい場合は、SKILL.md 内に参照を追記する:

```markdown
## Step 3: ステータス更新
> `/project-status` を実行してステータスを変更する。
```

### テストコマンドのカスタマイズ

`dev-execute` はプロジェクトの CLAUDE.md に記載されたテストコマンドを使用する。CLAUDE.md に以下を記載しておくこと:

```markdown
## Commands
- テスト: `make test-backend && make test-e2e`
- Lint: `make lint`
```
