---
name: capture-learning
description: 作業・修正・レビュー対応・設計が一段落するごとに、得た判断基準・学びをナレッジに蓄積するスキル。作業した本人(担当エージェント)が自分のコンテキストを持ったまま実行する(専用サブエージェントには作業の文脈が引き継がれず捕捉が劣化するため)。学びをグローバル(全プロジェクト共通)とプロジェクト固有に振り分けて書き込む。ユーザーに指摘・訂正されたとき、レビューで同種の指摘が繰り返し出たとき、「やってみて判明した」とき、設計を確定したとき(非自明な設計判断・設計 issue の合意)、タスク完了の振り返り時に使う。
---

# capture-learning — 学びをナレッジに蓄積する（担当エージェントが実行）

対応が完了するたび、得た**判断基準・学び**をナレッジに残す。繰り返す問題は Guides/Sensors に昇格させ、
ハーネスとプロジェクトを少しずつ賢くする。

## これは skill であって subagent ではない
**作業した本人が、自分のコンテキストを持ったまま実行する。**
「何が起きて・なぜ間違えて・正しい基準は何か」は作業の文脈に依存するため、専用サブエージェントに投げると
文脈が引き継がれず捕捉が劣化する。隔離すべきタスクではない → in-context の skill。

> **loop の責務・recall/capture の不変条件は ルール `knowledge`（常時オンの正本）**。
> 本 skill はその **capture（後）の具体手順**を担う。誰が回すか（主体追従・省略不可）はルール参照。

## いつ
- ユーザーに**指摘・訂正**されたとき（同じ間違いを繰り返さないため）。
- レビューで**同種の指摘が繰り返し**出たとき（→ ルール/観点へ昇格）。
- 実装中に「**やってみて判明した**」制約・事実が出たとき。
- **設計を確定したとき**（非自明な設計判断・設計 issue の合意）に、再利用可能な知見（判断基準・パターン・制約・落とし穴）を残す。
- タスク完了時の振り返り。
- **recall で既存知見の腐りを検出したとき**（`yosage-dev-harness:librarian` の `⚠要確認`/`✗陳腐化`、または inline 経路でのハンドル不在）＝ fix-on-recall（下記）。
- **外部調査（`yosage-dev-harness:researcher`）で引いた定石が判断に効いたとき**＝残す価値のある差分だけ知見化（下記「価値ゲート」）。

## fix-on-recall（recall で腐りを検出したとき）
recall（[[recall-knowledge]]）で知識の腐り（参照が実体と合わない／教訓が覆った）が判明したら、**その recall で判明した「今の正しい姿」**を使って主体がその場で直す（使うほど直る自己修復）。検出と修復の分離は ルール `knowledge` の原則に従う。
- **軽い修正**: yosage-dev-harness:librarian の `修正案`（supersede 即適用ペイロード）を使い、その場で supersede する（新エントリを書き、旧を `status: superseded` ＋ `supersedes` で繋ぐ）。`⚠` も積極的に更新する。
- **後継の無い陳腐化**: `✗陳腐化` と判定したが置き換える新エントリが無い（`supersedes` に書く先が無い）場合は `status: archived` で退役させる（**削除しない**＝判断履歴を資産として残す）。`archived:`（退役日）を frontmatter に付け、理由を本文に書く。専用の判断スキルや一括スイープは作らない（fix-on-recall の一手として、その場の主体が行う）。
- **重い修正（要再調査）**: 今のタスクを脱線させず follow-up issue へ逃がす。**切る前に当該知識の follow-up issue が既にないか検索**し、**あれば委譲**（新情報があればコメント追記）、**なければ** `docs` ラベルで新規に切る（[[issue-create]]。重複調停の台帳は issue トラッカー）。
- ベースの一括棚卸しは別 capability。fix-on-recall は既存 `status: active|superseded|archived` ＋ issue-offload に留める。

## promote-on-recall（recall で昇格候補を検出したとき）
recall（[[recall-knowledge]]）で `yosage-dev-harness:librarian` が `⇧昇格候補` または `⇧staging未PR` を surface したとき、主体が昇格または staging drain を実行する。ポリシーと検出/行為の分離は ルール `knowledge` の promote-on-recall 参照。`⇧staging未PR`（既に `scope: global` マーク済みの staging entry）は明示実行の `promote-knowledge`（別スキル）でストアへ PR し drain する（staging→PR 出口の詳細は下記「グローバル」節）。

