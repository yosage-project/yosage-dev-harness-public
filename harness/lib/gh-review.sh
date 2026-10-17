#!/usr/bin/env bash
# gh-review.sh — PR へレビューを1回の review 送信で投稿する、または既存レビュースレッドへ返信するラッパー。
#
# 一次レビュー(yosage-dev-harness:code-reviewer / yosage-dev-harness:consistency-reviewer / yosage-dev-harness:best-practice-reviewer)の投稿経路と、
# その指摘への返信経路をこの1本に封じ込める。settings の Bash 許可はこのラッパー呼び出しだけに
# 絞られており(gh api への広い許可を持たない)、破壊的な gh api サブコマンド(PR マージ等)は
# ここを経由できない(許可を「意味単位」に寄せることで、許可文字列の前方一致が持つ表現力の限界を
# 回避する)。
#
# 使い方(review 投稿・既定):
#   yosage-dev-harness-gh-review <pr-number> [--repo <owner>/<repo>] [--file <json-path>]
#   JSON は既定で stdin から読む(--file 指定時はファイルから読む)。
#
# 使い方(返信モード・--reply-to 指定時のみ):
#   yosage-dev-harness-gh-review <pr-number> --reply-to <review-comment-id> [--repo <owner>/<repo>] [--file <json-path>]
#   JSON は { "body": "<返信本文>" } のみを見る(comments は無視する)。
#   返信は元のレビュー投稿(POST .../reviews)とは別エンドポイント(POST .../comments、in_reply_to
#   付き)へ変換される。返信は review ではないため event は意味を持たない。event キーを含む入力
#   JSON を渡すとエラーで終了する(黙って無視すると、呼び出し側が「指定した内容で投稿された」と
#   誤認しうるため)。
#   返信先の <review-comment-id> は review comment の id(issue comment の id ではない)。
#   取得は読み取り API で行う: gh api repos/<owner>/<repo>/pulls/<pr>/comments --jq '.[] | {id, path, line}'
#   review comment の id 以外(issue comment の id 等)を渡した場合、GitHub API がエラーを返し、
#   このラッパーも非ゼロ終了する(成功したように見えない)。
#   **返信は冪等ではない**: 同じ返信を2回投稿すると重複コメントが2件付く(呼び出し側が
#   二重送信しないよう注意する)。
#
# 使い方(resolve モード・--resolve 指定時のみ):
#   yosage-dev-harness-gh-review <pr-number> --resolve <review-comment-id> [--repo <owner>/<repo>]
#   JSON 入力は取らない(resolve に本文は無いため stdin を読みにいかない。パイプ元が無くても
#   ハングしない)。**--file と併用するとエラーで終了する**(exit 1。渡された --file の中身を黙って
#   無視すると、呼び出し側が「指定した内容が使われた」と誤認しうるため。--reply-to に event キーを
#   渡したときと同じ理由・同じ扱い)。--reply-to と --resolve は同時に指定できない(別モードのため exit 1)。
#   resolve は返信と**構造が異なる**(実測して確認済み)。
#     - REST ではなく GraphQL の `resolveReviewThread` mutation。
#     - REST の review comment id(<review-comment-id>。--reply-to と同じ形式・取得手段)からは
#       直接 resolve できず、まず GraphQL で PR の reviewThreads を引いて対象コメントを含む
#       スレッドの node id(`PRRT_...`)を特定する中間ステップが要る。
#     - そのため呼び出しは2回以上(GraphQL query でスレッド id 解決 → GraphQL mutation で resolve)。
#       返信(1回の POST)とは呼び出し回数も endpoint 種別も違う。
#   **スレッド id 解決のページング**: スレッド一覧(reviewThreads)は cursor ページングで全件を
#   走査する(先頭ページで打ち切らない)。往復の多い PR で新しいスレッドが積み重なる経路(=
#   スレッド数が増える経路)では取りこぼしが起きない。一方、**各スレッド内のコメント一覧
#   (comments)はページングしない**(先頭ページ分のみ)。1つのスレッド内の返信の応酬がその
#   上限を超えるのは現実的な運用では稀だが、原理的には取りこぼしうる——この軸では取りこぼしを
#   解消していない(採らなかった側の帰結)。代わりに、上限に達しているスレッドが走査中に
#   1つでもあれば検出し、最終的に見つからなかった場合のメッセージを「存在しない id」から
#   区別する(「見つからない」と「(スレッド内コメントの上限到達で)見ていない可能性がある」を
#   混同させない。誤った id と誤認させないことが、このモードの存在意義)。
#   --repo 未指定時は `gh repo view --json owner,name` で現在の git remote から owner/repo を
#   解決する(review/reply モードが使う REST の `{owner}/{repo}` プレースホルダは GraphQL クエリの
#   変数には無いため、明示的に解決する)。
#   **resolve は冪等**: 既に resolve 済みのスレッドに対して呼んでも `resolveReviewThread` は
#   エラーにならず `isResolved: true` を返す(GitHub 側の mutation 自体が冪等)。同じ id へ
#   複数回呼んでも重複した副作用は起きない(返信の非冪等性とは対照的な性質)。
#   **unresolve は提供しない**(誤って resolve した場合に戻す手段は無い。含めないほうが安全側という
#   判断。必要になったら別途追加を検討する)。
#   失敗するとき(成功したように見えない): 存在しない/review comment ではない id を指定した場合は
#   スレッド id 解決の時点(全ページ走査後)で空になり非ゼロ終了する。この場合、走査中にコメント
#   一覧の上限に達したスレッドが無かったかどうかでメッセージが変わる(上記)。権限が無い場合は
#   GraphQL 呼び出し自体(スレッド id 解決 or mutation)が非ゼロ終了し、その旨を stderr に出す。
#   mutation が成功しても応答の `isResolved` が true でない場合も非ゼロ終了する(応答だけで
#   成功とみなさない)。スレッド一覧の走査には安全弁として上限ページ数を設けており(暴走防止。
#   通常の PR 規模では到達しない)、到達した場合も「id 誤り」とは異なる専用メッセージで
#   非ゼロ終了する。
#
# 入力 JSON スキーマ(review 投稿モード):
#   {
#     "body": "<review 全体のサマリ本文>",
#     "event": "COMMENT" | "REQUEST_CHANGES",
#     "comments": [
#       { "path": "<file>", "line": <int>, "body": "<コメント本文>" }
#     ]
#   }
#   各コメントの severity(🔴/🟡/🟢)・欠陥/トレードオフラベルは、呼び出し側が comments[].body の
#   テキストに含めて渡す(このラッパーは投稿を1回にまとめるだけで、レビュー内容の整形は関与しない)。
#   event は COMMENT / REQUEST_CHANGES のみ許可する(APPROVE は拒否して exit 1。マージは人間の
#   チェックポイントという pr-loop の不変を、レビュー投稿の入口でも機械的に担保するため)。
#   event: REQUEST_CHANGES かつ投稿者自身が PR 作成者(self-authored)の場合、GitHub API は
#   422 を返し投稿全体(サマリ・インライン共)が無言に失われる。このラッパーは投稿前に認証
#   ユーザと PR 作成者を比較し、一致すれば event を COMMENT へ自動フォールバックする(理由を
#   stderr へ出力。呼び出し側は REQUEST_CHANGES を渡し続けてよい)。
#
# 実行: gh api repos/{owner}/{repo}/pulls/<pr-number>/reviews (返信モードは .../comments) への
#   1回の POST(--input -)に変換して送る。
#   --repo 未指定時は gh のデフォルト解決(現在の git remote)に委ねる(プレースホルダ {owner}/{repo} のまま)。
#   --repo 指定時は gh api に -R/--repo フラグが無いため、owner/repo をパスへ直接埋め込む
#   (repos/<owner>/<repo>/pulls/<pr-number>/reviews または .../comments)。エンドポイントパスへ
#   結合する前に owner/repo 形(スラッシュ1つ区切り・両セグメント非空・空白なし)を検証し、
#   外れていれば gh api を呼ぶ前に非ゼロ終了で停止する(silently-wrong な API パス構成を避ける。
#   返信モードでも同じ検証をそのまま通す)。
#   event: REQUEST_CHANGES のときは self-authored 判定のため追加で2回の GET(gh api user /
#   PR 情報取得)が先に走る(review 投稿そのものは変わらず1回の POST)。返信モードではこの
#   判定自体を行わない(event が存在しないため)。resolve モードは review 投稿(POST reviews)を
#   経由しない別経路(GraphQL query→mutation)であり、event の概念自体が存在しない。
#
# 組織境界の識別子の警告(ブロックしない・review/reply 投稿のみが対象。resolve は本文を
#   投稿しないため対象外):
#   --repo 指定時のみ判定する(--repo 未指定時は gh の暗黙解決により現在のリポジトリへ投稿する
#   ことになり、宛先は常に自分自身なので越境しない)。
#   自組織 = 現在地から上へ辿って見つかる、最も外側の git リポジトリ(探索は
#   ハーネスの `lib/git-outermost-root.sh` の `git_outermost_root()` を source して使う共有実装。
#   `yosage-dev-harness-epic-scope-resolve` の計画ドキュメント置き場解決も同じ関数を使う)の owner
#   (自分自身を候補に含める。上に他のリポジトリが無ければ自分自身が最も外側)。ワークスペース構成では、同居する
#   メンバーリポジトリは現在のリポジトリの「子」であって「親の兄弟」ではないため、上方向へ
#   辿って外側の境界を探す。自分自身を候補に含めることで、cwd がワークスペースリポジトリ
#   そのもの(その管理者がまさに作業する位置)でも、単発の repo(上に他のリポジトリが無い)
#   でも、特別分岐なしに自組織を導出できる。単発構成では自組織=自分自身の owner になり、
#   自分自身への投稿(宛先owner=自組織owner)は後段の判定で自動的にスキップされ、別組織への
#   投稿ではその repo 自身の owner/name が保護対象になる(従来の「外側が無ければ検査しない」
#   という分岐は不要)。
#   保護対象の識別子 = その外側リポジトリの owner 名 ＋ その配下(ワークスペース)に同居する
#   リポジトリのうち、その owner に属するものの repo 名。他 owner のメンバーリポジトリ(客先
#   org のリポジトリ等)の名前は保護対象に含めない。認証ユーザの login は使わない(投稿主体は
#   内外どちらでも同じなので、主体の identity では組織境界を判定できない。加えて受託では
#   客先 org にメンバーとして招かれることがあり、所属組織の一覧を引いても客先 org が「自分の
#   所属」として返るため、同じ穴が残る。境界は主体ではなく配置=どこに置かれているかから導く)。
#   --repo で指定した投稿先の owner が自組織と異なる場合に、投稿本文(body・返信本文・レビューの
#   各コメント本文)に保護対象の識別子が含まれていないかを調べる。設定ファイルは持たない
#   (git remote から動的に導出するため、環境ごとの設定忘れが起きない)。一致しても投稿は止めない
#   (stderr に警告を出すのみ)。一致した語そのものはメッセージに出さず、宛先と一致件数のみを
#   出す(出すとその出力が別の成果物へ転記されうるため)。
set -uo pipefail

