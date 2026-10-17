#!/usr/bin/env bash
# gh-subissue-link.sh — Epic Issue まわりの gh api / gh issue edit 操作をこの1本に封じ込める。
#
# harness/skills/epic-create-issues/SKILL.md の (1) Sub-issue リンク手順(addSubIssue mutation ＋
# subIssues 検証クエリでの欠け再リンクループ)と (2) Epic 本文更新(gh issue edit)を、この1本の
# ラッパーへ切り出す。settings の Bash 許可はこのラッパー呼び出しだけに絞られており(gh api / 任意
# issue への gh issue edit への広い許可を持たない)、harness/lib/gh-review.sh と同じ型(gh api は
# ラッパー内部でのみ使用、入力契約は引数)を踏襲する。
#
# 使い方:
#   yosage-dev-harness-gh-subissue-link link <epic-number> [--repo <owner>/<repo>] <sub-issue-number>...
#   yosage-dev-harness-gh-subissue-link update-body <epic-number> [--repo <owner>/<repo>] --body-file <path>
#
# link サブコマンド:
#   1. Epic ＋各 Sub-issue の GraphQL node ID を解決する(gh issue view --json id)。
#   2. addSubIssue mutation で各 Sub-issue をリンクする(gh api graphql)。
#   3. subIssues 検証クエリで Epic に実際に紐づいた番号を取得し、意図したリストと突き合わせる。
#      欠けがあれば再リンクし、再検証する(最大 MAX_RETRIES 回)。揃わなければ非ゼロ終了で
#      報告する(黙って進めない。epic-create-issues/SKILL.md 手順3のハードゲートと同じ意図)。
#
# update-body サブコマンド:
#   --body-file で渡したファイルの中身で Epic Issue の本文を更新する(gh issue edit --body-file)。
#   任意 issue への任意フィールド編集(--add-assignee 等)は許さず、この用途(Epic 本文更新)だけに
#   絞る。
#
# --repo 指定時は gh issue view / gh issue edit の --repo フラグへそのまま渡す(gh api graphql は
# グローバル node ID のみで動くため owner/repo を必要としない。gh api には -R/--repo フラグが
# 無いことに注意。harness/lib/gh-review.sh の型に倣う)。
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  gh-subissue-link.sh link <epic-number> [--repo <owner>/<repo>] <sub-issue-number>...
  gh-subissue-link.sh update-body <epic-number> [--repo <owner>/<repo>] --body-file <path>
USAGE
  exit 1
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# --repo は owner/repo 形式のみ許可する(gh-review.sh と同じ検証。パス越え・不正形式を
# gh コマンドに渡す前に落とす)。
validate_repo() {
  local repo="$1"
  case "$repo" in
    ''|*[[:space:]]*|*/*/*|/*|*/) return 1 ;;
    */*) : ;;
    *) return 1 ;;
  esac
  local repo_owner="${repo%%/*}"
  local repo_name="${repo#*/}"
  case "$repo_owner" in
    .|..) return 1 ;;
  esac
  case "$repo_name" in
    .|..) return 1 ;;
  esac
  return 0
}

[ $# -ge 1 ] || usage
mode="$1"; shift
case "$mode" in
  link|update-body) : ;;
  *) usage ;;
esac

[ $# -ge 1 ] || usage
epic="$1"; shift
is_uint "$epic" || usage

repo=""
repo_set=0

if [ "$mode" = "link" ]; then
  subs=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)
        [ $# -ge 2 ] || usage
        repo="$2"; repo_set=1; shift 2 ;;
      *)
        is_uint "$1" || usage
        subs+=("$1"); shift ;;
    esac
  done
  [ "${#subs[@]}" -ge 1 ] || usage
else
  bodyfile=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)
        [ $# -ge 2 ] || usage
        repo="$2"; repo_set=1; shift 2 ;;
      --body-file)
        [ $# -ge 2 ] || usage
        bodyfile="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$bodyfile" ] || usage
  [ -f "$bodyfile" ] || { echo "gh-subissue-link.sh: --body-file が見つかりません: $bodyfile" >&2; exit 1; }
fi

if [ "$repo_set" = "1" ]; then
  validate_repo "$repo" || { echo "gh-subissue-link.sh: --repo は owner/repo 形式で指定してください(指定値: ${repo})" >&2; exit 1; }
fi