- **昇格した場合（promoted）**: 既存ルール「昇格＝move、ローカル昇格元 entry は削除」でローカルから消える。消えた entry は再 flag され得ない。**新たなマークは不要**（昇格後始末の詳細は下記「昇格後の後始末」）。
- **見送った場合（declined）**: 新フィールド（`promote: declined` 等）を追加しない。代わりに、`scope: local` 本文に**反証可能な理由**を書く（例: 「<project> の X 設定固有であるため Y が崩れると昇格可になる」のように、何が崩れたら昇格可になるかが分かる形）。yosage-dev-harness:librarian の昇格ゲートは「明示的 local 理由を持ち、その理由が現在の content とまだ合致する entry」を `⇧昇格候補` から除外する（理由と gate を結合させる）。
  - **decline はソフトゲートで hard block しない**: entry が一般化方向に育つ、または理由 X が崩れると、理由と content が食い違い yosage-dev-harness:librarian が**自己再オープン**（再 flag）する。「decline したから恒久抑止」ではなく「理由がまだ content と合致するから今は抑止」が正確な意味。
  - **boolean フィールドを採らない理由**: content と decoupled なので、entry を一般化しても `declined` が貼り付いたまま（消し忘れ）再昇格を取りこぼす。promote-on-recall 自体は（fix-on-recall とは別に）新しいライフサイクル状態を持ち込まない方針であり、ここで安易にフィールドを足すとその方針を崩すことになる。
  - **フォールバック（YAGNI）**: content 結合の抑止が実運用で弱く再 nag が残る場合のみ、最小の任意フィールド `promote: declined`（既定は無＝eligible、entry の実質編集時にクリア）を後から足す。初手では入れない。

## 価値ゲート（残す価値の判定＝base model への差分だけ）
外部定石・一般論は、**モデルが既に持っている分を残しても価値が無い**（recall を膨らませ過信を量で再発させる）。残すのは base model への**差分**だけ:
- ① プロジェクトの**選択・逸脱**（「一般は A、ここは Z 理由で B」）→ `scope: local`。
- ② **非自明 / 版依存 / 新しすぎてモデルが弱い**確定定石 → グローバル候補（昇格は下記「振り分け」に従う）。出所は `source:`＋`checked:`。
- ③ この層が採る**規約**（複数正解のどれを採るか）→ 蒸留層 / `scope: local`。
- 「composition over inheritance」級の**一般論そのものは残さない**（引けば済む）。

## 何を書くか（1件1ルール、簡潔に）
- **判断基準**: 「X のときは Y する / しない」＋ **なぜ**（理由）。実例の出所は、**内部**なら `path` ＋ 安定ハンドル（関数名 / 見出し / 短い特徴的な引用。grep 再解決できる形。行番号は任意の便宜ヒント）、**外部（言語定石・公式 doc 等）**なら frontmatter の `source:`（URL）＋ `checked:`（確認日＝今日）で示す（grep 接地しないので安定ハンドルの代わり。`yosage-dev-harness:librarian` が recall 時に経過で鮮度判定）。**`source:` を付ける前に原典と照合する**（下記「引用照合」）。
- 推測でなく、起きた事実から書く（外部定石も「誰がどこで言っているか」を `source` で接地し、出所なしの一般論にしない）。
- **増やす前に既存を確認**: 重複なら更新（`supersedes`）、無ければ追加。古くなったら後継があれば `status: superseded`、無ければ `status: archived`（上記「後継の無い陳腐化」）。
- **形式（小分け）**: 1エントリ＝1ファイル `.claude/knowledge/<domain>/YYYY-MM-DD-<slug>.md`（置き場は `.claude/knowledge` に固定。置き場を変える機能は撤去済み）。書き込み先ディレクトリが解決できない（親ディレクトリが存在しない等）場合は、既定レイアウトを勝手に作らず停止して報告する（ストアの位置解決に失敗した可能性がある。「知見なし」の誤認と対になる書き込み側の失敗モード）。
  雛形は **`yosage-dev-harness-knowledge-template` の出力を新しいエントリのファイルに書いて埋める**（導入先に雛形ファイルを置かない＝プラグインの中から取り出す。frontmatter: `id/date/domain/tags/scope/status/summary`。`summary` は INDEX 用の1行要約。**必ず1行のプレーンスカラーで書く**＝行頭に `>` `|` を置かず複数行にしない。生成器は1行 `key: value` 前提で、多行にすると値が壊れ警告が出る。長くても改行せず1行に収めればよい。バッククォート・コロンは値に含めてよい）。
  `id` は**省略可**。省略時は生成器がファイル名の slug（拡張子を除去し、先頭が `YYYY-MM-DD-` にマッチすればそれを除去した残り。例: `2026-07-08-foo-bar.md` → `foo-bar`）から実効 id を導出する。明示 `id:` があればそれが優先される（override）。
  **project-local の `INDEX.md` は作らない＝ローカル索引は廃止**。エントリを足すと **PostToolUse フック(`knowledge-index.sh`)が検証だけのモード（`--check`）で生成器を走らせ、frontmatter の書式検証だけを行う**（ファイルは書かない）。recall はエントリの直接列挙（`yosage-dev-harness-knowledge-index ".claude/knowledge" --list`）を使う。
  日付/ドメイン/タグで小分けされ、膨大化しても `yosage-dev-harness:librarian` / [[recall-knowledge]] が選り分けられる。loop の不変条件は ルール `knowledge`。