# 最も外側の git リポジトリを探す共有ロジック(git_outermost_root)を source する
# (`yosage-dev-harness-epic-scope-resolve` の計画ドキュメント置き場解決も同じ関数を使う共有実装)。
# shellcheck source=./git-outermost-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/git-outermost-root.sh"

usage() {
  echo "usage: $0 <pr-number> [--repo <owner>/<repo>] [--file <json-path>] [--reply-to <review-comment-id>] [--resolve <review-comment-id>]" >&2
  exit 1
}

# <remote-url> から "owner name" を1行で返す(空白区切り)。解決できなければ何も出力しない。
# scp-like syntax(git@host:owner/repo.git)・https(https://host/owner/repo.git)・
# ssh://host/owner/repo.git のいずれにも対応する。
_ghr_parse_owner_repo() {
  local url="$1"
  [ -n "$url" ] || return 0
  url="${url%.git}"
  case "$url" in
    git@*:*) url="${url#*:}" ;;
    *://*) url="${url#*://}"; url="${url#*/}" ;;
  esac
  local name="${url##*/}"
  local rest="${url%/*}"
  local owner="${rest##*/}"
  if [ -n "$owner" ] && [ -n "$name" ] && [ "$owner" != "$url" ]; then
    printf '%s %s\n' "$owner" "$name"
  fi
}

