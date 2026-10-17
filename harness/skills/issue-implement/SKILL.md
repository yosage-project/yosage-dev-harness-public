---
name: issue-implement
description: Epic に属さない単発 issue を導入先の既定ブランチ基点で実装するレーン。分類して単発と確定したら yosage-dev-harness:implementer に dispatch し（メインは統制）、ブランチ作成→実装→検証→コミット(Closes)→draft PR(ベースへ)→一次レビューまで回す。Epic の Sub-issue 実装は epic-implement-subissue。
argument-hint: "<issue-number> | <owner>/<repo>#<issue-number>"
allowed-tools: Bash(yosage-dev-harness-gh-issue-resolve *)
---

# issue-implement — 単発 issue を導入先の既定ブランチ基点で実装する

1件の issue を**端から端まで**対応する基本レーン。これはプリミティブで、ベースは **導入先の既定ブランチ**（解決は ルール `pr-loop` の「ベースブランチ / クローズ / マージ」節）。
Epic の Sub-issue の実装は [[epic-implement-subissue]]（このレーンの epic 版。ベースブランチの既定/選択は
ルール `pr-loop` に従う——取り込み先は Sub-issue の本文に書かれた Epic ブランチか導入先の既定ブランチ）。
レーンの選び方（単発か Epic か Sub-issue か）と「メインは実装せず dispatch」の正本は **ルール `implement-routing`**（常時オン）。

## 動的コンテキスト
Issue の内容:

!`yosage-dev-harness-gh-issue-resolve "$ARGUMENTS"`

## 手順

メインは**統制に徹し、実装は `yosage-dev-harness:implementer` に dispatch する**（正本 ルール `implement-routing`）。下の step 2–6 は dispatch された `yosage-dev-harness:implementer` が worktree で行う（接地・実装・検証・commit・draft PR と recall→capture を内蔵規律で）。メインは step 1（解析・分類確認）・dispatch・step 7（一次レビュー差配）・報告を担う。

### 1. issue の解析（メイン）
本文から **ゴール / 受け入れ条件 / 対象 / 検証方法**を特定する。self-contained でない（外部参照に依存し着手できない）場合は、起票元に追記を求める（[[issue-create]] の規律）。分類して**単発（非 Epic）**と確認する（Epic／Sub-issue なら正本のレーンへ回す）。
次に**実装入口 OQ ゲートを踏む**（ルール `implement-routing` 「実装入口 OQ ゲート」節）。

### 2. ブランチ作成（ベースから）
```bash
git fetch origin
# 投入時に明示されたベース、または導入先の profile の宣言があれば --declared に渡す（無ければ --declared を省く）
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  git checkout -b <type>/<name> "origin/$base" || echo "ブランチ作成に失敗（同名のブランチが既にある等）: 止めて案内する（別名にするか既存ブランチの扱いを人に聞く）" >&2
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```
- 解決の順と終了コードの扱いは ルール `pr-loop` の「ベースブランチ / クローズ / マージ」節に従う。決まらなければ（終了コード 1）止めて人に聞く。宣言したブランチが origin に無ければ（終了コード 3）宣言の誤りとして、宣言を直すよう止める。`exit` でシェルを閉じない（`if` で分ける）。
- **`$base` は別の Bash 呼び出しには残らない前提**で書く。step 6 の直前で同じ呼び方で解決し直す。
- 接頭辞は issue の種別に一致（`feat`/`fix`/`refactor`/`chore`/`docs`/`test`/`perf`）。
- 例: 「worktree の gitignore 追加」→ `fix/worktrees-gitignore`。

### 3. 接地（recall）→ 実装
- **接地（必須）**: 書き始める前に [[grounded-design]]（既定。単発の知識照会だけなら [[recall-knowledge]] 単独）で**このドメインの過去の判断・落とし穴を recall** する。CLAUDE.md の規約・既存パターンを踏襲。
- **実装は必ず `yosage-dev-harness:implementer` に dispatch する**（粒度に関わらず＝正本 ルール `implement-routing`）。単発＝**N=1・並列なし**で `yosage-dev-harness:implementer` を1体 worktree 起動し、上の接地と担当範囲を渡す。**メインが解決したベース（投入時の明示・profile の宣言から決めたもの。無ければ無いと書く）を投入指示に明示して渡す**（`yosage-dev-harness:implementer` は会話の文脈を持たないので、明示や宣言は投入の文面でしか届かない）。`yosage-dev-harness:implementer` は渡されたベースを `--declared` に渡して解決する。実装規律（接地・規約遵守・commit・draft PR・recall→capture）は yosage-dev-harness:implementer 定義に内蔵。
- dispatch したら、メインは**受け身で待たず watchdog を踏む**（有界待ち＋ネット進捗確認。ルール `agent-watchdog`）。
- **knowledge loop に従う**（ルール `knowledge` — 常時オンの正本）。本 skill では recall（step 3 の接地）→ capture（step 8）。

