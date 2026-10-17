#!/usr/bin/env bash
# epic-implement-probe.sh — epic-implement SKILL の動的コンテキスト収集ロジック。
#
# 経緯: SKILL.md の動的コンテキスト行(`!`command`` 形式)にインラインの command substitution
# `$(…)`・`if…fi` 分岐を直書きすると、ホスト側の permission チェック(静的解析不能な複雑シェルを
# 難読化コマンドとみなすヒューリスティック)に弾かれ、SKILL 起動自体(動的コンテキストのロード)が
# 失敗する。番号抽出・分岐ロジックは複雑なので lib スクリプトへ出し、SKILL 側は
# `yosage-dev-harness-epic-implement-probe <mode> "$ARGUMENTS"` という単純呼び出しにする。
#
# Epic 番号の解決は gh-issue-resolve.sh が持つ判定ロジック(scoped <owner>/<repo>#<N> 形式の検出・
# 壊れた scoped 形式の拒否・ワークスペース直下での bare 番号拒否)を source して再利用する
# (同じ判定を2箇所に持つと片方だけ更新されて drift するため。新しい記法・設定は追加しない)。
#
# 使い方:
#   yosage-dev-harness-epic-implement-probe epic <args>       … 引数から Epic 番号(+repo)を解決し issue 本文を表示
#                                                (番号が無ければ「番号未指定」案内を表示。解決には
#                                                成功も失敗もありうる=呼び出し元は下記の終了コードを見る)
#   yosage-dev-harness-epic-implement-probe subissues <args>  … 解決できた Epic 本文中の Sub-issue 番号一覧を
#                                                重複排除して表示(repo が判明していれば
#                                                <owner>/<repo>#<N> 形式、不明なら従来どおり #<N>)。
#                                                この一覧は SKILL 全体で使い回す共有入力なので、
#                                                表示前にネイティブ Sub-issue の集合(GraphQL)と
#                                                突き合わせる。欠落側(不完全である可能性)は stderr へ
#                                                "(要確認)" 付きで警告する。過剰抽出側(ネイティブに
#                                                無い関連issueへの言及)は警告せず、ネイティブ集合が
#                                                非空のときに限り出力そのものから絞り込む(詳細は
#                                                eip_subissues のコメント)。
#
# <args> は SKILL の argument-hint 由来の生文字列(例: "42" や "42 phase1" や
# "your-org/your-repo#<N> phase1")をそのまま渡す。
#
# 終了コード(epic_implement_probe 経由。呼び出し元 SKILL の手順1が参照する):
#   0 … 番号が解決できた、または「番号未指定」(会話からの類推が妥当なケース)。subissues モードは
#       この場合でも一覧の完全性照合(上記)で警告(stderr の "(要確認)")が出ることがあるが、
#       それ自体は非ゼロ終了にしない(標準出力の一覧はそのまま出す。停止するかどうかの判断は
#       呼び出し元 SKILL の手順に委ねる)。
#   1 … epic モード: 番号は指定されたが解決に失敗した(scoped 形式が壊れている・ワークスペース
#       直下での bare 番号)。エラー理由は stderr に出力済み。呼び出し元は「会話から類推」へ進まず、
#       このエラーを提示して停止する(エラーを抱えたまま推測へ進まない)。
#       subissues モード: Epic 本文の取得そのものが失敗した(この場合のみ非ゼロ終了。標準出力は空)。
# best-effort な収集コマンドだが、番号解決・本文取得の失敗だけは非ゼロ終了で明示する(黙って進まない)。
#
# stderr(eip_log)の警告・エラーは、呼び出し元 SKILL の動的コンテキスト行(`epic-implement/SKILL.md`)
# が末尾に付ける `2>&1` によって標準出力へ合流し、SKILL 起動時にホストへ届く標準出力へ乗る。
# 動的コンテキストの実行結果のうちホストが会話コンテキストへ確実に注入するのは標準出力であり、
# 標準エラーの扱いはこのリポジトリの外(ホスト実装)に委ねられ仕様が無い。したがってこのスクリプトが
# 出す `(要確認)` 警告・解決失敗のエラーメッセージを含む stderr 出力は、呼び出し元が `2>&1` を
# 付けることを前提にしている。このスクリプトを新しい場所から呼ぶ場合は、呼び出し側で同様に
# stderr を標準出力へ合流させること(合流させないと、この関数が返す警告・エラーは呼び出し元へ
# 届く保証が無い)。
set -uo pipefail

