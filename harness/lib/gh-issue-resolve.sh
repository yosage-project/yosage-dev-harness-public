#!/usr/bin/env bash
# gh-issue-resolve.sh — issue-implement / epic-implement-subissue / epic-review の
# 動的コンテキストが表示する対象 issue を解決する共有ロジック。
#
# 経緯: 動的コンテキストの `!` 行にインラインの command substitution `$(…)`・if 分岐を
# 直書きすると、ホスト側の permission チェック(静的解析不能な複雑シェルを難読化コマンドと
# みなすヒューリスティック)に弾かれ SKILL 起動自体(動的コンテキストのロード)が失敗する。
# 解決ロジックは複雑なので lib スクリプトへ出し、SKILL 側は
# `yosage-dev-harness-gh-issue-resolve "$ARGUMENTS"` という単純呼び出しにする
# (既存の epic-implement-probe.sh と同じ形)。
#
# 背景: 複数リポジトリを束ねるワークスペース直下の新規セッションで対象 skill を起動すると、
# 動的コンテキストの `!` はセッションの作業ディレクトリ(ワークスペースのルート)で解決される。
# ワークスペースのルート自身が独立した git リポジトリであることが多く、bare な issue 番号を
# 渡すと本来のメンバーリポジトリではなくワークスペース側リポジトリの同番号 issue を解決して
# しまう(番号衝突時に静かに誤ったリポジトリの issue を対象にする経路)。
#
# 解決順:
#   1. 引数に <owner>/<repo>#<N> 形式(# の直前に空白/タブが1個以上入る揺れも許容。
#      空白区切りのトークン化ベースなので個数は問わない)が含まれる
#      → `gh issue view --repo <owner>/<repo> <N>`
#      (対象リポジトリを明示指定するため取り違えが構造的に起きない)
#   1a. scoped 参照を試みたとみられるが形式が壊れている(# の後が数字以外・owner/repo
#      部が空 等) → 停止(非ゼロ終了)。bare 番号抽出へは黙って落ちない
#      (誤った現在リポジトリの番号を静かに解決してしまう経路を塞ぐ)
#   2. 引数が bare <N> かつ設定の workspace が true
#      → 停止(非ゼロ終了)して <owner>/<repo>#<N> 形式での指定を要求する
#      (ワークスペース側リポジトリの同番号issueを黙って掴む経路を構造的に塞ぐ)
#   3. 引数が bare <N> かつ設定の workspace が false → 従来どおり `gh issue view <N>`
#      (単一リポジトリ利用者はゼロ摩擦・回帰なし)
#
# 使い方:
#   yosage-dev-harness-gh-issue-resolve "$ARGUMENTS"
#
# 呼び出し元(SKILL)の cwd を対象にする(workspace 判定はスクリプト自身の場所ではなく
# cwd 基準のリポジトリルートで行う。lib は動的コンテキストの `!` と同一 cwd で走るため検出可能)。
set -uo pipefail

gir_log() { printf 'gh-issue-resolve: %s\n' "$1" >&2; }

# 引数文字列を空白区切りトークンに分解し、scoped 参照を試みたとみられる候補トークンを
# 拾う(無ければ空を返す)。候補と判定する条件は次の2通り:
#   - 1トークン中に "/" と "#" が両方含まれる(例: owner/repo#<N>, owner/repo#abc)
#   - "/" を含み "#" を含まないトークンの直後のトークンが "#" で始まる
#     (例: `owner/repo #<N>` のように # の直前に空白/タブを1個以上はさむ打ち間違いを吸収する。
#     単語分割ベースの検出なので空白の個数は問わない)
# 拾った候補は well-formed とは限らない(gir_is_valid_scoped で別途検証する)。
# 線引きの根拠(反証可能な理由): "/" と "#" の隣接は <owner>/<repo>#<N> 形式を意図した
# 強いシグナルであり、素の bare 番号や無関係な文中の "#" 単独(例: "実装 #<N> 完了")には
# 現れない。誤検知を許すより、誤って別リポジトリの番号を静かに解決する事故の方が高くつく
# ため、この隣接シグナルを見たら常に scoped 経路(検証 or 拒否)へ倒す。
# もし将来 "$ARGUMENTS に自由文中で slash を含むパスと # 番号が両方混在する" ような
# 正当な入力が増えて誤検知が実運用上問題になったら、この行を再検討する。
gir_find_scoped_candidate() {  # <args>
  local args="${1:-}" i n tok nxt j _gir_restore_glob=0
  # unquoted word splitting はパス名展開(グロブ)も一緒に起動してしまう。cwd に glob
  # マッチするファイルがあると、そのファイル名が引数のトークン列に混ざり込み、無関係な
  # "/"+"#" 隣接を誤検出する事故になる(例: 引数 "fix src/*.sh #<N>" が cwd の src/b.sh
  # 展開で "src/b.sh" トークンに化ける)。一時的に noglob を立てて展開を止める
  # (呼び出し元の glob 設定は壊さず、関数を抜けたら元に戻す)。
  case $- in *f*) : ;; *) _gir_restore_glob=1; set -f ;; esac
  set -- $args
  [ "$_gir_restore_glob" -eq 1 ] && set +f
  n=$#
  i=1
  while [ "$i" -le "$n" ]; do
    tok="${!i}"
    case "$tok" in
      */*#*)
        printf '%s' "$tok"
        return 0
        ;;
      */*)
        j=$((i + 1))
        if [ "$j" -le "$n" ]; then
          nxt="${!j}"
          case "$nxt" in
            '#'*)
              printf '%s%s' "$tok" "$nxt"
              return 0
              ;;
          esac
        fi
        ;;
    esac
    i=$((i + 1))
  done
  return 1
}