# <root-dir> [<max-depth>] [<max-visits>] : root-dir 配下(root-dir 自身は含まない)にある
# git リポジトリのディレクトリを1行1件で列挙する。リポジトリ境界(.git の存在)を見つけたら、
# その配下へは descend しない(prune。ネストした submodule 相当や .git 内部のオブジェクト群を
# 辿ってコストが膨らむのを避ける)。max-depth は既定 6(見つからないまま辿る深さの上限。
# ワークスペース直下 + worktree 収納ディレクトリの1段下、程度を想定した保守的な上限)。
# max-visits は既定 5000(訪問した子ディレクトリの延べ数の上限)。深さの範囲内であっても、
# 依存パッケージの展開先等の巨大な非 git ディレクトリ(数千ディレクトリになりうる)が
# あると全て歩いてしまうため、深さとは別に総数でも打ち切る。上限に達すると走査を打ち切って
# それまでに見つかった分だけを返す(黙って打ち切る。呼び出し側=保護対象の識別子収集が
# 減る=警告が弱くなる=検出漏れが増えうる、という帰結を招くが、投稿のたびに出るメッセージを
# 増やすと警告の常態化=慣れを招くため、ここでは何も出力しない)。
_ghr_scan_repos_under() {
  local root="$1" max_depth="${2:-6}" max_visits="${3:-5000}"
  local queue=("$root:0") item dir depth d visited=0
  while [ "${#queue[@]}" -gt 0 ]; do
    item="${queue[0]}"
    queue=("${queue[@]:1}")
    dir="${item%:*}"
    depth="${item##*:}"
    [ "$depth" -le "$max_depth" ] || continue
    for d in "$dir"/*/; do
      [ -d "$d" ] || continue
      visited=$((visited + 1))
      [ "$visited" -le "$max_visits" ] || return 0
      d="${d%/}"
      if [ -e "$d/.git" ]; then
        printf '%s\n' "$d"
        continue
      fi
      queue+=("$d:$((depth + 1))")
    done
  done
}

# 自組織(現在地から上へ辿って見つかる、最も外側の git リポジトリ。自分自身を含む)の owner を
# _GHR_OWN_OWNER(単一値)へ、その owner に属する同居リポジトリ(外側のリポジトリ自身を含む)の
# repo 名を _GHR_OWN_NAMES(配列)へ集める。認証ユーザの login は使わない(ファイル冒頭コメント
# 参照。投稿主体では組織境界を判定できないため、配置=どこに置かれているかから導く)。
# 検査しないのは次の2つの場合だけ: (1) 現在地が git リポジトリの外(git_outermost_root が
# 解決できない)、(2) 外側のリポジトリ(自分自身を含む)の remote が解決できない。いずれも
# fail open で _GHR_OWN_OWNER を空のまま返す(本チェックは警告のみのため、導出できないことを
# 理由に処理を止めない)。単発構成(自分自身の上に他の git リポジトリが無い)は特別扱いしない
# (git_outermost_root の探索で自然に自分自身が「最も外側」になる)。
_ghr_collect_own_identifiers() {
  _GHR_OWN_OWNER=""
  _GHR_OWN_NAMES=()
  local outer_top remote_url first_remote parsed d o n
  # 現在地から上へ辿り、最も外側の git リポジトリ(自分自身を候補に含む)を探す共有ロジック。
  outer_top="$(git_outermost_root)" || return 0

  remote_url="$(git -C "$outer_top" remote get-url origin 2>/dev/null)"
  if [ -z "$remote_url" ]; then
    first_remote="$(git -C "$outer_top" remote 2>/dev/null | head -n1)"
    [ -n "$first_remote" ] && remote_url="$(git -C "$outer_top" remote get-url "$first_remote" 2>/dev/null)"
  fi
  [ -n "$remote_url" ] || return 0
  parsed="$(_ghr_parse_owner_repo "$remote_url")"
  [ -n "$parsed" ] || return 0
  _GHR_OWN_OWNER="${parsed%% *}"
  _GHR_OWN_NAMES+=("${parsed#* }")

  # outer_top 配下(ワークスペース)に同居するリポジトリのうち、_GHR_OWN_OWNER に属するものの
  # repo 名だけを保護対象へ加える(他 owner のメンバーリポジトリの名前は含めない)。
  while IFS= read -r d; do
    remote_url="$(git -C "$d" remote get-url origin 2>/dev/null)"
    if [ -z "$remote_url" ]; then
      first_remote="$(git -C "$d" remote 2>/dev/null | head -n1)"
      [ -n "$first_remote" ] && remote_url="$(git -C "$d" remote get-url "$first_remote" 2>/dev/null)"
    fi
    [ -n "$remote_url" ] || continue
    parsed="$(_ghr_parse_owner_repo "$remote_url")"
    [ -n "$parsed" ] || continue
    o="${parsed%% *}"
    n="${parsed#* }"
    [ "$o" = "$_GHR_OWN_OWNER" ] || continue
    case " ${_GHR_OWN_NAMES[*]+${_GHR_OWN_NAMES[*]}} " in *" $n "*) : ;; *) _GHR_OWN_NAMES+=("$n") ;; esac
  done < <(_ghr_scan_repos_under "$outer_top")
}

# <api_payload json> <dest_owner> <dest_repo> : 投稿本文(body・comments[].body)に、
# 自組織(外側のリポジトリの owner ＋ その配下に同居する自組織リポジトリの repo 名)の識別子が
# 含まれていれば stderr へ警告する(ブロックしない・常に exit 0)。一致した語そのものは
# 出さない(宛先と件数のみ)。
_ghr_warn_outbound_identifiers() {
  local payload="$1" dest_owner="$2" dest_repo="$3" text hit ident seen
  [ -n "$dest_owner" ] || return 0
  _ghr_collect_own_identifiers
  [ -n "$_GHR_OWN_OWNER" ] || return 0
  [ "$dest_owner" != "$_GHR_OWN_OWNER" ] || return 0

  if command -v jq >/dev/null 2>&1; then
    text="$(printf '%s' "$payload" | jq -r '[(.body // ""), ((.comments // []) | map(.body // "") | join("\n"))] | join("\n")' 2>/dev/null)"
  elif command -v python3 >/dev/null 2>&1; then
    text="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
parts = [d.get("body") or ""]
for c in (d.get("comments") or []):
    parts.append(c.get("body") or "")
print("\n".join(parts))
' 2>/dev/null)"
  else
    return 0
  fi
  [ -n "$text" ] || return 0

  hit=0
  seen=""
  for ident in "$_GHR_OWN_OWNER" "${_GHR_OWN_NAMES[@]+"${_GHR_OWN_NAMES[@]}"}"; do
    [ -n "$ident" ] || continue
    case "$seen" in *"|${ident}|"*) continue ;; esac
    seen="${seen}|${ident}|"
    # here-string(パイプではなく単純なリダイレクト)で渡す。`printf ... | grep -qi` という
    # 素朴なパイプだと、`grep -q` は一致した時点で読み込みを打ち切るため、`printf` 側がまだ
    # 書き込み中だと SIGPIPE(終了コード141)で終了しうる。set -o pipefail 下ではこの141が
    # パイプライン全体の終了コードになり、実際には一致していたのに「不一致」として扱ってしまう
    # (高負荷でタイミングがずれると顕在化するレース。$text は PR 本文＋全コメントの連結で
    # サイズが大きくなりうる)。
    # here-string はパイプラインの一員ではない: `<<<` の中身を書き込むのはコマンド起動前の
    # シェル自身であり、`grep` を fork/exec する時点で書き込みは既に完了している。SIGPIPE を
    # 受けうる別プロセスの書き手が存在しないため、この種のレースが構造的に起きない(パイプが
    # 実ファイルを経由するかどうかというシェル実装の詳細には依らない)。
    # なお元は `printf '%s'`(末尾改行なし)だったのに対し、here-string(`<<<`)は渡す内容の
    # 末尾に改行を1つ付加する。ここでは `-F` の部分一致(exact line match ではない)なので、
    # この末尾改行の有無は判定結果に影響しない。
    if grep -F -qi -- "$ident" <<< "$text"; then
      hit=$((hit + 1))
    fi
  done

  if [ "$hit" -gt 0 ]; then
    echo "gh-review.sh: 警告: 投稿先 ${dest_owner}/${dest_repo} はワークスペースに同居するリポジトリと異なる組織です。投稿本文にワークスペース内リポジトリの識別子が ${hit} 件含まれている可能性があります(一致した語は表示しません。投稿前に見直してください)。" >&2
  fi
  return 0
}

[ $# -ge 1 ] || usage
pr="$1"; shift
case "$pr" in
  ''|*[!0-9]*) usage ;;
esac

repo=""
repo_set=0
jsonfile=""
reply_to=""
reply_to_set=0
resolve_id=""
resolve_set=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      [ $# -ge 2 ] || usage
      repo="$2"; repo_set=1; shift 2 ;;
    --file)
      [ $# -ge 2 ] || usage
      jsonfile="$2"; shift 2 ;;
    --reply-to)
      [ $# -ge 2 ] || usage
      reply_to="$2"; reply_to_set=1; shift 2 ;;
    --resolve)
      [ $# -ge 2 ] || usage
      resolve_id="$2"; resolve_set=1; shift 2 ;;
    *) usage ;;
  esac
done

# --reply-to と --resolve は別モード(構造が違う。ファイル冒頭コメント参照)なので同時指定を拒否する。
if [ "$reply_to_set" = "1" ] && [ "$resolve_set" = "1" ]; then
  echo "gh-review.sh: --reply-to と --resolve は同時に指定できません(別のモードです)" >&2
  exit 1
fi

# --resolve は JSON 入力を取らない(resolve に本文は無い)。--file が渡された場合、黙って無視すると
# 呼び出し側が「指定した内容が使われた」と誤認しうる(--reply-to に event キーを渡したときと同じ
# 理由でエラーにする。ファイル冒頭コメント参照)。
if [ "$resolve_set" = "1" ] && [ -n "$jsonfile" ]; then
  echo "gh-review.sh: --resolve(resolve モード)では --file を指定できません(resolve は JSON 入力を取りません)。--file を取り除いてください。" >&2
  exit 1
fi

# --reply-to は返信先の review comment id(数値)を要求する(PR番号と同じ形式検証)。
if [ "$reply_to_set" = "1" ]; then
  case "$reply_to" in
    ''|*[!0-9]*)
      echo "gh-review.sh: --reply-to は数値の review comment id を指定してください(指定値: ${reply_to})" >&2
      exit 1
      ;;
  esac
fi

# --resolve も同じ形式の review comment id(数値)を要求する(取得手段は --reply-to と同じ)。
if [ "$resolve_set" = "1" ]; then
  case "$resolve_id" in
    ''|*[!0-9]*)
      echo "gh-review.sh: --resolve は数値の review comment id を指定してください(指定値: ${resolve_id})" >&2
      exit 1
      ;;
  esac
fi

# --repo 指定時は owner/repo 形を検証してから使う(gh api を呼ぶ前に落とす。owner/repo 形以外を
# そのままエンドポイントパスへ結合すると、意図しない API パスを silently に構成しうるため)。
invalid_repo() {
  echo "gh-review.sh: --repo は owner/repo 形式で指定してください(指定値: ${repo})" >&2
  exit 1
}
if [ "$repo_set" = "1" ]; then
  case "$repo" in
    ''|*[[:space:]]*|*/*/*|/*|*/) invalid_repo ;;
    */*) : ;;
    *) invalid_repo ;;
  esac
  # ここまで通れば "owner/repo" 形(スラッシュちょうど1個・両セグメント非空・空白なし)。
  # 片方のセグメントだけが "." / ".." のケース(例: "../foo" "foo/.." )はスラッシュが1個しか
  # 無いため上の case をすり抜けるので、セグメントごとに個別チェックする(パス越え対策)。
  repo_owner="${repo%%/*}"
  repo_name="${repo#*/}"
  case "$repo_owner" in
    .|..) invalid_repo ;;
  esac
  case "$repo_name" in
    .|..) invalid_repo ;;
  esac
