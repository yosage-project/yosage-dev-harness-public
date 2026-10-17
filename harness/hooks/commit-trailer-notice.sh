#!/usr/bin/env bash
# PostToolUse(Bash) フック: commit 時点での Co-Authored-By 署名トレーラ欠落に気づかせる。
#
# 背景: squash しない運用ではコミットは履歴に残る。マージ前に署名トレーラの欠落が判明すると
# 「push 済み履歴の書き換え(force push)」という取り消し不能な操作をしないと直せない状況が
# 生まれる(実際に、統制側がこの状況に直面して push 済みブランチの履歴を人間の確認なしに
# 書き換えてしまった事故がある)。トレーラの欠落を commit の時点で捕まえられれば、この状況
# そのものが生じない。
#
# なぜハードブロックしないか: トレーラの要否は無条件ではない。ルール `commit`の
# 「Co-Authored-By 署名トレーラ」節が正本で、コミット先リポジトリの所有(自社所有か)と、
# 自社所有でない場合は project-profile の開示宣言の有無で分岐する。この判断材料(所有・開示宣言)
# は導入先固有の事実であり、このフック(全 install 先へ配布される汎用スクリプト)は機械的に
# 持たない。無条件に強制すると規約(自社所有でない・未宣言なら「付けない」が既定)に反するため、
# hard block ではなく additionalContext で気づかせるだけに留める(判断は commit.md の条件に
# 従って actor/人間が行う)。
#
# なぜコマンド文字列を静的パースせず実際の HEAD を読むか: このハーネス自身のコミット規約は
# 複数行メッセージを heredoc 経由で組み立てる(git commit -m "$(cat <<'EOF' ... EOF)")。
# guard.sh の fold_quotes_and_heredocs はセグメント分割の安全のため heredoc 本体を意図的に
# 空行化する((D)節のコメント参照)ため、コマンド文字列の静的パースではメッセージ本文
# (トレーラを含む)を復元できない。実際に作られたコミットの HEAD を読めば、シェル展開・
# heredoc・複数 -m の連結など、どの書き方で組み立てられたメッセージでも一律に正しく検査できる。
#
# 判定は「直近に作られたコミットが古いままトレーラを欠いていないか」に限定する(cwd 配下の
# git リポジトリの HEAD)。commit 以外の Bash 呼び出しにも毎回発火するが、以下の安価な前置
# フィルタ(コマンド文字列に "commit" という文字列が含まれるか)で大半を早期に抜け、
# 実際に git を呼ぶのは commit らしき呼び出しの直後だけに絞る(セッション全体のオーバーヘッドを
# 抑える。厳密な構文判定ではなく best-effort の前置フィルタ)。
set -uo pipefail
input="$(cat)"

jqget() { command -v jq >/dev/null 2>&1 && printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

# jq が無い環境向けの python3 フォールバック(guard.sh の get_cmd/get_cwd と同じ2段構え)。
get_cmd_py() {
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$input" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null
}
get_cwd_py() {
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$input" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null
}

cmd="$(jqget '.tool_input.command // empty')"
if [ -z "$cmd" ] && ! command -v jq >/dev/null 2>&1; then cmd="$(get_cmd_py)"; fi
[ -n "$cmd" ] || exit 0

# 前置フィルタ: "commit" という文字列を含まないコマンドは対象外(commit-tree・cherry-pick 等の
# 取りこぼしを許容する best-effort。本チェックは非ブロッキングの気づかせ目的であり、厳密な
# コマンド解析より実装の単純さ・低オーバーヘッドを優先した意図的な判断)。
printf '%s' "$cmd" | grep -q "commit" || exit 0
# --dry-run はコミットを作らない。--no-verify/-n によるバイパスは別のガード((A))が扱う対象
# であり、ここで二重に警告しない(このチェックはコミットが実際に作られたかどうかで判定するため、
# --dry-run で何も作られなければ後段の「直近のコミット」判定が自然に対象外になるが、明示しておく)。
printf '%s' "$cmd" | grep -Eq -- '--dry-run\b' && exit 0

command -v git >/dev/null 2>&1 || exit 0

cwd="$(jqget '.cwd // empty')"
if [ -z "$cwd" ] && ! command -v jq >/dev/null 2>&1; then cwd="$(get_cwd_py)"; fi
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"

repo="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
git -C "$repo" rev-parse -q --verify HEAD >/dev/null 2>&1 || exit 0

# 直近に作られたコミットだけを対象にする(fail-safe): commit が pre-commit フック等で失敗した
# 場合、HEAD は動かず古いコミットを指したままになる。委細構わず毎回検査すると、無関係な古い
# コミットへ繰り返し警告することになるため、コミット日時が「直近」(15秒以内)の場合に限る
# (best-effort・境界ではない。この Bash 呼び出しが実際にそのコミットを作ったことの厳密な
# 証明ではなく、直近の HEAD を対象にする緩い近似)。
committed_at="$(git -C "$repo" log -1 --format=%ct 2>/dev/null)" || exit 0
[ -n "${committed_at:-}" ] || exit 0
now="$(date -u +%s)"
age=$((now - committed_at))
{ [ "$age" -ge 0 ] && [ "$age" -le 15 ]; } 2>/dev/null || exit 0

msg="$(git -C "$repo" log -1 --format=%B 2>/dev/null)" || exit 0
printf '%s\n' "$msg" | grep -Eq '^Co-Authored-By:' && exit 0

head_short="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)"
note="⚠ 直近のコミット(${head_short:-HEAD})に Co-Authored-By 署名トレーラがありません。squash しない運用ではマージ後には補えません。要否はルール commit の「Co-Authored-By 署名トレーラ」節(リポジトリの所有・開示宣言の有無で判断)に従って確認してください。付けるべきだと判断した場合、まだ push していなければ今のうちに 'git commit --amend' で直せます。既に push 済みなら、書き換えず・force push もせず、人間へ報告して指示を仰いでください(push 済み履歴の書き換えは取り消し不能です)。"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$note" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys;print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}}))' "$note"
fi
# jq/python3 どちらも無ければ無処理(非ブロッキング。CLAUDE.md フック規約: 常に exit 0)
exit 0