_eip_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./gh-issue-resolve.sh
. "$_eip_dir/gh-issue-resolve.sh"

eip_log() { printf 'epic-implement-probe: %s\n' "$1" >&2; }

# 引数から Epic 番号(と repo)を解決する。
#   戻り値 0: 解決成功。_EIP_REPO(scoped でなければ空文字列)/_EIP_NUM を設定。
#   戻り値 1: 番号は見つかったが解決に失敗(理由は stderr に出力済み)。
#   戻り値 2: 番号そのものが見つからない(未指定)。
eip_resolve() {  # <args>
  local args="${1:-}" scoped bare
  _EIP_REPO=""
  _EIP_NUM=""
  scoped="$(gir_find_scoped_candidate "$args")"
  if [ -n "$scoped" ]; then
    if ! gir_is_valid_scoped "$scoped"; then
      eip_log "scoped 形式('${scoped}')に見えますが不正です(<owner>/<repo>#<N> 形式で、# の後ろは数字のみにしてください)。"
      return 1
    fi
    _EIP_REPO="$(gir_scoped_repo "$scoped")"
    _EIP_NUM="$(gir_scoped_number "$scoped")"
    return 0
  fi

  bare="$(gir_extract_bare_number "$args")"
  if [ -n "$bare" ]; then
    local _eip_ws_rc
    gir_is_workspace_mode; _eip_ws_rc=$?
    if [ "$_eip_ws_rc" = 0 ]; then
      eip_log "ワークスペース直下(設定の workspace が true)では bare な Epic 番号(${bare})を解決できません(番号衝突時に別リポジトリの issue を誤って掴む可能性があるため)。"
      eip_log "対象リポジトリを明示する <owner>/<repo>#<N> 形式で指定してください(例: your-org/your-repo#${bare})。"
      return 1
    elif [ "$_eip_ws_rc" = 2 ]; then
      eip_log "ワークスペース判定に失敗しました(設定ファイルが壊れた JSON、または jq/python3 が無い)。単一リポジトリとはみなさず停止します。"
      return 1
    fi
    _EIP_NUM="$bare"
    return 0
  fi

  return 2
}