## 引用照合（source: を持つ知見は capture 時点で原典と照合する）
真偽軸の照合手順の正本は ルール `knowledge` の「書き方不変: 引用照合ゲート」節（本 skill には再記述しない）。capture 固有の挙動:
- **照合は capture 時点で行う**: エントリを書き込む前に済ませる。未照合のまま `source:`＋`checked:` を先に埋めない。
- **一致したら `checked:` を今日にする**: 照合した日がそのままエントリの `checked:`。
- **矛盾・原典に無い主張・照合不能を検出したら、その記述は書かない**: 矛盾・原典に無い主張は原典に合わせて訂正するか支持されない記述を削る。照合不能は確認できない旨を残して `source:`／`checked:` を付けずに保留する（正本の「止める」の capture 時点での具体化）。人間へのエスカレーションは昇格時点のバックストップ（`promote-knowledge`）が担う。

## 振り分け: ローカル or グローバル
判定の問い: **この学びは他プロジェクトでも成り立つか？**

### プロジェクト固有 → そのまま直接書く（プロジェクト所有・同期で上書きされない。上書きされるのは `global/` のミラー）
- **生エントリ（既定）**: タグ付きエントリを `.claude/knowledge/<domain>/` に追加（project-local の `INDEX.md` は作らない。上記「形式」）。promote-on-recall で昇格を見送る場合は、本文に**反証可能な local 理由**（何が崩れたら昇格可になるかが分かる形）を書いておく（理由が陳腐化すると yosage-dev-harness:librarian が自己再オープンする）。
- **繰り返し効くものは蒸留層へ昇格**（常時オンで適用される確定観点に）:
  - レビュー判断基準 → `.claude/yosage-dev-harness-review-criteria.md`
  - コーディング/テスト規約（特定パス） → `.claude/rules/<該当パス>/coding.md`（or `testing.md`）
  - アーキ判断・設計意図 → `.docs/architecture/`

### グローバル（全プロジェクト共通の判断・原則）→ 既定はまずローカルに staging
グローバル知識は**専用の単一ソース＝グローバル知識ストア**（`.claude/yosage-dev-harness.local.json` の `knowledge.source` で設定する独立リポ）で管理し、ツーリング(harness)とは別ライフサイクル。消費側は `.claude/knowledge/global/` のミラーを、セッション開始時の同期（SessionStart フックの knowledge-sync）で受け取るだけ（プロジェクトから直接 global を書かず、**ストアへの反映は昇格スキル経由**）。

**既定: 「global と判断したら、まずローカルに `scope: global` で staging」**（capture 時点では直接 PR しない）。2経路:
- **生層（エントリ）**: エントリ frontmatter に **`scope: global`** を付けて `.claude/knowledge/<domain>/` に書く（プロジェクト固有 entry と同じ形式・`scope` だけ変える）。**根拠 / 実例が配布 payload のパス（正本 ルール `knowledge` の「home repo 固有パスと配布 payload パスの区別」節が挙げるパターン）に接地できるなら、この時点で安定ハンドルとして書いておく**（travel 面でも grep で再解決できる取っ手。持てないエントリを block はしない）。
- **蒸留層（レビュー観点）**: **`.claude/review/criteria.global-proposed.md`** に基準＋理由＋出どころ `path:line` を追記する。