fi

# resolve モード: JSON入力(stdin/--file)は使わない。review/reply モードの読み込み(下)より
# 前で完結させ、stdin を読みにいかない(呼び出し側が何もパイプしなくてもハングしない)。
if [ "$resolve_set" = "1" ]; then
  if [ "$repo_set" = "1" ]; then
    gr_owner="$repo_owner"
    gr_repo="$repo_name"
  else
    # --repo 未指定時は現在の git remote から owner/repo を解決する(review/reply モードが使う
    # REST の {owner}/{repo} プレースホルダは GraphQL クエリの変数には存在しないため)。
    gr_repo_view="$(gh repo view --json owner,name 2>&1)"; gr_repo_view_status=$?
    if [ "$gr_repo_view_status" -ne 0 ]; then
      echo "gh-review.sh --resolve: --repo 未指定時のリポジトリ解決(gh repo view)に失敗しました: ${gr_repo_view}" >&2
      exit 1
    fi
    if command -v jq >/dev/null 2>&1; then
      gr_owner="$(printf '%s' "$gr_repo_view" | jq -r '.owner.login // empty')"
      gr_repo="$(printf '%s' "$gr_repo_view" | jq -r '.name // empty')"
    else
      gr_owner="$(printf '%s' "$gr_repo_view" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print((d.get("owner") or {}).get("login") or "")
