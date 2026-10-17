---
id: <kebab-slug>            # 省略可(空値も同様)。省略時はファイル名(YYYY-MM-DD-<slug>)の <slug> が実効 id になる(生成器が導出)。明示指定は override(ファイルを開くだけで id が分かる／リネーム耐性がある)として推奨
date: YYYY-MM-DD            # 記録日(絶対日付)
domain: <api|architecture|testing|security|ops|frontend|mobile|...>
tags: []                   # 検索用。技術名・状況など自由（例: [auth, jwt, fastapi]）
scope: local               # local(このプロジェクト固有) | global(全プロジェクト共通と判断 → まずここに staging。ストアへの昇格は promote-knowledge が担う)
status: active             # active | superseded | archived(後継無しで退役。ファイルは残す)
summary:                   # INDEX 用の1行要約（生成器がここを読む。INDEX は手編集せず生成）。必ず1行のプレーンスカラーで書く: 行頭に `>` `|`（YAML ブロックスカラー指示子）を置かない・複数行にしない（生成器は1行 key: value 前提。多行にすると値が壊れ、生成器が警告を出す）。長くても改行せず1行に収める（バッククォートやコロンを値に含めてよい）
supersedes:                # 置き換えた古いエントリの id（あれば）
archived:                  # status: archived のみ。退役日(YYYY-MM-DD)。理由は本文にも書く
source:                    # 外部由来のみ。出典 URL（言語定石・公式 doc 等、コードに grep 接地しない知識）。在る＝外部エントリ
checked:                   # 外部由来のみ。出典を最後に確認した日(YYYY-MM-DD)。鮮度の起点（古くなると recall 時に ⚠ が付く＝yosage-dev-harness:librarian）
---

## 判断 / ルール
<X のときは Y する / しない。1〜2文で。>

## なぜ
<理由・背景。「やってみて判明した」制約や、間違えた経緯など。>

## 根拠 / 実例
- 内部（このリポのコード/doc）: `path` ＋ 安定ハンドル（関数名 / 見出し / 短い特徴的な引用） — <該当箇所の説明>
  （grep で在/不在を再解決できる形で。行番号は任意＝記録時点の便宜ヒントで、権威はハンドル側。コードが動いても腐りにくく、recall 時に現在地へ引き直せる）
- 外部（言語定石・公式 doc 等）: コードに grep 接地しないので、安定ハンドルの代わりに frontmatter の `source:`（URL）＋ `checked:`（確認日）で出所と鮮度を示す。

## 適用
<具体的にどう守るか。チェックの仕方・落とし穴など。>
