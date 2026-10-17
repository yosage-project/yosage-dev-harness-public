# 変更レーン定義（不変条件）

変更依頼は規模・性質に応じて4レーン（Direct / Tracked single / Design-first single / Epic）に分類される
決まりになっている。**本 rule は各レーンの判定基準・進め方・成果物の単一ホーム**として扱われている。
各レーン固有の帰結（PR ループでのレビュー要否・ベースブランチ、討議着火の要否等）は各着火点のルール
（[[pr-loop]] / [[design-routing]] / [[implement-routing]]）側が持つことになっている
（本 rule には持ち込まない・再記述しない決まりになっている）。

## 独立した2軸
4レーンは単純な重さの序列ではなく、**「追跡の要否」と「設計判断の要否」という独立した2軸**の組み合わせで決まる。
- **追跡の要否**（issue に残すか）: この軸だけが Direct と Tracked single を分ける（自明な小修正か、follow-up・
  セッション跨ぎで追跡が要るか）。
- **設計判断の要否**（実装着手前に設計討議が要るか）: この軸だけが Tracked single と Design-first single を分ける
  （複数案・後戻りコストの高い設計選択が要るか）。Design-first single は討議収束後、Direct/Tracked single いずれかの
  進め方で実装することになっている。
- Epic は上記2軸に加えて**規模（スケール）の軸**で分離される別次元（単発スキルがプリミティブ、Epic スキルは
  そのスケール版）。**Epic を Sub-issue へ分割する際は「独立に取り込めるか」も判定軸に持つ**（基準の実体は
  再記述せず [[epic-create-docs]] の分割基準に正本を置く）。この判定が、各 Sub-issue の PR をどこへ
  統合するか（既定＝Epic ブランチ・独立に取り込めて先に出す事情があるものだけ既定ブランチへ直接）の判断材料になる（取り込み先の規定は [[pr-loop]]）。

## レーン定義表
| レーン | 判定基準 | 進め方 | 成果物 |
|---|---|---|---|
| **Direct** | 自明な小修正（設計判断なし・同セッションで完結） | `<type>/<name>` を導入先の既定ブランチから → 実装 → 検証 → draft PR → 自己レビュー → ready → 人間マージ | PR のみ（issue 省略可） |
| **Tracked single** | 単発だが追跡が要る（follow-up / セッション跨ぎ / 引き継ぎ） | `issue-create` → `issue-implement`（導入先の既定ブランチ基点）→ PR は `Closes #` | issue + PR |
| **Design-first single** | 非自明（複数ファイル / 設計選択 / 後戻りが高い） | `design-doc` で設計 issue を立て合意 → 上の Direct/Tracked single へ | 設計 issue + PR |
| **Epic** | 大きい / 多面的 / 並列可能 | `epic-create-docs` → `epic-create-issues` → `epic-implement(-subissue)` → `epic-review` | `.epic_docs/` + Epic + Sub-issues |

- 自明でないが Epic ほどでないものは Tracked single が既定（迷ったら軽い方から）。ただし設計判断が要ると判れば
  Design-first single へ上げることになっている（2軸は独立なので Tracked single のまま設計判断だけ足す、
  ということはしない決まりになっている）。
- 各レーンの PR の回し方は [[pr-loop]]、issue の作り方は [[issue-discipline]]、knowledge loop は [[knowledge]]。
- **マージ後のブランチ・worktree の掃除は、どのレーンを通っても要求される共通の工程**（[[pr-loop]]
  「マージ後の掃除」節が正本。本表には持たない）。

## なぜ単一ホームへ統合したか（過去方針の反転）
レーン語彙は複数の配布 rule（[[pr-loop]] / [[design-routing]] / [[implement-routing]]）から横断的に参照される。
以前は「定義正本が非配布なら配布ゲートは最小判定基準だけをインラインする」方針だったが、複数 rule が同じ語彙を
個別に部分インラインすると重複・drift の芽が rule の数だけ生まれるため、定義そのものを配布側の単一ホームへ
完全移動し、各 rule は本 rule への名前参照に統一することにした。
