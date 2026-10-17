# 変更の規模ごとの流れ

変更は、規模と性質に応じて4つの進め方に分かれる。Claude は頼まれた変更をまずこの4つに分類し、
その進め方で動く（ルール `change-lanes`）。人が分類を指定することもできるし、迷ったら
Claude が軽い方から選ぶ。

| 進め方 | 当てはまる変更 | 成果物 |
|---|---|---|
| 自明な小修正 | 設計判断が要らず、同じセッションで終わる | PR（issue は省略してよい） |
| 追跡が要る単発 | 単発だが、あとで引き継ぐ・セッションをまたぐ・follow-up として残したい | issue と PR |
| 設計判断が要る単発 | 複数案がある・後戻りが高くつく・複数ファイルにまたがる | 設計 issue と PR |
| Epic | 大きい・多面的・並列に進められる | 計画ドキュメント・Epic・Sub-issue・PR 群 |

分類は2つの軸で決まる。「追跡するか」は小修正と追跡が要る単発を分け、「設計判断が要るか」は
追跡が要る単発と設計判断が要る単発を分ける。Epic は規模の軸で別になる。自明でないが Epic ほど
大きくもないものは、追跡が要る単発から始める。ただし設計判断が要ると分かった時点で、設計判断が
要る単発へ移る。

どの進め方でも共通する点は次のとおり。

- 実装は `yosage-dev-harness:implementer`（実装役）に任せ、隔離した作業ツリーで行う。
- すべての変更は PR を通り、**人がマージして閉じる**。Claude はマージしない。
- PR は draft で出し、一次レビューを経てから ready にする。

## 自明な小修正

誤字・コメントの修正・設定値の1行変更など。

**頼み方**: 普通の言葉で頼む。コマンドは要らない。

```
config の説明文の誤字を直して。
```

**流れ**: ブランチを切る → 実装役が実装 → 検証 → draft PR → 一次レビュー → ready → 人がマージ。

**この進め方だけの特徴**: 一次レビューは Claude 自身の見直しで代えてよい。ただし
「draft → ready → 人がマージ」は省かない。判断に迷ったら、追跡が要る単発に上げる。

## 追跡が要る単発

**頼み方**:

```
/yosage-dev-harness:issue-create <タイトル>
/yosage-dev-harness:issue-implement <owner>/<repo>#<N>
```

1行目で、背景・ゴール・受け入れ条件を本文に書いた self-contained な issue を作る（それだけ
読めば着手できる形）。起票の前に、同じ内容の issue が既に無いか、open と closed の両方を検索する。
2行目で実装を頼む。`issue-implement` は issue を読んで、実装入口の問いの整理 → 実装役に任せる →
検証 → コミット（`Closes #<N>`）→ draft PR → 一次レビュー → ready まで進める。

**人がやること**: 実装入口で、実装する物が変わる問いに答える。PR をマージする。

**一次レビュー**: `yosage-dev-harness:code-reviewer` によるレビューが必須。

issue の番号は、単一のリポジトリなら `<N>` だけでもよい。

## 設計判断が要る単発

作り方が一通りに決まらない、後戻りが高くつく、という変更。いきなり実装せず、先に設計を
**issue の上で**議論して合意する。検討中の設計をリポジトリのファイルに置かないのは、引き継ぎが
でき、議論が GitHub に残るため。

**頼み方**（どちらも、普通の言葉で「設計から詰めたい」と頼んでもよい）:

```
/yosage-dev-harness:design-doc
/yosage-dev-harness:deliberate-design
```

- `design-doc` は、設計 issue（背景・ゴール・採用案と捨てた案・影響・テスト方針・未解決の問い）を
  立てて議論する。
- `deliberate-design` は、複数の案を同じ抽象度で並べた比較表（メリット・デメリットつき）を作り、
  人と往復して詰める。収束の前に、既存との食い違いを見る視点と、定石から外れていないかを見る
  視点のレビューを別々に1回ずつ通す。

