# yosage-dev-harness

開発領域（実装ルーティング・PR ループ・knowledge loop 等）のワークフローを Claude Code に統合する
プラグイン。Claude の操作を制限しつつ、設計・実装・レビュー・ナレッジの規律を常時オンのルールと
スキル・エージェントで配る。

- **フックはこのプラグイン独自の発火条件を持たない**: プラグインが有効なリポジトリでは常に動く。
  どこで使うか（どのリポジトリ・どのセッションで有効にするか）は Claude Code の有効化の単位で決める。
- **スコープ**: ソフトウェア開発の作業スコープを対象とする。他部署向けの用途や、複数リポジトリ／
  案件を跨いで統制する組織統制層向けの用途はスコープ外。

## このリポジトリについて

- **読み取り専用のミラー**: 開発は別の場所で行い、リリースごとにここへ反映している。
  **issue と PR は受け付けない**。
- **フィードバック・要望・動作についての報告・導入の相談**は、次のフォームへ。
  https://docs.google.com/forms/d/e/1FAIpQLSdNgSa2CdrNid2AjCtODmLN133zvqXOvbMMUbmJRuzRLCUszA/viewform
  - 報告に書いてほしいこと: 使っているバージョン（Claude Code で `/plugin` を開き、
    `yosage-dev-harness` の詳細に出るバージョン）、何をしようとしたか（どう頼んだか）、何が起きたか。
  - 返信の目安（3営業日以内）は導入相談にだけ示す。報告や要望には、個別の返信や調査・修正を約束しない。
  - ログやエラーを貼るときは、秘密情報（トークン・パスワード等）や個人情報を伏せる。
- **ライセンス**: MIT（[LICENSE](LICENSE)）。
- **運営・窓口**: Yosage Project株式会社。
- **お願い**: 権利侵害や他人に迷惑をかける使い方はしないでほしい（これはお願いであり、法的な拘束力はない）。

## 前提

- **Claude Code v2.1.280 以降**（非公開リポジトリからの自動更新にこの版以降が必要）。
- `git`。
- `jq` か `python3` のいずれか（無いとガード（`guard.sh`）や、常時オンのルールをサブエージェントへ
  注入する仕組み（`inject-rule.sh`）が動かない）。

## セットアップ

1. **マーケットプレイスを追加する**（公開用リポジトリを、マーケットプレイス
   `yosage-dev-harness` として追加する）:

   ```bash
   claude plugin marketplace add yosage-project/yosage-dev-harness-public --scope project
   ```

   公開用リポジトリが非公開のうちは、読むには招待と git の認証が要る。
   `--scope` は導入単位で選ぶ（下記）。

2. **導入単位を選ぶ**: `--scope` には `project`（そのリポジトリの全員に共有・`.claude/settings.json`
   にマーケットプレイスの場所が書かれてコミットされる）と `local`（自分のマシンだけ）がある。
   ユーザー単位（`user`）にする利点は無い。
   - **推奨: プロジェクト単位かローカル単位**。
   - **他社のリポジトリはローカル単位（`--scope local`）にする**: プロジェクト単位だと、他社の
     リポジトリの `.claude/settings.json` に社内の非公開リポジトリ名（＝マーケットプレイスの場所）
     が書かれてコミットされ、他社のメンバーはそこへ認証できない。

3. **プラグインを有効にする**:

   ```bash
   claude plugin install yosage-dev-harness@yosage-dev-harness --scope project
   ```

4. **導入先へ最小限のものを書き込む**（`.gitignore` の不足行・`.claude/worktrees/.gitignore`・
   設定ファイル・推奨設定の見本。書かないものは下記「導入先に書かれるもの」を参照）:

   ```
   /yosage-dev-harness:setup
   ```

5. **状態を確認する**（書き込まない）:

   ```
   /yosage-dev-harness:status
   ```

## 使い方

導入のあとの使い方（何をどう頼めば、何が起きて、人はどこで何をするか）は [docs/](docs/README.md)
にまとめてある。初めてなら [はじめての1件](docs/getting-started.md) から読む。

- [変更の規模ごとの流れ](docs/workflows.md) — 小修正・追跡が要る単発・設計判断が要る単発・Epic の進め方
- [Epic の進め方](docs/epic.md) — 計画・起票・実装・レビュー・完了
- [知見](docs/knowledge.md) — 作業前に引く・作業後に残す。共有ストアの設定と昇格。共有ストアは、公開の
  テンプレートリポジトリ `yosage-dev-knowledge-template`（GitHub の「Use this template」）から始められる
- [ガードと機密](docs/guard-and-sensitive-data.md) — 実行前に止まるものと、秘密・個人情報の扱い
- [ワークスペース](docs/workspace.md) — 複数のリポジトリを1つの案件として扱う
- [よくある詰まり](docs/troubleshooting.md) — 止められた・反映されない・知見が引けない、など

## 導入先に書かれるもの

`setup`・`update` はいずれも、対象リポジトリ直下の `.gitignore` に足りない行を足す（他社の
リポジトリの追跡物が変わることは、導入を選んだ利用者が受け入れる）。書くのは次の最小限だけ:

- リポジトリ直下 `.gitignore` への不足行（`/.claude/yosage-dev-harness.local.json`・
  `/.claude/knowledge/global/`・`/.claude/knowledge/.global.tmp*`・`/.claude/knowledge/.global.old/`・
  `/.claude/knowledge/.global-sync`・`/.claude/knowledge/.sync-log`・`/.claude/review/criteria.md`・
  `/.claude/tmp/`）。利用者が意図的に `!` で打ち消している行は上書きしない。
- `.claude/worktrees/.gitignore`（並列 worktree の隔離置き場を追跡外にする `*` 1行）。
- 設定ファイル `.claude/yosage-dev-harness.local.json`（`setup` のみ・無ければ新規作成。`update` は
  既存の項目を書き足さない）。
- 推奨設定の見本 `.claude/yosage-dev-harness.recommended-settings.json`（Claude Code はこのファイルを
  読まない。採るものは利用者が自分で `.claude/settings.json` へ移す）。

**書かないもの**: `.claude/settings.json` には一切書き込まない。allow は配らない。

## 設定

導入先ごとの設定は単一ファイル `.claude/yosage-dev-harness.local.json`（git で追跡しない）に
まとめる。書くのは既定値から変えた項目だけ。スキーマは
`harness/config/yosage-dev-harness.schema.json`、既定値は `harness/config/defaults.json`。

| 項目 | 既定値 | 説明 |
|---|---|---|
| `workspace` | `false` | 複数リポジトリが同居するワークスペースの直下かどうか。 |
| `knowledge.enabled` | `false` | グローバル知識ストアの同期を有効にするか（opt-in）。 |
| `knowledge.source` | `""` | グローバル知識ストア（独立リポジトリ）。git clone/fetch できる URL。ストアは公開のテンプレートリポジトリ `yosage-dev-knowledge-template` から作れる（[知見](docs/knowledge.md)）。 |
| `knowledge.ref` | `"main"` | 取得する ref（ブランチ/タグ）。 |
| `notify.url` | `""` | Discord/Slack への通知 webhook URL。**秘密**。未設定なら無音（opt-in by URL）。 |
| `notify.provider` | `""` | `slack` \| `discord`。未指定なら URL のホスト名から判別する。 |
| `notify.on_notification` / `notify.on_stop` / `notify.on_subagent_stop` | `true` | イベント別の通知 on/off。 |

環境変数では設定しない（利用者が変えた項目だけを設定ファイルに書く運用にするため、環境変数は
読まない）。エージェント・スキルは設定ファイルを丸ごと開かず
`bash harness/bin/yosage-dev-harness-config-get <dotted.key>` で1項目だけ取り出す。

**秘密の値は守りきれない**: `notify.url` のような秘密も `.claude/yosage-dev-harness.local.json`
（git で追跡しない）に置く。プラグイン自身は値を文脈に出さない（`/yosage-dev-harness:status` は
「設定あり／なし」だけを表示する）が、Claude が自分から Bash で読むことは止められない。
「文脈に入らない」とは約束しない。

## 更新

プラグインの `version`（`harness/.claude-plugin/plugin.json`）を上げたリリースのときだけ、
マーケットプレイス経由の更新が届く。導入先の不足行・推奨設定の見本を今の版に合わせるには:

```
/yosage-dev-harness:update
```

（設定ファイルの既存項目は書き足さない。初回導入は `setup` を使う。）

## ガード

`hooks/guard.sh`（PreToolUse）が次を止める:

- 破壊的・危険なシェルコマンド（`rm -rf /`・`curl | sh`・保護ブランチへの force push 等）。
- 割り当てられた作業ツリー（worktree）の外への書き込み・git 操作（worktree 隔離サブエージェント向け）。
- 秘密ファイル（`.env` 系 / `*.pem` / `*.key` / `id_rsa` / `secrets/**`）の読み取り
  （Read・Grep・Bash 経由のいずれも）。

**解除の手段は無い**（環境変数での opt-out を持たない）。止まったら Claude は報告して止まり、
本当に必要な操作は人が自分のターミナルで行う。これらはいずれも **Claude の操作だけを止める**——
人がエディタや別ターミナルで行うコミット・操作は範囲外。

**GitHub の push 保護（secret scanning の push protection）の併用を推奨する**: ガードが捕まえるのは
このプラグイン経由の Bash 操作に限られるため、リポジトリ側の push 保護を有効にしておくと、
経由を問わず秘密の push を止められる。

## profile（導入先固有の座標）

harness 由来の横断ルールはプラグインの中にあり、セッション開始時・サブエージェント起動時の
フックで注入される（導入先の `.claude/` にはファイルとして置かれない）。一方
`.claude/rules/<名前>/profile.md` は利用者所有（導入先固有の座標を書く場所。プラグインは
生成も上書きもしない）。所有権の境界はルール `project-profile`（常時オン）が正本。

- **profile は差分だけを持つ**（スタック・ビルド/検証コマンド・ワークスペースのトポロジ・
  repo ごとの取扱い）。既に `.docs/` に正本がある事項（ユビキタス言語は `glossary` skill、
  構造面の正本は `document-architecture` skill）は重複させない。