except Exception:
    print("")
' 2>/dev/null)"
      gr_repo="$(printf '%s' "$gr_repo_view" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("name") or "")
except Exception:
    print("")
' 2>/dev/null)"
    fi
  fi
  if [ -z "$gr_owner" ] || [ -z "$gr_repo" ]; then
    echo "gh-review.sh --resolve: owner/repo の解決に失敗しました" >&2
    exit 1
  fi

  # 1) review comment id(REST) -> 対応する review thread の GraphQL node id を引く。
  #    採用した対応: reviewThreads(外側のスレッド一覧)は cursor ページングで全件を走査する。
  #    comments(スレッド内のコメント一覧)は引き続き固定ページのまま(ページングしない)。
  #    走査中に comments 側が上限に達しているスレッドを検出したら gr_inner_cap_hit を立て、
  #    最終的に見つからなかった場合のメッセージをそれで出し分ける(下記)。
  #    ページサイズはテストでの境界到達検証のために環境変数で上書きできる(既定は GitHub 側の
  #    上限である100件のまま)。
  gr_page_size="${GHR_RESOLVE_PAGE_SIZE:-100}"
  gr_comment_page_size="${GHR_RESOLVE_COMMENT_PAGE_SIZE:-100}"
  gr_cursor=""
  gr_page_no=0
  gr_max_pages=50
  gr_inner_cap_hit=0
  thread_id=""
  gr_query='
    query($owner:String!, $repo:String!, $pr:Int!, $pageSize:Int!, $commentPageSize:Int!, $cursor:String) {
      repository(owner:$owner, name:$repo) {
        pullRequest(number:$pr) {
          reviewThreads(first: $pageSize, after: $cursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              comments(first: $commentPageSize) {
                pageInfo { hasNextPage }
                nodes { databaseId }
              }
            }
          }
        }
      }
    }'
  gr_jq_filter="{found: ((.data.repository.pullRequest.reviewThreads.nodes // []) | map(select(any((.comments.nodes // [])[]; .databaseId == ${resolve_id}))) | (.[0].id // null)), hasNext: (.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage // false), endCursor: (.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // \"\"), innerCap: ((.data.repository.pullRequest.reviewThreads.nodes // []) | any(.comments.pageInfo.hasNextPage == true))}"

  while :; do
    gr_page_no=$((gr_page_no + 1))
    if [ "$gr_page_no" -gt "$gr_max_pages" ]; then
      echo "gh-review.sh --resolve: review thread の走査が安全上限(${gr_max_pages}ページ)に達しました(PR #${pr})。review comment id ${resolve_id} が誤りとは断定できません——スレッド数が想定を大きく超えている可能性があります。" >&2
      exit 1
    fi
    if [ -z "$gr_cursor" ]; then
      gr_cursor_args=(-F cursor=null)
    else
      gr_cursor_args=(-f cursor="$gr_cursor")
    fi
    gr_stderr="$(mktemp)"
    gr_page="$(gh api graphql -f query="$gr_query" -f owner="$gr_owner" -f repo="$gr_repo" -F pr="$pr" \
      -F pageSize="$gr_page_size" -F commentPageSize="$gr_comment_page_size" "${gr_cursor_args[@]}" \
      -q "$gr_jq_filter" \
      2>"$gr_stderr")"
    gr_page_status=$?
    if [ "$gr_page_status" -ne 0 ]; then
      echo "gh-review.sh --resolve: review thread の検索(GraphQL)に失敗しました(PR #${pr}, review comment id=${resolve_id}): $(cat "$gr_stderr" 2>/dev/null)" >&2
      rm -f "$gr_stderr"
      exit 1
    fi
    rm -f "$gr_stderr"

    if command -v jq >/dev/null 2>&1; then
      gr_found="$(printf '%s' "$gr_page" | jq -r '.found // empty')"
      gr_has_next="$(printf '%s' "$gr_page" | jq -r 'if .hasNext then "true" else "false" end')"
      gr_end_cursor="$(printf '%s' "$gr_page" | jq -r '.endCursor // empty')"
      gr_page_inner_cap="$(printf '%s' "$gr_page" | jq -r 'if .innerCap then "true" else "false" end')"
    else
      gr_found="$(printf '%s' "$gr_page" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("found") or "")
