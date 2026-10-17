---
name: epic-implement
description: Epic Issue 全体を実装する（人間トリガ）。Sub-issues を取得し依存解析して順次/並列で実装。スコープ無しなら全フェーズを人間の追加トリガ無しに完走、phase/Sub-issue リストを明示指定した場合のみそのスコープで停止。番号なしなら直前会話から類推し確認。
argument-hint: "[<epic-issue-number> | <owner>/<repo>#<epic-issue-number>] [phase<N> | #a,#b]"
disable-model-invocation: true
allowed-tools: Bash(yosage-dev-harness-epic-implement-probe *)
---

# Implement Epic Skill

Epic 全体のオーケストレーション。Sub-issues を依存関係に基づいて順次/並列で実装する。

## 動的コンテキスト

Epic Issue の内容（引数から Epic 番号を抽出。無ければ step 1 で会話から類推）:

!`yosage-dev-harness-epic-implement-probe epic "$ARGUMENTS" 2>&1`

Sub-issues の番号一覧（本文から抽出）:

!`yosage-dev-harness-epic-implement-probe subissues "$ARGUMENTS" 2>&1`

## 手順

### 1. Epic 情報の確認（引数の解釈・人間トリガ）

このスキルは**人間がトリガ**する（`disable-model-invocation: true` のまま＝重い phase 遷移は人が引く。正本 ルール `implement-routing`）。まず引数を解釈する:
- **Epic 番号**: 引数の数値、または `<owner>/<repo>#<N>`（cwd と異なるリポジトリの Epic を指すときに使う。動的コンテキストの番号解決は `yosage-dev-harness-gh-issue-resolve` と同じ判定ロジックを共有する `epic-implement-probe.sh` が行う）。
- **動的コンテキストの解決失敗は停止条件**: 上の動的コンテキストが「番号未指定 → step 1 で直前会話から類推・確認」以外の**エラーメッセージ**（scoped 形式が不正・ワークスペース直下での bare 番号拒否 等）を出している場合、そのエラーを抱えたまま会話からの類推へ進まない。**何が解決できなかったか**と**どう指定すればよいか**（動的コンテキストのエラー文言をそのまま提示すればよい）を示してユーザーに停止・確認する。**番号が本当に指定されていない**（「番号未指定」の案内文のみが出ている）場合に限り、直前の会話から類推し「Epic #<N> でよいか」を確認してから進む（明示指定があれば常に優先）。
- **スコープ**（任意・明示指定した場合のみ実行範囲を絞って停止する）: 優先順位は ① 明示 Sub-issue リスト（`#a,#b`）＞ ② フェーズ（`phaseN`）＞ ③ 依存ウェーブ（各 Sub-issue の依存から導出。フェーズ計画が無くても効く普遍フォールバック）。**① か ② を明示指定した場合**: そのスコープだけ実行して停止する（回帰させない・現状どおり）。**スコープ無し**（① ② いずれも未指定）の場合: フェーズ定義あり→**全フェーズを人間の追加トリガ無しに順に完走する**（ループの詳細は次項「全フェーズ完走時のループ（スコープ無しの場合のみ）」）／フェーズ無し→依存ウェーブ順に完走（現状どおり）。

**計画ドキュメント（`.epic_docs/<epic-name>/`）の不在検出（実装着手前・必須。スコープ/フェーズ引数の有無に関わらず、Sub-issue への dispatch より前に必ず1回実行する）**: Epic の分割方針が対話の中で固まっても、issue の起票だけが進み、計画ドキュメントが作られないまま実装段階に来ることがある。issue には書かれない情報（なぜその軸で分割したか・落とした別案の理由・スコープ外にしたものが必要になる契機・未決事項）は計画ドキュメントにしか残らないため、ここで確認する:

計画ドキュメントがブランチの上（Epic ブランチ）にだけあることがあるため、探す前に `git fetch origin` を行う（単一リポジトリの導入先では、計画は Epic ブランチへコミットされ、このセッションは既定ブランチにいることが多い）:

```bash
git fetch origin
yosage-dev-harness-epic-scope-resolve locate-docs <epic-name>
```

`git fetch origin` に失敗しても（オフライン・origin 無し等）警告にとどめて探索を続ける（手元の ref で探せる）。exit 1 になったときだけ、「fetch に失敗したため Epic ブランチの最新を見られていない」旨を添えて止める。

終了コードで「そもそも計画ドキュメントが無い」と「探索の前提が欠けている」を区別する（**両者を同じ扱いにしない**）:
- **exit 0**: 計画ドキュメントが作業ツリーに見つかった。下のフェーズ定義の探索へ進む。
- **exit 4（作業ツリーには無いが、Epic ブランチの上にある）**: **停止しない**。stdout の `<ref>:.epic_docs/<epic-name>`（`<ref>` は `refs/remotes/origin/epic/<epic-name>`、無ければ `refs/heads/epic/<epic-name>`）が計画の所在。計画の中身は `git show <stdout の値>/<ファイル>` で読む（作業ツリーへは展開されない・展開しない）。下のフェーズ定義の探索へ進む（exit 4 は「見つかった」の一形）。
- **exit 1（そもそも計画ドキュメントが無い）**: 作業ツリーにも Epic ブランチ（`origin/epic/<epic-name>`・`epic/<epic-name>`）にも `.epic_docs/<epic-name>/` が存在しない。**exit 1 だけが「計画が無い」**。**ここで停止し、ユーザーに確認する**（黙って依存ウェーブへ進まない）。
  - なぜ起票の工程ではなくここで確認するか: 起票時点では計画ドキュメントが無くても正当な場合（小さい Epic）があり、そこで警告すると毎回空振りする。分割の根拠・落とした案・未決事項は実装を割り当てる段になって初めて参照される＝**要る時点で要る**。
  - なぜ警告に留めず停止するか: この工程は人間がトリガする重い遷移であり、ここで一度止めても摩擦は一度きりで済む。警告に留めて素通りできる形にすると、起票時点で避けたはずの「空振りする警告」と同じ無視され方をこの工程でも辿りかねない。
  - 停止時はユーザーに「計画ドキュメントが見つからない。今から作るか、無いまま進めるか」を確認する。**無いまま進める判断が出た場合のみ**、フェーズ定義も無いものとして依存ウェーブへ進む（下記のフェーズ定義探索は行わない）。
- **exit 2（前提が欠けている）**: git リポジトリの外・epic-name 未指定。「そもそも無い」と混同せず、設定/呼び出しの誤りとして報告する（探索自体が実行できていないだけで、存在しないと決まったわけではない）。

**フェーズ定義の所在は cwd 直下に固定しない**（上の不在検出を通過し計画ドキュメントが見つかった場合のみ、以下へ進む）。計画ドキュメント（`.epic_docs/`）は、実装先リポジトリの外（ワークスペース側リポジトリ）に置かれることがある。フェーズ定義の有無・場所は次のコマンドで解決する（cwd から上へ辿って見つかる最も外側の git リポジトリの直下を見る。単一リポジトリの導入先では自分自身が最も外側になるため、従来どおり cwd 直下の `.epic_docs/` を見る＝後方互換）:

```bash
yosage-dev-harness-epic-scope-resolve locate-phase <epic-name> <phaseN>
```

このコマンドの終了コードで「計画はあるのに指定フェーズが見つからない」を判定する（**silent なフォールバックを避けるため、下記exit 3を「そもそも無い」と同じ扱いにしない**。上の不在検出を通過済みなのでこの呼び出しで exit 1 が返ることは通常無い。返った場合は不在検出との結果の食い違いであり、設定/呼び出しの誤りとして報告する）:
- **exit 3（あるのに見つけられない）**: `.epic_docs/<epic-name>/` は見つかったが指定フェーズのサブディレクトリが無い。フェーズ名の誤り・未作成の可能性があり、**黙って依存ウェーブへ落ちない**。ユーザーに状況（見つかった計画ドキュメントのパス・探したフェーズ名）を提示して確認する。
- **exit 2（前提が欠けている）**: git リポジトリの外・引数不足。設定/呼び出しの誤りとして報告する。
- **exit 0**: 見つかったフェーズディレクトリのパスを使って Sub-issue 一覧・検証条件を読む。
- **exit 4**: フェーズが Epic ブランチの上にある。stdout の `<ref>:.epic_docs/<epic-name>/<phaseN>` に対し `git show <stdout の値>/<ファイル>` で Sub-issue 一覧・検証条件を読む（`git ls-tree <stdout の値>/` でファイル一覧）。

上記の動的コンテキストから以下を把握する:

- Epic のスコープと目的
- Sub-issues の番号一覧（動的コンテキストが repo を解決できていれば `<owner>/<repo>#<N>` 形式で出力される。以降の手順・dispatch でもこの形式をそのまま使う）
- Epic ブランチ名（本文や既存ブランチから特定）
- **Sub-issue ごとの取り込み先**（各 Sub-issue 本文の `## 取り込み先`。Epic ブランチ／既定ブランチ（理由））。既定は Epic ブランチ。
  既定ブランチ向けは、計画の時点で「独立に取り込める・先に出す事情がある」と判断された例外。**書かれた取り込み先に従う**。
  **取り込み先の記載が無い Sub-issue があっても、推測で決めない**（旧い形で起票された Epic で起こりうる）。そのような Sub-issue の一覧を、
  次の「着火前に計画を提示」で示して、人に取り込み先を確かめてから進める
- **着火前に計画を提示**: 対象 Sub-issue・依存グラフ・ウェーブ・直列指定（`直列実行:`）・対象フェーズ／スコープ・**取り込み先の記載が無い Sub-issue の一覧（あれば）**を1度提示してから着手する。

**Sub-issues の番号一覧の完全性チェック（この一覧はスキル全体で使い回す共有入力・以降のすべての手順に効く）**:
「Sub-issues の番号一覧」動的コンテキストは `epic-implement-probe.sh` 内で、抽出直後にネイティブ
Sub-issue の集合（GraphQL）と突き合わせ済み（本文取得の失敗・突き合わせ自体の失敗・突き合わせの
相手が存在しない場合（ネイティブリンクが0件なのに本文抽出は非ゼロ）・本文からの抽出漏れのいずれも
検知する）。動的コンテキストの出力に **`(要確認)`** で終わる警告が含まれて
いる場合、その一覧を「対象ゼロ件」とみなさない——一覧が空・不完全である可能性を示す合図である。
この場合、**依存関係解析（手順2）・Sub-issue の並列/順次実装（手順4・5）・Epic issue のクローズ
確認（手順8）を含む、この一覧を使うすべての手順へ黙って進まず**、警告の内容をそのまま提示して
ユーザーに停止・確認する（着火前の計画提示より前に確認する）。`(要確認)` が無ければ、一覧（0件を
含む）をそのまま信頼して先へ進んでよい。

各 Sub-issue の状態を確認する（Epic が別リポジトリにある場合は `--repo <owner>/<repo>` を付ける）:

```bash
gh issue view <sub_number> [--repo <owner>/<repo>] --json number,title,state -q '"#\(.number) [\(.state)] \(.title)"'
```

**フェーズ（`phaseN`）または Sub-issue リストを明示指定して実行したときは、この時点（冒頭）で、前の実行で取り込み済みなのに
開いたままの Sub-issue を閉じる**（前のフェーズの PR を人がマージした後に、次のフェーズを指定して再開する流れで、閉じる契機が
他に無いため）。まず `git fetch origin` し、OPEN の各 Sub-issue について、取り込み先で確かめる先を分ける:
Epic ブランチ向けは `origin/epic/<epic-name>`、既定ブランチ向けは解決したベースの `origin/$base`。**この時点（手順3より前）で、
ベースを自分で解決する**（`$base` は別の Bash 呼び出しには残らないので、`$base` を使うブロックごとに冒頭で解決し直す。
解決の順と終了コードの扱いは ルール `pr-loop` の「ベースブランチ / クローズ / マージ」節）:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  # <n> は OPEN の Sub-issue。既定ブランチ向けのものだけ、origin/$base の履歴を確かめる
  git log "origin/$base" --format='%B' | grep -Fx "Closes #<n>"
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

その履歴にコミット末尾の `Closes #<n>` があれば取り込み済みなので、マージされた PR へのリンクを添えて閉じる。
確かめ方と閉じ方は手順7と同じ（手順7の確認ループ・`gh issue close <n> --comment`）。取り込めていないものは閉じない。
スコープ無しの完走では、この確認は手順7が行う。

上記の把握・計画提示が済んだら、**Sub-issues 着火前に Epic 全体 OQ ゲートを踏む**（ルール `implement-routing` 「実装入口 OQ ゲート」節—分類・surface・記録法の詳細はこの節が正本）。対象は **Epic 本文の `## Open Questions` / `## 補完・前提（要確認）` 節のうち Epic 全体に効く OQ**。deferrable の記録先は **Epic 本文の「## 仮定（実装中に検証）」節**（特定 Sub-issue にのみ効く仮定はその Sub-issue 側に置く）。

### 1a. 全フェーズ完走時のループ（スコープ無しの場合のみ）

**スコープ無し（phase 引数・Sub-issue リストのいずれも未指定）かつフェーズ定義がある場合**に適用する（フェーズ定義が無い Epic はそのまま依存ウェーブ順の完走に進む＝現状どおりで、本項の対象外）。① か ② を明示指定した場合（そのスコープだけ実行して停止する経路）も本項の対象外。