- **ワークフロー（調査 / 設計 / issue 分割 / 実装 / PR / レビュー）は harness の汎用 skill / agent に流す**。
  profile 側に再記述しない（harness 側の手順が変わると profile が追従できず drift する）。

## 注意

**同じ名前のプラグインを2つのマーケットプレイスから同時に有効にしない**: 同じ
`yosage-dev-harness` を、別のマーケットプレイスからも重ねて有効にしない（開発者向けの開発用
マーケットプレイスについては「開発者向け」節を参照）。

**claude.ai の組織設定（Organization settings > Plugins & skills）からの配布には対応しない**:
このプラグインは最上位に `harness/bin/` を持つため、組織設定経由の同期（organization sync）では
拒否される（`Plugin contains a top-level bin/ directory` というエラーで弾かれ、マーケットプレイスの
他のプラグインは同期される）。上記「セットアップ」の `claude plugin marketplace add` /
`claude plugin install` の経路（組織設定を介さない）を使うこと。

## 機能カタログ（自動生成）

skill / agent / rule / hook / 実行ファイルの名前と説明の一覧。**生成物**（frontmatter/ヘッダから
`scripts/catalog-gen.sh` が生成。手編集しない）。skill・agent は `/yosage-dev-harness:<名前>` /
`yosage-dev-harness:<名前>` の形で呼ぶ（skill は `disable-model-invocation: true` が付いているものは
明示実行のみ）。

<!-- BEGIN yosage-dev-harness catalog (generated) -->
<!-- 生成物: scripts/catalog-gen.sh が生成。手編集しない(各ファイルの frontmatter/ヘッダを直す) -->

### skills