except Exception:
    print("")
' 2>/dev/null)"
      gr_has_next="$(printf '%s' "$gr_page" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("true" if d.get("hasNext") else "false")
except Exception:
    print("false")
' 2>/dev/null)"
      gr_end_cursor="$(printf '%s' "$gr_page" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("endCursor") or "")
except Exception:
    print("")
' 2>/dev/null)"
      gr_page_inner_cap="$(printf '%s' "$gr_page" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("true" if d.get("innerCap") else "false")
except Exception:
    print("false")
' 2>/dev/null)"
    fi

    if [ "$gr_page_inner_cap" = "true" ]; then
      gr_inner_cap_hit=1
    fi
    if [ -n "$gr_found" ]; then
      thread_id="$gr_found"
      break
    fi
    if [ "$gr_has_next" != "true" ] || [ -z "$gr_end_cursor" ]; then
      break
    fi
    gr_cursor="$gr_end_cursor"
  done

  if [ -z "$thread_id" ]; then
    if [ "$gr_inner_cap_hit" = "1" ]; then
      echo "gh-review.sh --resolve: review comment id ${resolve_id} に対応する review thread が見つかりません(PR #${pr})。ただし走査中に、コメント一覧が上限(${gr_comment_page_size}件)に達しているスレッドが少なくとも1つありました(スレッド内コメントはページングしていません)。対象がその先に存在する可能性があり、id が誤っているとは断定できません。" >&2
    else
      echo "gh-review.sh --resolve: review comment id ${resolve_id} に対応する review thread が見つかりません(PR #${pr})。存在しない id、または review comment の id ではない(issue comment の id 等)可能性があります。" >&2
    fi
    exit 1
  fi

  # 2) resolveReviewThread mutation(1で得たスレッド id を渡す)。
  gr_stderr2="$(mktemp)"
  resolved_flag="$(gh api graphql -f query='
    mutation($id:ID!) {
      resolveReviewThread(input: {threadId: $id}) { thread { id isResolved } }
    }' -f id="$thread_id" \
    -q '.data.resolveReviewThread.thread.isResolved' \
    2>"$gr_stderr2")"
  mutation_status=$?
  if [ "$mutation_status" -ne 0 ]; then
    echo "gh-review.sh --resolve: resolveReviewThread(GraphQL mutation)に失敗しました(thread id=${thread_id})。権限不足の可能性があります: $(cat "$gr_stderr2" 2>/dev/null)" >&2
    rm -f "$gr_stderr2"
    exit 1
  fi
  rm -f "$gr_stderr2"
  if [ "$resolved_flag" != "true" ]; then
    echo "gh-review.sh --resolve: resolveReviewThread の応答で isResolved=true を確認できませんでした(応答: ${resolved_flag})。成功したとはみなしません。" >&2
    exit 1
  fi

  echo "gh-review.sh --resolve: review thread を resolve しました(review comment id=${resolve_id}, thread id=${thread_id})"
  exit 0
