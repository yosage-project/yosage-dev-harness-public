# 実装ルーティング / dispatch（不変条件）

実装の依頼を受けたら、着手前に**対象 issue を分類してレーンを固定**することになっている。そして**メインは実装しない**決まりになっている（実装は `yosage-dev-harness:implementer` に dispatch）。これは「分離されたり されなかったり」の不可視な揺れと、オーケストレーションの取りこぼしを断つ狙いがある。

> **上流フェーズとの関係**: 本 rule は「設計合意済み → 実装 dispatch」を担う。「設計討議が必要か」の判定は上流フェーズの [[design-routing]]（設計ルーティング）が担うことになっている。design-routing の出力（合意した設計 / design-doc issue）が本 rule の入力になる（上流→下流の別フェーズ）。

## レーンを分類して選ぶ（着手前・必須）
「<issue> を実装して」を受けたら、まず対象を分類してから動くことになっている:
- **Epic**（`epic` ラベル / 本文が複数 Sub-issue を束ねる）→ 全体オーケストレーションは**人間がトリガ**する決まりになっている。Sub-issue はメインでは実装し始めない・勝手な一括起動もしない（Sub-issue は、下記「phase 遷移」節の委譲の例外の対象外でもある）。`/yosage-dev-harness:epic-implement <N>` を**正確なコマンドで案内**することになっている（[[epic-implement]]）。
- **Epic の Sub-issue**（本文に親 Epic リンク）→ **[[epic-implement-subissue]]** で実装することになっている。取り込み先は Sub-issue の本文の「取り込み先」に従う（既定は Epic ブランチ、例外は導入先の既定ブランチ。規則は [[pr-loop]] に従う。再記述しない）。名指し1件なら**その1件だけ**を扱う（指した粒度がレーンの粒度）。未マージの兄弟依存があれば surface して確認。
- **非 Epic の単発** → **導入先の既定ブランチ基点**で実装することになっている（[[issue-implement]]）。[[change-lanes]] の Direct / Tracked single / Design-first single（討議収束後）はいずれもここに入る（本 rule は dispatch の base 判定のみを担い、追跡・討議の要否は問わない）。

## 実装入口 OQ ゲート（dispatch 前・メインが踏む）
踏む主体は**メイン（オーケストレーター）**であり、dispatch 前に1回踏むことになっている。`yosage-dev-harness:implementer` は会話文脈を持たないため踏まない。

1. **収集**: 対象 issue 本文の `## Open Questions` / `## 補完・前提（要確認）` 節を**正本として読む**ことになっている（会話の記憶には頼らない）。
   - Sub-issue の場合: **Sub-issue 自身の OQ ＋ 親 Epic の OQ のうちこの Sub-issue に効くもの**を対象に含めることになっている。Epic 全体に効く OQ は [[epic-implement]] 側の責務であり（入口では拾わない）。
   - OQ 節が無い／空 → **no-op で続行**する（Direct 小修正はゼロ摩擦）。
2. **分類**（[[grounded-design]] の価値トレードオフ判断パターン「recall に前例があれば裁定、無ければ人間へ」を OQ 分類に応用）: 各 OQ を二分することになっている。
   - **blocking**: 実装する物自体が変わる・後から安く戻せない・recall に裁定前例が無い。**迷ったら blocking 寄せ**とする（緩く「前例有」に引き伸ばさない）。
   - **deferrable**: 実装中の技術検証で初めて判明する・安く戻せる・局所的。
3. **blocking → 解決必須**: `AskUserQuestion` で詰めることになっている。質問は **self-contained** とする（issue 正本を読んだ上で「この問題は何か / 各案 / 推奨案＋メリット / デメリット」を展開する。文脈的自己完結は [[issue-discipline]] 正本）。回答は**設計 issue 本文へ反映**してから dispatch することになっている。
4. **deferrable → 記録して続行**: `soft-decline-via-content-coupled-reason`（`.claude/knowledge/process/`）に従い、boolean フラグでなく**反証可能な理由（何が崩れたら再検討か）**で記録することになっている。記録先は**実装 issue 本文の「## 仮定（実装中に検証）」節**とする（issue を self-contained に保つ）。
5. **deferrable をまとめて surface**: dispatch 前に deferrable OQ を**バッチで1回**ユーザーに示すことになっている（「以下は deferrable として進めます: 仮定 X（崩れたら再検討）…」）。ブロックはしないが、**誤分類（本来 blocking）を安く検知**できる。
6. **再オープン**: 実装中に仮定が崩れたら、既存フック「実装が issue 記載と矛盾したらユーザーに確認」（[[issue-implement]] / [[epic-implement-subissue]] 注意事項）が再浮上の引き金になる。