| skill | description |
|---|---|
| `capture-learning` | 作業・修正・レビュー対応・設計が一段落するごとに、得た判断基準・学びをナレッジに蓄積するスキル。作業した本人(担当エージェント)が自分のコンテキストを持ったまま実行する(専用サブエージェントには作業の文脈が引き継がれず捕捉が劣化するため)。学びをグローバル(全プロジェクト共通)とプロジェクト固有に振り分けて書き込む。ユーザーに指摘・訂正されたとき、レビューで同種の指摘が繰り返し出たとき、「やってみて判明した」とき、設計を確定したとき(非自明な設計判断・設計 issue の合意)、タスク完了の振り返り時に使う。 |
| `deliberate-design` | 設計フェーズで「接地つき多案比較→討議→収束」のループを駆動するスキル。比較盤（MADR 型）を立て、往復討議し、二軸レビューで過収束を防ぎ、収束基準を満たしたら design-doc か knowledge へ蒸留する。「この変更どう進める？ 複数案を比べたい」「設計討議を始めたい」「案を出して詰めてほしい」のような場面で使う。討議するかの入口判定（着火モデル）は ルール `design-routing`（常時オン）が担う。 |
| `design-doc` | 非自明な機能追加・変更・リファクタを始める前に、設計を「issue に書いて」議論し合意を取るスキル。検討中の設計は .docs でなく issue に置く(self-contained・引き継ぎ可能・issue-first)。決まったら正本(.docs)と決定(.claude/knowledge)へ蒸留する。「設計してから作る」「アーキの方針を決めたい」「この変更どう進める？」のような場面で使う。 |
| `document-architecture` | プロジェクトのアーキテクチャを確立し `.docs/architecture/` に正本化するスキル。新規プロジェクトはスタックに応じたベースケースを提案し、既存プロジェクトはコードから実際のアーキを抽出して記述する。設計を始める前、ハーネス導入時、「アーキテクチャを決めたい/書き出したい」場面で使う。ここで作る doc が grounded-design・yosage-dev-harness:consistency-reviewer・.claude/rules の参照先になる。 |
| `document-profile` | 導入先固有の座標をまとめた `.claude/rules/<名前>/profile.md` を、対象を調査した下書きとして起こし、人間の確認を経て書き出すスキル。既存の profile がある場合は `refresh` 引数を渡すと、記述と実体のズレを列挙するだけの鮮度チェックモードになる（自動修正はしない）。`document-architecture`（`.docs/architecture/` を正本化）と対になる命名。利用者所有ファイルへの書き込みを伴うため `/yosage-dev-harness:document-profile` の明示実行でのみ動く。 |
| `epic-create-docs` | Epic の計画ドキュメント (.epic_docs/) を作成する。調査→設計→Sub-issue 分割までを行う。 |
| `epic-create-issues` | Epic Issue と Sub-issues を一括作成し、GitHub でリンクする。 |
| `epic-implement-subissue` | Epic 配下の Sub-issue を実装するレーン。PR の取り込み先は Sub-issue の本文の「取り込み先」（既定は Epic ブランチ、例外は導入先の既定ブランチ。pr-loop.md の規則）。名指し1件なら yosage-dev-harness:implementer に dispatch して1件だけ実装→コミット→draft PR。単発(非Epic)は issue-implement。epic-implement 経由では yosage-dev-harness:implementer がこの手順を踏む。 |
| `epic-implement` | Epic Issue 全体を実装する（人間トリガ）。Sub-issues を取得し依存解析して順次/並列で実装。スコープ無しなら全フェーズを人間の追加トリガ無しに完走、phase/Sub-issue リストを明示指定した場合のみそのスコープで停止。番号なしなら直前会話から類推し確認。 |
| `epic-review` | Epic ブランチ向けの PR をレビューする（マージは実行しない。人間にマージを促す）。epic-implement と並行して使用可能。 |
| `glossary` | プロジェクトのユビキタス言語(ドメイン用語)と、クラス名・データモデル・テーブル/フィールド名との対応を一元管理するスキル。同じ概念を別名で呼ぶ揺れや命名の不統一を防ぐ。新しいドメイン概念が出たとき、命名に迷うとき、設計・実装・レビュー時に使う。正本は .docs/glossary.md。 |
| `grounded-design` | 設計・アーキテクチャ判断・既存コードを参照する実装の前に使う、接地(grounding)の規律。既存実装からの逸脱とハルシネーション(存在しない関数/ファイル/API/カラムの参照)を防ぐ。加えて、言語/FWのベストプラクティス・仕様への外部接地と、Claudeの補完の明示(補完するなら根拠ラベルつきでsurfaceしユーザーが前さばきできるように)も行う。「設計して」「この機能どう作る」「既存に合わせて」のような場面で、憶測で書き始める前に必ず適用する。 |
| `harness-help` | 導入済みハーネスの自己ディスカバリ用スキル。今どんな skill/agent/rule/hook を持っているか、それぞれをどう使うか、「この作業どうやる?」に対しどのフローへ進めばよいかを案内する。ハーネスの機能を把握したいとき、使い方に迷ったとき、久しぶりに触って全体像を思い出したいときに使う。 |
| `issue-create` | Epic に属さない単発の GitHub issue を self-contained に作成するスキル。follow-up・レビューで出たスコープ外・別セッション跨ぎ・Epic 後に対応すべき発覚事項を「issue を見れば対応できる」形で起票する。Epic 一括作成は epic-create-issues。 |
| `issue-implement` | Epic に属さない単発 issue を導入先の既定ブランチ基点で実装するレーン。分類して単発と確定したら yosage-dev-harness:implementer に dispatch し（メインは統制）、ブランチ作成→実装→検証→コミット(Closes)→draft PR(ベースへ)→一次レビューまで回す。Epic の Sub-issue 実装は epic-implement-subissue。 |
| `orchestrate-parallel` | 複数の worktree エージェントを並列で動かすとき、メインセッションが司令塔(管理者)として統制するためのスキル。並列実装・並列タスク・worktree 並列を始める前/最中に使う。コンフリクト回避(ファイルが衝突する作業は並列にしない)、ストール検知(止まったエージェントを放置せず停止・回収)、逐次統合(コンフリクトはメインが解消)を徹底する。 |
| `promote-knowledge` | staged なグローバル候補知見（ローカル scope:global entry ＋ criteria.global-proposed.md）を精査し、travel 面で自己完結するよう de-localize し、外部出典を持つ候補は原典と引用照合してからグローバル知識ストアへバッチ PR する昇格ゲートスキル。ユーザーの明示実行（`/yosage-dev-harness:promote-knowledge`）でのみ起動する。 |
| `proposal` | 新規プロダクトや大きな機能の起点となる提案書(.docs/proposal.md)を、ユーザーとの壁打ちで作るスキル。企画の始まり。実装に入ったら凍結し、よほどのことがない限り書き換えない。新規プロダクト着手時や「提案書/企画をまとめたい」ときに使う。 |
| `recall-knowledge` | 作業・設計・レビューの前に、蓄積された知識ベースから「今の作業に関連するものだけ」を選り分けて読み込むスキル(司書役)。膨大な知識を全部読まず、project-local はエントリを直接列挙(索引には依存しない)、global は索引で domain/tags を絞って必要なエントリだけ貸し出す。設計判断を固める前、ドメイン固有の判断が必要なとき、レビュー観点を揃えるときに使う。蓄積側は capture-learning。 |
| `scratch-run` | ローカル(Windows/Mac)に uv/python/node 等が無い、またはグローバルを汚したくない時に、使い捨て Docker コンテナで一時コマンドを実行するスキル。ad-hoc なデータ解析・doc一致チェック・ワンオフのツール実行に使う。Docker を基本ランタイムとし、ホストには何も入れない。lib/scratch.sh を使う。 |
| `setup` | 導入先に守りに必要な最小のものだけを書き込む(.gitignore の不足行・.claude/worktrees/.gitignore・設定ファイル・推奨設定の見本)。`/yosage-dev-harness:setup` の明示実行でのみ動く。 |
| `status` | 導入先の設定(既定値と今の値)・.gitignore の不足/打ち消し・.claude/worktrees/.gitignore の状態・推奨設定の見本がプラグインの版と一致するか・使われなくなった項目を表で見せる(書き込まない)。設定を確認したいとき・導入状態を把握したいときに使う。 |
| `sync-design-docs` | 実装中/PR時に設計ドキュメント(.docs)を実装と同期させるスキル。設計が実装で変わった・やってみて判明したケースを取りこぼさず吸収する。実装からドキュメントを起こし(derive)、docの主張をコードと照合(verify)し、PR・Epic-PRの段階でdoc更新を必須化する。「設計が変わった」「docの更新漏れ」「実装に合わせてドキュメント直す」場面で使う。 |
| `update` | 導入先の .gitignore の不足行・.claude/worktrees/.gitignore・推奨設定の見本を今のプラグインの版に合わせて更新する(設定ファイルの項目は書き足さない)。`/yosage-dev-harness:update` の明示実行でのみ動く。 |
| `visual-design` | 視覚デザイン（UI の見た目・配色・タイポグラフィ・レイアウトを起こす／作り直す）ためのスキル。design brief から色・書体・レイアウト・signature のトークン系を先に立て、「どのブリーフでも出しそうな既定解になっていないか」を批評してから作る2パスの craft プロセスを提供する。「UI のビジュアルを起こしたい」「配色やタイポグラフィを決めたい」「見た目をデザインしたい」「テンプレっぽくない見た目にしたい」「トップページの見た目を考えたい」のような場面で使う。**ソフトウェア設計**（仕組み・アーキテクチャをどう作るかの判断）は対象外（`deliberate-design`/`design-doc`/`grounded-design` を使う）。「design」の二義性の正本は ルール `visual-design-routing`。 |