fi

if [ -n "$jsonfile" ]; then
  [ -f "$jsonfile" ] || { echo "gh-review.sh: ファイルが見つかりません: $jsonfile" >&2; exit 1; }
  payload="$(cat "$jsonfile")"
else
  payload="$(cat)"
fi

if [ "$reply_to_set" = "1" ]; then
  # 返信モード: JSON は body のみを見る(comments は無視)。event は意味を持たないため、
  # 入力 JSON にキーとして存在するだけでエラーにする(黙って無視すると、呼び出し側が
  # 「指定した内容で投稿された」と誤認するため)。
  if command -v jq >/dev/null 2>&1; then
    has_event="$(printf '%s' "$payload" | jq -r 'has("event")')" || { echo "gh-review.sh: 入力 JSON の解析に失敗しました(jq)" >&2; exit 1; }
  elif command -v python3 >/dev/null 2>&1; then
    has_event="$(printf '%s' "$payload" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("true" if "event" in d else "false")
')" || { echo "gh-review.sh: 入力 JSON の解析に失敗しました(python3)" >&2; exit 1; }
  else
    echo "gh-review.sh: jq/python3 のいずれも見つかりません" >&2
    exit 1
  fi
  if [ "$has_event" = "true" ]; then
    echo "gh-review.sh: --reply-to(返信モード)では event を指定できません(返信は review 投稿ではなく comment 投稿であり、event は意味を持ちません)。入力 JSON から event キーを取り除いてください。" >&2
    exit 1
  fi

  if command -v jq >/dev/null 2>&1; then
    api_payload="$(printf '%s' "$payload" | jq --argjson rid "$reply_to" '{
      body: (.body // ""),
      in_reply_to: $rid
    }')" || { echo "gh-review.sh: 入力 JSON の解析に失敗しました(jq)" >&2; exit 1; }
  else
    api_payload="$(printf '%s' "$payload" | python3 -c "
import json, sys
d = json.load(sys.stdin)
out = {'body': d.get('body', ''), 'in_reply_to': ${reply_to}}
print(json.dumps(out))
")" || { echo "gh-review.sh: 入力 JSON の解析に失敗しました(python3)" >&2; exit 1; }
  fi

  if [ -n "$repo" ]; then
    # gh api に -R/--repo フラグは無い(unknown shorthand flag で失敗する)。
    # --repo 指定時はプレースホルダではなく owner/repo をパスへ直接埋め込む。
    endpoint="repos/${repo}/pulls/${pr}/comments"
  else
    # --repo 未指定時は gh のデフォルト解決(現在の git remote)に委ねる。
    endpoint="repos/{owner}/{repo}/pulls/${pr}/comments"
  fi