### 4. 検証
受け入れ条件・issue の「検証方法」を実行（テスト/型/lint。このハーネス自身のリポジトリなら `bash test/run.sh`）。

### 5. コミット（規約は ルール `commit` ＋ `Closes #`）
commit 前に **`sensitive-data` ルール**（ルール `sensitive-data`）の secret/PII チェックを踏む。

`Closes #` には**常に bare な issue 番号のみ**を書く（GitHub の自動クローズ構文は `Closes #<数字>` のみを認識する）。
`$ARGUMENTS` が `<owner>/<repo>#<N>` 形式(ワークスペースでは必須)のときは、末尾の `#` の後ろの `<N>` 部分
だけを取り出して使う（`<owner>/<repo>#<N>` を丸ごと `Closes #` の後ろに貼らない）。以下の 5・6 で同様。

```bash
git add <変更ファイル>
git commit -m "<type>(<scope>): <要約>

Closes #<issue番号>"
```
**`Co-Authored-By` 署名トレーラの要否**は ルール `commit` の「Co-Authored-By 署名トレーラ」節に従う（本 skill では再記述しない）。付ける場合は上のコミットメッセージ末尾に空行を挟んで `Co-Authored-By: <実行モデルの署名（例: Claude Opus 4.8 (1M context) <noreply@anthropic.com>）>` を追記する。

### 6. Push & draft PR（ベースへ）
```bash
git push -u origin <type>/<name>
# 別の Bash 呼び出しでは step 2 の $base は残らないので、ここで同じ呼び方で解決し直す（解決できなければ `if` の else 側で step 2 と同じ扱いで止め、PR 作成に進まない）
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  # worktree 隔離運用では --head 省略で head 誤推定→ "No commits between X and X" で失敗しうるため明示
  gh pr create --draft --base "$base" \
    --head <type>/<name> \
    --assignee @me \
    --title "<type>: <要約>" \
    --body "## Summary
<変更要約>

Docs-impact: <api|architecture|detail|ui / none(理由)>

未実行の検証: <コマンド> / 理由: <資源名>（対象 repo の `project-profile` に「検証時排他資源」が宣言
されている、または実装中にその検証をスキップした場合に必須。該当が無ければこの行自体を省略してよい
——テンプレート化はしない。宣言の不在を「検証済み」と読まない fail-safe のため、該当する場合に
書き漏らさない）

Closes #<issue番号>

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（PR は作らない）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる（PR は作らない）" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する（PR は作らない）" >&2 ;;
  esac
fi
```

### 7. 一次レビュー → PR単位ゲート → ready → 報告
**標準PRループに従う**（ルール `pr-loop` — 常時オンの正本）。単発レーン固有の点だけ:
- 一次レビューは **メインが `yosage-dev-harness:code-reviewer` を dispatch**（単体実行なので自分で差配）。
- 指摘は **PR コメント上**で yosage-dev-harness:implementer に対応させ（`SendMessage` で継続）→ push → resolve。**スコープ外/follow-up は `issue-create` で issue 化**（落とさない）。
- **PR単位ゲート**: 対象 repo の `project-profile` に「検証時排他資源」が宣言されている、または PR 本文に「未実行の検証」が記載されている場合、**`gh pr ready` の前に**メインがそのブランチ単体（`git fetch` してブランチをチェックアウト、または既存の割り当て worktree）で**直列に**該当検証を実行する。実装（worktree 並列）は妨げない——ゲートは検証ステップだけに掛かる。成功したら PR 本文の「未実行の検証」行を検証済みへ更新（または削除）する。失敗したら yosage-dev-harness:implementer へ差し戻す。
- ゲートを通ったら **`gh pr ready`** → PR URL を報告。

### 8. 学びの蓄積（capture・必須で loop を閉じる）
実装の学び（接地・レビュー対応・「やってみて判明した」制約/事実）は **yosage-dev-harness:implementer が in-context で** [[capture-learning]] する（step 3 の recall と対）。メインは**統制で判明した学び**（あれば）を capture する。
（誰が回すか・省略不可は ルール `knowledge`。捕捉の書き方は [[capture-learning]]。）

## 注意事項
- ベースは **導入先の既定ブランチ**（step 2 で解決した `$base`。名前を直書きしない）。PR もそこへ。
- **PR 本文は repo 内で自己完結**（issue 規律 ルール `issue-discipline`）。
- 設計に影響する doc 更新は同 PR でやらず `Docs-impact:` に記録（[[sync-design-docs]] の方針）。実体更新はまとめて。
- 実装が issue 記載と矛盾したらユーザーに確認する。