### agents

| agent | description |
|---|---|
| `architect` | 提案書(.docs/proposal.md)や機能要望と既存コードベースを調べ、アーキテクチャ/実装方針を設計して返すサブエージェント。新規=proposal からアーキ案、既存=機能をどう実装し Epic にどう分割するかの方針。読み取り中心で設計案(digest)を返し、コードは変更しない。設計フェーズや機能のEpic化検討時に使う。 |
| `best-practice-reviewer` | 設計ドキュメントまたはコード差分を「言語/FW の定石・原理原則・ベストプラクティスから外れていないか(＝単に動くだけの劣った型・車輪の再発明・既知のアンチパターンでないか)」の外部軸だけに絞って点検するサブエージェント。yosage-dev-harness:consistency-reviewer(内部軸＝既存逸脱・実在)の鏡。設計フェーズで、過信由来の非定石な解を実装前に止めるのに使う。読み取り専用。版依存・現行権威が要る点は yosage-dev-harness:researcher で裏取りさせる。 |
| `code-reviewer` | 現在の差分(git diff)をレビューし、正しさ・設計・テスト・セキュリティ観点で指摘するサブエージェント。実装が一段落したとき、PRを出す前、「レビューして」と言われたときに使う。読み取り中心でコードは変更しない。 |
| `consistency-reviewer` | 設計ドキュメントまたはコード差分を「既存実装からの逸脱」と「ハルシネーション(実在しない参照)」の2点に絞って点検するサブエージェント。設計レビュー時、実装前の設計確認、「この設計は既存に沿っているか」「参照は実在するか確かめて」のような場面で使う。読み取り専用。 |
| `doc-writer` | Epic 完了時に、Epic 全体の差分と既存 .docs/ を突き合わせて設計ドキュメントを実装に合わせて更新する専門サブエージェント。実装部隊(yosage-dev-harness:implementer)は完了/分散しており、管理者は差分を抱えない方針なので、whole-Epic の大きな差分を隔離文脈で読んで docs を更新する役を担う。sync-design-docs の規律に従い derive→verify→commit し、更新の digest を返す。.docs 以外(本番コード)は変更しない。 |
| `explorer` | プロジェクト内のコードベースを横断的に調べて「どこに何があるか」「この機能は実装済みか」「今どうなっているか(現状把握)」「この種の実装はどうやっているか」「影響範囲はどこか」を返す読み取り専用サブエージェント。広いファンアウト探索向き。結論(要点+path:line)だけ返し、ファイル全文は出し過ぎない。設計・実装の前の所在確認・実装済み確認・現状把握・規約把握・影響調査に使う。(プロジェクト外のWeb調査は yosage-dev-harness:researcher。) |
| `implementer` | 実装を担当する作業部隊サブエージェント。worktree で隔離し、割り当てられた1つの作業単位(Sub-issue 等)を規約に従って実装→検証→commit/push→draft PR まで行い、レビュー指摘に対応し、学びを蓄積する。orchestrate-parallel の管理者(司令塔)がディスパッチする。詰まったら回らずに停止して報告する。 |
| `librarian` | 蓄積された知識ベース(.claude/knowledge + 同期されたグローバル知識)から、与えられたドメイン/問いに関連するものだけを選り分け、要約(digest)にして返す司書サブエージェント。膨大な知識を呼び出し元(worker)の文脈に載せず、隔離した文脈で検索・選別する。設計・実装・レビューの前に「このドメインで効く過去の判断・落とし穴・パターンを集めて」と頼むときに使う。読み取り専用。 |
| `researcher` | プロジェクト外の技術調査を行うサブエージェント。実装のベストプラクティス、ライブラリの使い方、定番/よく使われるライブラリ探し、選択肢の比較などを Web で調べ、出典(URL)付きの digest を返す。プロジェクトの既存依存も確認して現実的な推奨にする。「どうやるのが定石？」「このライブラリの使い方」「定番ライブラリある？」「A と B どっち？」のときに使う。読み取り中心。(プロジェクト内のコード調査は yosage-dev-harness:explorer。) |
| `test-writer` | 変更に対するテストを作成・補強するサブエージェント。既存のテスト規約・パターンに従い、抜けているケースを洗い出して書き、実行して通す。実装後にテストを足したい/カバレッジを上げたいときに使う。テストのみを扱い、テストを通すために本番コードやテストを安易に弱めない。 |