1. **フェーズ一覧を列挙する**（`phase1` 始まりとは限らない前提。`.epic_docs/<epic-name>/` 直下に実在する `phase<N>` サブディレクトリを番号の昇順で列挙する）:
   ```bash
   yosage-dev-harness-epic-scope-resolve list-phases <epic-name>
   ```
   出力は見つかったフェーズ名（例: `phase0` → `phase1` → `phase2` の順）を1行1件で返す。終了コードの意味は `locate-docs` と同じ（0=計画ドキュメント自体は作業ツリーで発見・4=Epic ブランチの上で発見（0件でも4。出力のフェーズ名の列挙は 0 のときと同じ形で、読むときは `git show` を使う）・1=そもそも計画ドキュメントが無い・2=前提が欠けている）。**0件の出力（フェーズ定義自体が無い）は「そもそも計画が無い」（終了コード1）とは別**——計画ドキュメントはあるがフェーズ分割していない Epic として扱い、依存ウェーブ順の完走へフォールバックする。
2. **列挙された順にフェーズを処理する**。各フェーズについて:
   - `yosage-dev-harness-epic-scope-resolve locate-phase <epic-name> <phaseN>` でそのフェーズのディレクトリを確認し、対象 Sub-issue を特定する（phase を明示指定して実行するときと同じ要領）。
   - そのフェーズの対象 Sub-issue に対して手順2（依存関係解析）を行う。
   - 手順4（依存なし Sub-issue の並列実装）・手順5（依存あり Sub-issue のスタック方式）でそのフェーズを実装する。**フェーズをまたぐ依存も手順5の仕組みでそのまま進めてよい**——先行フェーズの Sub-issue の PR がまだマージされていなくても、そのブランチを base にスタックすれば依存は満たされる（手順5は元々マージを待たない設計）。
   - **フェーズ間で人間の確認・レビュー待ちを挟まない**——このフェーズの実装・PR 作成が終わったら停止せずそのまま次のフェーズへ進む。
3. **全フェーズの処理が終わったら手順6（レビュー依頼）へ進み、その時点で初めて一括報告する**（フェーズごとの中間報告はしない）。

**無闇に完走を優先しない（メインの裁定ゲート）**: 完走ループの実行中に、Sub-issue の実装（`yosage-dev-harness:implementer`）から判断待ちとして停止報告が来た場合、または PR レビューで価値トレードオフ・スコープ判断の指摘が出た場合は、**完走ループ全体をそこで止め**、`grounded-design` Step3 の裁定分岐（客観的欠陥→標準に倒す／価値トレードオフ→recall に前例があれば適用・無ければ人間へエスカレーション）に従って対応する（`pr-loop.md`「指摘対応」節・`implement-routing.md`「実装入口 OQ ゲート」節は、いずれもこの Step3 をそれぞれの文脈—レビュー後／dispatch前—へ適用したものであり、本節が扱う「実装中・レビュー前にメインが停止報告を受け取る」場面はどちらの文字通りのスコープにも一致しないため、分岐の正本である Step3 を直接参照する）。対応が終わるまで次フェーズへは自動的に進まない。

### 2. Sub-issues の依存関係解析

各 OPEN な Sub-issue の本文を確認し、依存関係を解析する（Epic が別リポジトリにある場合は `--repo` を付ける）:

```bash
gh issue view <sub_number> [--repo <owner>/<repo>] --json body -q '.body'
```

依存関係グラフを構築:
- **依存なし**: 即座に並列実装可能
- **依存あり**: 先行 Sub-issue の完了後に実装

### 3. Epic ブランチの準備

Epic ブランチは**実装先リポジトリ**（Sub-issue が起票されているリポジトリ）で作成する。cwd がそのリポジトリと異なる場合（例: cwd がワークスペース側リポジトリ）、**git 操作の前に対象リポジトリのローカルチェックアウトへ移動する**（`cd <対象リポジトリのパス>`。存在しなければ用意する）。cwd が対象リポジトリと一致しているかは `git remote get-url origin` の owner/repo で確認できる。

**ベースブランチを解決する**（以降の手順の `$base`。ブランチ名を決め打ちしない。解決の順と終了コードの扱いは ルール `pr-loop` の「ベースブランチ / クローズ / マージ」節）。
**`$base` は別の Bash 呼び出しには残らない**ため、以降の手順で `$base` を使うブロックは、毎回その冒頭で同じ呼び方で解決し直す
（この手順3の次のブロックの形。`exit` でシェルを閉じず、`if` で分け、`$base` を使う処理は `then` 側に入れる。空の `$base` で進まない）。
投入時に明示されたベース、または導入先の profile の宣言があれば `--declared` に渡す（無ければ `--declared` を省く）:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  # ブランチの存在確認
  git ls-remote --heads origin epic/<epic-name>

  # 存在しなければ作成（取り込み先が Epic ブランチの Sub-issue がある場合のみ）
  git checkout -b epic/<epic-name> "origin/$base"
  git push -u origin epic/<epic-name>
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

決まらなければ（終了コード 1）止めて人に聞く。宣言したブランチが origin に無ければ（終了コード 3）宣言の誤りとして止める。

**Epic ブランチを作るのは、取り込み先が Epic ブランチの Sub-issue が1つでもあるとき**（正本は `epic-create-docs` 手順6）。ワークスペースで
全件が既定ブランチ向けなら作らない。通常は `epic-create-issues` が起票のときに作って push 済みなので、ここでは存在を確かめ、
**存在しなければ**解決したベースから作成する（上のブロックのとおり。存在しないときだけ作る）。

### 4. 依存なし Sub-issues の並列実装

依存関係のない Sub-issues を Agent で並列実装する。
**統制は `orchestrate-parallel` スキルに従う**（メイン＝司令塔）。特に:
- **対象ファイルが重なる Sub-issue は並列にしない**（直列化してコンフリクト回避）。
- **Sub-issue 本文に `直列実行:` 宣言があれば直列化**（ファイルが素に見えても。conflict-driven 判断を著者宣言で補完。honor は `orchestrate-parallel`）。
- 各エージェントを放置せず **watchdog に従って監視**（有界待ち＋ネット進捗。nudge → 無反応なら `TaskStop`。ルール `agent-watchdog`）。数十分の無音待ちを避ける。
- 統合（Epic ブランチへのマージ）は**1本ずつ**、コンフリクトはメインが解消（マージ戦略は ルール `pr-loop`）。

各ユニットは **`yosage-dev-harness:implementer` サブエージェント**で起動する（実装規律は yosage-dev-harness:implementer 定義に内蔵、手順は `epic-implement-subissue` に従う）。要点:

1. `gh issue view <number> [--repo <owner>/<repo>]` で Issue 内容を取得（dispatch する番号は把握した `<owner>/<repo>#<N>` 形式のまま yosage-dev-harness:implementer へ渡す）
2. Sub-issue 本文の取り込み先から sub-issue ブランチを作成する。**Epic ブランチ向け**は `origin/epic/<epic-name>` から。
   **既定ブランチ向け（例外）**は `origin/$base` から作り、PR は `--base "$base"` で作る（**メインが解決したベース**——投入時の明示、または導入先の profile の宣言を `--declared` に渡して `yosage-dev-harness-base-branch` で解決したもの——を、**投入指示に明示して渡す**。
   実装者は会話の文脈も profile の宣言も知らず、`$base` は別の Bash 呼び出しにも残らないので、渡された値を `--declared` に渡して解決し直す。渡す値が無いときは無いと書く）
