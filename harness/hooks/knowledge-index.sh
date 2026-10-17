#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit) フック: knowledge エントリ変更時に生成器(lib/knowledge-index.sh)を
#   検証だけのモード(`--check`)で毎回走らせ、併せて編集された1エントリの構造的欠陥を
#   lib/knowledge-audit.sh で監査する。project-local の INDEX.md/INDEX.archive.md は生成物として
#   持たない(ローカル索引は廃止済み。recall は `knowledge-index.sh --list`/`--list-archive` の
#   直接列挙が主経路。ルール `knowledge` の「ローカル索引は任意のキャッシュ」節)。本フックの
#   目的は、project-local ストア(`.claude/knowledge` 固定)配下の `<domain>/*.md` が変わるたびに
#   生成器を走らせて宣言部(frontmatter)の書式検証(壊れた summary の検出等)を効かせること。
#   グローバル側の `global/INDEX.md` は同期(knowledge-sync.sh)が生成する対象であり、本フックは
#   project-local だけを対象にするため関与しない。
#   best-effort: 対象外/python3 非在は何もしない(exit 0)。
#   生成器の失敗(exit 非0)、生成器の警告(exit 0 だがこの1ファイルに関する stderr 警告あり)、
#   または構造監査でこの1ファイルに欠陥が見つかった場合、stdout に systemMessage(ユーザー向け
#   警告)と hookSpecificOutput.additionalContext(Claude 向け: 再生成/修正をやり直させる指示)
#   の両方を返して可視化する(欠陥が無ければ無出力)。
#   構造監査の check 全種のうち dangling-link(check4)だけは、この書き込み時の報告からは除く
#   (理由・代償は下の audit_lines 算出箇所のコメント参照。この絞り込みは監査本体
#   (lib/knowledge-audit.sh)には手を入れず、ここでの報告フィルタとしてのみ行う)。dangling-link は
#   まとめて走らせる監査(`yosage-dev-harness-knowledge-audit .claude`)では引き続き報告される。
set -uo pipefail
input="$(cat)"