# scoped 候補トークンが <owner>/<repo>#<N> の厳密形式(owner・repo は非空で "/" を含まず、
# # の後ろは数字のみ)に一致するかを判定する。
gir_is_valid_scoped() {  # <candidate>
  printf '%s' "${1:-}" | grep -qE '^[^/ ]+/[^/ ]+#[0-9]+$'
}

# <owner>/<repo>#<N> トークンから <owner>/<repo> 部分を取り出す。
gir_scoped_repo() {  # <owner/repo#N>
  printf '%s' "${1:-}" | sed -E 's/#[0-9]+$//'
}

# <owner>/<repo>#<N> トークンから <N> 部分を取り出す。
gir_scoped_number() {  # <owner/repo#N>
  printf '%s' "${1:-}" | sed -E 's/^.*#([0-9]+)$/\1/'
}

# 引数文字列から最初の数値トークン(bare issue番号)を抽出する。無ければ空を返す。
gir_extract_bare_number() {  # <args>
  printf '%s' "${1:-}" | tr ' ' '\n' | grep -E '^[0-9]+$' | head -1
}

# ワークスペース直下かどうか(呼び出し元 cwd の設定ファイルで workspace が true か)。
# 戻り値は3値: 0=true(workspace) / 1=false(単一リポジトリ) / 2=判定不能
# (設定ファイルが壊れた JSON・jq/python3 が無い等。ydh_config_get の rc 3/4)。
# 判定不能は「単一リポジトリ」とはみなさない(黙って違うモードで進まない)。
gir_is_workspace_mode() {
  local lib root val rc
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
  [ -f "$lib" ] || return 2
  # shellcheck source=./config.sh
  . "$lib"
  root="$(ydh_repo_root 2>/dev/null)" || root="$PWD"
  val="$(ydh_config_get "$root" workspace 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] || return 2
  [ "$val" = "true" ] && return 0
  return 1
}

# 対象 issue を解決し gh issue view の出力を表示する。
gh_issue_resolve() {  # <args>
  local args="${1:-}" scoped repo n bare
  scoped="$(gir_find_scoped_candidate "$args")"
  if [ -n "$scoped" ]; then
    if ! gir_is_valid_scoped "$scoped"; then
      gir_log "scoped 形式('${scoped}')に見えますが不正です(<owner>/<repo>#<N> 形式で、# の後ろは数字のみにしてください)。"
      gir_log "bare な issue 番号として解釈すると別リポジトリの番号を誤って解決する恐れがあるため、ここで停止します。"
      return 1
    fi
    repo="$(gir_scoped_repo "$scoped")"
    n="$(gir_scoped_number "$scoped")"
    gh issue view --repo "$repo" "$n"
    return $?
  fi

  bare="$(gir_extract_bare_number "$args")"
  if [ -n "$bare" ]; then
    local _gir_ws_rc
    gir_is_workspace_mode; _gir_ws_rc=$?
    if [ "$_gir_ws_rc" = 0 ]; then
      gir_log "ワークスペース直下(設定の workspace が true)では bare な issue 番号(${bare})を解決できません(番号衝突時に別リポジトリの issue を誤って掴む可能性があるため)。"
      gir_log "対象リポジトリを明示する <owner>/<repo>#<N> 形式で指定してください(例: your-org/your-repo#${bare})。"
      return 1
    elif [ "$_gir_ws_rc" = 2 ]; then
      gir_log "ワークスペース判定に失敗しました(設定ファイルが壊れた JSON、または jq/python3 が無い)。単一リポジトリとはみなさず停止します。"
      return 1
    fi
    # workspace でなければ従来どおり bare 番号で解決する(単一リポジトリはゼロ摩擦・回帰なし)。
    gh issue view "$bare"
    return $?
  fi

  # 数値トークンも <owner>/<repo>#<N> トークンも見つからない(空引数・数値以外のみ等)場合は、
  # 従来どおり引数をそのまま gh issue view に渡す(以前からの失敗挙動を保つだけで新規動作は足さない)。
  gh issue view $args
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then gh_issue_resolve "${1:-}"; fi