## メインは実装しない（dispatch する）
- 実装は**単発でも Sub-issue でも `yosage-dev-harness:implementer` に dispatch** し worktree で隔離することになっている。単発＝N=1・並列なしの dispatch（Sub-issue と同型）。メインは分配・監視・統合・一次レビュー差配・判断に徹することになっている（並列統制は [[orchestrate-parallel]]、監視は agent-watchdog）。
- 「自明だからメインで」は**例外にしない**決まりになっている。粒度に関わらず作業部隊へ回すことになっている（生成者と実行者を分け、メインは自分の実装を自分では見ない）。

## phase 遷移は人間がトリガ・次の一手を示す
- **着火が重い** phase 遷移（設計合意後→**実装 dispatch**・Epic 全体実装・Sub-issue 一括起票）は**人間がトリガ**する決まりになっている（実装 dispatch に限り、次項の委譲の例外がある。Epic は対象外）。ハーネスは勝手には着火せず、**次に人間が引くべきトリガを正確なコマンドで提案**して摩擦を消す設計になっている（例: Sub-issues 作成後は `/yosage-dev-harness:epic-implement <N>`）。
- **例外: 人が profile で委譲を宣言した範囲では、メイン（オーケストレーター）が実装 dispatch を着火してよい**。委譲の対象は**宣言した範囲に入る、Epic に属さない単発の issue の実装 dispatch の着火**に限る。どの issue に着手させるかはメインが選んでよい。次は委譲の対象にせず、委譲があっても従来どおり人が引く: Epic 全体の実装（`epic-implement`）・**Epic の Sub-issue（1件ずつであっても。連続で着火すると実質 Epic 全体の実装になるため）**・Sub-issue の一括起票・大きい設計討議（Epic 級）への入場・PR のマージ（[[pr-loop]]）。
  - **「委譲した」ことの示し方は profile の宣言1本**: 導入先の profile（`.claude/rules/<名前>/profile.md`）に、[[project-profile]] が定める固定の1行（`` - **実装の着火の委譲: `単発 issue`** ``）があること。この書式どおりでなければ未宣言として扱う。profile はモデルも編集しうるため、「人が書いた宣言に限る」ことの担保は文面だけである（既知の限界）。モデルが「委譲されたはず」と推測した場合は含まない。
  - **未宣言は委譲していない側に倒す**: 宣言が無い・書式どおりでない・委譲の有無が分からない場合は、従来どおり人が引く（次に打つコマンドを提案する）。ルール `commit` の Co-Authored-By が未宣言を「付けない」側へ倒すのと同じ考え方（着火の誤りは取り消しにくく、着火し損ねの損失は提案の一往復で済むため、非対称）。
  - **委譲があっても、着火の前提は緩めない**: 実装入口 OQ ゲートを踏むこと、メインは自分で実装せず `yosage-dev-harness:implementer` に dispatch すること、は変わらない。委譲が外すのは「人がコマンドを打つ」手順だけである。
- これは「重い遷移は人が引く（人が委譲を明示した範囲を除く）／個別実装の dispatch は妨げない」の両立。flag（`disable-model-invocation`）が守るのは前者だけ。
- **「設計討議への入場」との区別**: 軽い Design-first 討議の開始（読む・考える・喋るだけ）は [[design-routing]] の範疇であり、ここで言う「着火が重い遷移」には含まない。重いのは**実装 dispatch の着火**（コードを書く・worktree を作る・test を走らせる等の不可逆コストが発生する遷移）。
- **案内するコマンドは名前空間つきの形で書く**: 人間に打たせるスラッシュコマンドは `/yosage-dev-harness:<スキル名> <引数>` の形で案内する（例: `/yosage-dev-harness:epic-implement <owner>/<repo>#<N>`）。プラグインのスキルは名前空間つきでないと貼っても起動しない。人間トリガのスキル（`disable-model-invocation`・上の項）は人が打つ以外に起動する経路が無いので、案内の正確さがこの節の狙い（摩擦を消す）そのものになる。スキルを名前で参照するだけの箇所（`[[epic-implement]]` 等）は対象外。各所のコマンド例は、貼ればそのまま動くよう引数つきの完全な形で書く（本項への参照だけにしない）。