else
  # 受け取った JSON から review API が要求するフィールドだけを抽出して組み立てる
  # (余計なフィールドが紛れ込んでいても無視する)。jq 優先 → python3 フォールバック。
  if command -v jq >/dev/null 2>&1; then
    api_payload="$(printf '%s' "$payload" | jq '{
      body: (.body // ""),
      event: (.event // "COMMENT"),
      comments: [ (.comments // [])[] | {path, line, body} ]
    }')" || { echo "gh-review.sh: 入力 JSON の解析に失敗しました(jq)" >&2; exit 1; }
  elif command -v python3 >/dev/null 2>&1; then
    api_payload="$(printf '%s' "$payload" | python3 -c '
import json, sys
d = json.load(sys.stdin)
out = {
    "body": d.get("body", ""),
    "event": d.get("event", "COMMENT"),
    "comments": [
        {"path": c.get("path"), "line": c.get("line"), "body": c.get("body", "")}
        for c in d.get("comments", [])
    ],
}
print(json.dumps(out))
')" || { echo "gh-review.sh: 入力 JSON の解析に失敗しました(python3)" >&2; exit 1; }
  else
    echo "gh-review.sh: jq/python3 のいずれも見つかりません" >&2
    exit 1
  fi

  # event は COMMENT / REQUEST_CHANGES のみ許可する(APPROVE 等はここで弾く。pr-loop の
  # 「APPROVE はしない/マージは人間のチェックポイント」不変をラッパー層でも機械的に守る)。
  if command -v jq >/dev/null 2>&1; then
    event_val="$(printf '%s' "$api_payload" | jq -r '.event')"
  else
    event_val="$(printf '%s' "$api_payload" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("event",""))')"
  fi
  case "$event_val" in
    COMMENT|REQUEST_CHANGES) : ;;
    *)
      echo "gh-review.sh: event は COMMENT または REQUEST_CHANGES のみ許可されます(指定値: ${event_val})。APPROVE はできません(マージは人間のチェックポイントです)。" >&2
      exit 1
      ;;
  esac

  if [ -n "$repo" ]; then
    # gh api に -R/--repo フラグは無い(unknown shorthand flag で失敗する)。
    # --repo 指定時はプレースホルダではなく owner/repo をパスへ直接埋め込む。
    endpoint="repos/${repo}/pulls/${pr}/reviews"
    pr_info_endpoint="repos/${repo}/pulls/${pr}"
  else
    # --repo 未指定時は gh のデフォルト解決(現在の git remote)に委ねる。
    endpoint="repos/{owner}/{repo}/pulls/${pr}/reviews"
    pr_info_endpoint="repos/{owner}/{repo}/pulls/${pr}"
  fi

  # self-authored 検出 ＋ 自動フォールバック(REQUEST_CHANGES → COMMENT)。
  #
  # 背景: 投稿者自身が作成した PR に REQUEST_CHANGES で投稿すると GitHub API が
  # 422(Review Can not request changes on your own pull request)を返す。このラッパーは
  # 1回の POST で body/comments をまとめて送る設計なので、422 になると投稿全体(サマリも
  # インラインも)が無言に失われる。このワークスペースは `gh pr create --assignee @me`
  # (作成者＝自分)運用で、一次レビューを投稿する主体と PR 作成者が solo では一致するのが
  # 常態なので、REQUEST_CHANGES は構造的に常に 422 になりうる。
  #
  # 対策: 投稿前に「現在の認証ユーザ」と「PR 作成者」を比較し、一致すれば event を COMMENT
  # へ落として投稿を通す(呼び出し側は REQUEST_CHANGES を渡し続けられる)。フォールバックした
  # 旨は stderr へ通知する(サイレントに severity を消さない)。severity(🔴/🟡/🟢)・欠陥/
  # トレードオフラベルは呼び出し側が body/comments[].body のテキストに埋め込む運用なので、
  # event が COMMENT に落ちても記録内容自体は失われない。
  #
  # 判定不能(gh api user / PR 情報取得が失敗)の場合も同じ理由で安全側は「フォールバックして
  # 投稿を通す」側を選ぶ(422 による無言喪失の防止を、判定不能ケースでも優先する)。
  if [ "$event_val" = "REQUEST_CHANGES" ]; then
    current_user_raw="$(gh api user 2>/dev/null)"; current_user_status=$?
    pr_author_raw="$(gh api "$pr_info_endpoint" 2>/dev/null)"; pr_author_status=$?

    if command -v jq >/dev/null 2>&1; then
      current_user="$(printf '%s' "$current_user_raw" | jq -r '.login // empty' 2>/dev/null)"
      pr_author="$(printf '%s' "$pr_author_raw" | jq -r '.user.login // empty' 2>/dev/null)"
    else
      current_user="$(printf '%s' "$current_user_raw" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("login") or "")
except Exception:
    print("")
' 2>/dev/null)"
      pr_author="$(printf '%s' "$pr_author_raw" | python3 -c '
import json, sys
try:
    print((json.load(sys.stdin).get("user") or {}).get("login") or "")
except Exception:
    print("")
' 2>/dev/null)"
    fi

    fallback_reason=""
    if [ "$current_user_status" -ne 0 ] || [ "$pr_author_status" -ne 0 ] || [ -z "$current_user" ] || [ -z "$pr_author" ]; then
      fallback_reason="gh-review.sh: 認証ユーザ/PR作成者の判定に失敗しました(gh api user または PR #${pr} の情報取得エラー)。self-authored かどうか判定不能なため、安全側で REQUEST_CHANGES を COMMENT へ自動フォールバックします(422 による投稿の無言喪失を避けるため)。"
    elif [ "$current_user" = "$pr_author" ]; then
      fallback_reason="gh-review.sh: PR #${pr} は投稿者自身(${current_user})が作成しているため、GitHub API は REQUEST_CHANGES を拒否します(422)。COMMENT へ自動フォールバックします(severity/合否はサマリ・各コメント本文のラベルに残ります)。"
    fi

    if [ -n "$fallback_reason" ]; then
      echo "$fallback_reason" >&2
      if command -v jq >/dev/null 2>&1; then
        api_payload="$(printf '%s' "$api_payload" | jq '.event = "COMMENT"')" || { echo "gh-review.sh: フォールバック用 payload の再構築に失敗しました(jq)" >&2; exit 1; }
      else
        api_payload="$(printf '%s' "$api_payload" | python3 -c '
import json, sys
d = json.load(sys.stdin)
d["event"] = "COMMENT"
print(json.dumps(d))
')" || { echo "gh-review.sh: フォールバック用 payload の再構築に失敗しました(python3)" >&2; exit 1; }
      fi
    fi
  fi
fi

# 組織境界の識別子の警告(review/reply 投稿の直前。resolve はここへ到達しない=既に exit 済み)。
# --repo 未指定時は repo_owner/repo_name が代入されていない(set -u 下で参照するとエラーになる
# ため ${...:-} で既定値を与える)。
_ghr_warn_outbound_identifiers "$api_payload" "${repo_owner:-}" "${repo_name:-}"

args=(api "$endpoint" --input -)

printf '%s' "$api_payload" | gh "${args[@]}"