**ストアへの昇格（PR）は明示実行の `promote-knowledge`（別スキル）に一本化**する。cross-repo・外向き着火は重い遷移＝人間トリガという不変（ルール `knowledge`）に整合させるため、capture-learning の責務は**staging までで完結**し、ストアへの PR 送出は行わない。

昇格（`promote-knowledge` 実行 → ストア PR マージ）後は knowledge sync で全プロジェクトの `.claude/knowledge/global/`・`.claude/review/criteria.md` へ伝播（opt-in）。

#### 昇格後の後始末（昇格＝move、コピーではない）
**1つの事実に家は1つ**。一般事実は store が唯一の家（接続プロジェクトには `global/` に read-only で返る）。だから:
- **store にマージされたら、ローカルの昇格元 entry は削除**（既定。project-local の `INDEX.md` は無いので再生成は要らない）。残すと二重管理＋再精査で**再プロモートされる**リスク。
- **project 固有の適用**が別途価値あるなら、それは**独立した `scope: local` エントリ**として書く（store の一般版とは別物。本文で一般版に言及してよい）。`scope: local` なので昇格候補にならず再昇格しない。1エントリを「半分 global・半分 local」にしない。
- **重複（他プロジェクトからの独立昇格・再昇格）は store の PR レビューで dedup**（同 id / `supersedes`）。完全自動の dedup は無く、ゲート＝store の PR レビューが担う。

> 消費側（skills/agents）は常に `.claude/review/` を読むだけで、知識の出所（harness 同梱 か 専用リポジトリか）に依存しない。

> グローバルは全プロジェクトに効くため高リスク。**自動では入れず、必ずストアへの PR レビュー（人間ゲート）を通す**。ストアへの反映は `promote-knowledge` 経由のみ（capture-learning は直接 PR しない）。

## 手順
1. 学びを1〜2文に言語化（基準＋理由）。
2. ローカル / グローバルを判定。
3. `source:`（外部出典）を伴うなら、書き込む前に原典と照合する（上記「引用照合」）。
4. **書き込む前に自己チェックを通す**（粒度混在・scope 妥当性。正本は ルール `knowledge` の
   「書き方不変: 書き込み前の自己チェック」節。本 skill には再記述しない）。混在・scope の誤りに気づいたら、
   ここで分割・修正してから次に進む（書いてから直すのではない）。
5. 対象ファイルの既存を確認 → 重複は更新、無ければ追記。project-local の `INDEX.md` は作らない（フックは検証だけ。一覧は `yosage-dev-harness-knowledge-index .claude/knowledge --list`）。
6. グローバルと判断したら **既定はまずローカルに staging**（生層=エントリ frontmatter に `scope: global` を付けて `.claude/knowledge/<domain>/` へ、蒸留層=`.claude/review/criteria.global-proposed.md` へ追記）。ストアへの PR は `promote-knowledge`（別スキル）が担う（capture-learning はここでは PR しない）。

## 原則
- **本人が書く**: 文脈を持つ担当エージェントが実行（subagent に投げない）。
- **1件1ルール＋理由**: 後で効くのは「なぜ」。
- **重複させない・腐らせない**: 既存を見てから書き、古い基準は直す。
- **グローバルはまずローカル staging が既定・ストアへの反映は `promote-knowledge` に一本化**: capture-learning は直接 PR しない。単一ソースを汚さない。
- **文脈的自己完結**: capture 成果物（knowledge エントリ）もセッション内符牒を展開して書く（正本 ルール `issue-discipline` の `## self-contained`）。
- **travel 面の自己完結**: knowledge エントリの書き方の不変は正本 ルール `knowledge` の `## 書き方不変: travel 面の自己完結` を参照（本 skill には再記述しない）。
- **引用照合ゲートを省略しない**: `source:` を持つエントリは capture 時点で原典と照合する（正本 ルール `knowledge` の `## 書き方不変: 引用照合ゲート` を参照。本 skill には再記述しない）。
- **書き込む前の自己チェックを省略しない**: 粒度混在・scope 妥当性は書き込む前に主体 in-context で自問する（正本 ルール `knowledge` の `## 書き方不変: 書き込み前の自己チェック` を参照。本 skill には再記述しない）。