jqget() { command -v jq >/dev/null 2>&1 && printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

file="$(jqget '.tool_input.file_path // .tool_input.path // empty')"
if [ -z "$file" ] && command -v python3 >/dev/null 2>&1; then
  file="$(printf '%s' "$input" | python3 -c 'import sys,json;ti=json.load(sys.stdin).get("tool_input",{});print(ti.get("file_path") or ti.get("path") or "")' 2>/dev/null)"
fi
[ -n "$file" ] || exit 0

# 対象は project-local エントリ `<dir>/<domain>/*.md` のみ。`<dir>` はストアの固定置き場
# `.claude/knowledge`(置き場を変える機能は撤去済み。ルール `knowledge`)。
# global/(sync が生成) と base 直下(INDEX.md・雛形) は対象外。
# Claude Code は file_path を絶対パスで渡す前提(grounding-check.sh と同様)。
dir=".claude/knowledge"
case "$file" in
  */"$dir"/global/*) exit 0 ;;
  */"$dir"/*/*.md) : ;;
  *) exit 0 ;;
esac

# 再生成の基点は、編集されたファイル自身の絶対パス(`$file`)から導出する。
# `$file` は上の case で `/$dir/` を含むことが確定しているので、その手前で
# 切り出せば、そのエントリが属するリポジトリのルートが取れる。
# `%` (最短サフィックス除去)で最も内側(=最後)の出現から切る。`%%`(最長サフィックス除去)だと
# `/$dir/` がパス中に複数回現れるネスト構成で最も外側の出現から切ってしまい、
# エントリを所有するリポジトリより浅い(=別の)ディレクトリを掴む。出現が1回だけの通常の
# 構成・worktree 構成(`/.claude/worktrees/` を挟むため既定の `/.claude/knowledge/` は1回しか
# 出ない)では `%` と `%%` は同じ結果になるため、既定レイアウトの既存挙動は変わらない。
# `CLAUDE_PROJECT_DIR` やセッションの `.cwd`/`$PWD` は参照しない: 複数リポジトリが同居する
# ワークスペース直下でセッションを開いている場合、これらはワークスペースのルートを指し、
# 編集されたエントリが属するメンバーリポジトリのルートとは別物になる
# (単一リポジトリ構成ではプロジェクトルート=リポジトリルートなので、この導出でも一致する)。
proj="${file%/"$dir"/*}"

# 編集されたエントリが実際に属するストアのディレクトリ(既定なら `$proj/.claude/knowledge`)。
kdir="$proj/$dir"

# 補助スクリプトは常に自分の位置(このフック自身が属する `lib/`)から見つける。導入先の
# インストール済みディレクトリ配下の lib を見に行かない(プラグイン化後は導入先にそうした
# ディレクトリが存在しない前提になる。`${CLAUDE_PLUGIN_ROOT}/hooks/knowledge-index.sh` として
# 発火しても、フック自身の位置からの相対関係は変わらないので同じ式で解決できる)。
resolve_lib() {  # <name>
  printf '%s' "$(dirname "${BASH_SOURCE[0]}")/../lib/$1"
}

gen="$(resolve_lib knowledge-index.sh)"
gen_err=""
gen_rc=0
if [ -f "$gen" ] && [ -d "$kdir" ]; then
  gen_err="$(bash "$gen" "$kdir" --check 2>&1 1>/dev/null)"; gen_rc=$?
fi

# 生成器(lib/knowledge-index.sh)は非致命的な警告(summary 欠落/YAML ブロックスカラー)を
# stderr に出しつつ exit 0 で graceful degrade する(INDEX 自体は正しく再生成される)。
# 真の失敗(対象ディレクトリ不正等)は exit 非0。よって成否は exit code で判定し、
# stderr の有無だけでは判定しない(非0時のみ「失敗」を出す)。
# rc=0 かつ stderr 非空(警告)の場合は、既存の構造監査(下)と同じ粒度に揃え、今回編集された
# 1エントリに関する行だけを「警告」として分離して surface する。生成器の stderr 行の書式は
# `knowledge-index: <basename>: <msg>` の固定 `: `(コロン+空白)区切りなので、awk でフィールド
# 完全一致させる(basename の部分文字列一致にしない。例: 編集 `notes.md` と未編集
# `important-notes.md` のように一方が他方の部分文字列になるケースで、部分文字列一致だと
# 編集していないエントリの警告まで拾ってしまう)。
gen_warn=""
if [ "$gen_rc" -eq 0 ] && [ -n "$gen_err" ]; then
  gen_warn="$(printf '%s\n' "$gen_err" | awk -F': ' -v b="$(basename -- "$file")" '$2==b')"
fi

# 構造監査(lib/knowledge-audit.sh)は knowledge ディレクトリ全体を対象に決定論チェックを行うが、
# ここでは編集された1ファイルに関する行だけへ絞り込む(相対パスの列で照合)。監査本体
# (lib/knowledge-audit.sh の各 check)自体は変更しない — ここは書き込み時の「報告」の絞り込みだけ。
#
# dangling-link(check4)は書き込み時のこの報告からは除く。相互に [[...]] で参照し合う
# エントリを2件書くとき、1件目を書いた時点では相手がまだ存在しないため必ず一度 dangling-link が
# 報告される。これは「実在しない参照(typo・相手が存在しない)」という恒久的な欠陥と、「これから
# 書くだけ」の過渡状態を区別できない偽陽性であり、書き込み時フックの起動単位(1ファイルの編集)
# には「同一ターンで他に何を書いたか」という概念が無いため、同一ターン内での解決も実装できない
# (却下案: 同一ターンの他エントリを解決対象に含める→フックにその概念が無く不成立。前方参照を
# 別分類にする→前方参照かどうかは書き手の意図でしかなく検出器から確認できない。既存の
# dangling-link-skipped(下記)のような確認可能な事実を根拠にできない)。
# **代償**: 恒久的に壊れた参照(typo・相手が存在しない)も、誰かがまとめて監査
# (`yosage-dev-harness-knowledge-audit .claude`)を回すまで書き込み時には知らされなくなる。
#
# dangling-link-skipped(グローバルミラー global/ が未 sync のため判定不能として skip した区分)は
# 対象外(=書き込み時にも残す)。dangling-link と違い、こちらは「global/ ディレクトリが存在しない/
# 未 sync」という確認可能な事実を根拠にしており、書き手の意図を推測していない。したがって
# dangling-link と同じ「過渡状態か恒久的な欠陥か区別できない」問題を抱えていないので、除く理由が無い。
#
# 監査(lib/knowledge-audit.sh)は常に呼び出す。監査本体は `<base-dir>` 単一引数の契約
# (`<base-dir>` は skills/agents/rules/knowledge の親。走査対象は常に `<base-dir>/knowledge` 固定)
# を持つため、`$proj/.claude` を渡すだけで既定レイアウトを正しく走査する。出力の relpath の基点は
# `<base-dir>`(`.claude`)なので、照合する `rel` も同じ基点で相対化する。
audit_lines=""
aud="$(resolve_lib knowledge-audit.sh)"
if [ -f "$aud" ] && [ -d "$kdir" ]; then
  rel="${file#"$proj"/.claude/}"
  full_audit="$(bash "$aud" "$proj/.claude" 2>/dev/null)"
  if [ -n "$full_audit" ]; then
    audit_lines="$(printf '%s\n' "$full_audit" | awk -F'\t' -v r="$rel" '$1==r && $2!="dangling-link"')"
  fi
fi

note=""
ctx=""
if [ "$gen_rc" -ne 0 ]; then
  note="⚠ knowledge-index の検証に失敗しました($kdir): $gen_err — 手動で \`yosage-dev-harness-knowledge-index $dir --check\` を実行して確認してください。"
  ctx="knowledge-index の検証に失敗しました。対象: $kdir — 生成器(\`$gen\`)の stderr: $gen_err — \`bash $gen $kdir --check\` を実行して確認してください。"
elif [ -n "$gen_warn" ]; then
  note="⚠ knowledge-index: このエントリに警告があります: $gen_warn"
  ctx="knowledge-index(検証は成功・exit 0)がこのエントリについて警告を出しました。該当箇所を修正してください: $gen_warn"
fi
if [ -n "$audit_lines" ]; then
  audit_human="$(printf '%s\n' "$audit_lines" | awk -F'\t' '{printf "- [%s] %s\n", $2, $3}')"
  note="${note}${note:+
}⚠ knowledge 構造監査: このエントリに構造的欠陥が見つかりました:
${audit_human}"
  ctx="${ctx}${ctx:+
}knowledge 構造監査(lib/knowledge-audit.sh)がこのエントリに以下の構造的欠陥を検出しました。該当箇所を修正してください:
${audit_human}"
fi

if [ -n "$note" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$note" --arg c "$ctx" '{systemMessage:$m,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys;print(json.dumps({"systemMessage":sys.argv[1],"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[2]}}))' "$note" "$ctx"
  fi
  # jq/python3 どちらも無ければ通知手段が無い(=不可視)が、その環境では入力 JSON の
  # パース自体も既に不可能なので、この hook 全体が事実上 no-op になっている。
fi
exit 0