3. Issue 本文の実装内容に従って実装（担当ファイル範囲外は触らない）
4. 検証方法が記載されていれば実行
5. コミット（`Closes #<number>` 付き。**Epic ブランチ向けでも末尾の `Closes #` は残す**。手順7が取り込みの確認に使う）
6. push → 取り込み先（Epic ブランチ、または既定ブランチ）向けに draft PR 作成。**PR 本文は取り込み先で分ける**: Epic ブランチ向けは
   `Closes #` ではなく「Part of #<epic_number>」と Sub-issue への参照を書く（PR 本文の `Closes #` は既定ブランチ向けの PR でしか
   解釈されない。Sub-issue は手順7で取り込みを確かめてから明示的に閉じる）。既定ブランチ向けは従来どおり `Closes #<number>`
7. PR URL を報告（詰まったら回らず停止して報告）

**取り込み先を途中で変えたくなったとき**（実装の途中で、独立に取り込めない・先に出す事情が無くなった・逆に先に出す事情ができた等）:
**黙って変えない**。ハーネス（メイン）が変更を**提案**し、理由とともに **Sub-issue にコメントで記録してから**従う。実装者が自分で
変えることはしない（実装者は統制側へ提案を返して止まる）。計画の取り込み先の記載（計画ドキュメント・Sub-issue 本文）も、記録のとき併せて直す。

**worktree 隔離（`isolation="worktree"`）が使えるのは、実装先が cwd を含むリポジトリと同じ場合だけ**（既定・多くのケース）。

**Epic issue（と Sub-issue）が cwd と別のリポジトリにある構成では `isolation="worktree"` を使わない**。理由:
- worktree 隔離は、dispatch 時点の作業ディレクトリを含むリポジトリに worktree を作る（セッション開始時のディレクトリが固定というわけではなく、dispatch する瞬間の作業ディレクトリで決まる）。
- 実装先が別リポジトリだと、その worktree から実装先へ**到達できない**。ワークスペース構成では、メンバーリポジトリはワークスペース側リポジトリの追跡対象外（gitignore 済み）であることが多く、作られた worktree にはメンバーリポジトリのディレクトリそのものが**存在しない**。
- 「隔離できない」だけでは足りない。到達できない状態で実装を指示すると、実装エージェントに残る選択肢は「見つからず停止する」か「共有チェックアウトへ絶対パスで到達して作業する」のどちらかになり、**後者はこのリポジトリが繰り返し扱ってきた事故経路そのもの**（隔離した作業者が共有チェックアウトを書き換える）。**隔離を指定したことが、かえってその経路へ誘導する。**

cross-repo 構成での代替（メイン=司令塔が行う）:
1. `git worktree add` の前に、対象リポジトリのルートに対して `yosage-dev-harness-ensure-worktrees-ignore <対象リポジトリのルート>` を実行する（`.claude/worktrees/.gitignore` を用意し、後続の作業ツリーが誤って追跡対象にならないようにする）。続けてメインが対象リポジトリのローカルチェックアウト内で `git worktree add <絶対パス> <sub-issue-branch>` を実行し、専用の作業ツリーを用意する（`isolation` パラメータは指定しない）。**`<絶対パス>` の置き場は [[worktree-placement]] が正本**（本節では再記述しない）。
2. Agent への指示（プロンプト）に、その**絶対パス**を「あなたに割り当てられた作業ツリーはここです」と明示して渡す。指示には「このディレクトリの外を編集しない」「割り当てられたパスが対象リポジトリの構造を持つか着手前に確認し、違えば停止して報告する」を含める（ルール `agent-watchdog` の停止規律と同じ扱い）。
3. 統合（Epic ブランチへのマージ）・クリーンアップは、その対象リポジトリのローカルチェックアウトに対して行う。

```
Agent(
  description="Implement sub-issue #<number>",
  prompt="...",
  isolation="worktree",  # cross-repo 構成では指定しない（上記の代替手順に従う）
  run_in_background=true
)
```

### 5. 依存あり Sub-issues の順次実装（スタック方式）

先行 Sub-issue の PR が作成されたら、**マージを待たずに**依存する Sub-issue の実装へ進む。依存は
先行ブランチの base で満たされる（先行の成果物が既にそこに在る）。ハーネスからマージすることは
できない（ルール `pr-loop`）ため、この形を使う。

- 依存する Sub-issue のブランチは、**Epic ブランチではなく先行 Sub-issue のブランチから**作成する。
- **PR の base も先行 Sub-issue のブランチにする。** base が先行ブランチを指すこと自体が、どの PR が
  どの PR に依存しているかを成果物（PR）から読み取れる形にする。
- **依存チェーンの根（他に依存されていない先頭 Sub-issue）だけは、手順4と同じく取り込み先（Epic ブランチ、
  または既定ブランチ向けの例外なら `$base`）を base にする**（根を手順4に合わせて整合を保つ）。
- 作成直後に base の指定を確認する（機械的に確認できる操作）:
  ```bash
  gh pr view <依存する Sub-issue の PR番号> --json baseRefName -q .baseRefName
  ```
  出力が先行ブランチ名と一致しなければ、そのまま進まず修正する。

**マージ順序（手順6の報告に必ず含める）**: 積んだ PR は Epic ブランチに近い側（依存されている側）から
順に人間がマージする。

**base の自動付け替えを前提にしない**——GitHub は先行ブランチの**削除**を引き金に、積んだ PR の base を
その先行ブランチが向いていた先へ自動で付け替えるが、リポジトリ設定でマージ時のブランチ自動削除が
無効だと発火しない（実例: 本案件で自動削除が無効なリポジトリに積んだ PR を連続マージしたところ
付け替えが起きず、後続 PR が意図した統合先ではなく先行ブランチへマージされ、復旧のための PR を
別途立てることになった）。したがって**次の PR をマージする前に、都度 base を確認する**（上と同じ
`gh pr view --json baseRefName`）。付け替わっていなければ、マージする前に base を手動で正しい対象へ
変更する。**順序を間違えると、後続の変更が意図した統合先へ反映されないまま「マージ済み」に見える**
——取り込み後は差分が実際に統合先へ入ったかを確認し、反映されていなければ先行ブランチから統合先への
PR を別途立てて復旧する。

**既定ブランチへ直接入れた Sub-issue に、後の Sub-issue が依存する場合（既定ブランチ → Epic ブランチの同期）**:
依存先が既定ブランチ向けの Sub-issue で、依存する側が Epic ブランチ向けなら、**依存する Sub-issue を投入する前に**、既定ブランチを Epic ブランチへ
取り込む（既定ブランチに入った成果物を Epic ブランチの上に載せるため）。**既定ブランチ側は人がマージ済みであること**を `origin/$base` の履歴の
`Closes #<依存先>` で確かめてから行う。**直接 push しない**。`$base` から Epic ブランチへの PR を作り、人がマージする:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  gh pr create --draft \
    --base epic/<epic-name> \
    --head "$base" \
    --assignee @me \
    --title "chore: $base を epic/<epic-name> へ取り込む(同期)" \
    --body "Part of #<epic_number>