view_args=(issue view)
[ "$repo_set" = "1" ] && view_args+=(--repo "$repo")

resolve_id() {
  # $1 = issue number → stdout に GraphQL node ID
  gh "${view_args[@]}" "$1" --json id -q '.id'
}

if [ "$mode" = "update-body" ]; then
  edit_args=(issue edit "$epic")
  [ "$repo_set" = "1" ] && edit_args+=(--repo "$repo")
  edit_args+=(--body-file "$bodyfile")
  gh "${edit_args[@]}"
  exit $?
fi

# --- link サブコマンド ---

epic_id="$(resolve_id "$epic")" || { echo "gh-subissue-link.sh: Epic #${epic} の node ID 解決に失敗しました" >&2; exit 1; }
[ -n "$epic_id" ] || { echo "gh-subissue-link.sh: Epic #${epic} の node ID が空です" >&2; exit 1; }

link_one() {
  # $1 = sub-issue number
  local sub="$1" sub_id
  sub_id="$(resolve_id "$sub")" || { echo "gh-subissue-link.sh: Sub-issue #${sub} の node ID 解決に失敗しました" >&2; return 1; }
  [ -n "$sub_id" ] || { echo "gh-subissue-link.sh: Sub-issue #${sub} の node ID が空です" >&2; return 1; }
  gh api graphql -f query='
    mutation($epic:ID!, $sub:ID!) {
      addSubIssue(input: { issueId: $epic, subIssueId: $sub }) { subIssue { number } }
    }' -f epic="$epic_id" -f sub="$sub_id" >/dev/null
}

linked_numbers() {
  gh api graphql -f query='
    query($id:ID!) {
      node(id:$id) { ... on Issue { subIssues(first:100) { totalCount nodes { number } } } }
    }' -f id="$epic_id" -q '.data.node.subIssues.nodes[].number'
}

missing_of() {
  # $1 = linked_numbers() の出力(改行区切り)。$subs 全体と突き合わせ、欠けている番号を
  # 改行区切りで返す。
  local linked="$1" sub
  for sub in "${subs[@]}"; do
    # here-string(パイプではなく単純なリダイレクト)で渡す。`printf ... | grep -Fxq` という
    # 素朴なパイプだと、`grep -q` は一致した時点で読み込みを打ち切るため、`printf` 側がまだ
    # 書き込み中だと SIGPIPE(終了コード141)で終了しうる。set -o pipefail 下ではこの141が
    # パイプライン全体の終了コードになり、実際には一致していたのに「不一致」として扱ってしまう
    # (高負荷でタイミングがずれると顕在化するレース)。
    # here-string はパイプラインの一員ではない: `<<<` の中身を書き込むのはコマンド起動前の
    # シェル自身であり、`grep` を fork/exec する時点で書き込みは既に完了している。SIGPIPE を
    # 受けうる別プロセスの書き手が存在しないため、この種のレースが構造的に起きない(パイプが
    # 実ファイルを経由するかどうかというシェル実装の詳細には依らない)。`-e` は `$sub` が
    # `-` で始まる値であってもオプションと誤認されないようにする安全策。
    if ! grep -Fxq -e "$sub" <<< "$linked"; then
      printf '%s\n' "$sub"
    fi
  done
}

for sub in "${subs[@]}"; do
  link_one "$sub" || exit 1
done

max_retries=3
attempt=0
while :; do
  linked="$(linked_numbers)" || { echo "gh-subissue-link.sh: Epic #${epic} の subIssues 検証クエリに失敗しました" >&2; exit 1; }
  missing="$(missing_of "$linked")"
  [ -z "$missing" ] && break
  attempt=$((attempt+1))
  if [ "$attempt" -gt "$max_retries" ]; then
    echo "gh-subissue-link.sh: ${max_retries}回再リンクしても Epic #${epic} に紐づかない Sub-issue があります: $(printf '%s' "$missing" | tr '\n' ' ')" >&2
    exit 1
  fi
  echo "gh-subissue-link.sh: Epic #${epic} に紐づいていない Sub-issue を再リンクします(試行${attempt}/${max_retries}): $(printf '%s' "$missing" | tr '\n' ' ')" >&2
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    link_one "$m" || exit 1
  done <<< "$missing"
done

echo "gh-subissue-link.sh: Epic #${epic} に Sub-issue ${subs[*]} をリンクしました"