### rules (harness)

| rule | 見出し |
|---|---|
| `agent-watchdog` | agent watchdog（不変条件） |
| `change-lanes` | 変更レーン定義（不変条件） |
| `commit` | コミット / PR タイトル規約（不変条件） |
| `design-routing` | 設計ルーティング / 討議着火ゲート（不変条件） |
| `doc-placement` | doc / 設計の置き場（不変条件） |
| `grounding-labels` | 接地ラベル（不変条件） |
| `implement-routing` | 実装ルーティング / dispatch（不変条件） |
| `issue-discipline` | issue 規律（不変条件） |
| `knowledge` | knowledge loop（不変条件） |
| `naming` | 命名の優先順位（不変条件） |
| `pr-loop` | PR 標準ループ（不変条件） |
| `project-profile` | project-profile（不変条件） |
| `sensitive-data` | センシティブデータ取り扱い（不変条件） |
| `visual-design-routing` | visual-design-routing（不変条件） |
| `worktree-placement` | 割り当て作業ツリーの置き場（不変条件） |

### hooks

| hook | description |
|---|---|
| `commit-trailer-notice.sh` | PostToolUse(Bash) フック: commit 時点での Co-Authored-By 署名トレーラ欠落に気づかせる。 背景: squash しない運用ではコミットは履歴に残る。マージ前に署名トレーラの欠落が判明すると 「push 済み履歴の書き換え(force push)」という取り消し不能な操作をしないと直せない状況が 生まれる(実際に、統制側がこの状況に直面して push 済みブランチの履歴を人間の確認なしに 書き換えてしまった事故がある)。トレーラの欠落を commit の時点で捕まえられれば、この状況 そのものが生じない。 なぜハードブロックしないか: トレーラの要否は無条件ではない。ルール `commit`の 「Co-Authored-By 署名トレーラ」節が正本で、コミット先リポジトリの所有(自社所有か)と、 自社所有でない場合は project-profile の開示宣言の有無で分岐する。この判断材料(所有・開示宣言) は導入先固有の事実であり、このフック(全 install 先へ配布される汎用スクリプト)は機械的に 持たない。無条件に強制すると規約(自社所有でない・未宣言なら「付けない」が既定)に反するため、 hard block ではなく additionalContext で気づかせるだけに留める(判断は commit.md の条件に 従って actor/人間が行う)。 なぜコマンド文字列を静的パースせず実際の HEAD を読むか: このハーネス自身のコミット規約は 複数行メッセージを heredoc 経由で組み立てる(git commit -m "$(cat <<'EOF' ... EOF)")。 guard.sh の fold_quotes_and_heredocs はセグメント分割の安全のため heredoc 本体を意図的に 空行化する((D)節のコメント参照)ため、コマンド文字列の静的パースではメッセージ本文 (トレーラを含む)を復元できない。実際に作られたコミットの HEAD を読めば、シェル展開・ heredoc・複数 -m の連結など、どの書き方で組み立てられたメッセージでも一律に正しく検査できる。 判定は「直近に作られたコミットが古いままトレーラを欠いていないか」に限定する(cwd 配下の git リポジトリの HEAD)。commit 以外の Bash 呼び出しにも毎回発火するが、以下の安価な前置 フィルタ(コマンド文字列に "commit" という文字列が含まれるか)で大半を早期に抜け、 実際に git を呼ぶのは commit らしき呼び出しの直後だけに絞る(セッション全体のオーバーヘッドを 抑える。厳密な構文判定ではなく best-effort の前置フィルタ)。 |
| `format.sh` | PostToolUse(Edit/Write/MultiEdit) フック: 編集されたファイルを言語に応じて自動整形する。 方針: best-effort。フォーマッタ未導入や失敗でもセッションは止めない(常に exit 0)。 |
| `grounding-check.sh` | PostToolUse(Edit/Write/MultiEdit) フック: 設計ドキュメントの接地チェック。 grounded-design の `path:line` 引用(= "実在する" という主張)を検証する。 引用先が存在しない/行数が足りない = ハルシネーション(偽の接地)の疑い。 additionalContext で Claude に自己修正を促す(非ブロッキング。編集は失敗扱いにしない)。 設計ドキュメント以外、または引用が無ければ無反応(ノイズゼロ)。 |
| `guard.sh` | PreToolUse(Bash / Edit/Write/MultiEdit / Read/Grep) フック: Bash: 破壊的・危険なシェルコマンドを実行前にブロックする。 Edit/Write/MultiEdit: worktree 隔離サブエージェントが割り当て worktree 外へ書き込むのを防ぐ (下記 (I) セクション)。 Read/Grep: 秘密ファイル(.env系/*.pem/*.key/id_rsa/secrets/**)の読み取りを遮断する (下記 (K) セクション)。 ブロック時は exit 2 + 理由を stderr へ(Claude に届く)。問題なければ exit 0。 解除の手段(env opt-out)は持たない: 止まったら報告して止まり、本当に必要な操作は人が 自分のターミナルで行う。 ここは「最後の安全網」。粗いマッチで十分(細かい許可制御は settings の permissions 側)。 |
| `inject-check.sh` | inject-check.sh — SessionStart(matcher なし)で1回、ルール注入の前提を確認する。 背景: SubagentStart での注入が失敗しても、利用者からは見えない(サブエージェント自身の会話記録 にしか出ない)。セッション開始時にメインで前提を確認し、問題があれば利用者に見える形(標準エラー 出力の "hook error")で知らせる。 確認すること: (a) jq か python3 のどちらかがある(無いと inject-rule.sh は SubagentStart への注入ができない)。 (b) harness/rules/*.md がすべて読める(1本でも読めなければ、そのルールは注入できない)。 「hooks.json に載っている全ルール」は hooks.json 自身を読まずに harness/rules/*.md の一覧で 代える(jq が無い環境でも本チェック自体が動くように)。hooks.json とルール一覧の一致は test/suites/91-inject.sh の静的テストで別途保証する。 利用者に見えるのは標準エラー出力の1行目だけ(hook error の表示は先頭行しか出ないため)。 1行目だけで意味が通る文にする。問題が無ければ何も出さず exit 0。 |
| `inject-rule.sh` | inject-rule.sh — 常時オンのルール1本を SessionStart/SubagentStart フックで注入する。 背景: プラグインは CLAUDE.md を配れない(プラグイン直下の CLAUDE.md は読まれず、常時オンの 規律を配る正規の手段が無い)。ルール `knowledge` の判断どおり、導入先へファイルを写さず SessionStart(メイン)・SubagentStart(サブエージェント)のフックで注入する。1ルールにつき1フック (1フックの出力の上限は1万字だが、フックごとに別計上され複数フックの出力はすべて届く。同じ イベントのフックは並行に走り届く順序が保証されないため、1つのルールを途中で切らない)。 使い方(hooks.json の args から): bash inject-rule.sh <SessionStart/SubagentStart> <rule-name> 標準入力(フックの入力 JSON)は使わないが、読み切ってから終了する(パイプの詰まりを避ける)。 |
| `knowledge-index.sh` | PostToolUse(Edit/Write/MultiEdit) フック: knowledge エントリ変更時に生成器(lib/knowledge-index.sh)を 検証だけのモード(`--check`)で毎回走らせ、併せて編集された1エントリの構造的欠陥を lib/knowledge-audit.sh で監査する。project-local の INDEX.md/INDEX.archive.md は生成物として 持たない(ローカル索引は廃止済み。recall は `knowledge-index.sh --list`/`--list-archive` の 直接列挙が主経路。ルール `knowledge` の「ローカル索引は任意のキャッシュ」節)。本フックの 目的は、project-local ストア(`.claude/knowledge` 固定)配下の `<domain>/*.md` が変わるたびに 生成器を走らせて宣言部(frontmatter)の書式検証(壊れた summary の検出等)を効かせること。 グローバル側の `global/INDEX.md` は同期(knowledge-sync.sh)が生成する対象であり、本フックは project-local だけを対象にするため関与しない。 best-effort: 対象外/python3 非在は何もしない(exit 0)。 生成器の失敗(exit 非0)、生成器の警告(exit 0 だがこの1ファイルに関する stderr 警告あり)、 または構造監査でこの1ファイルに欠陥が見つかった場合、stdout に systemMessage(ユーザー向け 警告)と hookSpecificOutput.additionalContext(Claude 向け: 再生成/修正をやり直させる指示) の両方を返して可視化する(欠陥が無ければ無出力)。 構造監査の check 全種のうち dangling-link(check4)だけは、この書き込み時の報告からは除く (理由・代償は下の audit_lines 算出箇所のコメント参照。この絞り込みは監査本体 (lib/knowledge-audit.sh)には手を入れず、ここでの報告フィルタとしてのみ行う)。dangling-link は まとめて走らせる監査(`yosage-dev-harness-knowledge-audit .claude`)では引き続き報告される。 |
| `knowledge-sync.sh` | SessionStart フック: グローバル知識ストアを best-effort で取得・反映する。 セッション開始を遅らせないよう既定では **非ブロッキング**(バックグラウンド)で lib を回して 即 exit 0 を返す。`--foreground` を渡すと、lib の完了を待ってから exit する(前景実行)。 手動でキャッシュ状態を確認・再同期したい場合や、結果を待ってから次の処理へ進みたい場合に使う (例: このスクリプト自身のテスト。test/suites/35-knowledge.sh は `.sync-log` 等の同期結果を 直後に検証するため、非同期のポーリング待ちを避けてこのオプションで呼ぶ)。 opt-in/オフライン/失敗の判定は lib 側(無効なら何もしない)。 同期ライブラリは自分自身の位置から見つける(target のインストール済みディレクトリ配下の lib を読みに行かない — プラグイン内の hooks/knowledge-sync.sh から見て `../lib/knowledge-sync.sh` がプラグイン内の lib/knowledge-sync.sh に一致する、という相対関係だけに依存する)。 |
| `notify.sh` | Notification / Stop / SubagentStop フック: Discord/Slack へフラット通知を webhook POST する。 設定は単一ファイル `.claude/yosage-dev-harness.local.json`(harness/lib/config.sh 経由)。 設定用の環境変数は読まない(利用者が変えた項目だけを設定ファイルに書く運用にするため)。 webhook URL 未設定なら無音 exit 0(opt-in by URL。base に既定配線しても無影響)。 POST 失敗・依存欠如でも hook 全体を落とさない(通知はベストエフォート。常に exit 0)。 ydh_config_get の戻り値が 3(jq/python3 無し)・4(設定ファイルが壊れた JSON)でも同様に 何もせず exit 0(best-effort。セッションを止めない)。 provider 差は payload キーで吸収(Slack: text / Discord: content)。判別は URL ホスト名 (プロキシ等で崩れる場合は provider 明示指定で上書き)。 |

### 実行ファイル

| コマンド | description |
|---|---|
| `yosage-dev-harness-base-branch` | yosage-dev-harness-base-branch — lib/base-branch.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-config-get` | yosage-dev-harness-config-get — lib/config-get.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-detect-stack` | yosage-dev-harness-detect-stack — lib/detect-stack.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-doc-drift-check` | yosage-dev-harness-doc-drift-check — lib/doc-drift-check.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-ensure-worktrees-ignore` | yosage-dev-harness-ensure-worktrees-ignore — .claude/worktrees/.gitignore だけを確認/作成/書き換える。 |
| `yosage-dev-harness-epic-cleanup` | yosage-dev-harness-epic-cleanup — lib/epic-cleanup.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-epic-implement-probe` | yosage-dev-harness-epic-implement-probe — lib/epic-implement-probe.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-epic-scope-resolve` | yosage-dev-harness-epic-scope-resolve — lib/epic-scope-resolve.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-gh-issue-resolve` | yosage-dev-harness-gh-issue-resolve — lib/gh-issue-resolve.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-gh-review` | yosage-dev-harness-gh-review — lib/gh-review.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-gh-subissue-link` | yosage-dev-harness-gh-subissue-link — lib/gh-subissue-link.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-knowledge-audit` | yosage-dev-harness-knowledge-audit — lib/knowledge-audit.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-knowledge-convert-paths` | yosage-dev-harness-knowledge-convert-paths — lib/knowledge-convert-paths.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-knowledge-index` | yosage-dev-harness-knowledge-index — lib/knowledge-index.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-knowledge-store-check` | yosage-dev-harness-knowledge-store-check — lib/knowledge-store-check.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-knowledge-template` | yosage-dev-harness-knowledge-template — lib/knowledge-template.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-promote-collect` | yosage-dev-harness-promote-collect — lib/promote-collect.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-scratch` | yosage-dev-harness-scratch — lib/scratch.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-setup` | yosage-dev-harness-setup — 導入先に守りに必要な最小のものだけを書き込む。 |
| `yosage-dev-harness-status` | yosage-dev-harness-status — 既定値と今の値を並べて見せる(書き込まない)。 |
| `yosage-dev-harness-sync-labels` | yosage-dev-harness-sync-labels — lib/sync-labels.sh の入口(名前で呼ぶ。パスを書かない) |
| `yosage-dev-harness-update` | yosage-dev-harness-update — setup の手順2〜5(設定ファイルは作らない・項目も書き足さない)。 |
| `yosage-dev-harness-update-base` | yosage-dev-harness-update-base — lib/update-base.sh の入口(名前で呼ぶ。パスを書かない) |
<!-- END yosage-dev-harness catalog (generated) -->

## 開発者向け

このリポジトリ自身を開発するときの手順（プラグインの利用者向けではない）。

- **テスト**: `bash test/run.sh`（自己テスト一式。payload を変えたら必ず通す）。
- **機能カタログの再生成**: `bash scripts/catalog.sh --write`（上記「機能カタログ」区間を
  `harness/` から再生成する。`--check` は再生成した内容と README の区間を比較し、不一致なら exit 1）。
- **ローカルのディレクトリを開発用マーケットプレイスとして読む**: 開発用リポジトリでは、直下の
  `.claude-plugin/marketplace.json` が `yosage-dev-harness-dev` という名前のマーケットプレイスを
  定義している（公開用リポジトリでは名前が `yosage-dev-harness` に書き換わる）。提供するプラグインの
  名前は配布用と同じ `yosage-dev-harness` なので、配布用と両方を同時に有効にしない。ローカルの
  作業ツリーをこの開発用マーケットプレイスとして追加するには:

  ```bash
  claude plugin marketplace add <このリポジトリの絶対パス> --scope local
  claude plugin install yosage-dev-harness@yosage-dev-harness-dev --scope local
  ```

- **公開面に issue/PR 番号を書かない決まり**: `harness/`・`scripts/`・`test/`・`README.md`・
  `.claude-plugin/` は公開面（identity 指紋スキャンが `test/run.sh` に組み込まれている）。経緯は
  コミットメッセージ・PR 本文に残す。