# Epic Issue 本文を表示する。
#   - 番号未指定(eip_resolve が2): 「番号未指定 → step 1 で直前会話から類推・確認」を表示し 0 終了。
#   - 解決失敗(eip_resolve が1): eip_resolve が既に理由を stderr へ出力済みなのでここでは追加せず、
#     非ゼロ終了のみ返す(呼び出し元 SKILL は「エラーが出ている=推測へ進まず停止」と判断する)。
#   - 解決成功: issue 本文を表示。
eip_epic() {  # <args>
  local rc
  eip_resolve "${1:-}"
  rc=$?
  case "$rc" in
    0)
      if [ -n "$_EIP_REPO" ]; then
        gh issue view --repo "$_EIP_REPO" "$_EIP_NUM"
      else
        gh issue view "$_EIP_NUM"
      fi
      return $?
      ;;
    2)
      echo "番号未指定 → step 1 で直前会話から類推・確認"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Epic Issue 本文から Sub-issue 番号一覧(#N)を重複排除して表示する。
# repo が判明していれば <owner>/<repo>#<N> 形式(gh-issue-resolve.sh がそのまま解決できる形。
# 後続の dispatch 先 SKILL へそのまま渡せる)で出力する。repo が不明(bare のみ・非ワークスペース)
# なら従来どおり #<N> 形式。解決に失敗した場合は何も出力しない(eip_epic 側が理由を報告済みで、
# ここでの二重報告はしない)。
#
# この一覧は SKILL 全体(依存解析・dispatch・クローズ確認)で使い回す共有入力であり、ここでの抽出が
# 空・不完全でも下流の個々の手順からは「対象ゼロ件」と区別がつかない(何も表示されずに正常終了する)。
# そのため下流の各手順に検証を分散させず、抽出直後のここで完全性を照合する。照合先は Epic に実際に
# ネイティブリンクされている Sub-issue の集合(GraphQL subIssues.nodes[].number。gh-subissue-link.sh
# の検証クエリ(linked_numbers)と同じ照合先=構造的な正本)。
#   - ページングは `pageInfo.hasNextPage` を見て全ページ取得する(`eip_native_subissues` ヘルパ)。
#     1ページ分(first:100)しか見ないと、Sub-issue が100件を超える Epic で101件目以降が黙って
#     欠落し、この完全性チェック自身が「一覧取得の既定件数上限で枠外が漏れる」という、この手順
#     (epic-implement 手順8)で既に修正済みの欠陥と同型のものを再生産してしまう(一次レビューで
#     指摘・実機で再現された)。**返ってきた件数が100件ちょうどだったことだけを根拠に「続きがある」
#     と判定しない**(ちょうど100件で終わる正当な Epic と区別できない)。`hasNextPage` という
#     GraphQL 自身が返す「続きの有無」の情報を使う。1ページに収まる Epic では問い合わせ回数は
#     従来どおり1回のまま増えない。収まらない場合に限り、収まるまで問い合わせを重ねる(この照合の
#     目的上必要なコストとして許容する)。
#   - 本文取得そのものが失敗した場合(gh issue view --json body が非ゼロ終了) → 空ではなく取得
#     失敗である旨を標準エラーへ出し、非ゼロ終了する(この場合だけ標準出力は空のまま)。
#   - node ID 解決・GraphQL クエリ(いずれかのページ)が失敗した場合は、完全性を確認できなかった旨を
#     標準エラーへ出す(不完全と決めつけない。ただし「確認できた」とも言わない。ページの途中で
#     失敗した場合、それまでに集めた部分集合は使わず「確認できない」扱いにする=中途半端な集合で
#     欠落判定をしない)。
#   - ネイティブリンクされた Sub-issue が1件も無い場合、本文抽出件数が0件なら突き合わせる相手が
#     お互いに存在しないだけで「対象ゼロ件」として扱う(警告なし)。本文抽出件数が1件以上あるのに
#     ネイティブリンクが0件なら、突き合わせの相手が存在せず完全性を確認できない(この Epic がまだ
#     ネイティブリンクを経由していない可能性がある。手作業で作成された Epic 等)。**件数の比較
#     (0 < 0 は偽)だけでは検知できない構成であり、必ず「相手が存在するか」を先に判定する。**
#   - ネイティブリンクが1件以上ある場合、その集合の各番号が本文抽出した集合に含まれているかを
#     1件ずつ照合する(gh-subissue-link.sh の missing_of と同じ判定方式)。含まれていない番号が
#     あれば、一部の Sub-issue が本文から抜け落ちている(不完全)可能性がある旨を標準エラーへ出す
#     (出力する一覧そのものは変えない=挙動の互換を保つ)。
#   - 本文抽出した集合がネイティブリンクの集合より広い(Sub-issue 以外への言及を含む)場合は
#     **警告せず、出力そのものから絞り込む**。ネイティブリンクの集合が非空の
#     ときに限り、本文抽出した集合をネイティブリンクの集合との積集合(intersection)に絞り込んで
#     出力する。実在する Epic 本文の抽出結果を確認したところ、Sub-issue ではない関連 issue への
#     言及がネイティブリンクと混在する例が実際にあり、この方向を警告対象にすると
#     正当な記述に対して誤検知し続けることが実データで確認されている。したがって警告(呼び出し元を
#     止める "(要確認)")ではなく、後続の手順(依存解析・dispatch・クローズ確認)が無関係な issue を
#     対象にしてしまう経路そのものを塞ぐ形(絞り込み)で対処する。
#     - **ネイティブリンクの集合が空の場合は絞り込まない**(絞り込む基準そのものが無い状態であり、
#       基準があって外れた状態=上記の「突き合わせる相手が存在しません」の「確認できません」区分
#       とは異なる。空だからといって本文抽出した一覧を丸ごと捨てるのは誤り)。node ID 解決・
#       GraphQL クエリが失敗して確認できない場合も同様に絞り込まない(絞り込みには構造的な正本の
#       集合が要る。確認できない=正本が使えない、なので絞り込まず本文抽出した集合をそのまま返す)。
#     - 絞り込みで1件以上除外した場合、除外した番号を標準エラーへ出す。ただし **"(要確認)" は
#       付けない**(付けると誤検知の警告に逆戻りする)。完全に沈黙もさせない——沈黙すると、本文の
#       書き方が変わって抽出そのものが壊れても、対象が黙って減るだけで抽出側の欠陥に気づく手段が
#       無くなる。"(要確認)" 抜きの情報行として残すことで、呼び出し元 SKILL の停止条件(下記)には
#       影響させず、人が事後に stderr を見れば絞り込みが発生した事実を追える形にする。
# 完全性(欠落側)の警告は末尾に "(要確認)" を付ける。呼び出し元 SKILL はこの語を合図に、一覧を
# 「対象ゼロ件」とみなさず停止・確認する(ルール `grounding-labels` の
# `+補完(要確認)` と同じ語彙)。絞り込みの情報行にはこの語を付けない(上記)。

# ネイティブリンクされた Sub-issue の番号を、ページングしながら全件取得するヘルパ。
#   引数: $1 = epic の node ID(GraphQL の Issue node ID。gh api graphql はグローバル ID のみで
#         動くため owner/repo は不要=gh-subissue-link.sh と同じ)。
#   標準出力: 番号を1行1件で出力(全ページ分。空なら無出力)。
#   戻り値: 0 = 全ページ取得成功(0件を含む)。1 = いずれかのページの取得に失敗(標準出力は
#           それまでの部分集合を含みうるが、呼び出し元は戻り値が非ゼロなら出力を使わない)。
# ページ数の上限(1000ページ=最大10万件相当)は業務上の制約ではなく、GraphQL 応答が壊れて
# hasNextPage が常に true を返し続けるような異常系での無限ループを避けるための安全弁。
eip_native_subissues_page_limit=1000
eip_native_subissues() {  # <epic_node_id>
  local epic_id="$1" cursor="" page=0 gql_args page_out page_rc meta_line has_next
  while :; do
    page=$((page + 1))
    if [ "$page" -gt "$eip_native_subissues_page_limit" ]; then
      eip_log "ネイティブ Sub-issue 一覧のページ取得が${eip_native_subissues_page_limit}回を超えました(異常系の可能性)。打ち切ります。"
      return 1
    fi
    gql_args=(api graphql -f query='
      query($id:ID!, $after:String) {
        node(id:$id) { ... on Issue { subIssues(first:100, after:$after) { pageInfo { hasNextPage endCursor } nodes { number } } } }
      }' -f id="$epic_id")
    [ -n "$cursor" ] && gql_args+=(-f after="$cursor")
    gql_args+=(-q '(.data.node.subIssues.pageInfo.hasNextPage|tostring) + "\t" + (.data.node.subIssues.pageInfo.endCursor // ""), (.data.node.subIssues.nodes[].number|tostring)')
    page_out="$(gh "${gql_args[@]}" 2>/dev/null)"
    page_rc=$?
    [ "$page_rc" -eq 0 ] || return 1
    meta_line="$(printf '%s\n' "$page_out" | head -n1)"
    has_next="${meta_line%%$'\t'*}"
    cursor="${meta_line#*$'\t'}"
    printf '%s\n' "$page_out" | tail -n +2
    [ "$has_next" = "true" ] || break
  done
  return 0
}

eip_subissues() {  # <args>
  local rc body body_rc view_args grep_list grep_count grep_numlist epic_id id_rc
  local native_list native_rc missing num
  local output_numlist narrowed excluded
  eip_resolve "${1:-}"
  rc=$?
  [ "$rc" -eq 0 ] || return 0

  if [ -n "$_EIP_REPO" ]; then
    view_args=(issue view --repo "$_EIP_REPO")
  else
    view_args=(issue view)
  fi

  body="$(gh "${view_args[@]}" "$_EIP_NUM" --json body -q '.body' 2>/dev/null)"
  body_rc=$?
  if [ "$body_rc" -ne 0 ]; then
    eip_log "Epic本文の取得に失敗しました(gh issue view --json body の終了コード${body_rc})。Sub-issue番号一覧は空ではなく取得できていません(要確認)。"
    return 1
  fi

  grep_list="$(printf '%s\n' "$body" | grep -oE '#[0-9]+' | sort -u)"
  if [ -n "$grep_list" ]; then
    grep_count="$(printf '%s\n' "$grep_list" | grep -c '^')"
    grep_numlist="$(printf '%s\n' "$grep_list" | sed 's/^#//')"
  else
    grep_count=0
    grep_numlist=""
  fi

  # output_numlist は既定では本文抽出した集合そのまま(絞り込まない)。絞り込みは下の else 分岐
  # (ネイティブ Sub-issue の集合が構造的な正本として使える=非空で取得できた場合)だけで行う。
  # 「確認できない」状態(node ID 解決失敗・GraphQL 失敗・ネイティブ集合が空)では絞り込む基準が
  # 無いので、本文抽出した集合を丸ごと落とさずそのまま返す。
  output_numlist="$grep_numlist"

  epic_id="$(gh "${view_args[@]}" "$_EIP_NUM" --json id -q '.id' 2>/dev/null)"
  id_rc=$?
  if [ "$id_rc" -ne 0 ] || [ -z "$epic_id" ]; then
    eip_log "Epic の node ID を取得できず、本文抽出した番号一覧(${grep_count}件)がネイティブ Sub-issue と一致するか確認できません(要確認)。"
  else
    native_list="$(eip_native_subissues "$epic_id")"
    native_rc=$?
    if [ "$native_rc" -ne 0 ]; then
      eip_log "ネイティブ Sub-issue 一覧の取得に失敗しました(終了コード${native_rc})。本文抽出した番号一覧(${grep_count}件)の完全性を確認できません(要確認)。"
    elif [ -z "$native_list" ]; then
      if [ "$grep_count" -gt 0 ]; then
        eip_log "この Epic にはネイティブリンクされた Sub-issue が1件も無く、本文抽出した番号一覧(${grep_count}件)と突き合わせる相手が存在しません。完全性を確認できません(要確認)。"
      fi
      # grep_count が0件ならネイティブ側も0件=お互いに対象が無い(正当にゼロ件)。警告不要。
    else
      missing=""
      while IFS= read -r num; do
        [ -n "$num" ] || continue
        # here-string(パイプではなく単純なリダイレクト)で渡す。`printf ... | grep -Fxq` という
        # 素朴なパイプだと、`grep -q` は一致した時点で読み込みを打ち切るため、`printf` 側がまだ
        # 書き込み中だと SIGPIPE(終了コード141)で終了しうる。set -o pipefail 下ではこの141が
        # パイプライン全体の終了コードになり、実際には一致していたのに「不一致」として扱ってしまう
        # (高負荷でタイミングがずれると顕在化するレース。実測で負荷下・再現率per反復で確認済み)。
        # here-string はパイプラインの一員ではない: `<<<` の中身を書き込むのはコマンド起動前の
        # シェル自身であり、`grep` を fork/exec する時点で書き込みは既に完了している。SIGPIPE を
        # 受けうる別プロセスの書き手が存在しないため、この種のレースが構造的に起きない(パイプが
        # 実ファイルを経由するかどうかというシェル実装の詳細には依らない)。`-e` は `$num` が
        # `-` で始まる値であってもオプションと誤認されないようにする安全策。
        if ! grep -Fxq -e "$num" <<< "$grep_numlist"; then
          missing="${missing}${missing:+ }#${num}"
        fi
      done <<< "$native_list"
      if [ -n "$missing" ]; then
        eip_log "本文から抽出した番号一覧にネイティブ Sub-issue が含まれていません:${missing} 。一部の Sub-issue が番号一覧から抜け落ちている可能性があります(要確認)。"
      fi

      # ネイティブ Sub-issue の集合が構造的な正本として使える(非空で取得できた)ので、本文抽出
      # した集合をこの正本との積集合に絞り込む。ネイティブに無い番号(関連issueへの言及等)は
      # 対象から外す(警告ではなく絞り込み)。
      narrowed=""
      excluded=""
      while IFS= read -r num; do
        [ -n "$num" ] || continue
        # here-string・-e を使う理由は上の missing 判定と同じ(SIGPIPE + pipefail のレース回避・
        # `$num` がハイフン始まりでもオプション誤認しない安全策)。
        if grep -Fxq -e "$num" <<< "$native_list"; then
          narrowed="${narrowed}${narrowed:+$'\n'}${num}"
        else
          excluded="${excluded}${excluded:+ }#${num}"
        fi
      done <<< "$grep_numlist"
      output_numlist="$narrowed"
      if [ -n "$excluded" ]; then
        eip_log "本文から抽出した番号一覧のうち、ネイティブ Sub-issue の集合に含まれない番号を対象から除外しました:${excluded} 。Sub-issue ではない関連issueへの言及の可能性があります。"
      fi
    fi
  fi

  if [ -n "$output_numlist" ]; then
    while IFS= read -r num; do
      [ -n "$num" ] || continue
      if [ -n "$_EIP_REPO" ]; then
        printf '%s#%s\n' "$_EIP_REPO" "$num"
      else
        printf '#%s\n' "$num"
      fi
    done <<< "$output_numlist"
  fi
  return 0
}

epic_implement_probe() {  # <mode> <args>
  local mode="${1:-}" args="${2:-}"
  case "$mode" in
    epic)      eip_epic "$args"; return $? ;;
    subissues) eip_subissues "$args"; return $? ;;
    *)
      eip_log "不明な mode: ${mode:-(空)}(epic か subissues を指定)"
      return 1
      ;;
  esac
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then epic_implement_probe "${1:-}" "${2:-}"; fi