**討議を始める条件**: 局所的で後戻りが軽い設計は、Claude が自分から討議に入る（人はいつでも
やめられる）。後戻りが重い・アーキ全体にわたる設計は、Claude が「討議が有益そう」と提案して
コマンドを示し、**人が承認してから**入る。設計判断のない小修正は討議しない。

**合意したら**: 決定は設計 issue に反映し、製品やアーキに効く内容は `.docs/` の正本へ、
再利用できる判断は知見へ蒸留する。そのあと、`issue-implement` で実装する。
**実装の着火は人が引く**（Claude は勝手に始めず、次に打つコマンドを示す）。例外として、Epic に属さない単発の issue の実装に限り、導入先の profile に委譲の宣言（`- **実装の着火の委譲: `単発 issue`**`）がある場合は、メイン（オーケストレーター）が着火してよい（宣言が無ければ従来どおり）。Epic（Sub-issue を含む）の実装・マージは委譲の対象にならない。

設計の前提を確かめる道具として、`/yosage-dev-harness:grounded-design`（既存実装と外部の
定石に根拠を取ってから設計する規律）がある。

## Epic

複数の Sub-issue に分けて、依存関係を見ながら順次・並列に進める。流れは [Epic の進め方](epic.md)
で説明する。

```
/yosage-dev-harness:epic-create-docs <epic-name> <概要>
/yosage-dev-harness:epic-create-issues [epic-title]
/yosage-dev-harness:epic-implement <owner>/<repo>#<N>
/yosage-dev-harness:epic-review <owner>/<repo>#<N>
```

Epic の Sub-issue を1件だけ実装するときは `/yosage-dev-harness:epic-implement-subissue
<owner>/<repo>#<N>` を使う（通常は `epic-implement` が内部で使う）。

## 実装入口の問いの整理（単発・Sub-issue 共通）

issue に `Open Questions` や `補完・前提（要確認）` の節があると、Claude は実装役に任せる前に
問いを2つに分ける。

- **実装する物が変わる・後から戻しにくい・前例が無い**もの → 実装前に**人へ選択肢を示して
  確認**する。答えは設計 issue の本文に反映してから進む。迷ったらこちらに寄せる。
- **実装中に確かめれば足りる・戻しやすい・局所的**なもの → 「仮定（実装中に検証）」として
  issue 本文に、何が崩れたら見直すかとともに記録して先へ進む。進める前に、仮定をまとめて
  1回示す（誤って軽く扱っていないか、人が早く気づける）。

実装中に仮定が崩れたら、Claude は人に確認する。

## そのほかの道具

必要になったときに使う。全体は [README の機能カタログ](../README.md#機能カタログ自動生成)。

| やりたいこと | コマンド |
|---|---|
| 新しいプロダクトや大きな機能の提案書を壁打ちでまとめる | `/yosage-dev-harness:proposal` |
| アーキテクチャを `.docs/architecture/` に正本化する | `/yosage-dev-harness:document-architecture` |
| ドメイン用語と命名の対応を揃える | `/yosage-dev-harness:glossary` |
| 実装と設計ドキュメント（`.docs/`）のずれを直す | `/yosage-dev-harness:sync-design-docs` |
| UI の見た目・配色・レイアウトを起こす（仕組みの設計とは別の進め方） | `/yosage-dev-harness:visual-design` |
| 導入先固有の座標（`.claude/rules/<名前>/profile.md`）の下書きを作る・鮮度を見る | `/yosage-dev-harness:document-profile`、`/yosage-dev-harness:document-profile refresh` |
| 複数の作業ツリーを並列で動かす統制の規律 | `/yosage-dev-harness:orchestrate-parallel` |
| 手元の環境を汚さず、使い捨てコンテナ（Docker）でコマンドを試す | `/yosage-dev-harness:scratch-run` |
| 今の導入状態を確かめる（書き込まない） | `/yosage-dev-harness:status` |
| 今何ができるか、この作業はどのスキルで進めるかを案内してもらう | `/yosage-dev-harness:harness-help` |

`document-profile` は利用者所有のファイルを書くため、明示的に打ったときだけ動く。
`profile` の書式と所有の考え方は [README の profile](../README.md#profile導入先固有の座標)。