既定ブランチへ直接入れた Sub-issue (#<依存先>) の成果物を Epic ブランチへ取り込む同期。人がマージする。

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

人がこの PR をマージしてから、依存する Sub-issue を投入する（Epic ブランチ向けの Sub-issue の base は `epic/<epic-name>`）。
作成直後に `gh pr view <PR番号> --json baseRefName -q .baseRefName` が `epic/<epic-name>` と一致することを確かめる。

**Epic の PR（draft）が無ければ作る**: Epic ブランチへ**最初の Sub-issue が取り込まれた時点**（手順7、またはフェーズ指定の実行の冒頭で
取り込みを確かめたとき）で、既定ブランチへの Epic の PR がまだ無ければ draft で作る（ワークスペースの経路。単一リポジトリでは
`epic-create-issues` が起票のときに作成済み）。取り込み漏れの受け皿になる（途中で流れが止まっても、開いたままの PR として見える）:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  # 既にあるかを先に確かめる（あれば作らない）
  gh pr list --head epic/<epic-name> --base "$base" --state open --json number,url,isDraft
  # 無ければ作る（作成後の base の確認は、返った URL を `gh pr view "<URL>" --json baseRefName -q .baseRefName` で行い、$base と一致させる）
  gh pr create --draft \
    --base "$base" \
    --head epic/<epic-name> \
    --assignee @me \
    --title "Epic: <タイトル>" \
    --body "## Summary

Epic #<epic_number> の全実装を取り込む。

Part of #<epic_number>

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

ワークスペースで Epic ブランチを作らない Epic（全件が既定ブランチ向け）では、この PR も作らない。

### 6. レビュー依頼

**スコープ範囲の** Sub-issues の PR が作成されたら**停止し**、ユーザーにレビュー依頼を報告する。報告のタイミングと次の一手はスコープの種別で変わる:
- **phase / Sub-issue リストを明示指定して実行した場合**（そのスコープだけ実行して停止する経路）: そのスコープの PR が揃った時点で報告し、次フェーズがあれば「次は `/yosage-dev-harness:epic-implement <N> phase<k+1>`」を提案する（次の人間トリガ）。
- **スコープ無しで完走した場合**（フェーズ定義の有無を問わない）: 「全フェーズ完走時のループ」（手順1a）に従い、全フェーズ・全 Sub-issue の実装が終わった時点で初めて一括報告する（フェーズごとの中間報告はしない・次フェーズの提案も不要）。

```
## 実装完了報告

以下の PR をレビューしてください:

- [ ] #<pr_number> <タイトル>
- [ ] #<pr_number> <タイトル>
...
```

手順5でスタックした（依存あり）Sub-issue が含まれる場合は、**マージ順序**（Epic ブランチに近い側から）
を上の報告に明記する。

### 7. 取り込みの確認と Sub-issue のクローズ → ドキュメント反映 → Epic PR（draft を一次レビュー → ready）

以降の `gh pr` / `git` 操作は**手順3で用意した対象リポジトリのローカルチェックアウト内**で行う（cwd が対象リポジトリと異なるままだと別リポジトリの PR/ブランチを誤って操作しうる）。

全 Sub-issues の変更が取り込み先に入っていることを確認する（Epic ブランチ向けは Epic ブランチ、既定ブランチへ直接入れたものは `origin/$base`）。**base で絞り込む確認
（`gh pr list --base epic/<epic-name> --state open`）は、手順5でスタックした PR（base がまだ
先行ブランチのままの間）を取りこぼす**ため使わない。代わりに、**手順1で取得済み・完全性照合済みの
Sub-issue 番号一覧**を使い、各番号のコミット（`Closes #<n>` トレーラ。コミットは squash されない
運用のため履歴にそのまま残る）が Epic ブランチの実際の履歴に入っているかを確認する:

```bash
git fetch origin
_epic_closes="$(git log origin/epic/<epic-name> --format='%B' | grep -E '^Closes #[0-9]+$')"
for n in <sub-issue番号...>; do
  if ! printf '%s\n' "$_epic_closes" | grep -Fxq "Closes #$n"; then
    echo "Sub-issue #$n の変更が Epic ブランチの履歴に見当たらない(未マージの可能性)" >&2
  fi
done
```

**既定ブランチへ直接入れた Sub-issue**（取り込み先が既定ブランチの例外）は、同じ確認を `origin/$base` の履歴に対して行う
（ベースはこのブロックの冒頭で解決し直す）:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  _base_closes="$(git log "origin/$base" --format='%B' | grep -E '^Closes #[0-9]+$')"
  for n in <既定ブランチ向けの sub-issue番号...>; do
    printf '%s\n' "$_base_closes" | grep -Fxq "Closes #$n" \
      || echo "Sub-issue #$n の変更が origin/$base の履歴に見当たらない(未マージの可能性)" >&2
  done
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

**確かめられた Sub-issue は、マージされた PR へのリンクを添えて、統制側が明示的に閉じる**（Epic ブランチ向けの PR は本文に `Closes #` を
持たず自動では閉じない。ルール `pr-loop`）。すでに閉じていれば何もしない:

リンクする PR は、**その Sub-issue 自身の PR**を選ぶ（同期の PR や、依存する側の Sub-issue の PR ではないもの）。条件は、
head のブランチがその Sub-issue のブランチであるか、その PR のコミット末尾に `Closes #<n>` があること。同期の PR（head が既定ブランチ）と
Epic の PR（head が Epic ブランチ）は除く。本文に `#<n>` が書かれているだけの PR は選ばない。
**一覧の取得に `commits` を含めない**（`gh pr list --json ...,commits` は GraphQL の上限（50万ノード）を超えて、件数を絞っても失敗する）。
まず head のブランチで引き、引けなかったときだけ、候補の PR を1件ずつ `gh pr view <番号> --json commits` で見る:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  # <n> は上の確認で履歴に見つかった Sub-issue、<sub-issue-branch> はその Sub-issue のブランチ
  _cands="$(gh pr list --state merged --limit 200 --json number,url,headRefName \
    | jq -r --arg base "$base" --arg epic "epic/<epic-name>" '
        .[] | select(.headRefName != $base and .headRefName != $epic)
            | "\(.number)\t\(.url)\t\(.headRefName)"')"
  _pr_url="$(awk -F'\t' -v b="<sub-issue-branch>" '$3 == b {print $2; exit}' <<< "$_cands")"
  if [ -z "$_pr_url" ]; then
    while IFS=$'\t' read -r _num _url _head; do
      [ -n "$_num" ] || continue
      if gh pr view "$_num" --json commits -q '[.commits[].messageBody] | join("\n")' | grep -Fxq "Closes #<n>"; then
        _pr_url="$_url"; break
      fi
    done <<< "$_cands"
  fi
  if [ -z "$_pr_url" ]; then
    echo "Sub-issue #<n> 自身のマージ済み PR が引けない: リンク無しでは閉じない" >&2
  elif [ "$(gh issue view <n> [--repo <owner>/<repo>] --json state -q .state)" = "OPEN" ]; then
    gh issue close <n> [--repo <owner>/<repo>] --comment "取り込み済み: $_pr_url"
  fi
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

その Sub-issue 自身の PR が引けなければ、リンク無しでは閉じず、人に確かめる。
**Epic ブランチへ最初の Sub-issue が取り込まれたことを確かめた時点で、Epic の PR（draft）がまだ無ければ作る**（手順5の末尾「Epic の PR（draft）が無ければ作る」）。

（`grep -Fx` で行全体を厳密一致させる。単純な部分一致だと、短い番号の `Closes #<n>` 行が、その番号を
前方一致に含むより長い番号の行（例: 1桁の番号が、それを含む2桁の番号）に誤って一致しうる。）

**この確認が保証するのは「対象コミットが Epic ブランチの履歴に一度でも入ったこと」だけである。内容が
現在のツリーに実際に残っているかは保証しない**（後続の変更が同じ領域を衝突なく上書きした場合・当該
コミットが後から取り消された（revert）場合のいずれも、履歴には残るため見逃す）。また、旧方式が拾えて
いた「Sub-issue 番号一覧に無い想定外の open な PR」はこの確認では見ない（一覧を起点にするため）。

**Epic PR の前に docs をまとめて反映**。docs 更新はこの Epic 完了段階で行う方針（途中の手戻り回避）。
実装部隊は分散済み・管理者は差分を抱えない方針なので、**`yosage-dev-harness:doc-writer` サブエージェントに委譲**する:
- `yosage-dev-harness:doc-writer` に **Epic ブランチ ＋ 各 sub-issue の `Docs-impact:` ＋ `<base>`**（メインが解決したベース。`agents/doc-writer.md` が要求する。会話の文脈を持たないので投入指示に明示して渡す）を渡す。yosage-dev-harness:doc-writer が
  `doc-drift-check.sh` → `sync-design-docs`(derive→verify) → `docs:` コミットまで隔離文脈で行い、更新の digest を返す。
- 管理者は digest を受け取って Epic PR へ進む（doc 変更の中身は Epic PR で人間がレビュー）。

全てマージ済み・docs 反映済みなら、**Epic の PR を新しく作らない**。起票のとき（単一リポジトリ）または最初の取り込みのとき（ワークスペース、手順5）に
作った **draft の Epic PR** を使い、本文を現在の状態（Docs の記載と Sub-issues のチェック）に更新する:

```bash
gh pr list --head epic/<epic-name> --state open --json number,url,isDraft,baseRefName
gh pr edit <Epic PR番号> --body "## Summary

Epic #<epic_number> の全実装を取り込む。

Part of #<epic_number>

Docs: <更新あり 対象 / 更新不要 理由>

## Sub-issues

- [x] #<number> <タイトル>
...

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

**draft の Epic PR が見つからなければ**（起票がこの形になる前の Epic 等）、解決したベースへ向けて draft で作る。ベースはこのブロックの冒頭で解決し直し、
作成後に base が `$base` と一致することも同じブロックで確かめる（本文は上と同じ）:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  if pr_url="$(gh pr create --draft --base "$base" --head epic/<epic-name> --assignee @me --title "Epic: <タイトル>" --body-file <上と同じ本文のファイル>)"; then
    [ "$(gh pr view "$pr_url" --json baseRefName -q .baseRefName)" = "$base" ] \
      || echo "Epic の PR の base が $base と一致しない: 修正する" >&2
  fi
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

**Epic PR の一次レビュー（whole-Epic の品質チェック）**:
**標準PRループに従う**（ルール `pr-loop` — 常時オンの正本）。sub-issue は個別レビュー済みだが、Epic PR は **全体が組み上がった姿**。以下は Epic PR 固有の点:
- 管理者が Epic PR の URL を渡してレビューさせ、指摘は **Epic PR にコメント**で残す:
  - `yosage-dev-harness:code-reviewer` — 統合後の正しさ・回帰・cross-cutting な問題。
  - `yosage-dev-harness:consistency-reviewer` — 組み上がった全体の既存逸脱・ハルシネーション、**doc↔コードの整合**。
  - `yosage-dev-harness:architect`（規模が大きい/構造的な Epic のとき）— 組み上がりが `.docs/architecture` と Epic の目的・スコープを満たすか。
- 要修正なら対応（必要なら該当 sub-issue を追修正）→ 再レビュー（2〜3 往復で収束しなければ人間へエスカレーション）。
- **通らない/スコープ外の指摘は GitHub issue として起票**して追跡する（落とさない。起票はスキル `issue-create`・ルール `issue-discipline` に従う）。Epic にリンク/言及する。
- 解消したら、この **draft の Epic PR を `gh pr ready`** で draft 解除 → 人間にレビュー＆マージを依頼。

### 8. Epic の完了確認（Epic の PR・状態1・状態3）

**契機**: 人間から Epic PR が実際に既定ブランチへマージされたと確認できた時点（手順7で draft を ready
にした直後ではない）。**Epic の完了時に必ず満たす状態**を確かめ、**満たさないものがあれば案内して止まる**（Epic issue を閉じない）:

0. **Epic の PR がマージ済み**: `gh pr view <Epic PR番号> --json state,isDraft,mergedAt`。**draft のまま残っていれば止めて案内する**
   （「Epic の PR が draft のまま。一次レビューを終えて ready にし、人がマージする」）。Epic ブランチに変更が1つも入らないまま完了する場合
   （ワークスペースで全件が既定ブランチ向けなら Epic ブランチ自体を作らない。通常は起きない）は PR が無く、Epic ブランチが残っていれば
   消して完了とする。
1. **計画ドキュメントが合流している**: 単一リポジトリでは Epic の PR で既定ブランチへ入っている（下のブロックで確かめる。
   中身が計画だけでも出す）。ワークスペースでは、計画に実装との差分（変えた判断・やらなかったこと）が追記され、ワークスペース自身の
   流れで反映されていること（追記の有無を計画で確かめ、無ければ追記を案内して止まる）。
2. **Epic ブランチが閉じている**（作った場合）: 既定ブランチへマージ済みで、リモート・ローカルとも削除されている。Epic ブランチに
   Sub-issue が取り込まれないまま残っていない（手順7の確認で全件が見つかっていること）。**この状態は掃除（手順9）で初めて揃う**ので、
   ここでは確かめず、**手順9の後の手順10で1回だけ確かめる**（手順8と9のあいだで往復しない）。
3. **Sub-issue がすべて閉じている**: 下の確認で、開いたままのものを**報告する**（閉じ忘れの安全網。この確認は黙って閉じない。閉じるのは手順7の確認を経たものだけ）。

状態1（単一リポジトリ）の確認。ベースはこのブロックの冒頭で解決し直す:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  git ls-tree "origin/$base" .epic_docs/<epic-name>/
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

**出力が空（計画が既定ブランチに無い）なら、案内して止まる**（不在でも終了コードは0なので、出力の有無で判定する）。

Epic の PR のマージ・状態1・状態3（下の確認）が揃ったら、手順9（掃除）へ進む。Epic issue を閉じるのは手順10（状態2の確認の後）。

Sub-issue PR の取り込み先・クローズの規則（自動クローズが発火しない構成を含む）は
ルール `pr-loop` の「ベースブランチ / クローズ / マージ」節が正本（ここでは再記述しない）。
Epic ブランチ向けの Sub-issue は手順7で取り込みを確かめた時点で明示的に閉じているので、ここでの確認は取りこぼしを見つけるための安全網である。
閉じ忘れが見つかったら、この確認は**報告するだけで閉じない**。報告を受けたメインが、手順7と同じく取り込み済みであることを確かめ、マージされた PR へのリンクを添えて閉じてから先へ進む（取り込めていないものは閉じない）。

対象 Sub-issue は番号を明示指定して1件ずつ状態を確認する（`gh issue list` は既定の取得件数上限を持ち、
対象の open issue 数がそれを超えると一覧から漏れて「閉じている」と誤判定しうる。番号を指定した問い合わせは
その上限の影響を受けないため、対象の Sub-issue 全件を確実に見ている）:

```bash
for n in <sub-issue番号...>; do
  if ! state="$(gh issue view "$n" [--repo <owner>/<repo>] --json state -q .state)"; then
    echo "Sub-issue #$n の状態を取得できなかった(直前の gh issue view 自体のエラー出力を確認する)" >&2
    break
  fi
  if [ "$state" = "OPEN" ]; then
    echo "Sub-issue #$n が開いたまま: 取り込み済みかを手順7の確認で確かめ、PR へのリンクを添えて閉じる(この確認は閉じない)" >&2
  fi
done
```

**`gh issue view` の終了コードを見る**（`state` への代入の成否で判定する。代入自体は失敗時も成立するため、
出力が空文字かどうかでは判定しない）。**標準出力だけを `$state` に取り込み、標準エラーは合流させない**
（`2>&1` を付けると、成功時でも `gh` 自体が標準エラーへ出す出力（アップデート通知等）が混ざって `$state` を
汚染し、成功しているのに `[ "$state" = "OPEN" ]` の比較が壊れて「open ではない」と誤判定されうる）。失敗時の
標準エラーは合流させていないぶん `$state` には入らないが、リダイレクトしていないのでコマンド自身の出力として
そのまま表示される——**失敗の原因は `$state` を経由せず、`gh` 自身の標準エラー出力から確認する**。
問い合わせが失敗した場合（存在しない番号・`--repo` の誤り・権限不足・一時的な通信断）は、その Sub-issue を
「open ではない＝閉じている」とみなさない。
この確認の目的は閉じ忘れを見つけて報告することなので、**確認できていない・開いたままの Sub-issue が残ったまま「確認完了」として先へ進まない**
——問い合わせの失敗ではループを止め、原因を解消してから未確認の番号を再確認する。開いたままの番号が出たら、メインが手順7の確認
（取り込み済みかの確認・PR へのリンク・`gh issue close <n> --comment`）を経て閉じ、改めてこの確認を通す。
開いたままのものが1件も出なければ何もしない（＝空振りのまま終了）。

### 9. ローカルブランチ・worktree のクリーンアップ

マージ後の掃除（トリガ・削除コマンドを失敗する側に倒す、という基本要件）はレーンに依存しない
共通の要求であり、正本は [[pr-loop]]「マージ後の掃除」節（本節では再記述しない）。**Epic はそれに
加えて、単発には無い専用のフィルタリングを持つ**——複数の Sub-issue が並行して走り、他タスク・
他 Epic の現役 worktree と同居しうるため、[[worktree-placement]] が定める置き場の配下にあるという
だけでは対象を絞ったことにならない（無関係な稼働中 worktree を巻き込みうる）。以下はこの Epic
固有の追加要件。

掃除の前に手元の base を進める手順（`yosage-dev-harness-update-base`）は [[pr-loop]]「マージ後の掃除」節が正本で、Epic でも先に行う（非0ならその理由を人に知らせる。掃除は続けてよい）。`epic-cleanup.sh` 自体は origin 側の ref を基準にし、上流を付け替えてから `-d` するので、手元の base が遅れていても判定は狂わない。

`epic-cleanup.sh` は git 操作のみで完結するため、**対象リポジトリのローカルチェックアウト内**（手順3で用意した場所）で実行する。cross-repo 構成で手順4の代替手順（明示 `git worktree add`）を使った場合の置き場の要求は [[worktree-placement]] が正本（本節では再記述しない。手順4のとおり従っていれば、このスクリプトの走査対象（第3引数の既定値）に自動的に含まれる）。

**対象はこの Epic のブランチ**（リモートの `epic/<epic-name>` に merge 済みのブランチ。Epic の完了時だけ `epic/<epic-name>` 本体も）だけに限定する。
worktree の削除もブランチの削除も、必ずこの Epic 集合でフィルタする。
セッションに同居する無関係なローカル専用ブランチ・他 Epic の worktree は対象外・触らない。
**既定ブランチへ直接入れた例外の Sub-issue は対象にしない**（ルール `pr-loop` の「マージ後の掃除」のとおり、その作業が作ったブランチを名指しで消す）。

安全なフィルタリング・削除ロジックは `harness/lib/epic-cleanup.sh` に切り出し済み（回帰テストあり）。
このスキルからは実行するだけでよい:

```bash
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  yosage-dev-harness-epic-cleanup "epic/<epic-name>" "$base"
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

第2引数に、このブロックの冒頭で解決したベース（`$base`）を**明示して渡す**（epic ブランチの分岐元。省略した場合の既定は導入先の既定ブランチの解決だが、
スキルの手順では毎回明示する）。第3引数（既定は [[worktree-placement]] が定める
割り当て作業ツリー置き場）で worktree 走査の置き場を上書きできる。

**判定は `git fetch --prune origin` の後に、リモートの Epic ブランチ（`origin/epic/<epic-name>`）を基準にする**（ローカルの Epic ブランチは古いままのことがあり、
基準にすると途中でマージ済みの Sub-issue を消せない。比較の相手も `origin/$base` で、ローカルの `$base` は使わない）。
**Epic の途中か完了かで挙動が違う**:
- **途中**（Epic ブランチが既定ブランチへ未マージ）: リモートの Epic ブランチへマージ済みの Sub-issue の作業ツリーとブランチを消す。
  **Epic ブランチ自身と、それをチェックアウトしている作業ツリーは消さない**。
- **完了**（既定ブランチの first-parent の履歴に、Epic ブランチを取り込んだマージコミットがある）: ローカルの Epic ブランチと、それをチェックアウトしている作業ツリーも消す。
  リモートの Epic ブランチが残っていれば報告する（消さない。人に削除を依頼する）。
- マージコミットが無く、Epic ブランチが既定ブランチの先端と同じか祖先なだけのときも**途中**として何も消さない（作ったばかりの場合と fast-forward で入った場合は履歴から区別できないので、fast-forward かどうかは判定しない。注意が出る。Epic の PR はマージコミットで入る決まりなので、後者は普通は起きない）。
- **完了と判定するのはマージコミットで取り込んだ場合だけ**。squash・rebase で入った Epic は途中のまま扱われ、Epic ブランチは消えない（手順8の完了の確認で止まったときの原因になる）。

出力の先頭に「基準: <R>@<sha>（途中|完了）、base: <名前>（<出どころ>）、除外の基準: <ref>」が出る。続いて対象が0件なら「対象: 0件」、
あれば `deleted: <branch>` / `skip (未マージ or 使用中): <branch>` の一覧（未マージ/集合外は削除されず一覧に残るので、要否の判断を人に委ねる）。

**止まるとき**（何も消さず、次の終了コードで終わる。原因を解消してから再実行する。止まったまま完了としない）:

| 終了コード | 意味 | 対処 |
|---|---|---|
| 1 | ベースブランチが決まらない | 手順3のとおり明示する／profile に宣言する／`git remote set-head origin --auto` |
| 10 | `git fetch --prune origin` に失敗した（古いローカルでは判定しない） | 通信・認証を直して再実行する |
| 11 | 基準の ref が実在しない（`origin/<base>` や、リモートに無くローカルも取り込まれていない Epic ブランチ） | 名前を直す／`git remote set-head origin --auto`／Epic ブランチの所在を確かめる |

**タイミング**（[[pr-loop]] が定める共通トリガ「人間マージを確認できた時点」を、Epic では
Sub-issue 単位ではなく次の単位で回す）:
- **phase を明示指定して個別実行した場合のみ**: Phase 間のレビュー待ち時（途中の掃除。次の `phase<k+1>` 実行前、そのフェーズの Sub-issue が Epic ブランチへ取り込まれた時点）。
- Epic 完了時（スコープの種別によらず共通。完了の掃除）: Epic の PR が既定ブランチへマージされた後（手順8の確認の後。手順8の2は、ここの掃除の後に再確認する）。

**スコープ無しで完走する場合はこの「Phase 間のレビュー待ち時」は発生しない**——「全フェーズ完走時のループ」（手順1a）が定めるとおりフェーズ間で人間の確認・レビュー待ちを挟まないため、掃除のタイミングも Epic 完了時の1回だけになる。

### 10. 状態2の最終確認 → Epic issue のクローズ

手順9の掃除の後に、**1回だけ**「Epic ブランチが閉じている」を確かめる（手順8から送った確認。手順8へ戻らない）。

**Epic ブランチを作らなかった Epic**（ワークスペースで全件が既定ブランチ向け。手順3）では、この確認は行わない（閉じるものが無い）。
下の Epic issue のクローズへ進む。

Epic ブランチを作った Epic では、リモートの Epic ブランチが削除・prune 済みでも判定できるようにする（リモートの ref が無いときは、
既定ブランチの first-parent の履歴に Epic ブランチを取り込んだマージコミットがあるかで判定する。`epic-cleanup` の完了の判定と同じ考え方）。
マージコミットが無いときは、**fast-forward で入った**（マージコミットが残らず、`epic-cleanup` と同じく区別できない）か、取り込まれていないかの
どちらかなので、誤警報にせず、Epic の PR が MERGED かを確かめて止めて報告する。`--grep` は Epic ブランチ名の後に語の終わりが来る形にする
（`epic/<epic-name>-v2` に当たらない）。ベースはこのブロックの冒頭で解決し直す:

```bash
git fetch --prune origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  if git show-ref --verify -q refs/remotes/origin/epic/<epic-name>; then
    # リモートの Epic ブランチが残っている: マージ済みでも「リモートも削除済み」を満たさない
    if git merge-base --is-ancestor origin/epic/<epic-name> "origin/$base"; then
      echo "リモートの Epic ブランチが残っている: 人に削除を依頼する" >&2
    else
      echo "Epic ブランチが既定ブランチへ入っていない: 完了としない" >&2
    fi
  else
    # リモートの ref が無い(削除・prune 済み): 既定ブランチの履歴に Epic ブランチを取り込んだマージコミットがあるか
    if [ -z "$(git log --first-parent --merges -E "origin/$base" --grep="epic/<epic-name>(\$|[^[:alnum:]_/.-])" --format=%H | head -n 1)" ]; then
      echo "取り込んだマージコミットが見つからない: fast-forward で入った(区別できない)か未取り込み。Epic の PR が MERGED かを確かめて止めて報告する" >&2
    fi
  fi
  # ローカルの Epic ブランチが残っていないこと
  if git show-ref --verify -q refs/heads/epic/<epic-name>; then
    echo "ローカルの Epic ブランチが残っている: 手順9の出力を確認する" >&2
  fi
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

揃っていなければ案内して止まる（Epic issue を閉じない）。揃っていれば、Epic issue を閉じる（配下の Sub-issue が閉じているかは手順8の状態3で確認済み）:

```bash
if ! gh issue close <epic_number> [--repo <owner>/<repo>]; then
  echo "Epic issue <epic_number> を閉じられなかった。原因を確認してから再実行する。" >&2
fi
```

**`gh issue close` の終了コードも見る**（すでに閉じている issue に対する呼び出しは終了コード0で成功する
——issue を作成して `gh issue close` を2回連続で実行し確認した（`✓実測`）。1回目は通常どおり成功、2回目
（既に closed）は「既に閉じている」旨の警告付きだが終了コードは0のままだった。したがって既に閉じている
Epic issue に対して再実行しても安全に扱える）。失敗した場合は Epic issue が実際には閉じていないので、
閉じたものとして扱わない。

## 注意事項

- スキル `epic/implement-subissue` の直接呼び出しはできないため、Agent への指示にはインラインで手順を記載する
- 各 Agent は worktree で隔離して並列実行する（**Epic issue が cwd と別リポジトリにある構成では例外**。手順4の代替手順に従う）
- 実装中にエラーが発生した Sub-issue はスキップせず、ユーザーに報告する
- Epic ブランチへの PR 作成が完了した段階でユーザーに報告し、レビューを待つ
- **管理者(メイン)の学びも capture**: Sub-issue の学びは `yosage-dev-harness:implementer` が内包するが、**統合段階で判明した競合・設計ドリフト・横断的判断**は管理者自身が [[capture-learning]] で蓄積する（実装＝yosage-dev-harness:implementer 内 / 統合＝メイン。誰が回すかは ルール `knowledge`）。
