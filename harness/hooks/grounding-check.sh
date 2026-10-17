#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit) フック: 設計ドキュメントの接地チェック。
#   grounded-design の `path:line` 引用(= "実在する" という主張)を検証する。
#   引用先が存在しない/行数が足りない = ハルシネーション(偽の接地)の疑い。
#   additionalContext で Claude に自己修正を促す(非ブロッキング。編集は失敗扱いにしない)。
#   設計ドキュメント以外、または引用が無ければ無反応(ノイズゼロ)。
set -uo pipefail
input="$(cat)"

jqget() { command -v jq >/dev/null 2>&1 && printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

file="$(jqget '.tool_input.file_path // .tool_input.path // empty')"
if [ -z "$file" ] && command -v python3 >/dev/null 2>&1; then
  file="$(printf '%s' "$input" | python3 -c 'import sys,json;ti=json.load(sys.stdin).get("tool_input",{});print(ti.get("file_path") or ti.get("path") or "")' 2>/dev/null)"
fi
[ -n "$file" ] && [ -f "$file" ] || exit 0

# 対象は設計ドキュメントのみ
case "$file" in
  */.docs/*|*/.epic_docs/*|*design*.md|*DESIGN*.md|*設計*.md) : ;;
  *) exit 0 ;;
esac

# 解決基点は「編集対象ファイル自身が属する git リポジトリのルート」にする。効いている変数は
# worktree か否かではなく編集対象ファイルがどのリポジトリに属するかであり(複数リポジトリが
# 同居するワークスペースのルートを基準ディレクトリとするセッションから、その配下の別リポジトリ
# 内のファイルを編集すると、フックプロセスの作業ディレクトリ・CLAUDE_PROJECT_DIR・入力JSONの
# cwd がいずれもワークスペースのルートを指してしまい、file が属するリポジトリ相対の参照が
# どれを基点に選んでも解決できなくなる)、file の絶対パス(tool_input.file_path)から
# `git rev-parse --show-toplevel` でそのファイル自身のリポジトリルートを直接導出する。
proj="$(command -v git >/dev/null 2>&1 && git -C "$(dirname -- "$file")" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$proj" ]; then
  # 編集対象ファイルが git リポジトリの外にある場合のフォールバック: 従来どおり
  # CLAUDE_PROJECT_DIR → 入力JSONのcwd → フックプロセスのPWD の順で基準ディレクトリを取る。
  proj="${CLAUDE_PROJECT_DIR:-}"
  [ -z "$proj" ] && proj="$(jqget '.cwd')"
  [ -z "$proj" ] && proj="$PWD"
fi

# `path:line` 引用を抽出 (拡張子付きパス + コロン + 行番号。先頭の `/` は付いていれば保持する)。
# 誤検知対策: `docker-compose.yml:5000` のような「ファイル名:ポート番号」表記を path:line と
# 誤認しないよう、(1) URL(`scheme://...`) は丸ごと除去してから抽出し、(2) スキーム省略の
# `host:port/...` 表記(例 `localhost:5000/docs/index.md:20`)も authority と判断して丸ごと
# 除去し、(3) 抽出パターンはディレクトリ区切り `/` を含むものだけを対象にする(ルート直下の
# ファイル名だけの `name.ext:number` は「ファイル名:ポート/バージョン」等の非パス表記との
# 衝突が大きいため対象外)。(2) の判定条件は「識別子:数字の直後に `/` が続く」こと
# (真の path:line 引用は行番号の後ろに `/` が続かない=末端であるため、両者はこの形で区別できる)。
# 数値の大小では判定しない(実ファイルが数千行を超えるのは珍しくなく、閾値では真の誤参照を
# 取りこぼす)。既知の gap: ルート直下ファイルへの bare 参照(例 `README.md:20`)は本チェックの
# 対象外になる(このリポジトリの実際の引用は一貫してディレクトリ付きで書かれているため実害は
# 小さいと判断)。また `dir/compose.yml:5000` のようにディレクトリ付きのポート表記や、
# `host:port/dir/file.ext:line` のように host:port の後ろに正当な path:line が続く複合表記は、
# (2) の除去で丸ごと消える(取りこぼし)ことがある(誤検知の削減を優先した意図的なトレードオフ。
# 意味的な曖昧性解消は grep ベースのフックの範囲外)。
refs="$(sed -E 's#[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]*##g; s#[A-Za-z0-9][A-Za-z0-9._-]*:[0-9]+/[^[:space:]]*##g' "$file" 2>/dev/null \
  | grep -oE '/?[A-Za-z0-9._-]+/[A-Za-z0-9._/-]*\.[A-Za-z0-9]+:[0-9]+' | sort -u)"
[ -n "$refs" ] || exit 0

missing=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  path="${ref%:*}"; line="${ref##*:}"
  case "$path" in
    /*)
      # 先頭 `/` を保持したまま抽出された参照は真にファイルシステム絶対パスとして書かれた
      # ものなので、cwd/proj を経由せずそのまま存在確認する(既存の絶対パス参照の扱いと同じ経路)。
      if [ -f "$path" ]; then target="$path"
      else missing="$missing
  - $ref — ファイルが存在しない"; continue; fi
      ;;
    *)
      # 判断: 旧実装が備えていた「フックプロセスの作業ディレクトリからの相対」という1段目の
      # 素の存在チェック(`[ -f "$path"]`、cwd 相対)は、この修正で意図的に外した。$proj が
      # 編集対象ファイル自身のリポジトリルートを正しく指すようになった以上、それとは別枠で
      # フックの起動ディレクトリを基点にした素のチェックを残しても得るものがなく、むしろ
      # 「たまたまフックの起動ディレクトリ配下に同じ相対パスの無関係なファイルが存在すると
      # 誤って実在すると判定してしまう」(=本当は存在しない参照を見逃す方向の穴)経路が
      # 残るだけなので、外す方を選んだ。
      if [ -f "$proj/$path" ]; then target="$proj/$path"
      else missing="$missing
  - $ref — ファイルが存在しない"; continue; fi
      ;;
  esac
  total="$(wc -l < "$target" 2>/dev/null | tr -d ' ')"
  case "$total" in ''|*[!0-9]*) total=0 ;; esac
  if [ "$line" -gt "$total" ] 2>/dev/null; then
    missing="$missing
  - $ref — 実体は $total 行までしかない"
  fi
done <<EOF
$refs
EOF

[ -n "$missing" ] || exit 0

note="⚠ grounded-design 接地チェック: 次の path:line 引用が実体と一致しません。ハルシネーション(偽の接地)の可能性があります。実コードを開いて正しい参照に訂正するか、未確認であれば接地ラベルを適切なもの(+補完(要確認) 等)に置き換えてください:$missing"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$note" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys;print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}}))' "$note"
fi
# jq/python3 どちらも無ければ無処理(非ブロッキング。CLAUDE.md フック規約: 常に exit 0)
exit 0
