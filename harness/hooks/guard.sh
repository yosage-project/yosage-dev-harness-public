#!/usr/bin/env bash
# PreToolUse(Bash / Edit|Write|MultiEdit / Read|Grep) フック:
#   Bash: 破壊的・危険なシェルコマンドを実行前にブロックする。
#   Edit|Write|MultiEdit: worktree 隔離サブエージェントが割り当て worktree 外へ書き込むのを防ぐ
#   (下記 (I) セクション)。
#   Read|Grep: 秘密ファイル(.env系/*.pem/*.key/id_rsa/secrets/**)の読み取りを遮断する
#   (下記 (K) セクション)。
#   ブロック時は exit 2 + 理由を stderr へ(Claude に届く)。問題なければ exit 0。
#   解除の手段(env opt-out)は持たない: 止まったら報告して止まり、本当に必要な操作は人が
#   自分のターミナルで行う。
#   ここは「最後の安全網」。粗いマッチで十分(細かい許可制御は settings の permissions 側)。
set -uo pipefail

# ブロックの既定メッセージ末尾: 解除の手段は無い(env opt-out は撤去済み)。止まったら
# Claude は報告して止まり、本当に必要な操作は人が自分のターミナルで行う。lib 欠落・JSON 解析器
# 欠落のような「判定できない」場合も同じ文言で止める(fail-open にしない)。
NO_BYPASS_MSG="この場では実行できません。必要な場合は依頼元へ報告し、指示を仰いでください。"

# 補助スクリプト(lib)が見つからない・読めない・source に失敗した場合は、判定できないまま
# 先へ進まず止める(fail-open をやめる)。フックは exit 2 以外で終わると素通りになるため、
# 止めるときは必ず exit 2。
# 以前は `[ -f "$path" ] && { source "$path" || true; }` という fail-open な形で、lib が
# 見つからない・読めない場合は該当セクションの判定が黙って発火しなくなっていた(詳細は
# 撤去済みの旧コメント参照。git 履歴で追跡可能)。
_guard_require_lib() {  # <path>
  if [ ! -r "$1" ] || ! source "$1"; then
    printf '⛔ yosage-dev-harness guard: 補助スクリプト %s を読み込めないため判定できません。%s\n' "$(basename "$1")" "$NO_BYPASS_MSG" >&2
    exit 2
  fi
}

# harness/lib/worktree-root.sh(割り当て作業ツリー置き場の単一ホーム。下記 (I)(C) 両方が使う値
# なので、どちらより前でここに source する。guard.sh と同じ hooks/ の隣 lib/ に配布される想定)。
_guard_require_lib "$(dirname "${BASH_SOURCE[0]}")/../lib/worktree-root.sh"

# harness/lib/secret-patterns.sh(下記 (K)(E) が使う。secret_file_deny_globs/sf_is_secret_path の
# 単一の家)。(K) が入力読み込み直後に判定するため、ここで早めに source する。
_guard_require_lib "$(dirname "${BASH_SOURCE[0]}")/../lib/secret-patterns.sh"

# harness/lib/branch-protection.sh(保護ブランチ集合の単一ホーム。下記 (J) が使う。
# lib/epic-cleanup.sh と同じ source 対象を、guard.sh からも重複定義せず参照する)。
_guard_require_lib "$(dirname "${BASH_SOURCE[0]}")/../lib/branch-protection.sh"

# harness/lib/base-branch.sh(GitHub の既定ブランチ＝origin/HEAD の読み取りの単一ホーム。下記 (J) が
# bb_origin_head を使う。`/` を含む既定ブランチ(例 release/x)も末尾の1要素に切らずに扱う)。
_guard_require_lib "$(dirname "${BASH_SOURCE[0]}")/../lib/base-branch.sh"

input="$(cat)"

# 補助スクリプト(lib)と同じく、JSON を解析できない(jq も python3 も無い)場合も判定できない
# まま先へ進まず止める(フックは exit 2 以外で終わると素通りになるため、止めるときは必ず exit 2)。
_json_tool=""
command -v jq >/dev/null 2>&1 && _json_tool=jq
[ -z "$_json_tool" ] && command -v python3 >/dev/null 2>&1 && _json_tool=python3
if [ -z "$_json_tool" ]; then
  printf '⛔ yosage-dev-harness guard: jq も python3 も見つからないため判定できません。%s\n' "$NO_BYPASS_MSG" >&2
  exit 2
fi

get_cmd() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.tool_input.command // empty'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("command",""))'
  fi
}

get_cwd() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.cwd // empty'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("cwd",""))'
  fi
}

# tool_input.file_path を取り出す(Edit/Write/MultiEdit 用。Bash の tool_input には file_path が
# 無いため、Bash 呼び出しでは常に空文字を返す。抽出は format.sh の get_path と同じ形)。
get_file_path() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.tool_input.file_path // empty'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))'
  fi
}

# 書き込まれようとしている内容を取り出す(Edit/Write/MultiEdit 用。下記 (I2) 専用)。
# Write は tool_input.content、Edit は tool_input.new_string、MultiEdit は
# tool_input.edits[].new_string を改行結合したもの。優先順位はこの順(1つのツール呼び出しは
# これらのうち1種類しか持たないため、上から見つかった最初のものを使うだけで tool_name の判定は
# 要らない=get_file_path が tool_name を見ないのと同じ考え方)。
get_write_content() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '
      .tool_input.content
      // .tool_input.new_string
      // ((.tool_input.edits // []) | map(.new_string) | join("\n"))
      // empty
    '
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c '
import sys, json
ti = json.load(sys.stdin).get("tool_input", {})
if ti.get("content") is not None:
    print(ti["content"])
elif ti.get("new_string") is not None:
    print(ti["new_string"])
else:
    edits = ti.get("edits") or []
    print("\n".join(e.get("new_string", "") for e in edits))
'
  fi
}

# tool_input.file_path 以外の任意フィールドを取り出す汎用ヘルパー(Read/Grep の path/glob/
# pattern 等、フィールド名を引数で渡す)。
get_tool_input_field() {  # <input> <field>
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r --arg f "$2" '.tool_input[$f] // empty'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_input",{}).get(sys.argv[1],"") or "")' "$2"
  fi
}

# tool_name を取り出す(Read/Grep と Edit/Write/MultiEdit を区別するため)。
get_tool_name() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.tool_name // empty'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_name",""))'
  fi
}

cmd="$(get_cmd "$input")"
# .cwd はこの hook 呼び出し1回につき1度だけ解析する。(I)・(C) はどちらも同じ入力の .cwd を見るが、
# 以前はそれぞれが独立に get_cwd を呼んでおり、Bash 経由の呼び出し((I) 側では file_path が無く
# no-op のまま終わる呼び出し)でも jq/python3 の起動が2倍かかっていた(一次レビュー実測: 約7ms/
# セグメントの増分。既存の「フックが重い」課題(別 issue で追跡中)を不要に悪化させていた)。
cwd="$(get_cwd "$input")"

# block() の第2引数(遮断 ID)は呼び出し側の互換のため残っている呼び出し箇所があるが、
# block() 自身はもう使わない(遮断発火のログ記録は撤去した。導入先に状態のファイルを持たない
# 決定。呼び出し側の第2引数は無害な no-op として残る)。
block() { printf '⛔ yosage-dev-harness guard: %s\n' "$1" >&2; exit 2; }

# block() の非ブロッキング版: 書き込みは妨げず stderr へ警告するだけ(exit しない)。
# 下記 (I2) が使う。
warn() { printf '⚠ yosage-dev-harness guard: %s\n' "$1" >&2; }

# --- (K) 秘密ファイルの Read / Grep 遮断 ---
# 背景: 秘密ファイルの読み取り禁止はこれまで settings.json の Read 拒否(推奨止まり。導入先の
# settings.json にハーネスは書かない)で止めていたが、ガードがフックとして Bash と同じ一覧
# (harness/lib/secret-patterns.sh の sf_is_secret_path)で Read・Grep も判定する。
# (I) より前に置く: (I) は tool_name を見ずに file_path があれば判定するため、そのままでは
# Read(file_path を持つ)に誤爆し、worktree 隔離のサブエージェントが worktree の外のファイルを
# **読む**だけで止まってしまう((I) 側は Edit/Write/MultiEdit へ対象を絞ることで対応済み。
# 本節を先に評価し、Read/Grep は exit 0 でここから抜けることで (I) まで進ませない)。
#
# 名指し判定に加え、ディレクトリ全体の Grep 検索も判定する。実測(本 PR 本文の観測構成・結果を
# 参照): output_mode="content"・path 省略(検索範囲=カレントディレクトリ全体)・秘密ファイルが
# gitignore されていない場合、秘密ファイルの中身がツール結果にそのまま出ることを確認した
# (`.env:1:KEY=...` という行が実際に返った)。一方、同じ秘密ファイルが gitignore されている
# 場合は Grep ツール自身が対象から除外し、中身は出なかった(実測)。したがって、検索範囲に
# gitignore されていない秘密ファイルが含まれ、かつ glob 指定でそれが除外されていない場合だけ
# 止める(出なかった条件では止めない、という決定どおり最小の条件にする)。
_k_tool_name="$(get_tool_name "$input")"
case "$_k_tool_name" in
  Read)
    _k_fp="$(get_file_path "$input")"
    if [ -n "${_k_fp:-}" ] && sf_is_secret_path "$_k_fp"; then
      block "秘密ファイルの読み取り(Read)を検出。${NO_BYPASS_MSG}"
    fi
    exit 0
    ;;
  Grep)
    _k_path="$(get_tool_input_field "$input" path)"
    _k_glob="$(get_tool_input_field "$input" glob)"
    if [ -n "${_k_path:-}" ] && sf_is_secret_path "$_k_path"; then
      block "秘密ファイルの読み取り(Grep の path)を検出。${NO_BYPASS_MSG}"
    fi
    if [ -n "${_k_glob:-}" ] && sf_is_secret_path "$_k_glob"; then
      block "秘密ファイルの読み取り(Grep の glob)を検出。${NO_BYPASS_MSG}"
    fi
    # ディレクトリ全体の検索(path 省略時は cwd を対象にする。Grep ツール自体の既定と同じ)。
    # git 管理下の(gitignore されていない)ファイルだけを候補にする(実測: gitignore された
    # 秘密ファイルは Grep ツール自身が除外し中身は出ない。ここで拾うと過剰検知になる)。
    _k_dir="${_k_path:-${cwd:-}}"
    if [ -n "${_k_dir:-}" ] && [ -d "${_k_dir:-}" ]; then
      _k_candidates="$(git -C "$_k_dir" ls-files --cached --others --exclude-standard 2>/dev/null)" || true
      if [ -n "${_k_candidates:-}" ]; then
        _k_hit=""
        while IFS= read -r _k_f; do
          [ -n "${_k_f:-}" ] || continue
          sf_is_secret_path "$_k_f" || continue
          if [ -n "${_k_glob:-}" ]; then
            case "$_k_f" in
              $_k_glob) : ;;
              *) continue ;;
            esac
          fi
          _k_hit="$_k_f"
          break
        done <<< "$_k_candidates"
        if [ -n "${_k_hit:-}" ]; then
          block "Grep の検索範囲(${_k_dir})に秘密ファイル(${_k_hit})が含まれており、除外されていません。glob に対象の拡張子だけを指定するか、path を秘密ファイルを含まないディレクトリに変えて検索し直してください。${NO_BYPASS_MSG}"
        fi
      fi
    fi
    exit 0
    ;;
esac

# --- (I) worktree 隔離サブエージェントが Edit/Write/MultiEdit で割り当て worktree 外へ書き込むのを防ぐ ---
# 背景: (C)(本ファイル下方)は worktree 隔離サブエージェントが Bash 経由で
# 共有チェックアウトを操作するのを防ぐが、Bash を経由しない Write/Edit/MultiEdit で絶対パスを直接
# 指定すれば同じ事故(割り当て worktree 外への書き込み)が素通りしていた。実際に、worktree 内で
# 作業しているつもりで絶対パスの Write が共有チェックアウト側を書き換えた事故が報告されている。
#
# この経路は (C) の Bash 側の残余バイパス(既知の穴。(C) 直前のコメント参照)とは性質が違う:
# 判定材料が「書き込み先パス1つ」であり、シェルの静的なテキスト解析が持つ限界(クォート・間接
# 呼び出し・サブシェル等)は持たない。tool_input.file_path はハーネスが直接受け取る構造化された
# 値であり、コマンド文字列を解析して間接呼び出しを推測する必要が無いため。
#
# ただし「パス1つで判定できる」ことと「そのパスが指す先が一意に定まる」ことは別であり、原理的に
# 塞げるわけではない。best-effort であり境界(boundary)ではない: 以下は既知の穴。
# (訂正: 当初ここには「原理的に塞げる」と記述していたが誤り。記号リンクを経由した書き込み先は
# 文字列比較では捕まえられないため、下記のとおり実際に穴がある。)
#   - 記号リンク経由の書き込み先: 割り当て worktree 内に、共有チェックアウト等の worktree 外を
#     指す記号リンクを作り、そのリンクの内側を通る絶対パスへ Write/Edit/MultiEdit すると、
#     tool_input.file_path の文字列表現は割り当て worktree 配下に見えるため block されない
#     (実測で block されないことを確認済み)。下記の判定はパスの実体(symlink の解決先)を辿らず、
#     `_wt_norm_path` による ./ ../ の字面上の正規化と prefix 一致だけを見る lexical な判定である
#     ため。パスの実体を解決してから比較する対応(realpath 相当)は、存在しないパスへの書き込み・
#     解決自体が失敗する場合の扱いなど別の設計判断を要するため本変更では入れない(意図的な現状固定。
#     既知の穴として明記するに留める)。
#
# 発火条件は (C) と同じ: hook 入力の .cwd が割り当て worktree(.claude/worktrees/<id>)配下の時のみ
# 有効(それ以外=通常のメインセッションは no-op。メインセッションの正当な cross-repo 書き込みを
# 誤爆させない)。$cmd が空(Bash 以外の呼び出し)でもこのセクションは実行する必要があるため、
# 下記の早期 exit(`[ -n "$cmd" ] || exit 0`)より前に置く。
#
# opt-out は設けない: 既存の opt-out env 11個は一度も設定された痕跡が無く、
# 成立する置き場も確認できず、作業者は存在を知る経路すら持たないことが実測で判明した(本ファイル
# 冒頭「対象から外したブロック」節・no-litter の項と同じ判断)。
#
# _wt_norm_path は (C) と共有する(相対パスの ../ ./ を解決した絶対パスを返す。存在確認はしない
# 純粋な文字列処理。bash 3.2(macOS 標準)互換)。二重定義を避けるためここを唯一の家にし、(C) 側は
# この定義を呼ぶだけにする(定義は下記のとおりファイル冒頭に置き、(C) より先に実行されるため
# (C) 実行時点でも参照できる)。
_wt_norm_path() {
  local _np_input="$1"
  local -a _np_parts=()
  local _np_part
  local _np_saved_ifs="$IFS"
  local _np_restore_glob=0
  case $- in *f*) : ;; *) _np_restore_glob=1; set -f ;; esac
  IFS='/'
  set -- $_np_input
  IFS="$_np_saved_ifs"
  [ "$_np_restore_glob" -eq 1 ] && set +f
  for _np_part in "$@"; do
    case "$_np_part" in
      ''|'.') continue ;;
      '..')
        if [ "${#_np_parts[@]}" -gt 0 ]; then
          unset "_np_parts[$((${#_np_parts[@]}-1))]"
          _np_parts=(${_np_parts[@]+"${_np_parts[@]}"})
        fi
        ;;
      *) _np_parts+=("$_np_part") ;;
    esac
  done
  if [ "${#_np_parts[@]}" -eq 0 ]; then
    printf '/'
  else
    printf '/%s' "${_np_parts[@]}"
  fi
}

# 割り当てルートへの切り詰めは worktree-root.sh の wt_assigned_root(単一ホーム)を呼ぶ
# (パターン一致・sed による切り詰めをここで再実装しない。(C) と同じ関数を使う)。
_wi_root="$(wt_assigned_root "${cwd:-}" 2>/dev/null)"
if [ -n "${_wi_root:-}" ]; then
  # 対象は書き込み系ツールに限る(下記 (K) が Read/Grep を先に判定して exit 0 するため、通常は
  # ここまで来ない。ただし tool_name が取れない古い形の入力では従来どおり判定する=fail-safe)。
  case "$(get_tool_name "$input")" in
    ""|Edit|Write|MultiEdit)
      _wi_fp="$(get_file_path "$input")"
      if [ -n "${_wi_fp:-}" ]; then
        case "$_wi_fp" in
          /*)   _wi_check="$(_wt_norm_path "$_wi_fp")" ;;
          '~'*) _wi_check="$(_wt_norm_path "$HOME${_wi_fp#\~}")" ;;
          *)    _wi_check="$(_wt_norm_path "$cwd/$_wi_fp")" ;;
        esac
        case "$_wi_check" in
          "$_wi_root"|"$_wi_root"/*) : ;;
          *) block "worktree 隔離サブエージェントが割り当て worktree 外(${_wi_check})への書き込みを試みています。書き込み先を割り当て worktree(${_wi_root})配下の絶対パスに直してください。" "worktree_isolation_write" ;;
        esac
      fi
      ;;
  esac
fi

# --- (I2) knowledge エントリの形をしたファイルが install 先のストア外へ書かれても検知されない ---
# 背景: knowledge エントリを検査するフックは2系統(guard.sh・hooks/knowledge-index.sh)あるが、
# どちらも install 先(`.claude/knowledge/<domain>/`)の外へ書かれた
# 場合は反応しない。書き込みは成功し(ディレクトリは自動生成される)、書いた主体には「capture 済み」
# と正しく見えるが、索引の再生成も構造監査も走らず、蓄積が静かにゼロになる。(I)と違い worktree
# 隔離文脈に限定しない: ドッグフーディングの通常セッション(worktree を経由しない main セッション)
# でも同じ構造が成立するため。
#
# 判定基準(「knowledge エントリの形」): frontmatter の `id:`/`domain:`/`scope:`/`status:` が
# **すべて** 行頭に揃っていること(`harness/knowledge/_entry-template.md` が定めるテンプレートの
# 必須フィールドと同じ4つ)。1つでも欠けていれば対象外とする(YAML frontmatter を持つだけの
# 無関係なドキュメントとの衝突を避けるため。「knowledge っぽいパス」では判定しない=対象の
# パスが違うこと自体が問題なので、パスでの判定は機能しない)。
#
# block ではなく警告(exit を伴わず stderr へ出すだけ。書き込みは妨げない)を選んだ。理由:
# 正当な理由(テストのフィクスチャ・ドキュメントの例示)でストア外へ knowledge 形式のファイルを
# 置くケースは実在し、block ならそこへの誤検知の逃げ道が要る。だが guard.sh には既存の設計判断
# (NO_BYPASS_MSG。本ファイル冒頭のコメント参照: 解除の手段を持たない止め方であることを伝える)
# があり、両者は正面から衝突する。加えて、このリポジトリ自身に該当パターンを持つ
# 正当なファイルが実在することを確認済み: `harness/knowledge/_entry-template.md`(id/domain/
# scope/status が揃ったテンプレートで、意図的にストア外(harness/配下)に置かれている)、
# 同じ4フィールドを frontmatter の書き方として例示するドキュメント。block だとこれら正当な
# ファイルの編集そのものが毎回止まり、対象外にする
# allowlist を新設すれば block の一般性(逃げ道を案内しない)が崩れる。警告なら「誤検知の逃げ道」
# は不要になる(何もブロックしていないため)。組織境界の識別子の警告(`lib/gh-review.sh` の
# `_ghr_warn_outbound_identifiers`)と同型のパターンを踏襲する: ブロックしない・一致した内容
# そのものはメッセージに出さない。
#
# **この警告が届くのは人間の操作者であり、書き込みを行ったエージェント自身ではない。**
# 本ファイル冒頭のコメントが「ブロック時は exit 2 + 理由を stderr へ(Claude に届く)。問題なければ
# exit 0。」と、"届く" を exit 2 の場合に限定して書いているとおり、このコードベース自身の理解として
# exit 0 の stderr は書き手のモデルの文脈へは入らない(このリポジトリ内に、PreToolUse hook の exit 0
# 側で非ブロッキングの理由をモデルへ伝える前例は無い。`permissionDecision`/`hookSpecificOutput` は
# リポジトリ全体を検索しても0件)。したがって、**自律的に走るエージェントは、この警告があっても
# 誤着地に気づかないまま先へ進む**。issue が問題にした「書いた主体には capture 済みと正しく見える」
# という状態は、この (I2) だけでは解消しない——解消するのは「誰も検知しない」という半分だけで、
# 警告が届く先は人間の端末である。エージェントへ実際に届く伝達手段(exit 2 化・別の非ブロッキング
# 経路等)をどうするかは、この PR の対応範囲に含めない。
# **未検証の事実**: 上記「exit 0 の stderr はモデルの文脈へ入らない」はこのコードベース自身の
# 記述(exit 2 に限定した書き方)から導いた判断であり、実機で「届かない」ことを確定させたわけでは
# ない(隔離された実行環境の制約で実測できなかった)。「届かないと確認した」わけではないことに注意。
#
# ストア位置は固定の `.claude/knowledge` を使う(置き場を変える機能は撤去した。設定の
# Sub-issue と guard.sh を衝突させないための決定)。
# ストアが属するリポジトリのルートは、書き込み先ファイル自身のディレクトリから `.git` を持つ
# 祖先を辿って求める(cwd から導出すると、複数リポジトリが同居するワークスペース直下で
# セッションを開いている場合にワークスペースのルートを掴んでしまう。grounding-check.sh の
# proj 導出と同じ判断・同じ理由)。`git rev-parse --show-toplevel` を呼ばない理由: これは
# symlink を解決した実体パスを返すため、tool_input.file_path(symlink を解決しない、書かれた
# ままの文字列)と単純な prefix 比較すると、/tmp が /private/tmp の symlink であるような環境で
# 常に不一致になり、ストア内への正常な書き込みまで誤検知する(実機再現済み)。祖先探索
# (`_kw_find_toplevel`)は `.git` の存在確認(`[ -e ]`)こそ行うが、パスの文字列自体は
# `_wt_norm_path` が正規化した ./ ../ 解決済みの形のまま dirname で遡るだけで、symlink を
# 解決した実体パスに置き換える操作(realpath 相当)は行わない。この「symlink 解決の有無」が
# 上記の不一致を避ける本質であり、ファイルシステムに一切触れないという意味ではない。
#
# 判定は書き込み先パスの**文字列としての prefix 一致**のみで行い、realpath/symlink 解決・
# 大文字小文字を畳む正規化は一切行わない((C)(I)と同じ lexical な判定。`_wt_norm_path` を再利用)。
# これにより判定結果は「実行環境のファイルシステムが大文字小文字を区別するか」に依存しない
# (同じ文字列の組には、ディスク上の実際の解決結果に関わらず常に同じ判定を返す。区別する環境
# (Linux 既定)では異なる大文字小文字のパスは実際に別ディレクトリであり検知は正しい。区別しない
# 環境(macOS 既定)でも同じ文字列比較を行うため判定は変わらず、結果としてどちらの環境でも
# 同一の入力に同一の判定を返す=挙動が環境に依存しない)。
_kw_find_toplevel() {  # <正規化済み絶対パスのディレクトリ>
  local d="$1"
  while :; do
    [ -e "$d/.git" ] && { printf '%s' "$d"; return 0; }
    [ "$d" = "/" ] && return 1
    d="$(dirname -- "$d")"
  done
}
_kw_fp="$(get_file_path "$input")"
if [ -n "${_kw_fp:-}" ]; then
  _kw_content="$(get_write_content "$input")"
  if [ -n "${_kw_content:-}" ] \
     && printf '%s\n' "$_kw_content" | grep -E '^id:' >/dev/null \
     && printf '%s\n' "$_kw_content" | grep -E '^domain:' >/dev/null \
     && printf '%s\n' "$_kw_content" | grep -E '^scope:' >/dev/null \
     && printf '%s\n' "$_kw_content" | grep -E '^status:' >/dev/null; then
    case "$_kw_fp" in
      /*)   _kw_check="$(_wt_norm_path "$_kw_fp")" ;;
      '~'*) _kw_check="$(_wt_norm_path "$HOME${_kw_fp#\~}")" ;;
      *)    _kw_check="$(_wt_norm_path "${cwd:-}/$_kw_fp")" ;;
    esac
    _kw_projroot="$(_kw_find_toplevel "$(dirname -- "$_kw_check")" 2>/dev/null)"
    if [ -z "${_kw_projroot:-}" ]; then
      _kw_projroot="${CLAUDE_PROJECT_DIR:-}"
      [ -z "$_kw_projroot" ] && _kw_projroot="${cwd:-}"
    fi
    if [ -n "${_kw_projroot:-}" ]; then
      _kw_store="$(_wt_norm_path "$_kw_projroot/.claude/knowledge")"
      case "$_kw_check" in
        "$_kw_store"|"$_kw_store"/*) : ;;
        *) warn "knowledge エントリの形(frontmatter に id:/domain:/scope:/status: が揃っている)をしたファイルが、install 先のストア(${_kw_store})の外(${_kw_check})へ書かれようとしています。索引の再生成・構造監査が効かず、蓄積が静かに失われます。正当な理由(テストのフィクスチャ・ドキュメントの例示等)が無ければ書き込み先をストア配下に直してください。書き込み自体は妨げません。" ;;
      esac
    fi
  fi
fi

[ -n "$cmd" ] || exit 0

# grep に -q を渡さない(全体を set -o pipefail で動かしているため)。-q は一致した時点で
# 読むのをやめて終了する。$cmd が長いと、まだ書き込み中の printf(パイプの書き手)が
# SIGPIPE(終了コード141)を受け、pipefail がその141をパイプライン全体の終了コードにする
# ため、実際には一致しているのに if 側は「不一致」と判定してしまう(fail-open)。
# -q を外し出力を捨てる形(`grep -E … >/dev/null`)にする。これは POSIX の保証ではない
# (GNU grep の NEWS 2.27 節も、-q 等の早期終了オプションを使わないこの書き方を
# nonportable scripts と呼んで救済しているだけで、規格上の約束としては書いていない)。
# GNU grep 2.27 以降・BSD grep・BusyBox では、-q 等の早期終了オプションが無ければパイプの
# 入力を最後まで読む(実装の挙動)。この実装の挙動に頼ってこの経路を塞ぐ。同じ理由で
# 本ファイル内の他の `printf … | grep -…q …` も同様に -q を外している。
chk()   { printf '%s' "$cmd" | grep -E "$1" >/dev/null; }

# ブロックの既定メッセージ末尾(${NO_BYPASS_MSG}、定義は本ファイル冒頭)は解除の手段を持たない
# 止め方であることを伝える。すべてのブロックがこれをメッセージ末尾に使う(以前は「opt-out env
# ゲートを持つブロック」と「持たないブロック」で2種の文言(解除できないと伝える文言／実行
# できないと伝える文言)を使い分けていたが、opt-out 自体が無くなったため区別する理由が無くなり、
# 1種類に統合した)。

# (A) のセグメント分割(; | & および改行)の前に、クォート(シングル/ダブル)で囲まれた領域と
# heredoc 本体を「区切り文字として機能しない」形へ折り畳む(over-detection 対策)。
# stdin の複数行文字列を1行ずつ走査し、状態(normal/squote/dquote/heredoc)を行を跨いで持ち回る:
#   - クォート内の ";"/"|"/"&" は空白に置換する(セグメント境界にしない)。閉じクォートまで
#     跨る複数行は改行の代わりに空白で連結し、1レコードとして出力する(newline もセグメント
#     境界として働かないようにするため)。
#   - heredoc(<<[-]['"]DELIM['"]、here-string "<<<" は対象外)を検知したら、対応する終端行
#     (delim のみの行。"<<-" は行頭タブを許容)までの本体行を空行へ置き換える(実行されない
#     データなので検知対象から外す)。
# 完全な shell パーサは目指さない best-effort(guard の設計方針どおり)。ネストしたコマンド
# 置換 $(...) の中で改めてクォート/heredoc パースが独立する、というシェルの実際の入れ子規則までは
# 再現しない(例: 外側の "..." の中に <<'EOF' が現れても、この関数は外側のクォート走査を継続する
# だけで heredoc として個別検知しない)。ただし外側のクォートが正しく閉じている限り、内側の
# heredoc本体を含む全体が1つの折り畳み対象として連結されるため、検知の安全側("git" 等の実コマンドの
# 先頭トークンではなく、それを包む実際の呼び出しコマンドの先頭トークンだけが見える)という
# 目的は達成される。known-gap(best-effort・境界ではない): バックスラッシュによる行継続、
# 同一行内の複数 heredoc 演算子(2つ目以降の delim は上書きされ見失う)は非対応。
fold_quotes_and_heredocs() {
  awk '
  BEGIN {
    mode = "normal"      # normal | squote | dquote | heredoc
    delim = ""
    striptabs = 0
    pending = ""
  }
  {
    line = $0
    if (mode == "heredoc") {
      trimmed = line
      if (striptabs) { sub(/^\t+/, "", trimmed) }
      if (trimmed == delim) { mode = "normal" }
      print ""
      next
    }
    n = length(line)
    out = ""
    i = 1
    cur = mode
    heredoc_triggered = 0
    while (i <= n) {
      c = substr(line, i, 1)
      if (cur == "normal") {
        if (c == "\x27") { cur = "squote"; out = out c; i++; continue }
        if (c == "\"")   { cur = "dquote"; out = out c; i++; continue }
        if (c == "<" && substr(line, i+1, 1) == "<") {
          if (substr(line, i+2, 1) == "<") {
            # here-string(<<<)は heredoc ではない(単一行の入力リダイレクト)。
            out = out "<<<"; i += 3; continue
          }
          j = i + 2
          if (substr(line, j, 1) == "-") { j++; hd_strip = 1 } else { hd_strip = 0 }
          while (substr(line, j, 1) == " " || substr(line, j, 1) == "\t") { j++ }
          q = ""; qc = substr(line, j, 1)
          if (qc == "\x27" || qc == "\"") { q = qc; j++ }
          wstart = j
          while (j <= n) {
            cc = substr(line, j, 1)
            if (cc ~ /[A-Za-z0-9_]/) { j++ } else { break }
          }
          word = substr(line, wstart, j - wstart)
          if (q != "" && substr(line, j, 1) == q) { j++ }
          if (word != "") {
            out = out substr(line, i, j - i)
            mode_pending_delim = word
            mode_pending_strip = hd_strip
            i = j
            heredoc_triggered = 1
            continue
          } else {
            # delim が取れなかった(不正な形) → heredoc とみなさずそのまま2文字を素通し。
            out = out "<<"; i += 2; continue
          }
        }
        out = out c; i++; continue
      } else if (cur == "squote") {
        if (c == "\x27") { cur = "normal"; out = out c; i++; continue }
        if (c == ";" || c == "|" || c == "&") { out = out " " } else { out = out c }
        i++; continue
      } else if (cur == "dquote") {
        # ダブルクォート内のバックスラッシュエスケープされた " は閉じクォートとして扱わない
        # (best-effort。他のエスケープ($ ` \ 等)までは追わない)。
        if (c == "\\" && substr(line, i+1, 1) == "\"") { out = out "  "; i += 2; continue }
        if (c == "\"") { cur = "normal"; out = out c; i++; continue }
        if (c == ";" || c == "|" || c == "&") { out = out " " } else { out = out c }
        i++; continue
      }
    }
    if (heredoc_triggered) {
      print pending out
      pending = ""
      mode = "heredoc"
      delim = mode_pending_delim
      striptabs = mode_pending_strip
      next
    }
    if (cur == "normal") {
      print pending out
      pending = ""
    } else {
      # クォートが行末でまだ閉じていない → この行の末尾に real newline を出さず、
      # 次の行と連結する(newline がセグメント境界として働かないようにするため)。
      pending = pending out " "
    }
    mode = cur
  }
  END {
    if (pending != "") print pending
  }
  '
}

# セグメント冒頭のシェルキーワード(if/then/else/elif/fi/while/until/do/done/{/})を読み飛ばし、
# 後続の実コマンドの先頭トークンが $1 になるよう文字列を作り直す(stdin を読み stdout へ書く)。
# ; | & でのセグメント分割は演算子でしか区切らないため、"if cd <外>; then git ...; fi" や
# "if true; then git commit --no-verify" のようにキーワードで包まれると、各セグメント先頭トークンの
# awk 判定($1 が "git"/"cd" か等)がキーワード自体を見てしまいすり抜ける。
#
# 通すべき対象はここに列挙しない(strip_command_prefix 定義直前のコメントと同じ判断・同じ理由):
# **セグメントの先頭トークンに判定を紐づけるチェックは、種類・場所を問わずすべてこの関数を通す**
# (性質で決まる。個数を数えて憶えておく必要は無い)。具体的な消費者を番号・記号で列挙する方式は、
# strip_command_prefix の消費者列挙で実際に4回訂正されて4回とも間違っていた(4箇所→6箇所→7箇所→
# 少なくとも9箇所、という具合。詳細は strip_command_prefix 定義直前のコメント参照)。消費者が
# ファイル中に散在し、新しい消費者が追加されるたびに全箇所の列挙を追随させる運用そのものが
# 持続しないため、この関数についても**列挙をここへは書かない・他箇所にも複製しない**(書けば
# 必ずまた古くなる。「先頭トークンで判定するチェックか」という性質さえ守れば、消費者の増減は
# このコメントを腐らせない)。strip_command_prefix と同様、呼び出し側は先にこの関数を通してから
# 自分の先頭トークン判定を行う。
#
# best-effort: 列挙したキーワードのみ対応(将来別キーワードでの再バイパスが出たら拡張する前提)。
# 実装は awk のデフォルトフィールド分割(空白区切り)で先頭トークンを判定し、キーワードである間
# 読み飛ばして残りのトークンを単一スペース区切りで再結合する(下流の awk も同じデフォルト分割で
# $1 を見るため、間隔の再構成による影響は無い)。
# 意図的に `(`/`)` は含めない: サブシェル `(...)` は cd のスコープが呼び出し元と分離される
# (subshell 内の cd は外へ漏れない)一方、(C) の cd 状態追跡はセグメント跨ぎで cd の永続を
# 前提にしサブシェル境界を認識しないため、`(`/`)` を読み飛ばすと
# "( cd <外> ) ; git log"(サブシェル内だけの cd で本来 git には影響しない)を誤って
# worktree 外 git として block する false positive を新たに生む(実機確認済み)。
# サブシェル経由の cd は既存コメントに記載の known-gap(best-effort・境界ではない)のまま維持する。
# known-gap(best-effort・境界ではない。この関数を通すすべての消費者に共通・この関数の性質
# そのもの): case/select/function のパターン一致行の内部に実コマンドが同居する形はこの読み飛ばし
# 方式では救えない。この方式は ";"/"|"/"&" で区切った「別セグメントの先頭」に実コマンドが来る
# if/while 系だけを想定しており、case の "パターン) 実コマンド ;;" のように同一セグメント内で
# ラベルと実コマンドが同居する形はセグメント分割の前提が異なるため対象外(例:
# case $x in a) git commit --no-verify -m x ;; esac /
# case 1 in 1) cd <worktree外>; git log ;; esac のどちらも検知できない)。対応するには
# case/in/パターン)/;; も分割境界に含める方式への変更が要り、実装が複雑化して過検知(FP)の
# リスクが増すため対応しない: guard は完全な shell パーサを目指さない best-effort な網であり、
# 過検知を増やさないことを優先する(捕まえたいのは「うっかり」で、case 文をわざわざ書いて
# 回避する操作者はうっかりではない)。
strip_shell_keywords() {
  awk '
    function is_kw(w) {
      return (w=="if" || w=="then" || w=="else" || w=="elif" || w=="fi" || \
              w=="while" || w=="until" || w=="do" || w=="done" || \
              w=="{" || w=="}")
    }
    {
      n = NF; start = 1
      while (start <= n && is_kw($start)) start++
      out = ""
      for (i = start; i <= n; i++) out = out (i > start ? " " : "") $i
      print out
    }
  '
}

# env / sudo が値を取る代表的なオプションの表(awk 連想配列の初期化コードそのものを文字列として
# 保持する)。strip_command_prefix() と (C) worktree 隔離ガードの git 判定側(_wt_gittarget を
# 組み立てる awk。本ファイル内で "envval\[" を grep すれば見つかる)の**両方**がこの2変数を
# 展開して BEGIN ブロックへ埋め込む。値そのものを1箇所に持ち両方へ展開することで、片方だけが
# 更新される drift を構造的に防ぐ(相互参照コメントだけでは強制力が無く、実際に「既存の解決を
# 知らずに新しい判定を書いて同型の穴を再生産した」事例が出ているため、コメント頼みにしない)。
# env -S/--split-string はこの表に含めない: -S は値を1トークン読み飛ばせば安全に無視できる
# 普通のオプションではなく、後続の引数文字列をシェルとして分割・実行するラッパー展開
# (sh -c / bash -c と同型)であるため、単純な値スキップとして扱うと実コマンドの文字列ごと
# 握り潰し確実に素通りする(`env -S "git commit --no-verify -m x"` が対象コマンドを失う)。
# 対応するなら _gi_extract_wrapped 側のラッパー展開として扱うべきで、この表の役割
# (「安全に読み飛ばしてよい値取りオプション」)とは性質が異なる。known-gap として明記し、
# この表には追加しない(`env -S` は修正後も素通りしたままの既知の残余)。
_GS_ENVVAL_TBL='envval["-u"]=1; envval["--unset"]=1; envval["-C"]=1; envval["--chdir"]=1'
# sudo が値を取る代表的なオプション。出典: sudo(1)。-D/--chdir は env の -C/--chdir と同じ
# 「実行時限りの作業ディレクトリ変更」効果を持つ(-C/--close-from は無関係な数値オプションで
# ディレクトリを取らないため対象外)。
_GS_SUDOVAL_TBL='sudoval["-u"]=1; sudoval["--user"]=1; sudoval["-g"]=1; sudoval["--group"]=1; sudoval["-h"]=1; sudoval["--host"]=1; sudoval["-p"]=1; sudoval["--prompt"]=1; sudoval["-r"]=1; sudoval["--role"]=1; sudoval["-t"]=1; sudoval["--type"]=1; sudoval["-U"]=1; sudoval["--other-user"]=1; sudoval["-C"]=1; sudoval["--close-from"]=1; sudoval["-D"]=1; sudoval["--chdir"]=1'

# セグメント冒頭の「実コマンドを間接的に起動する」前置トークン(環境変数代入 VAR=val・
# command/env/sudo/builtin/nohup・timeout)を読み飛ばし、実コマンドの先頭トークンが $1 になるよう
# 文字列を作り直す(stdin を読み stdout へ書く)。
#
# 通すべき対象はここに列挙しない: **セグメントの先頭トークンに判定を紐づけるチェックは、
# 種類・場所を問わずすべてこの関数を通す**(性質で決まる。個数を数えて憶えておく必要は無い)。
# 具体的な消費者を番号・記号で列挙する方式は、この関数を数え直すたびに違う数を出し続けた
# (起票時点「4箇所」→ 実装時に「6箇所」への訂正が必要と判明 →一次レビューで実は「7箇所」
# だったと訂正 → さらに調べると9箇所以上あると判明、という具合に4回とも数え間違えた)。
# 原因は数え方が下手だったことではなく、消費者がファイル中に散在し、かつ新しい消費者が
# 追加されるたびに全箇所の列挙を追随させる運用そのものが持続しないこと。そのため**列挙を
# ここへは書かない・他箇所にも複製しない**(書けば必ずまた古くなる。「先頭トークンで判定する
# チェックか」という性質さえ守れば、消費者の増減はこのコメントを腐らせない)。
# strip_shell_keywords と同様、呼び出し側は先にこの関数を通してから自分の先頭トークン判定を行う。
#
# env/sudo は自身もオプションを取り、しかも値を取るものがある(env -u NAME / sudo -u user 等)。
# 代表的な値取りオプションだけを上記の表(_GS_ENVVAL_TBL/_GS_SUDOVAL_TBL)で持ち、それ以外の
# "-" 始まりトークンは単独のフラグとして読み飛ばす。
# command は `-p`(既定の PATH で実際にコマンドを実行するため env/sudo と同型のバイパスになる。
# 読み飛ばす)と `-v`/`-V`(コマンドを実行せず場所を表示するだけ)とで扱いを分ける非対称:
# `-v`/`-V` は意図的に読み飛ばさない。読み飛ばして後続を実コマンドとして扱うと、実行されない
# 呼び出し(`command -v git`)を実コマンド呼び出しと誤認して block する過剰ブロックになる
# (解除手段の無い過剰なブロックは迂回を学習させる。既に別途観測・対処済みの失敗パターン)。
# 読み飛ばさなければ先頭トークンが "-v"/"-V" のまま残り、判定対象のコマンド名と一致しないため
# 結果として正しく非ブロックになる(意図的な非対称であり、表の漏れではない)。
# 表に無い分離形の値取りオプション(env/sudo とも。例 `sudo -T 30 <cmd>`)に遭遇した場合、
# そのオプションが値を取るかどうかを断定できない。この関数は「加工済み文字列を返し、呼び出し側は
# 先頭トークンだけを見る」インターフェースのため、(C) の git 判定側のような「loose 走査へ切り替える」
# 逃げ道を構造的に持てない(戻り値インターフェースと全消費者の判定方法を変える必要があり、
# 費用対効果に見合わない)。安全性はこの表の網羅性に依存させず、best-effort として単独フラグ扱いに
# 倒す(known-gap。strip_shell_keywords と同じ設計判断: 捕まえたいのは「うっかり」であり、
# 表に無い珍しいオプションをわざわざ選ぶ操作者はうっかりではない)。
# `--`(オプション終端)に到達したら、それ自体を読み飛ばして直後から実コマンドとして扱う。
# env/sudo/command/builtin/nohup は入れ子になりうる(例 `sudo env VAR=1 git …`)ため、
# 前置トークンが尽きるまで下記の while ループで回す。
# timeout だけ他の前置トークンと違い、自身の必須位置引数(DURATION)を持つため単純な1トークン
# skip では次のトークンが DURATION(例 "5")になってしまい実コマンドを取り違える。timeout 自身の
# オプション(値を取る代表的なもの -s/--signal・-k/--kill-after は2トークン、それ以外の "-" 始まり
# トークンは1トークン)を読み飛ばした後、DURATION を1トークンだけ追加で読み飛ばす。
strip_command_prefix() {
  awk '
    function is_prefix_kw(w) {
      return (w=="builtin" || w=="nohup")
    }
    function is_timeout_opt(w) {
      return (w=="-s" || w=="--signal" || w=="-k" || w=="--kill-after")
    }
    BEGIN {
      '"$_GS_ENVVAL_TBL"'
      '"$_GS_SUDOVAL_TBL"'
    }
    {
      n = NF; start = 1
      while (start <= n) {
        if ($start ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { start++; continue }
        if ($start == "command") {
          start++
          if (start <= n && $start == "-p") { start++ }
          continue
        }
        if (is_prefix_kw($start)) { start++; continue }
        if ($start == "env" || $start == "sudo") {
          kind = $start
          start++
          while (start <= n && substr($start,1,1) == "-" && $start != "--") {
            opt = $start
            if (opt ~ /^--[A-Za-z][A-Za-z-]*=/) { start++; continue }
            if ((kind == "env" && (opt in envval)) || (kind == "sudo" && (opt in sudoval))) {
              start += 2; continue
            }
            start++
          }
          if (start <= n && $start == "--") start++
          continue
        }
        if ($start == "timeout") {
          start++
          while (start <= n && substr($start,1,1) == "-") {
            if (is_timeout_opt($start)) { start += 2 } else { start++ }
          }
          if (start <= n) { start++ }
          continue
        }
        break
      }
      out = ""
      for (i = start; i <= n; i++) out = out (i > start ? " " : "") $i
      print out
    }
  '
}

# strip_shell_keywords_and_prefix: strip_shell_keywords() と strip_command_prefix() を
# 1回の awk 呼び出しに統合したもの(全 Bash 呼び出しの前段で走るセグメント単位のループが、
# 消費者ごとに `strip_shell_keywords | strip_command_prefix` で awk を2回起動していたぶんの
# プロセス起動コストを、セグメント数×消費者数だけ削るための対応)。両関数のロジックをそのまま
# 1つの awk プログラムへ複製し、is_kw の読み飛ばしに続けて前置トークンの読み飛ばしを**同じ
# フィールド配列上で連続して**行うだけで、判定そのもの(何を・どこまで読み飛ばすか)は一切
# 変更しない——2関数を順にパイプした場合と出力は常に同一になる(片方の出力を丸ごと次の入力に
# 渡すのと、同じフィールド列上で開始インデックスを引き継いで処理を続けるのとは、フィールド分割が
# 空白区切りである限り等価)。
# 中間結果(is_kw 読み飛ばし後・前置トークン読み飛ばし前)を別途必要とする消費者
# (GIT_DIR/GIT_WORK_TREE の値を保持したまま拾う (C)/(H) 各セクション。strip_command_prefix は
# それらの代入トークンを値ごと捨てるため、通した後の文字列からは値を取り戻せない
# ——strip_command_prefix 定義直前のコメント参照)はこの統合版を使わず、従来どおり
# strip_shell_keywords() と strip_command_prefix() を個別に呼ぶ(単一の家は2関数のまま。
# この関数はそれらを消費側の都合で束ねた薄いラッパーであり、ロジックの家を移さない)。
strip_shell_keywords_and_prefix() {
  awk '
    function is_kw(w) {
      return (w=="if" || w=="then" || w=="else" || w=="elif" || w=="fi" || \
              w=="while" || w=="until" || w=="do" || w=="done" || \
              w=="{" || w=="}")
    }
    function is_prefix_kw(w) {
      return (w=="builtin" || w=="nohup")
    }
    function is_timeout_opt(w) {
      return (w=="-s" || w=="--signal" || w=="-k" || w=="--kill-after")
    }
    BEGIN {
      '"$_GS_ENVVAL_TBL"'
      '"$_GS_SUDOVAL_TBL"'
    }
    {
      n = NF; start = 1
      while (start <= n && is_kw($start)) start++
      while (start <= n) {
        if ($start ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { start++; continue }
        if ($start == "command") {
          start++
          if (start <= n && $start == "-p") { start++ }
          continue
        }
        if (is_prefix_kw($start)) { start++; continue }
        if ($start == "env" || $start == "sudo") {
          kind = $start
          start++
          while (start <= n && substr($start,1,1) == "-" && $start != "--") {
            opt = $start
            if (opt ~ /^--[A-Za-z][A-Za-z-]*=/) { start++; continue }
            if ((kind == "env" && (opt in envval)) || (kind == "sudo" && (opt in sudoval))) {
              start += 2; continue
            }
            start++
          }
          if (start <= n && $start == "--") start++
          continue
        }
        if ($start == "timeout") {
          start++
          while (start <= n && substr($start,1,1) == "-") {
            if (is_timeout_opt($start)) { start += 2 } else { start++ }
          }
          if (start <= n) { start++ }
          continue
        }
        break
      }
      out = ""
      for (i = start; i <= n; i++) out = out (i > start ? " " : "") $i
      print out
    }
  '
}

# wt_write_targets_for_segment: 出力リダイレクト(> / >>)と代表的な書き込みコマンド
# (cp/mv/tee/dd)から書き込み先候補を抽出する(newline 区切り・未解決の生トークンのまま返す
# ——クォート除去・絶対パス化・cd 状態の適用は呼び出し側が行う)。
# 元は (C) worktree 隔離ガードの共有チェックアウト書き込み検知にインライン実装されていた awk を
# そのまま関数化したもの(判定ロジックは一切変更していない)。(C) と (I2-Bash) knowledge エントリ
# 誤着地検知(シェル経由)の両方から呼ばれる単一の家。
# 引数: $1 = 書き込み先候補を走査する対象テキスト(> / >> のトークンスキャンは前置トークン
#            (env 代入・env/sudo/command/builtin ラッパー)の有無に左右されないため、前置除去済み
#            でも未除去でもよい)。$2 = cp/mv/tee/dd 判定用の、前置トークンを読み飛ばし済みの
#            テキスト(cmd=ct[1] が実コマンド名になっている必要がある)。$1 と同じ文字列
#            (前置除去済みのもの)を渡してよい(呼び出し側が前置除去を1回で済ませられる場合)。
wt_write_targets_for_segment() {
  local _wwt_seg="$1" _wwt_cdtrim="$2"
  printf '%s' "$_wwt_seg" | awk -v cdtrim="$_wwt_cdtrim" '
    {
      for (i=1;i<=NF;i++) {
        tok=$i
        if (tok==">" || tok==">>") {
          if (i<NF) print $(i+1)
        } else if (tok ~ /^>>?[^[:space:]>]/) {
          t=tok
          sub(/^>>?/,"",t)
          if (t!="") print t
        }
      }
    }
    END {
      n = split(cdtrim, ct, " ")
      if (n>=1) {
        cmd=ct[1]
        if (cmd=="cp" || cmd=="mv") {
          has_t=0
          for (i=2;i<=n;i++) {
            tok=ct[i]
            if (tok=="--target-directory" || tok ~ /^--target-directory=/) { has_t=1 }
            else if (substr(tok,1,1)=="-" && substr(tok,1,2)!="--" && tok ~ /t/) { has_t=1 }
          }
          if (!has_t) {
            cnt=0; last=""
            for (i=2;i<=n;i++) { tok=ct[i]; if (substr(tok,1,1)!="-") { cnt++; last=tok } }
            if (cnt>=2) print last
          }
        } else if (cmd=="tee") {
          for (i=2;i<=n;i++) { tok=ct[i]; if (substr(tok,1,1)!="-") print tok }
        } else if (cmd=="dd") {
          for (i=2;i<=n;i++) { tok=ct[i]; if (tok ~ /^of=/) print substr(tok,4) }
        }
      }
    }'
}

# wt_heredoc_bodies: $cmd(生テキスト・fold_quotes_and_heredocs で折り畳む前)から
# heredoc(<<[-]['"]?DELIM['"]?)の出現を出現順に抽出し、各出現について「delim が引用符付きか
# (0/1。引用符付き=シェルによる変数展開・コマンド置換が起きない=内容が確実に読める)」と
# 「本体テキスト」を返す((I2-Bash) knowledge エントリ誤着地検知(シェル経由)専用)。
# fold_quotes_and_heredocs は heredoc 本体を空行化して捨てる設計(セグメント分割を壊さない
# ため)なので、本体そのものを保持するにはここで $cmd を別途スキャンし直す必要がある。
# 状態機械(引用符・heredoc 検知の判定)は fold_quotes_and_heredocs のものを元にしているが、
# 単一の家にはしない——fold 側は本体を「捨てる」ために回し、こちらは「保持する」ために回すという
# 役割の違いがあり、共有すると片方の変更がもう片方の意味を暗黙に変えてしまうため。
# 出力書式(1出現につき1ブロック。stdout。呼び出し側が \001 始まりの制御行で区切りを判定する):
#   \001H:<0|1>          (0=引用符無し=読めない可能性あり・1=引用符付き=読める)
#   <本体行...>           (0行以上)
#   \001E
# known-gap(best-effort。fold_quotes_and_heredocs と同じ制約を継承。同関数定義直前のコメント
# 参照): バックスラッシュによる行継続は非対応。同一行内の複数 heredoc 演算子は最初の1つだけを
# 認識する(fold 側は最後の1つを認識する——2つ目以降の delim を見失うという既存の known-gap を
# 継承しつつ、こちらは実装の単純さのため先頭を優先する。呼び出し側の対応づけは1コマンドにつき
# 高々1つの heredoc を想定した best-effort であり、複数 heredoc が絡む入れ子構成の対応づけは
# ズレうる)。
wt_heredoc_bodies() {
  awk '
  BEGIN { mode="normal"; delim=""; striptabs=0 }
  {
    line = $0
    if (mode == "heredoc") {
      trimmed = line
      if (striptabs) { sub(/^\t+/, "", trimmed) }
      if (trimmed == delim) { mode = "normal"; print "\001E"; next }
      # <<- は本体の各行(終端行だけでなく)からも先頭タブを除去してから実際にファイルへ
      # 書き込む(bash自身の heredoc 仕様)。striptabs が真のときは trimmed(タブ除去済み)を
      # 出力する——line(生の行)のままだと、タブインデントされた本体の frontmatter 判定が
      # 実際に書き込まれる内容とズレて発火しない(一次レビュー指摘・実機再現済み)。
      print (striptabs ? trimmed : line)
      next
    }
    n = length(line)
    i = 1
    triggered = 0
    while (i <= n) {
      c = substr(line, i, 1)
      if (mode == "normal") {
        if (c == "\x27") { mode = "squote"; i++; continue }
        if (c == "\"")   { mode = "dquote"; i++; continue }
        if (c == "<" && substr(line, i+1, 1) == "<") {
          if (substr(line, i+2, 1) == "<") { i += 3; continue }  # here-string(<<<)は対象外
          j = i + 2
          if (substr(line, j, 1) == "-") { j++; hd_strip = 1 } else { hd_strip = 0 }
          while (substr(line, j, 1) == " " || substr(line, j, 1) == "\t") { j++ }
          # delim の引用符扱いは '\''EOF'\''/"EOF"(囲み引用符)だけでなく \EOF(バックスラッシュに
          # よるエスケープ)も対象(シェル仕様: word の一部が引用符化されていれば全体が引用符化
          # 扱いになり展開が起きない)。バックスラッシュを見つけたら消費して q を立てる(囲み
          # 引用符と違い閉じ側の対応する文字は無い——EOF の直前1文字だけが実際にはエスケープ
          # 対象だが、判定としては「delim 全体が引用符扱い」で十分。一次レビュー指摘・実機
          # 再現済み: これを見落とすと <<\EOF が word="" のままヒアドキュメントとして検知されず、
          # frontmatter 判定にすら乗らない)。
          q = ""; qc = substr(line, j, 1)
          if (qc == "\x27" || qc == "\"") { q = qc; j++ }
          else if (qc == "\\") { q = "\\"; j++ }
          wstart = j
          while (j <= n) {
            cc = substr(line, j, 1)
            if (cc ~ /[A-Za-z0-9_]/) { j++ } else { break }
          }
          word = substr(line, wstart, j - wstart)
          if (word != "") {
            print "\001H:" (q != "" ? 1 : 0)
            delim = word; striptabs = hd_strip
            triggered = 1
            break
          } else { i += 2; continue }
        }
        i++; continue
      } else if (mode == "squote") {
        if (c == "\x27") { mode = "normal" }
        i++; continue
      } else if (mode == "dquote") {
        if (c == "\\" && substr(line, i+1, 1) == "\"") { i += 2; continue }
        if (c == "\"") { mode = "normal" }
        i++; continue
      }
    }
    if (triggered) { mode = "heredoc" }
  }
  '
}

# セグメント冒頭の前置区間(環境変数代入 VAR=val・env/sudo/command/builtin ラッパー)に現れる
# GIT_DIR/GIT_WORK_TREE の env 代入から値を抽出する(stdin を読み "GIT_DIR値|GIT_WORK_TREE値" を
# 1行で返す。無ければ空文字)。呼び出し側は strip_command_prefix を通す**前**のセグメントに対して
# これを呼ぶこと(strip_command_prefix はこれらの代入トークンを値ごと読み飛ばして捨てるため
# (strip_command_prefix 定義直前のコメント参照)、通した後では値が失われている)。
# 新しい方式は発明しない: (C) worktree 隔離ガードの git 判定側(_wt_gittarget を組み立てる awk。
# 本ファイル内で "envval\[" を grep すれば見つかる)が既に行っている抽出と同じ判定
# ——前置の env/sudo/command/builtin ラッパーを、値取りオプション表($_GS_ENVVAL_TBL/
# $_GS_SUDOVAL_TBL、strip_command_prefix と単一の家を共有)を使って安全に読み飛ばしつつ、その
# 合間に現れる VAR=val トークンのうち GIT_DIR/GIT_WORK_TREE を拾う——をここでも行う。読み飛ばし
# 中に表に無い値取りオプションへ遭遇したら(C) と同じ「loose フォールバック」に切り替え、残りの
# トークンを前方から走査して VAR=val を拾う(known-gap: (C) と同じくベストエフォート)。
# 出力を GIT_DIR/GIT_WORK_TREE の2値に分けているのは (C) との違い: (C) は「worktree の外を
# 指しているか」という単一の包含判定にしか使わないため両者を1つの target へ統合してよいが、
# ここでは実際に `git -C <dir> --git-dir=<gitdir> diff --staged` を組み立てて呼ぶ必要があり、
# どちらの変数か(作業ツリー相当か .git ディレクトリ相当か)を呼び出し側で区別する必要がある
# (抽出アルゴリズムそのものは (C) から流用し、出力の形だけを消費側の要件に合わせて変えている)。
extract_git_env_target() {
  awk '
    BEGIN {
      '"$_GS_ENVVAL_TBL"'
      '"$_GS_SUDOVAL_TBL"'
    }
    {
      gd = ""; gwt = ""
      i = 1
      fb = 0
      while (i <= NF) {
        if ($i ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
          eq = index($i, "=")
          var = substr($i, 1, eq - 1)
          val = substr($i, eq + 1)
          if (var == "GIT_DIR") { gd = val }
          if (var == "GIT_WORK_TREE") { gwt = val }
          i++
          continue
        }
        if ($i == "command" || $i == "builtin") { i++; continue }
        if ($i == "env" || $i == "sudo") {
          kind = $i
          i++
          while (i <= NF && substr($i, 1, 1) == "-" && $i != "--") {
            opt = $i
            if (opt ~ /^--[A-Za-z][A-Za-z-]*=/) { i++; continue }
            if ((kind == "env" && (opt in envval)) || (kind == "sudo" && (opt in sudoval))) { i += 2; continue }
            fb = 1; break
          }
          if (fb) break
          if (i <= NF && $i == "--") i++
          continue
        }
        break
      }
      if (fb) {
        for (k = i; k <= NF; k++) {
          if ($k ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
            eq = index($k, "=")
            var = substr($k, 1, eq - 1)
            val = substr($k, eq + 1)
            if (var == "GIT_DIR") { gd = val }
            if (var == "GIT_WORK_TREE") { gwt = val }
          }
        }
      }
      print gd "|" gwt
    }
  '
}

# セグメント文字列が cd/pushd による移動先を持つかを判定し、現在のディレクトリ($2)を基準に
# 解決した絶対パスを返す共有ヘルパー。(C) worktree 隔離ガード節が既に持つ cd/pushd 追跡ロジック
# (本ファイル内で "_wt_cdpath" を grep すれば見つかる。$_wt_cur を状態として持ち回りながら
# セグメントを前方から走査する形)と同じ判定を、(H)/(J) からも呼べる形に抽出したもの。新しい
# cd 解析ロジックを (H)/(J) 側に個別発明しない。**(C) 自身はこの関数を呼ばず、既存の実装を
# そのまま保持する**(挙動変更ゼロを保証するため。(C) の実装をこの関数の呼び出しへ置き換える
# リファクタリングは本対応のスコープに含めない)。
#
# $1: strip_shell_keywords | strip_command_prefix を両方通した後のセグメント文字列
#     ((H)/(J) が _scs_analyze_commit へ渡す直前の形 = $_scs_seg_sh/$_bpc_seg_sh と同じ形。
#     (C) の $_wt_cd_trim と同じ抽出結果になる)。
# $2: 現在のディレクトリ(絶対パス。bare cd の "~" や相対パスの解決基準に使う。空文字 = 基点
#     不明を意味する)。この関数を呼ぶのは (H)/(J) のみ((C) 自身はこの関数を呼ばない。定義直前の
#     コメント参照)であり、(H)/(J) は hook 入力に cwd フィールドが無いとき空文字を渡しうる。
# 出力: cd/pushd セグメントなら "CD|<解決後の絶対パス>"、そうでなければ "NOTCD"。
#
# 基点(cwd)が無い状態での相対パス cd は解決せず NOTCD 扱いにする(合成しない): (H) 節の
# known-gap コメント(「cwd も -C も得られない場合(hook 入力に cwd が無い等)は対象を特定できない
# ため走査をスキップする(fail-open)」)が宣言する不変条件を守るため。基点が空のまま相対パスを
# 合成すると _wt_norm_path("/<相対パス>") というルート直下の非空絶対パスが生まれてしまい、
# 「cwd 不明なら常にスキップする」という上記の不変条件を静かに破る(たまたま実在する git
# リポジトリと衝突すれば誤って block されうる。一次レビューで指摘され修正した)。
# 絶対パス・~ 展開の cd は基点を必要としないため、この制限の対象外(従来どおり合成してよい)。
wt_cd_target_for_segment() {
  local _wct_cd_trim="${1:-}"
  local _wct_cur="${2:-}"
  local _wct_cdpath
  _wct_cdpath="$(printf '%s' "$_wct_cd_trim" | awk '{ if ($1=="cd"||$1=="pushd") { if (NF>=2) print $2; else print "~" } }')"
  if [ -z "${_wct_cdpath:-}" ]; then
    printf 'NOTCD\n'
    return 0
  fi
  _wct_cdpath="$(printf '%s' "$_wct_cdpath" | sed -E "s/^['\"]//; s/['\"]\$//")"
  case "$_wct_cdpath" in
    /*) printf 'CD|%s\n' "$(_wt_norm_path "$_wct_cdpath")" ;;
    '~'*) printf 'CD|%s\n' "$(_wt_norm_path "$HOME${_wct_cdpath#\~}")" ;;
    *)
      if [ -z "${_wct_cur:-}" ]; then
        printf 'NOTCD\n'
      else
        printf 'CD|%s\n' "$(_wt_norm_path "$_wct_cur/$_wct_cdpath")"
      fi
      ;;
  esac
}

# ルート / ホーム直下を狙った再帰削除
# rm に続くフラグ群(トークン分割・並び順に依存しない)を集約し、r/R と f/F の両方が
# 含まれるかを見る(単一トークン内の順序 -rf/-fr だけでなく、-r -f / -f -r のような
# 複数トークンへの分割にも対応する)。長い連結オプション(-rfv 等)や
# --recursive/--force の long form も対象に含める。
# 対象トークンはクォート(シングル/ダブル)を1枚剥がしてから判定する(rm -rf "$HOME" 等の
# 標準的な書き方を取りこぼさないため)。フラグ列以降の全トークンを走査し、いずれかが対象なら
# block する(rm -rf X/foo / のように対象が2番目以降の引数でも検出する)。ただし ;/&&/||/&/|/
# リダイレクト(>/>>/</)が空白区切りの独立トークンとして現れたらそこで走査を止め、rm と無関係な
# 後続コマンド/リダイレクト先を対象パスとして誤検知しないようにする。
# 打ち切り判定は括弧の深さ(トークン中の "(" 出現数 - ")" 出現数の累計)が0の時だけ働かせる。
# $(...) やサブシェルの内側にある演算子トークン(例 $(echo a | echo b) の "|")を打ち切りと
# 誤認して、その後ろに続く実引数(root/home)を見逃さないようにするため。深さの追跡はトークン
# 単位のベストエフォート(トークン内の開閉順序までは見ない。空白を含む複雑な入れ子は非対応)。
# 対象パスの判定は既存仕様を維持: 厳密に "/" "~" "$HOME"、またはそれらの直後に
# もう1文字 "/" が続く形("//etc" 等)のみを対象とし、"/etc" や "./build" 等の
# 限定削除は対象外のまま(既存の known-gap・誤検知回避を変えない)。
# awk 側は一致しても exit しない(以前は `print "MATCH"; exit` で即終了していた)。
# $cmd が長いと、awk が入力を読み切る前に打ち切ることで書き手の printf が SIGPIPE を
# 受け、pipefail 下でその141がパイプライン全体の終了コードになって「一致した」判定を
# 隠してしまう。awk に最後まで読み切らせ、末尾の grep も -q を外して同じ理由で全読みに
# している(下の `| grep MATCH >/dev/null`)。
rm_root_delete() {
  printf '%s' "$cmd" | awk '
    BEGIN { SQ = sprintf("%c", 39) }
    function strip_q(t,    c, n) {
      c = substr(t,1,1)
      if (c == "\"" || c == SQ) t = substr(t,2)
      n = length(t)
      if (n > 0) {
        c = substr(t,n,1)
        if (c == "\"" || c == SQ) t = substr(t,1,n-1)
      }
      return t
    }
    # known-gap(best-effort・境界ではない): 対象がクォート内に空白を含む場合
    # (例 "~ mistake" や "/ mistake")、awk のデフォルト空白分割で断片化し、先頭断片の
    # クォートを剥がした結果が "~"/"/" と一致して誤検知(FP)しうる。真の修正にはクォート
    # 境界を畳み込む前処理(トークン再結合)が要り、実在頻度(そのような名前のパスを
    # 削除する)がほぼゼロな割に不釣り合いにコストが高いため対応しない。fail-safe
    # (block 側に倒れる)なので安全側の誤検知として許容する。
    function is_target(raw,    t) {
      t = strip_q(raw)
      return (t == "/" || t == "~" || t == "$HOME" || \
              (substr(t,1,1) == "/" && substr(t,2,1) == "/") || \
              (substr(t,1,1) == "~" && substr(t,2,1) == "/") || \
              (index(t, "$HOME") == 1 && substr(t, 6, 1) == "/"))
    }
    {
      for (i = 1; i <= NF; i++) {
        if ($i != "rm") continue
        has_r = 0; has_f = 0
        j = i + 1
        while (j <= NF && substr($j,1,1) == "-") {
          f = $j
          if (substr(f,1,2) == "--") {
            if (f == "--recursive") has_r = 1
            if (f == "--force") has_f = 1
          } else {
            g = f
            sub(/^-+/, "", g)
            if (g ~ /[rR]/) has_r = 1
            if (g ~ /[fF]/) has_f = 1
          }
          j++
        }
        if (has_r && has_f) {
          depth = 0
          for (k = j; k <= NF; k++) {
            t = $k
            if (depth == 0 && (t == ";" || t == "&&" || t == "||" || t == "&" || t == "|" || \
                t == ">" || t == ">>" || t == "<")) break
            opens = gsub(/\(/, "(", t)
            closes = gsub(/\)/, ")", t)
            depth += opens - closes
            if (depth < 0) depth = 0
            if (is_target(t)) { print "MATCH" }
          }
        }
      }
    }
  ' | grep MATCH >/dev/null
}
rm_root_delete \
  && block "ルート/ホーム配下の再帰削除を検出。対象パスを限定してください。" "rm_root_delete"

# force push のハードブロック(ブランチを問わず・--force-with-lease も免除しない)
# 背景: 以前は main/master への force push だけを対象とし、--force-with-lease は
# 免除していた。しかし --force-with-lease が防ぐのは「他者の未取得の更新を上書きしない」ことで
# あり、実際に起きた事故(push 済みでPRから参照されている履歴を、書き換えて置き換える)には
# 無関係(免除の根拠が守っているリスクと、実際に起きたリスクは別物)。しかも事故は main/master
# ではなく機能ブランチで起きた。したがってブランチ名では絞らず、force push そのもの
# (--force / -f / --force-with-lease / "+" refspec のいずれか)を対象にする。
# opt-out env は設けない: PR マージのハードブロック((D)(G)、本ファイル下方)と同じ判断——
# push 済み履歴の書き換えは押し戻しにくい操作であり、Claude 側にバイパス経路を用意する必要が
# 無い(討議収束済み。env を立てての自己承認を許すと「宣言(allow)≠実装(guard の特例)」の穴が
# 再び開いてしまう)。
# 判定方法は他の丁寧なセクション((D)(F)(G)(H)、本ファイル下方)と同じ型を先取りする:
# fold_quotes_and_heredocs でクォート/heredoc を折り畳んでから ; | & (と改行)でセグメント分割し、
# 各セグメント単位で先頭のシェルキーワード/前置トークンを読み飛ばしてから、実コマンドの先頭が
# git push 呼び出しかを awk で判定する(グローバルオプションを読み飛ばしてサブコマンドを見る、
# (A)(C)(D)(F)(H) と同じ型)。これにより PR 本文やコミットメッセージのテキストとして
# "git push ... --force" という文字列が引用符内に含まれるだけの場合は誤検知しない。
# 検出する force の形:
#   - --force(長形)
#   - --force-with-lease(=<refname>[:<expect>] 付きも含む。免除しない)
#   - -f(短形。単一ダッシュの短縮オプションクラスタ中の 'f' も含む。例 -uf)
#   - "+" で始まる refspec(例 git push origin +main / +HEAD:main。--force を明示しない
#     force push の別形)
# known-gap(best-effort・境界ではない): 動的に組み立てられる refspec・フラグ(変数展開等)は
# 静的パターンマッチの対象外(既存の best-effort な安全網という前提から変わらない)。
#
# 早期打ち切り: 判定が成立するには実コマンドの先頭トークンが "push" でなければ
# ならない(git のサブコマンド名は静的な文字列であり、実行時に組み立てられない)。したがって
# $cmd(セグメント分割・fold 前の生テキスト)のどこにも "push" という文字列が現れない場合、
# 以下のセグメント走査は絶対に何も検出しない。fold_quotes_and_heredocs はクォート/heredoc の
# **中の** ";"/"|"/"&" を空白へ置換するだけで、クォート外の文字列やクォート自体の文字を
# 追加することは無い(fold_quotes_and_heredocs 定義直前のコメント参照)——つまり fold 後の
# 文字列は生テキストに対して文字を「足さない」ため、fold 前に存在しない部分文字列が fold 後に
# 現れることは無い。この事実により、生テキストへの単純な部分文字列検査は fold 後の判定に対する
# 安全な上位集合(false negative を生まない早期スキップ)になる。1コマンドにつき grep を1回
# 追加するだけで、該当しないコマンド(大多数)ではセグメント数に比例するループ本体
# (プロセス起動を伴う awk 呼び出し)を丸ごと省略できる。
if printf '%s' "$cmd" | grep -E '(^|[^A-Za-z0-9_])push([^A-Za-z0-9_]|$)' >/dev/null; then
  _fp_folded=$(printf '%s' "$cmd" | fold_quotes_and_heredocs) || true
  _fp_segs=$(printf '%s' "${_fp_folded:-}" | tr ';|&' '\n\n\n') || true
  _fp_blocked=""
  while IFS= read -r _fp_seg; do
    [ -n "${_fp_blocked:-}" ] && continue
    case "${_fp_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
    _fp_seg_sh="$(printf '%s' "${_fp_seg:-}" | strip_shell_keywords_and_prefix)" || true
    _fp_result="$(printf '%s' "${_fp_seg_sh:-}" | awk '
      BEGIN { SQ = sprintf("%c", 39) }
      function strip_quotes(t,    r) {
        r = t
        gsub(/"/, "", r)
        gsub(SQ, "", r)
        return r
      }
      {
        n = length($0)
        cur=""; intok=0; qc=""; tc=0
        for (i=1;i<=n;i++) {
          c = substr($0,i,1)
          if (qc!="") { cur=cur c; if (c==qc) qc=""; continue }
          if (c=="\x27" || c=="\"") { qc=c; cur=cur c; intok=1; continue }
          if (c==" " || c=="\t") { if (intok) { tc++; arr[tc]=cur; cur=""; intok=0 }; continue }
          cur=cur c; intok=1
        }
        if (intok) { tc++; arr[tc]=cur }
        if (tc<1) { exit }
        # 絶対パス指定の git 呼び出し((C)(H)と同じ、先頭トークンの basename 判定)。
        nslash = split(arr[1], gitparts, "/")
        if (gitparts[nslash] != "git") { exit }
        two_tok["-C"]=1; two_tok["-c"]=1
        two_tok["--git-dir"]=1; two_tok["--work-tree"]=1; two_tok["--namespace"]=1
        two_tok["--super-prefix"]=1
        i=2
        while (i<=tc) {
          if (arr[i] in two_tok) { i+=2; continue }
          if (substr(arr[i],1,1)=="-") { i++; continue }
          break
        }
        if (i>tc || arr[i]!="push") { exit }
        i++
        has_force=0
        for (; i<=tc; i++) {
          t = strip_quotes(arr[i])
          if (t=="--force") { has_force=1; continue }
          if (t ~ /^--force-with-lease(=.*)?$/) { has_force=1; continue }
          if (substr(t,1,1)=="+" && length(t)>1) { has_force=1; continue }
          if (substr(t,1,1)=="-" && substr(t,2,1)!="-") {
            if (index(substr(t,2), "f") > 0) { has_force=1 }
          }
        }
        printf "PUSH|%d\n", has_force
      }
    ')"
    case "${_fp_result:-}" in
      PUSH\|1) _fp_blocked=1 ;;
    esac
  done <<< "${_fp_segs:-}"
  if [ -n "${_fp_blocked:-}" ]; then
    block "force push(--force / -f / --force-with-lease / '+' refspec のいずれか)を検出。ブランチを問わずハードブロックしています。--force-with-lease は他者の未取得の更新を上書きしないことは保証しますが、既に push され PR から参照されている履歴を書き換えて置き換えることは防ぎません。push 済みの履歴は書き換えられません(取り消し不能)。${NO_BYPASS_MSG}" "force_push"
  fi
fi

# 過剰な権限付与(chmod 777)
# 背景: 以前は $cmd 全文への chk()(部分一致 grep)一発で判定しており、実行されないリテラル
# (issue/PR 本文・コミットメッセージのようなドキュメント文脈で "chmod 777" という文字列を
# 例示・警告として書くだけ)でも誤ブロックしていた。force push ブロック(本ファイル上方)と
# 同じ型(クォート/heredoc を無害化 → ;|& でセグメント分割 → 各セグメントの先頭トークンへ
# 判定を紐づける)へ倣う。判定条件そのものは単一(AND を組む複数条件が無い)ため、force push の
# ようなパイプ連鎖判定は不要。
#
# 早期打ち切り: 判定が成立するには実コマンドの先頭トークンが "chmod" でなければならない
# (静的な文字列であり実行時に組み立てられない)。したがって $cmd(セグメント分割・fold 前の
# 生テキスト)のどこにも "chmod" という文字列が現れない場合、以下のセグメント走査は絶対に
# 何も検出しない(force push ブロック直前のコメントと同じ根拠: fold_quotes_and_heredocs は
# 文字を足さないため、fold 前に存在しない部分文字列が fold 後に現れることは無い)。
if printf '%s' "$cmd" | grep -E '(^|[^A-Za-z0-9_])chmod([^A-Za-z0-9_]|$)' >/dev/null; then
  _c7_folded=$(printf '%s' "$cmd" | fold_quotes_and_heredocs) || true
  _c7_segs=$(printf '%s' "${_c7_folded:-}" | tr ';|&' '\n\n\n') || true
  _c7_blocked=""
  while IFS= read -r _c7_seg; do
    [ -n "${_c7_blocked:-}" ] && continue
    case "${_c7_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
    _c7_seg_sh="$(printf '%s' "${_c7_seg:-}" | strip_shell_keywords_and_prefix)" || true
    _c7_result="$(printf '%s' "${_c7_seg_sh:-}" | awk '
      BEGIN { SQ = sprintf("%c", 39) }
      function strip_quotes(t,    r) {
        r = t
        gsub(/"/, "", r)
        gsub(SQ, "", r)
        return r
      }
      {
        n = length($0)
        cur=""; intok=0; qc=""; tc=0
        for (i=1;i<=n;i++) {
          c = substr($0,i,1)
          if (qc!="") { cur=cur c; if (c==qc) qc=""; continue }
          if (c=="\x27" || c=="\"") { qc=c; cur=cur c; intok=1; continue }
          if (c==" " || c=="\t") { if (intok) { tc++; arr[tc]=cur; cur=""; intok=0 }; continue }
          cur=cur c; intok=1
        }
        if (intok) { tc++; arr[tc]=cur }
        if (tc<1) { exit }
        # 絶対パス指定の chmod 呼び出し((C)(H)と同じ、先頭トークンの basename 判定)。
        nslash = split(strip_quotes(arr[1]), cparts, "/")
        if (cparts[nslash] != "chmod") { exit }
        # 短い1ダッシュのフラグクラスタ(-R・-Rv 等)だけを読み飛ばす(旧 chk() の正規表現
        # `(-[a-zA-Z]+[[:space:]]+)*` と同じ範囲。"--" 始まりの長いオプションは対象外)。
        i=2
        while (i<=tc) {
          t = strip_quotes(arr[i])
          if (substr(t,1,1)=="-" && substr(t,2,1)!="-") { i++; continue }
          break
        }
        if (i>tc) { exit }
        if (strip_quotes(arr[i]) == "777") { printf "CHMOD|1\n"; exit }
        printf "CHMOD|0\n"
      }
    ')"
    case "${_c7_result:-}" in
      CHMOD\|1) _c7_blocked=1 ;;
    esac
  done <<< "${_c7_segs:-}"
  if [ -n "${_c7_blocked:-}" ]; then
    block "chmod 777 は過剰な権限付与です。必要最小限の権限にしてください。" "chmod_777"
  fi
fi

# fork bomb
chk ':\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:' \
  && block "fork bomb と思われるパターンを検出。${NO_BYPASS_MSG}" "fork_bomb"

# ディスクデバイスへの直接書き込み
{ chk 'dd[[:space:]].*[[:space:]]of=/dev/' || chk 'mkfs(\.[a-z0-9]+)?[[:space:]]' \
  || chk '>[[:space:]]*/dev/(sd|nvme|disk|hd)'; } \
  && block "ディスクデバイスへの直接書き込みを検出。${NO_BYPASS_MSG}" "disk_device_write"

# SSH 公開鍵への追記
chk '>>?[[:space:]]*[^[:space:]]*\.ssh/authorized_keys' \
  && block "~/.ssh/authorized_keys への書き込みを検出。${NO_BYPASS_MSG}" "ssh_authorized_keys_append"

# --- プロジェクト方針: ローカルを汚さない ---
# (1)/(1b)/(2) no-litter はいずれも解除の手段を持たない無条件ブロック(本ファイル冒頭の
# 「解除の手段は無い」を参照)。docker-first は compose がある時だけ発火。

# (1) docker-first: compose があるのにホストで直接ランタイムを動かさない → make/docker へ誘導
#     対象はサーバ系(python/node/ruby/php)。Flutter/Dart・Unity 等ホスト実行が普通のものは対象外。
proj="${CLAUDE_PROJECT_DIR:-.}"
for f in compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
  if [ -f "$proj/$f" ]; then
    runtime='(^|[;&|]|[[:space:]])(python3?|pip3?|pytest|ruby|bundle|rails|rake|node|npm|pnpm|yarn|deno|bun|php|composer)([[:space:]]|$)'
    # docker/make 経由、ephemeral isolated(uv run/uvx/npx/pipx run/poetry run/venv) は許可
    via='(docker[[:space:]]+compose|docker-compose|(^|[[:space:]])make[[:space:]]|(^|[[:space:]])docker[[:space:]]|(^|[[:space:]])(uv[[:space:]]+run|uvx|npx|pipx[[:space:]]+run|poetry[[:space:]]+run)|python[[:space:]]+-m[[:space:]]+venv|uv[[:space:]]+venv)'
    vers='(--version|--help|[[:space:]]-v($|[[:space:]])|[[:space:]]-V($|[[:space:]])|[[:space:]]-h($|[[:space:]]))'
    if chk "$runtime" && ! chk "$via" && ! chk "$vers"; then
      block "このプロジェクトには docker compose があります。アプリのランタイムをホストで直接動かさず make / docker compose exec を使ってください。一時的な解析等は ephemeral isolated(uv があれば uv run --with / npx、無ければ使い捨てコンテナ yosage-dev-harness-scratch)で。${NO_BYPASS_MSG}" "docker_first_host_run"
    fi
    break
  fi
done

# (1b) グローバルへの恒久インストールを止め、ephemeral/isolated へ誘導
# ad-hoc 実行は可だがグローバルを汚さない。docker run 直書き(使い捨て)・scratch.sh
# (harness/lib/scratch.sh。内部で常に `docker run --rm ...` を組み立てて使い捨てコンテナを
# 起動するラッパー)経由は対象外。
#
# セグメント単位でゲート判定する(他のセクションと同じ型。fold_quotes_and_heredocs で
# クォート/heredoc を折り畳んでから ; | & (と改行)で分割し、各セグメントを個別に判定する)。
# 危険パターンの判定は他のセクションと同じ丁寧さ: まずそのセグメントの実コマンドの先頭トークンが
# 対象ツール(pip/pip3・python/python3 経由の `-m pip`・npm/pnpm・yarn・gem)であることを
# strip_shell_keywords | strip_command_prefix 済みの先頭トークンで確認してから、同じセグメント内の
# サブコマンド・オプションを見る。以前は素のセグメント全文への部分一致 grep のみで、そのセグメントの
# 実行コマンドが何かを一切見ていなかったため、危険パターンに一致する文字列がクォートされた引数値・
# ドキュメント本文として存在するだけ(実行されない)で誤ブロックしていた(実機確認: jq --arg に
# 渡した文字列リテラル内の "pip3 install"、gh issue create の本文中の npm/gem コマンド例が
# 誤って block されていた)。
#
# 間接呼び出し(実ツール名がラッパーの引数側にあり、セグメント先頭トークンがラッパー名になる形)は
# 2カテゴリある。いずれも一次レビューで実機確認された素通り(narrowing bypass)。
#   1. 別インタプリタのモジュール実行相当: `python -m pip install ...` / `python3 -m pip install ...`
#      (pip 公式ドキュメントが推奨する自然な呼び出し形)。
#   2. シェル/汎用ラッパー: `sh -c "<script>"` / `bash -c "<script>"` / `find ... -exec <cmd> ...` /
#      `xargs <cmd>`。
# 対応方針は一貫して「セグメント全文への部分一致へ戻さない」: セグメントの先頭トークンが既知の
# ラッパー(python/python3 の `-m`、sh/bash の `-c`、find の `-exec[dir]`、xargs)であることを
# 確認した上で、ラッパーの引数から実際に実行されるコマンド部分だけを抽出し、それを
# pip/npm/pnpm/yarn/gem の判定に**再度**通す(先頭トークンという錨は外さない。
# `gh issue create --body "sh -c 'npm install -g x'"` のように、ラッパー呼び出しの文字列を
# 引数値として含むだけの呼び出しは、セグメントの先頭トークンが gh のままなのでラッパー展開自体が
# 発火せず、誤ブロックは再発しない)。抽出・再判定は _gi_extract_wrapped / _gi_check_seg_text
# (関数定義は下記)が担う。
#
# 抽出したラッパーの引数が複数文(例 `sh -c "cd /tmp && pip install pandas"`)だった場合、
# 単純に1文として判定するだけでは2文目以降が検知されない(素通り。二次レビューで実機確認)。
# これを解くため、ラッパー展開は**再帰**にした: 抽出した引数テキストを新しい「解析対象」として、
# 同じ fold_quotes_and_heredocs → セグメント分割 → 先頭トークン確認 → 危険パターン判定 →
# ラッパー展開、のパイプライン全体(_gi_process_text)にもう一度通す。これにより
# `sh -c "cd /tmp && pip install pandas"` は、外側の展開で得た "cd /tmp && pip install pandas" を
# 再度セグメント分割し、"pip install pandas" セグメント単独で危険パターンに一致させて検知する。
#
# 再帰にあたり、セグメント分割そのものを見直した: fold_quotes_and_heredocs は「クォート内の
# ;|& は実行されないデータ」という前提で空白に中和するが、`sh -c "..."` の引数は逆に**実行される
# スクリプト**であり、中和すると再帰先で内部の ;|& を見失う(1回 fold すると元の文字が失われ、
# 再度 fold しても復元できない)。そこで _gi_raw_segments_from_folded を新設し、fold 済みテキストで
# 「クォート外に実際に残っている ;|& の文字位置」だけを境界として使い、**同じ文字位置**を raw
# (未加工)テキストから切り出す(fold_quotes_and_heredocs は 1 行・非 heredoc の入力に対して
# 文字数を変えない=1文字を1文字に置換するだけなので、raw と folded の文字位置は 1:1 対応する)。
# こうして得たセグメントはクォート境界は正しく認識しつつ、中身は加工されていない raw な文字列になり、
# ラッパー展開で取り出した引数の内部 ;|& が保持される。raw 復元は「単一行」かつ「fold 前後で
# 文字数が変わらない(heredoc 等が絡んでいない)」ときだけ行い、それ以外は中和済みセグメントへの
# フォールバックにする(下記 _gi_process_text 内のコメントに既定の倒れ方を明記)。
#
# npm/pnpm/yarn/gem 側は、python の `-m` に相当する「別インタプリタ経由でサブコマンドへ間接到達する」
# 自然な呼び出し形を確認したが、これらの CLI はいずれも自分自身のバイナリを直接起動する形以外に
# 広く文書化された間接呼び出し形を持たないため、python 以外のインタプリタ経由の対象は追加していない
# (sh/bash/find/xargs は「別インタプリタ」ではなく「シェル/汎用ラッパー」であり、上記の
# _gi_extract_wrapped で別途対応済み)。
#
# 免除(docker run 直書き・scratch.sh 経由)は本来「そのセグメントの先頭コマンドが実際に
# docker run / scratch.sh 呼び出しである」ときにだけ効かせる専用ロジックとして存在していたが、
# 上記の先頭トークン gate を pip/npm 等の危険パターン側にも適用した結果、両者は構造的に排他になった:
# 1セグメントの先頭トークンは1つの値にしかなり得ず、それが docker/bash(scratch.sh)であれば
# pip/pip3/python/python3/npm/pnpm/yarn/gem のいずれとも一致し得ないため、免除条件が真になる
# 状況では危険パターン側の gate が先に不成立になり、免除分岐へ到達する前に block 対象外と確定する
# (dead code 化。sh/bash ラッパー展開の awk が判定を担うようになった後も同じ理由で排他性は保たれる:
# docker run 直書きセグメントの先頭トークンは常に docker であり sh/bash ラッパー展開自体が発火
# しない。`yosage-dev-harness-scratch ...` セグメントの先頭トークンは bash だが、2番目のトークンが
# scratch.sh のパスであり "-o" のような既知オプションでも "-c" でもないため、sh/bash ラッパー展開の
# awk は非フラグ・非 -c トークンに到達した時点で抽出を諦め、無出力のまま終わる)。
# 実機確認(削除後も免除対象が block されないこと):
#   - docker run --rm python:3.12-slim sh -lc 'pip install pandas' → exit 0
#   - docker run --rm python:3.12-slim python -m pip install pandas → exit 0
#   - yosage-dev-harness-scratch --image python:3.12-slim -- pip install pandas → exit 0
#   - yosage-dev-harness-scratch --image python:3.12-slim -- pip install pandas → exit 0
# 上記により、免除の専用分岐(_gi_exempt)は撤去した(危険パターン gate が同じ役割を先頭トークンの
# 確認という形で既に担っているため、二重に判定する意味が無い)。
#
# 対象ツールの拡張・pip 判定の隣接要求撤廃(このセクションの追加分):
#
# (a) pip だけ「pip/pip3 の直後に install が隣接する」形を要求していた(npm/pnpm/yarn/gem は
#     ツール名の存在とサブコマンド/オプションの存在を独立2条件にしており、隣接を要求していない)。
#     このため pip 自身のグローバルオプションが間に挟まる形(例 `pip --no-cache-dir install x`)が
#     素通りしていた(実機確認)。オプションを列挙して読み飛ばす対応は、列挙から漏れれば同じ穴が
#     残り pip 側がオプションを追加するたびに腐るため採らない。npm/pnpm/yarn/gem と同じ
#     「同じ文の中にツール名と危険サブコマンドがある」形(隣接を要求しない独立2条件)へ揃えた。
#     この変更により、`pip help install` / `pip show install` のように "install" が別の意味で
#     現れる稀な形も新たに block されるが、実害は言い換えるだけで軽微であり、取りこぼしを残す
#     より望ましいと判断した(ホストを汚す操作は広く倒すのが正しいという方針に沿う)。
# (b) 見ていなかったツールを追加した: brew(install/reinstall/tap)・cargo install・go install・
#     pipx install(pipx run は使い捨てなので対象外。"install" 語を要求することで自然に除外される)・
#     uv tool install(uv pip install は別免除のまま・uv tool run/list/uninstall は "install" 語を
#     要求することで自然に除外される)・npm/pnpm link・gem update --system。
#     apt-get/apt は対象に含めない(sudo が前提であり、かつコンテナイメージのビルド中に書かれるのが
#     正常な形であるため、ブロックすると本来やってほしいことを妨げる)。
# (c) プロジェクト配下への明示的な相対パス指定(cargo install --root <相対パス>・
#     GOBIN=<相対パス> go install・npm install -g --prefix <相対パス>・pip install --target <相対パス>)
#     は免除する。判定は「値が英数字・`.`・`_` で始まる(=`/` 絶対パス・`~` ホームディレクトリ・
#     `$` 変数展開のいずれでもない)こと」のみとし、絶対パスがプロジェクト配下を指しているかどうかまでは
#     判定しない(パスの正規化と作業ディレクトリとの比較が必要になり失敗モードが増えるため。相対パスで
#     書くことに実質的な不便は無い)。
#     `$` 始まり(例 `$HOME/go/bin`・`$(pwd)/tools`)は免除しない: `$HOME` はホームディレクトリへ、
#     `$(pwd)` はカレントディレクトリの絶対パスへ展開され、値が実際に相対か絶対かは実行時にしか
#     決まらない(静的解析できない)。とくに `$HOME/go/bin` は go の既定のインストール先そのものであり、
#     これを免除すると「GOBIN を明示するだけで、本来ブロックしたかった既定の書き込み先がそのまま
#     通る」という取りこぼしになる(実機確認・一次レビュー指摘)。絶対パスと同じ理由(静的判定できない
#     ものは安全側=block に倒す)で `$` 始まりの値も免除対象に含めない。`GOBIN=$PWD/bin` のように
#     実質はプロジェクト配下を指す書き方も、静的には `$HOME` と区別できないためまとめて block になる。
#     利用者は `./bin` のように書けば免除されるため、実質的な不便は無い。この免除は明示指定がある
#     場合に限り、ツールごとの既定挿入先がプロジェクト配下かどうかは推測しない。
#
# _gi_relpath_exempt_flag / _gi_relpath_exempt_var: 相対パス免除(上記(c))の値抽出を担う共通処理。
# 一次レビュー再差戻し: 値の前後をクォートした形(例 --root "./tools"・--root '$HOME/x')が、
# クォート文字そのものが値パターン(英数字/./_ で始まる)に一致しないため、素直な相対パスでも
# クォートすると免除が外れてしまっていた(安全側=block へ倒れるので欠陥としては軽微だが、
# パスに空白を含み引用符が必須なケースで免除が使えないという実害があった)。値を分類する前に
# 前後のクォート(1層)を剥がす。剥がし方は $_wt_cdpath(cd/pushd の比較対象トークン)が使う
# 既存の方式 `sed -E "s/^['\"]//; s/['\"]\$//"`(独立した2つの単一文字除去)に揃える。
# パターン側で後方参照(\1)を使い「開き引用符と閉じ引用符が同じ文字であること」を要求する形は
# 使わない(BSD/macOS の sed -E は POSIX ERE の定義どおりパターン側の後方参照を解釈せず、
# 何もマッチせずに黙って無効化される。_gi_extract_wrapped 直前のコメントで既に踏んでいる)。
#
# _gi_relpath_exempt_flag: $1=判定対象テキスト $2=フラグ直前の境界を表す正規表現の代替候補
# (strict は `[[:space:]]`・loose は `[^A-Za-z0-9_]`) $3=フラグ名(例 --target)。
# フラグは "=値" 形・空白区切り値のどちらも見る(既存の危険パターン判定と同じ形)。
# 戻り値: 免除する(=block しない)なら 0、免除しない(=block を続ける)なら 1。
_gi_relpath_exempt_flag() {
  local _rp_text="${1:-}" _rp_b="${2:-}" _rp_flag="${3:-}"
  local _rp_val
  _rp_val="$(printf '%s' "$_rp_text" | grep -oE -- "(^|${_rp_b})${_rp_flag}(=|[[:space:]]+)[^[:space:]]+")" || true
  [ -n "${_rp_val:-}" ] || return 1
  _rp_val="$(printf '%s' "$_rp_val" | sed -E "s/^.*${_rp_flag}(=|[[:space:]]+)//")"
  _rp_val="$(printf '%s' "$_rp_val" | sed -E "s/^['\"]//; s/['\"]\$//")"
  printf '%s' "$_rp_val" | grep -E '^[A-Za-z0-9._]' >/dev/null
}

# _gi_relpath_exempt_var: $1=判定対象テキスト $2=変数直前の境界(同上) $3="=" を含む変数名
# (例 GOBIN=)。env 変数代入形(スペース区切り値は無い)専用。
_gi_relpath_exempt_var() {
  local _rp_text="${1:-}" _rp_b="${2:-}" _rp_var="${3:-}"
  local _rp_val
  _rp_val="$(printf '%s' "$_rp_text" | grep -oE -- "(^|${_rp_b})${_rp_var}[^[:space:]]+")" || true
  [ -n "${_rp_val:-}" ] || return 1
  _rp_val="$(printf '%s' "$_rp_val" | sed -E "s/^.*${_rp_var}//")"
  _rp_val="$(printf '%s' "$_rp_val" | sed -E "s/^['\"]//; s/['\"]\$//")"
  printf '%s' "$_rp_val" | grep -E '^[A-Za-z0-9._]' >/dev/null
}

# _gi_check_seg_text: 与えられたテキスト(セグメント全文、またはラッパーから抽出した内部
# コマンド文字列)に対し、pip/pip3(および python/python3 経由の `-m pip`)・npm/pnpm・yarn・gem・
# brew・cargo・go・pipx・uv の危険パターンを判定し、該当すれば _gi_blocked_pip / _gi_blocked_npm を
# 立てる(グローバル変数。呼び出し元が宣言・初期化する。_gi_blocked_npm は名前は npm 由来だが
# 「ホストへ永続的にインストールする npm 以外のツール全般」を含む共有バケットとして扱う)。
# セグメント本体とラッパー展開後の内部コマンドの両方に同じ判定を適用するための共通処理
# (重複実装を避ける)。
_gi_check_seg_text() {
  local _t="${1:-}"
  local _t_sh
  _t_sh="$(printf '%s' "$_t" | strip_shell_keywords_and_prefix)" || true
  # python -m pip / python3 -m pip: python の前方に来る値を取らない単純フラグ
  # (-u/-O/-B/-E/-s/-S/-v/-q/-I 等)を読み飛ばしてから "-m pip" が続くかを awk で確認する。
  # known-gap(best-effort): -X dev のような別トークンで値を取るフラグが -m より前にあると、
  # 値トークンが非フラグ(モジュール実行ではない呼び出し)と誤認され検知漏れになる
  # (実在頻度が低い形として許容。踏まれたら拡張する)。
  local _t_py
  _t_py="$(printf '%s' "${_t_sh:-}" | awk '
    {
      if ($1 != "python" && $1 != "python3") { exit }
      for (i = 2; i <= NF; i++) {
        if ($i == "-m") { if (i+1 <= NF) print $(i+1); exit }
        if (substr($i,1,1) != "-") { exit }
      }
    }
  ')" || true

  if [ -z "${_gi_blocked_pip:-}" ] \
     && { printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*pip3?([[:space:]]|$)' >/dev/null \
          || [ "${_t_py:-}" = "pip" ] || [ "${_t_py:-}" = "pip3" ]; } \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])install([[:space:]]|$)' >/dev/null \
     && ! printf '%s' "${_t:-}" | grep -E '(uv[[:space:]]+pip|\.venv/|(^|[[:space:]])venv/|activate)' >/dev/null \
     && ! _gi_relpath_exempt_flag "${_t:-}" '[[:space:]]' '--target'; then
    _gi_blocked_pip=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*(npm|pnpm)([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '([[:space:]]-g([[:space:]]|$)|--global)' >/dev/null \
     && ! _gi_relpath_exempt_flag "${_t:-}" '[[:space:]]' '--prefix'; then
    _gi_blocked_npm=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*(npm|pnpm)([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])link([[:space:]]|$)' >/dev/null; then
    _gi_blocked_npm=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*yarn([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E 'global[[:space:]]+add' >/dev/null; then
    _gi_blocked_npm=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*gem([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])install([[:space:]]|$)' >/dev/null; then
    _gi_blocked_npm=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*gem([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])update([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E -- '(^|[[:space:]])--system([[:space:]]|$)' >/dev/null; then
    _gi_blocked_npm=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*brew([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])(install|reinstall|tap)([[:space:]]|$)' >/dev/null; then
    _gi_blocked_npm=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*cargo([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])install([[:space:]]|$)' >/dev/null \
     && ! _gi_relpath_exempt_flag "${_t:-}" '[[:space:]]' '--root'; then
    _gi_blocked_npm=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*go([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])install([[:space:]]|$)' >/dev/null \
     && ! _gi_relpath_exempt_var "${_t:-}" '[[:space:]]' 'GOBIN='; then
    _gi_blocked_npm=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*pipx([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])install([[:space:]]|$)' >/dev/null; then
    _gi_blocked_npm=1
  fi
  if [ -z "${_gi_blocked_npm:-}" ] \
     && printf '%s' "${_t_sh:-}" | grep -E '^[[:space:]]*uv([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])tool([[:space:]]|$)' >/dev/null \
     && printf '%s' "${_t:-}" | grep -E '(^|[;&|]|[[:space:]])install([[:space:]]|$)' >/dev/null; then
    _gi_blocked_npm=1
  fi
}

# _gi_extract_wrapped: strip_shell_keywords | strip_command_prefix 済みのセグメント($1)の
# 先頭トークンが sh/bash/eval/ssh/find/xargs のいずれかで、かつラッパーとして実コマンドを内包する
# 形のときだけ、内包された実コマンド文字列を stdout へ出す(該当しなければ無出力=呼び出し側は
# 「このセグメントはラッパーではない/認識できない構造だった」として何もしない。これが既定の
# 倒れ方であり、意図的に素通り側にしている: guard は既知の自然な呼び出し形を狙い撃ちする
# best-effort な網であり、認識できない構造まで無理に block 側へ倒すと誤検知が増える)。
#   - sh -c "<script>" / bash -c "<script>": グローバルオプションをトークン境界を守って読み飛ばし
#     ((A)(--no-verify バイパス防止)・(G)(PR マージ操作のハードブロック)と同じ丁寧さ。値を取る
#     代表的なオプション -o <option> は2トークンとして読み飛ばす)、"-c" に到達したらそこから行末までを
#     substr で切り出す(フィールド分割で再構成しない。理由は下記)。"-c" は独立トークン
#     (`sh -c "..."`)・同一トークンへの結合(`sh -c'...'` / `sh -cfoo`)のどちらにも対応する。
#     切り出した引数の外側のクォート(1層)を剥がす。
#   - eval "<script>": "eval" の直後のトークンから行末までを substr で切り出す(sh/bash の "-c" と
#     同じ理由でフィールド再構成しない)。外側のクォート(1層)を剥がす。
#   - ssh [options] <destination> "<command>": 値を取る代表的なオプション(-p/-l/-i/-o/-F。
#     出典: man ssh(1))は2トークン、それ以外の "-" 始まりトークンは1トークンとして読み飛ばし、
#     最初の非フラグトークン(destination)の**次**のトークンから行末までを <command> とする
#     (ssh は destination 以降の複数引数を空白連結して1コマンドとしてリモート実行するため)。
#     外側のクォート(1層)を剥がす。destination だけで <command> が無い場合(対話ログイン)は
#     無出力(ラッパーではない)。
#   - find ... -exec[dir] <command> ... [\; または +]: -exec(dir) 以降をそのまま <command> として
#     抽出する(終端記号 \;/+ の位置を厳密に切り出さず、セグメント末尾までを渡す。危険パターン側の
#     判定は部分一致なので、末尾に残る \;・+・{} は判定に影響しない)。
#   - xargs [options] <command> [initial-args]: 値を取る代表的なオプション(-I/-i/-n/-P/-L/-l/-s/
#     -a/-d/-E/-J)は2トークンとして読み飛ばし、それ以外の "-" 始まりトークンは1トークンとして
#     読み飛ばして、最初の非フラグトークン以降を <command> とする(`-I {}` のような分離形も
#     `-I{}` のような結合形も両方対応する)。
#
# sh/bash の "-c" 引数抽出だけ、他(find/xargs)と違って awk のフィールド分割で値を再構成せず
# 行全体への substr で切り出している: フィールド分割は空白で機械的に区切るだけでクォートを
# 解さないため、"-c" の引数(クォートで囲まれ内部に空白を含みうる実行スクリプト)をフィールド単位で
# 再結合すると元の空白幅・引用符の位置関係が壊れる。フラグの認識(既知オプションかどうか)だけは
# フィールド走査で行い、抽出そのものは「そのフィールドが行の何文字目から始まるか」を使って
# 行全体から切り出す。find/xargs はコマンド名・オプション自体にクォート付き空白引数を持たない
# ため、フィールド再結合で十分(既存の実装のまま)。
_gi_extract_wrapped() {
  local _w="${1:-}"
  if printf '%s' "$_w" | grep -E '^[[:space:]]*(sh|bash)([[:space:]]|$)' >/dev/null; then
    printf '%s' "$_w" | awk '
      BEGIN {
        # 値を取る sh/bash のグローバルオプション(2トークン形)。出典: man bash(1) / POSIX sh。
        # 網羅ではなく "-c" の前に置かれる代表的なもの(-o <option>)を対象にする
        # (best-effort。他の2トークンオプションが前置される形は未対応・踏まれたら拡張する)。
        two_tok["-o"] = 1
      }
      # emit_c_arg: 引数の開始位置($spos)から、クォートで始まっていれば対応する閉じクォート
      # (同じ文字。二重引用符のみ直前の連続バックスラッシュが奇数のエスケープを除外する)までの
      # **内側だけ**を出力し、閉じクォート以降(find の "\;"/"+" のような後続の残骸)は捨てる。
      # クォートで始まっていなければ(裸の単語引数)行末までをそのまま出力する(既存挙動を維持)。
      # 旧実装は単純に「行末までを渡してから外側で sed により先頭/末尾のクォート文字を1枚剥がす」
      # 方式だったため、find -exec 経由でこの関数へ渡ってくる "-exec sh -c \x27...\x27 \;" のように
      # 閉じクォートの**後ろに他の文字が続く**形では末尾クォートが剥がれず、そのまま残ったクォートが
      # 再帰スキャン側の fold_quotes_and_heredocs を誤動作させて検知漏れになっていた(実機確認)。
      function emit_c_arg(spos,    qc, k, kc, bs, kj, found) {
        qc = substr($0, spos, 1)
        if (qc == "\x27" || qc == "\"") {
          found = 0
          for (k = spos + 1; k <= n; k++) {
            kc = substr($0, k, 1)
            if (kc == qc) {
              if (qc == "\"") {
                bs = 0; kj = k - 1
                while (kj >= 1 && substr($0, kj, 1) == "\\") { bs++; kj-- }
                if (bs % 2 == 1) { continue }
              }
              found = 1
              print substr($0, spos + 1, k - spos - 1)
              return
            }
          }
          if (!found) { print substr($0, spos + 1) }
          return
        }
        print substr($0, spos)
      }
      {
        if ($1 != "sh" && $1 != "bash") { exit }
        # 各フィールドの行内開始位置・長さを求める(理由は関数直前のコメント参照)。
        # 実装メモ: 旧実装は `while (match(substr($0, pos), ...))` のように残り全体を
        # substr で切り出してから match するループだった。substr はそのたびに「残り全体の
        # コピー」を新しく作るため、トークン数を N とすると本来 O(N^2) になりうる形であり、
        # アルゴリズムとして素直ではなかった。そこで fold_quotes_and_heredocs 等この関数内の
        # 他の走査と同じ「1文字ずつの substr($0, i, 1)」による左から右への1回のみの線形走査に
        # 改めた(1文字取り出しは残り全体をコピーしないため O(1)。合計で入力長に対して線形)。
        # GNU awk 拡張(3引数 index() 等)には依存しない(macOS の awk でも動く必要があるため)。
        #
        # 注意(単体ベンチで確認・想定と異なった点): この改修に着手した理由は、フルパイプライン
        # (guard.sh 全体)を約500トークンの `sh -c "echo x; echo x; …; pip install pandas"` 相当の
        # 入力で計測したときの秒〜タイムアウト級の遅さだった。しかし、このループだけを guard.sh
        # から切り出して単体で計測すると、**旧実装(改修前の substr ループ)でもこのトークン数域
        # (〜2000トークン)では数msで終わり、二乗劣化の兆候は出なかった**(旧: 50トークン2.6ms/
        # 200トークン2.4ms/500トークン3.1ms/2000トークン8.7ms。新: 同条件でいずれも数ms、
        # むしろ僅かに遅い場面すらある)。つまりフルパイプラインで観測された遅さの支配要因は
        # このループではなく、下記 _gi_process_text がラッパー展開後のテキストを ; 等で
        # N セグメントに分割し、セグメントごとに _gi_check_and_recurse(内部で複数のパイプ・
        # サブプロセス起動を伴う)を再帰的に呼ぶ構造にあった(1セグメントあたり実測約20ms強の
        # プロセス起動コストが N 倍に増幅される)。この改修自体はアルゴリズムとして素直なので
        # 維持するが、フルパイプラインの性能改善は主に _GI_MAX_SEGMENTS 側(下記)が担う。
        n = length($0)
        fn = 0; intok = 0
        for (ci = 1; ci <= n; ci++) {
          c = substr($0, ci, 1)
          if (c == " " || c == "\t") {
            if (intok) { flen[fn] = ci - fpos[fn]; intok = 0 }
          } else {
            if (!intok) { fn++; fpos[fn] = ci; intok = 1 }
          }
        }
        if (intok) { flen[fn] = n - fpos[fn] + 1 }

        i = 2
        while (i <= fn) {
          # トークンの文字列そのものが要る箇所だけ、その1トークン分(残り全体ではない)を
          # substr で切り出す(トークン自身の長さに比例するコストで済む)。
          tok = substr($0, fpos[i], flen[i])
          if (tok in two_tok) { i += 2; continue }
          if (tok == "-c") {
            if (i + 1 <= fn) { emit_c_arg(fpos[i+1]) }
            exit
          }
          if (flen[i] > 2 && substr($0, fpos[i], 2) == "-c") {
            # 結合形 -cARG(-c\x27...\x27 / -c"..." / -cfoo 等): このフィールド自身の "-c" の
            # 直後を引数の開始位置とみなす。
            emit_c_arg(fpos[i] + 2)
            exit
          }
          if (substr($0, fpos[i], 1) == "-") { i++; continue }
          exit   # -c に到達する前に非フラグトークンが来た → -c 呼び出しではない(無出力で終わる)
        }
      }
    '
    return
  fi
  if printf '%s' "$_w" | grep -E '^[[:space:]]*find([[:space:]]|$)' >/dev/null \
     && printf '%s' "$_w" | grep -E '(^|[[:space:]])-exec(dir)?[[:space:]]' >/dev/null; then
    printf '%s' "$_w" | sed -E 's/^.*[[:space:]]-exec(dir)?[[:space:]]+//'
    return
  fi
  if printf '%s' "$_w" | grep -E '^[[:space:]]*xargs([[:space:]]|$)' >/dev/null; then
    printf '%s' "$_w" | awk '
      BEGIN {
        two_tok["-I"]=1; two_tok["-i"]=1; two_tok["-n"]=1; two_tok["-P"]=1
        two_tok["-L"]=1; two_tok["-l"]=1; two_tok["-s"]=1; two_tok["-a"]=1
        two_tok["-d"]=1; two_tok["-E"]=1; two_tok["-J"]=1
      }
      {
        if ($1 != "xargs") { exit }
        for (i = 2; i <= NF; i++) {
          tok = $i
          if (tok in two_tok) { i++; continue }
          if (substr(tok,1,1) == "-") { continue }
          out = ""
          for (j = i; j <= NF; j++) out = out (j>i?" ":"") $j
          print out
          exit
        }
      }
    '
    return
  fi
  if printf '%s' "$_w" | grep -E '^[[:space:]]*eval([[:space:]]|$)' >/dev/null; then
    printf '%s' "$_w" | awk '
      # emit_c_arg: sh/bash 分岐(上記)と同じクォート対応抽出(重複コメントは避ける。詳細は
      # そちらの関数直前のコメント参照。awk の呼び出しはそれぞれ独立プロセスなので関数定義自体は
      # 複製が必要)。
      function emit_c_arg(spos,    qc, k, kc, bs, kj, found) {
        qc = substr($0, spos, 1)
        if (qc == "\x27" || qc == "\"") {
          found = 0
          for (k = spos + 1; k <= n; k++) {
            kc = substr($0, k, 1)
            if (kc == qc) {
              if (qc == "\"") {
                bs = 0; kj = k - 1
                while (kj >= 1 && substr($0, kj, 1) == "\\") { bs++; kj-- }
                if (bs % 2 == 1) { continue }
              }
              found = 1
              print substr($0, spos + 1, k - spos - 1)
              return
            }
          }
          if (!found) { print substr($0, spos + 1) }
          return
        }
        print substr($0, spos)
      }
      {
        if ($1 != "eval") { exit }
        n = length($0)
        fn = 0; intok = 0
        for (ci = 1; ci <= n; ci++) {
          c = substr($0, ci, 1)
          if (c == " " || c == "\t") {
            if (intok) { intok = 0 }
          } else {
            if (!intok) { fn++; fpos[fn] = ci; intok = 1 }
          }
        }
        if (fn < 2) { exit }
        emit_c_arg(fpos[2])
      }
    '
    return
  fi
  if printf '%s' "$_w" | grep -E '^[[:space:]]*ssh([[:space:]]|$)' >/dev/null; then
    printf '%s' "$_w" | awk '
      BEGIN {
        # 値を取る代表的な ssh オプション(2トークン形)。出典: man ssh(1)。
        # 網羅ではなく destination の前に置かれる代表的なもの(-p/-l/-i/-o/-F)を対象にする
        # (best-effort。他の2トークンオプションが前置される形は未対応・踏まれたら拡張する)。
        two_tok["-p"]=1; two_tok["-l"]=1; two_tok["-i"]=1; two_tok["-o"]=1; two_tok["-F"]=1
      }
      # emit_c_arg: sh/bash 分岐と同じクォート対応抽出(詳細はそちらの関数直前のコメント参照)。
      function emit_c_arg(spos,    qc, k, kc, bs, kj, found) {
        qc = substr($0, spos, 1)
        if (qc == "\x27" || qc == "\"") {
          found = 0
          for (k = spos + 1; k <= n; k++) {
            kc = substr($0, k, 1)
            if (kc == qc) {
              if (qc == "\"") {
                bs = 0; kj = k - 1
                while (kj >= 1 && substr($0, kj, 1) == "\\") { bs++; kj-- }
                if (bs % 2 == 1) { continue }
              }
              found = 1
              print substr($0, spos + 1, k - spos - 1)
              return
            }
          }
          if (!found) { print substr($0, spos + 1) }
          return
        }
        print substr($0, spos)
      }
      {
        if ($1 != "ssh") { exit }
        n = length($0)
        fn = 0; intok = 0
        for (ci = 1; ci <= n; ci++) {
          c = substr($0, ci, 1)
          if (c == " " || c == "\t") {
            if (intok) { flen[fn] = ci - fpos[fn]; intok = 0 }
          } else {
            if (!intok) { fn++; fpos[fn] = ci; intok = 1 }
          }
        }
        if (intok) { flen[fn] = n - fpos[fn] + 1 }

        i = 2
        while (i <= fn) {
          tok = substr($0, fpos[i], flen[i])
          if (tok in two_tok) { i += 2; continue }
          if (substr(tok, 1, 1) == "-") { i++; continue }
          # tok が destination。その次のトークンの開始位置から <command> を抽出する(無ければ無出力)。
          if (i + 1 <= fn) { emit_c_arg(fpos[i+1]) }
          exit
        }
      }
    '
    return
  fi
}

# _gi_raw_segments_from_folded: stdin の1行目=raw(未加工)テキスト・2行目=folded
# (fold_quotes_and_heredocs 済み)テキストを受け取り、folded 側で「クォート外に実際に残っている
# ;|&」の文字位置を境界として、raw 側の**同じ文字位置**をセグメントとして切り出す(1行ずつ標準出力)。
# fold_quotes_and_heredocs は単一行・非 heredoc の入力に対して文字数を変えない(1文字を1文字に
# 置換するだけ)ため、raw と folded は文字位置が1:1対応する。呼び出し側は raw/folded が同じ文字数
# (=この前提が成り立つ)であることを確認してから呼ぶこと。
_gi_raw_segments_from_folded() {
  awk '
    NR == 1 { raw = $0; next }
    NR == 2 {
      n = length($0)
      start = 1
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == ";" || c == "|" || c == "&") {
          print substr(raw, start, i - start)
          start = i + 1
        }
      }
      print substr(raw, start, n - start + 1)
    }
  '
}

# _gi_process_text: $1 のテキスト(raw・未加工)を fold + セグメント分割し、各セグメントを
# _gi_check_seg_text で判定した上で、ラッパー(sh -c/bash -c/find -exec/xargs)なら
# _gi_extract_wrapped で内部コマンドを取り出して**自分自身を再帰呼び出し**する
# ($2 は現在の再帰深さ・0起点)。
#
# 再帰の深さは _GI_MAX_DEPTH で有界にする(sh -c "sh -c 'sh -c ...'" のような入れ子で無限再帰に
# 落ちないため)。上限到達時は素通り(検知しない)側に倒す: guard は「うっかり」を捕まえる
# best-effort な網であり(ファイル冒頭のコメント参照)、_GI_MAX_DEPTH 段を超える人為的な多重ラップは
# 自然な誤操作の範囲を明確に超える(意図的な難読化)。誤検知(FP)のコストの方が実害が大きいため、
# ここでは block ではなく素通りを既定にする(natural-invocation-gap-is-not-closed-by-
# documenting-it が定める「自然な呼び出し形か」を軸に判定基準を適用: 深い入れ子は自然な呼び出し形の
# 範囲外なので、対応しないことが許容される)。
#
# known-gap(best-effort・深さ上限とは別の残余): 同じ種類のクォートを入れ子にしバックスラッシュで
# エスケープする形(例 `sh -c "bash -c \"pip install pandas\""`)は、_GI_MAX_DEPTH 内であっても
# 正しく展開できないことがある(実機確認)。fold_quotes_and_heredocs のエスケープ処理は「外側の
# クォート文脈の中でのみ意味を持つ」ため、1段展開した引数(バックスラッシュがそのまま残った文字列)を
# 独立した新しい入力として再度 fold すると、外側の文脈が失われエスケープの解釈が変わってしまう
# (shell の実際のネスト解決を模倣していない=fold_quotes_and_heredocs 冒頭コメントの
# 既存 known-gap と同根)。異なる種類のクォートを使った入れ子(例 `sh -c 'bash -c "pip install
# pandas"'`)はこの問題を踏まないため正しく展開できる(実機確認)。バックスラッシュエスケープを
# 伴う同種クォートの入れ子は、意図的な難読化に近い稀な形と判断し、対応しない。
[ -n "${_GI_MAX_DEPTH:-}" ] || _GI_MAX_DEPTH=3

# _GI_MAX_SEGMENTS: _gi_process_text の**再帰呼び出し**(深さ >= 1、つまりラッパーから
# 抽出した引数テキストを再解析するとき)に限って、「セグメントごとに再帰チェックする」通常経路を
# 取る上限(セグメント=; や && 等で区切られた1文)。トップレベル(深さ0=利用者が実際に書いた
# コマンド全体)には適用しない。理由は2つ: (1) トップレベルのセグメント数は利用者が書いた
# 長さそのものであり、ラッパー展開のように再帰で増幅されるものではない。(2) トップレベルの
# 多セグメント入力が遅いのは ベースブランチの版でも同じ特性(フック全体に元からある1セグメントあたりの
# コスト)であり、本 PR が持ち込んだ劣化ではないため、本 PR で先回りして頭打ちにする対象ではない
# (別途 issue で扱う)。
#
# 上限を再帰の内側だけに適用する理由: ラッパーの引数展開だけが「1回の呼び出し引数を
# 何セグメントにでも増幅できる」経路であり、そこにだけプロセス起動コストの増幅問題がある。
# 1セグメントの処理は複数のパイプ・サブプロセス起動を伴うため(strip_shell_keywords|
# strip_command_prefix・_gi_check_seg_text 内の複数 grep・_gi_extract_wrapped 内の grep/awk)、
# セグメント数に比例してプロセス起動コストが積み上がる(実測: 1セグメントあたり約20ms強)。
# 現実的なシェルスクリプト(デプロイスクリプト等)はせいぜい数〜十数文程度で収まる想定のため、
# 数十のオーダーであれば自然な呼び出し形を取りこぼさない一方、意図的に文を大量に並べた入力
# (無害な文で薄めて検知を逃れようとする形を含む)を安価に頭打ちできる。
[ -n "${_GI_MAX_SEGMENTS:-}" ] || _GI_MAX_SEGMENTS=40

# _gi_check_seg_text_loose: _GI_MAX_SEGMENTS を超える大きな展開済みテキスト(ラッパー引数の
# 中身。上記コメントのとおりトップレベルはこの経路に来ない)に対する、セグメント分割・再帰を
# 伴わない安価な一括スキャン(grep 呼び出し回数は入力のセグメント数に依存しない定数)。
#
# strict(_gi_check_seg_text)の「上位集合」になるよう設計する: strict が block するものは
# 必ず loose も block する(loose の方が広く=誤検知(FP)寄りに倒れる。狭くしない)。
#
# 避けたかったコストは「セグメントごとのプロセス起動」であって「文の境界という概念」では
# なかった(実測: パターンマッチ自体は2000トークンでも10ms未満。高いのはセグメントごとに
# strip_* や複数の grep をそれぞれ別プロセスとして起動すること)。したがって、セグメント分割
# ループを再現するのではなく、**正規表現の側で区切り文字(; | &)を跨がせない**ことで、
# grep の呼び出し回数を増やさずに「同じ文の中」の精度を得る。区切り文字を除いた文字クラス
# `[^;|&]` の連続 = 1つの文、という表現を使う。
#
# 一次レビューで、この「同じ文の中」制約を入れる前の版に2つの欠陥が実機で見つかった:
#   (A) 除外(uv pip/.venv//venv//activate)がテキスト全体のどこかに現れるだけで効いており、
#       無関係な文にある除外語1つで、別の文にある本物の危険パターンが丸ごと免除されていた
#       (例 `echo please activate the venv first; pip install pandas` が素通りしていた)。
#   (B) 「ツール名の存在」と「危険サブコマンド/オプションの存在」を位置関係を問わない独立
#       2条件にしていたため、無関係な2つの文の断片が組み合わさって誤検知していた
#       (例 `npm test; sort -g file` や `gem list; npm install lodash` が block されていた)。
# どちらも loose が抽出テキスト全体を1単位として扱っていたことが根本原因。個別に締めると
# 堂々巡りになる(除外を狭めると(B)側が、条件を結合すると superset 性が崩れる)ため、
# 両方を「同じ文の中」という同じ制約で解く。
#
# 実装は「まず対象トークンを含む文だけを grep -oE で1回抽出し(トリガは緩くてよい。抽出は
# 「どの文を見るか」を絞るだけ)、以降の判定はその抽出結果だけに対して行う」という2段構成に
# する。マッチが複数あれば grep -oE は1行ずつ出力するため、以降の grep は行内で完結し、
# 文をまたいだ組み合わせが起きない(strict のセグメント単位判定と同じ粒度になる。抽出後の
# テキストに対する境界チェックで `^`/`$` を使っても、grep は行単位で処理するため各抽出行=
# 各文の先頭/末尾に正しく効く)。除外側も同じ2段構成にすることで、除外の粒度も strict の
# セグメント単位と揃う(除外を丸ごと落とす=superset を守るため免除自体を諦める案も検討したが、
# それだと40文超のスクリプト内の正当な `uv pip install` まで block してしまう新たな誤検知を
# 生むため、粒度を揃える方を選んだ)。
#
# superset 性の論証: strict はセグメント(=文)の中で「先頭トークンの錨」+「危険パターンの
# 存在」を判定している。loose は同じく文の中で判定するが、先頭トークンの錨は掛けない
# (文中のどこにツール名があってもよい)分だけ、strict が捕まえるものは必ず loose も捕まえる
# (広い方への包含関係が保たれる)。
#
# 境界文字を strict の `(^|[;&|]|[[:space:]])` より広い `(^|[^A-Za-z0-9_])`(英数字・
# アンダースコア以外なら何でも良い)にする: strict は再帰展開でラッパー引数のクォートを
# 剥がしてから判定するため、危険パターンは常に「セグメント文字列の先頭」に来て `^` で
# マッチする。loose は展開しないため、入れ子ラッパー(例 `sh -c "…; sh -c 'pip install
# pandas'"`)の内側の危険パターンは、クォート文字がすぐ前にある形で埋め込まれたまま現れる。
# 境界をクォート等も含む「非英数字なら何でも」に広げることで、この入れ子ケースも(展開せずに)
# 文字列としてそのまま拾える。誤検知(FP)方向へ倒れるが、この関数が呼ばれるのは sh -c/bash -c
# に渡された「実際に実行されるスクリプト本文」を大量のセグメントに分割した場合に限られるため、
# 危険パターンが逐語で現れれば実行される蓋然性が高く、fail-open(素通り)にするより許容できる
# 判断とした(セグメント数はスクリプトを長く書くだけで到達できるため、_GI_MAX_DEPTH のネストと
# 違って素通りにすると「無害な文を大量に並べて薄める」だけで検知を外せてしまう。深さ上限とは
# 事情が異なる)。トップレベルにはこの上限自体を適用しない(上記コメント参照)ため、本 issue が
# 解消しようとした「実行されない引数値・ドキュメント本文」の誤検知は loose の適用範囲に
# 入らない(loose が走るのはラッパー引数=実際に実行されるスクリプト本文のときだけ)。
#
# スキャン前に fold_quotes_and_heredocs を1回通す(他のセクションと同じ扱いに揃える。
# 従来 loose だけが例外だった): `[^;|&]` という文字クラスは、クォートを解さず**生の文字**として
# ; | & を見るため、クォートで囲まれた引数値の中にリテラルな区切り文字がある形(例
# `pip "a;b" install requests` / `npm install "a;b" -g typescript`)では、その区切り文字が
# 「文の境界」として誤って働き、ツール名と危険サブコマンド/オプションが別の擬似文へ分断されて
# 一致しなくなる(一次レビューで実機確認・過剰分割ではなく検知漏れの向き)。fold_quotes_and_heredocs
# はクォート内の中身を保持したまま、その中の ;/|/& だけを空白に置換するため、`pip "a;b" install`
# は `pip "a b" install` となり、同じ文として正しく扱える。コストは1回の awk 呼び出しのみ
# (loose が走るのはラッパー引数のセグメント数が上限を超えた場合に限られ、セグメント数に比例も
# しないため、grep 呼び出し回数をセグメント数に依存させないという設計は壊れない)。
_gi_check_seg_text_loose() {
  local _t_raw="${1:-}"
  local _t _stmt
  _t="$(printf '%s' "${_t_raw:-}" | fold_quotes_and_heredocs)" || _t="${_t_raw:-}"

  # pip: ツール名(pip/pip3)を含む文だけを抽出し、"install" 語の存在(隣接を要求しない)・除外
  # (uv pip/.venv//venv//activate)・相対パス --target 免除の判定をその抽出結果(=同じ文)に対して
  # 行う(strict の条件と同じ独立2条件の形に揃えた。以前は "pip3?[[:space:]]+install" という
  # 隣接一致で抽出していたため、間にオプションが挟まる形(例 `pip --no-cache-dir install x`)を
  # loose 側でも取りこぼしていた)。
  if [ -z "${_gi_blocked_pip:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*pip3?[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])pip3?([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])install([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -vE '(uv[[:space:]]+pip|\.venv/|(^|[[:space:]])venv/|activate)' >/dev/null \
       && ! _gi_relpath_exempt_flag "$_stmt" '[^A-Za-z0-9_]' '--target'; then
      _gi_blocked_pip=1
    fi
  fi

  # npm/pnpm・yarn・gem・brew・cargo・go・pipx・uv: ツール名を含む文だけを抽出し、危険サブコマンド/
  # オプションの判定もその抽出結果(=ツール名と同じ文)だけに対して行う。無関係な文にある断片が
  # 組み合わさって誤検知することがなくなる。相対パス指定による免除(--prefix/--root/GOBIN)も
  # 同じ抽出結果に対して判定し、strict と同じ独立条件の形に揃える。
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*(npm|pnpm)[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])(npm|pnpm)([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '([[:space:]]-g([[:space:]]|$)|--global)' >/dev/null \
       && ! _gi_relpath_exempt_flag "$_stmt" '[^A-Za-z0-9_]' '--prefix'; then
      _gi_blocked_npm=1
    fi
  fi
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*(npm|pnpm)[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])(npm|pnpm)([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])link([^A-Za-z0-9_]|$)' >/dev/null; then
      _gi_blocked_npm=1
    fi
  fi
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*yarn[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])yarn([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E 'global[[:space:]]+add' >/dev/null; then
      _gi_blocked_npm=1
    fi
  fi
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*gem[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])gem([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])install([^A-Za-z0-9_]|$)' >/dev/null; then
      _gi_blocked_npm=1
    fi
  fi
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*gem[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])gem([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])update([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E -- '(^|[^A-Za-z0-9_])--system([^A-Za-z0-9_]|$)' >/dev/null; then
      _gi_blocked_npm=1
    fi
  fi
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*brew[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])brew([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])(install|reinstall|tap)([^A-Za-z0-9_]|$)' >/dev/null; then
      _gi_blocked_npm=1
    fi
  fi
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*cargo[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])cargo([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])install([^A-Za-z0-9_]|$)' >/dev/null \
       && ! _gi_relpath_exempt_flag "$_stmt" '[^A-Za-z0-9_]' '--root'; then
      _gi_blocked_npm=1
    fi
  fi
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*go[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])go([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])install([^A-Za-z0-9_]|$)' >/dev/null \
       && ! _gi_relpath_exempt_var "$_stmt" '[^A-Za-z0-9_]' 'GOBIN='; then
      _gi_blocked_npm=1
    fi
  fi
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*pipx[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])pipx([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])install([^A-Za-z0-9_]|$)' >/dev/null; then
      _gi_blocked_npm=1
    fi
  fi
  if [ -z "${_gi_blocked_npm:-}" ]; then
    _stmt="$(printf '%s' "${_t:-}" | grep -oE '[^;|&]*uv[^;|&]*')" || true
    if [ -n "${_stmt:-}" ] \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])uv([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])tool([^A-Za-z0-9_]|$)' >/dev/null \
       && printf '%s\n' "$_stmt" | grep -E '(^|[^A-Za-z0-9_])install([^A-Za-z0-9_]|$)' >/dev/null; then
      _gi_blocked_npm=1
    fi
  fi
}

_gi_process_text() {
  local _pt_raw="${1:-}"
  local _pt_depth="${2:-0}"
  [ "$_pt_depth" -le "$_GI_MAX_DEPTH" ] || return

  local _pt_folded
  _pt_folded="$(printf '%s' "${_pt_raw:-}" | fold_quotes_and_heredocs)" || true

  # raw セグメントへ復元できる条件: 単一行(改行を含まない)、かつ fold 前後で文字数が変わって
  # いない(heredoc 等が絡むと fold が行を書き換え/空行化するため文字位置対応が崩れる)。
  # 復元できない場合は中和済み(neutralized)セグメントへフォールバックする: この場合、ラッパー
  # 引数内に複数文(; や && で連結された文)があっても2文目以降は展開・検知できないが、これは
  # 先頭トークン確認を経ない非再帰チェック(このセクションの再帰化より前の実装)と同じ挙動であり
  # 悪化はしない(multi-line/heredoc を伴う $cmd は稀なケースであり、既定の倒れ方として許容する)。
  local _pt_use_raw=1
  case "$_pt_raw" in *$'\n'*) _pt_use_raw=0 ;; esac
  [ "${#_pt_raw}" = "${#_pt_folded}" ] || _pt_use_raw=0

  local _pt_segs _pt_seg
  if [ "$_pt_use_raw" = "1" ]; then
    _pt_segs="$(printf '%s\n%s\n' "$_pt_raw" "$_pt_folded" | _gi_raw_segments_from_folded)" || true
  else
    _pt_segs="$(printf '%s' "${_pt_folded:-}" | tr ';|&' '\n\n\n')" || true
  fi

  # セグメント数が多い(_GI_MAX_SEGMENTS 超)場合は、セグメントごとの再帰チェック(プロセス
  # 起動コストが N 倍に増幅される)を行わず、_gi_check_seg_text_loose による一括スキャンへ
  # フォールバックする(理由は _GI_MAX_SEGMENTS 直前のコメント参照)。**深さ0(トップレベル)には
  # 適用しない**: 増幅が起きるのはラッパー引数を再帰展開したとき(深さ >= 1)だけであり、
  # トップレベルのセグメント数は利用者が実際に書いた長さそのものであるため。
  if [ "$_pt_depth" -ge 1 ]; then
    local _pt_seg_count
    _pt_seg_count="$(printf '%s\n' "${_pt_segs:-}" | grep -Ec '[^[:space:]]')" || _pt_seg_count=0
    if [ "$_pt_seg_count" -gt "$_GI_MAX_SEGMENTS" ]; then
      _gi_check_seg_text_loose "${_pt_raw:-}"
      return
    fi
  fi

  while IFS= read -r _pt_seg; do
    [ -n "${_gi_blocked_pip:-}" ] && [ -n "${_gi_blocked_npm:-}" ] && continue
    case "${_pt_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
    _gi_check_and_recurse "$_pt_seg" "$_pt_depth"
  done <<< "${_pt_segs:-}"
}

# _gi_check_and_recurse: 1セグメント($1・深さ$2)を _gi_check_seg_text で判定し、ラッパーなら
# _gi_extract_wrapped で内部コマンドを取り出して _gi_process_text を深さ+1で再帰呼び出しする。
_gi_check_and_recurse() {
  local _gcr_seg="${1:-}"
  local _gcr_depth="${2:-0}"
  local _gcr_seg_sh
  _gcr_seg_sh="$(printf '%s' "${_gcr_seg:-}" | strip_shell_keywords_and_prefix)" || true

  _gi_check_seg_text "${_gcr_seg:-}"

  local _gcr_wrapped
  _gcr_wrapped="$(_gi_extract_wrapped "${_gcr_seg_sh:-}")" || true
  [ -n "${_gcr_wrapped:-}" ] && _gi_process_text "${_gcr_wrapped:-}" "$((_gcr_depth + 1))"
}

# 早期打ち切り: この判定が成立するには、対象ツール名(pip/pip3/python/python3/
# npm/pnpm/yarn/gem/brew/cargo/go/pipx/uv)か、それらを間接的に起動しうるラッパー
# (sh/bash/eval/ssh/xargs。_gi_extract_wrapped が対応する形。findは対象外)のいずれかが
# $cmd のどこかに現れている必要がある(この関数群が判定するのは常にこれらのトークンが実際に
# 実行される形であり、静的に存在しない文字列が実行時に出現することは無い)。fold_quotes_and_
# heredocs は生テキストに対して文字を「足さない」ため(force push ブロック直前のコメントと
# 同じ根拠)、生 $cmd への単純な部分文字列検査は再帰展開後の判定に対しても安全な上位集合になる
# ——ラッパー経由で間接的に取り出される内部コマンドの文字列も、常に生 $cmd の部分文字列である。
if printf '%s' "$cmd" | grep -E '(^|[^A-Za-z0-9_])(pip3?|python3?|npm|pnpm|yarn|gem|brew|cargo|go|pipx|uv|sh|bash|eval|ssh|xargs)([^A-Za-z0-9_]|$)' >/dev/null; then
  _gi_blocked_pip=""
  _gi_blocked_npm=""
  _gi_process_text "$cmd" 0

  if [ -n "${_gi_blocked_pip:-}" ]; then
    block "グローバルに pip install しようとしています。ホストへは永続的にインストールしません。プロジェクト配下に閉じたいだけなら 'pip install --target <相対パス>' を、使い捨て実行でよければ ephemeral/isolated(uv があれば 'uv run --with <pkg> script.py'、無ければ使い捨てコンテナ 'yosage-dev-harness-scratch --image python:3.12-slim -- ...')を使ってください。${NO_BYPASS_MSG}" "global_install_pip"
  fi
  if [ -n "${_gi_blocked_npm:-}" ]; then
    block "ホストへ永続的にインストール/リンクしようとしています(brew install/cargo install/go install/pipx install/uv tool install/npm -g/npm link/yarn global add/gem install/gem update --system 等)。ホストへは入れません。プロジェクト配下に閉じたいだけなら 'cargo install --root <相対パス>'・'GOBIN=<相対パス> go install'・'npm install -g --prefix <相対パス>' のような明示指定を、使い捨て実行でよければ npx/uvx か使い捨てコンテナ(yosage-dev-harness-scratch)を使ってください。${NO_BYPASS_MSG}" "global_install_other"
  fi
fi

# ネット取得物の直接シェル実行 (curl|sh / wget|bash …)
# 旧実装は chk()(=$cmd 全文への grep -Eq 部分一致)で判定しており、この形が実行されない
# 文字列リテラル(ドキュメント本文・コミットメッセージ・引数値)として存在するだけで誤ブロック
# していた(全文一致クラスの過剰検知)。
#
# この判定は他の全文一致修正(グローバル汚染ブロック等の先頭トークン判定)の型をそのまま
# 流用できない: 検知対象がパイプを跨ぐため、ダウンロード側と実行側が別セグメントに分かれる。
# 単一セグメントの先頭トークンだけを見る方式では判定できず、必要なのは「パイプで連結された
# セグメント連鎖(pipeline)の中に、ダウンロード系コマンド(curl/wget)を先頭トークンに持つ
# セグメントと、それより後方にシェル(sh/bash/zsh)を先頭トークンに持つセグメントが共存するか」
# を見る判定である(先頭セグメントとの隣接だけでなく、間に加工コマンドを挟む形も連鎖の中に
# あれば拾う)。本セクションは _gi_extract_wrapped 等(上記グローバルインストール抑止セクション)に
# 依存するため、それらの定義より後(本ファイルのこの位置)に置く。
#
# fold_quotes_and_heredocs でクォート/heredoc を折り畳んでから、";" 単独の "&"(および "&&") と
# 実際の改行を非パイプ境界(pipeline をリセットする境界)、"|" と "|&"(bash 拡張。stderr も
# まとめてパイプする構文だが実行結果がパイプへ渡る点は "|" と同じなので同様に扱う)をパイプ境界
# として扱う。"||"(論理 OR。パイプではない)は2文字纏めて非パイプ境界1個として消費する
# (1文字ずつ処理すると "||" が誤って2回のパイプ境界に化け、本来無関係な
# `curl url || sh backup.sh`(フォールバック実行。ダウンロード内容をシェルへパイプしていない)を
# 誤って同一 pipeline とみなし block してしまうため)。
#
# 複数行にまたがるパイプ(行末が "|"/"|&" で終わり、次の行が同じパイプラインの続きになる
# 標準的な bash 構文。バックスラッシュ継続は不要)も検知する: awk のレコード(行)処理は
# 通常「行末で必ず境界(STOP)へ戻す」が、直前に処理した文字が新鮮な "|"/"|&" 演算子の直後
# (open_pipe フラグ)である場合はリセットしない。open_pipe は「その演算子の直後から空白以外の
# 実文字が現れるまで」true のままにし(演算子直後の trailing whitespace が newline を跨いでも
# 継続と認識できるようにするため)、実文字が現れた時点で false に落として通常のセグメント蓄積へ
# 戻す(実機確認: 修正前は行末の "|" で状態が強制的に STOP へリセットされ、次行の先頭が
# 独立した新しいセグメントとして扱われるため、パイプ連鎖が切れて検知漏れになっていた)。
#
# 各セグメントの実効先頭トークンは _dlx_resolve_head が解決する(下記)。これは
# 他の先頭トークン判定セクションと同じ strip_shell_keywords | strip_command_prefix を通した後、
# 以下を行う:
#   - トークン前後の "(" ")" を1文字以上剥がしてから basename(末尾の "/" 区切り要素)を見る。
#     これにより裸のサブシェルで包む形(`(curl url | sh)` の先頭セグメント "(curl" や
#     `curl url | (sh)` の末尾セグメント "(sh)")もそれぞれ "curl"・"sh" として判定できる
#     (strip_shell_keywords が意図的に "(" ")" を読み飛ばさない設計(cd 追跡用の既存合理性。
#     関数直前のコメント参照)とは独立に、この判定専用のローカルな軽い対処として行う)。
#   - 小文字化してから比較する(macOS のデフォルトのブートボリュームは大文字小文字を区別しない
#     (case-insensitive・case-preserving)ファイルシステムであり、`CURL`/`SH` のような大文字表記も
#     実機の PATH 解決で実際に curl/sh を指しうるため)。
#   - busybox(組み込み/コンテナ環境で一般的な multi-call バイナリ)経由の間接呼び出し
#     (`busybox sh` 等)は、2番目のトークンが実際に起動されるアプレット名になるため、それを見て
#     実効トークンとする。
#   - xargs 経由の間接呼び出し(`xargs sh -c` 等)は、_gi_extract_wrapped で抽出した対象コマンドの
#     先頭トークンが sh/bash/zsh ならそれを実効トークンとする(xargs 自身がダウンロード内容を
#     受け取ってシェルを起動する構造は `curl | sh` と同じ危険性を持つため。xargs の対象コマンドの
#     中に隠れた別の curl→shell 連鎖を再帰的に見つける用途は下記の再帰展開が別途担う)。
#
# ラッパー経由の間接実行(sh -c "<script>" / bash -c "<script>" / eval "<script>" /
# ssh <host> "<script>" / find -exec / xargs)は、クォート内の文字列が実際に実行されるコマンドで
# あるため、fold_quotes_and_heredocs による無害化だけでは内側の curl→シェル連鎖が見えなくなる
# (旧実装(全文 grep)は皮肉にもクォートを解さないためこれらを偶然検知できていた回帰でもある)。
# これを塞ぐため、raw(未加工)セグメントへ復元できる場合(単一行・fold 前後で文字数が変わらない。
# _gi_raw_segments_from_folded と同じ既存の制約)に限り、既存の共有ヘルパー _gi_extract_wrapped
# (グローバルインストール抑止セクションが持つ。本チェックのために eval/ssh の抽出を追加拡張した)で
# ラッパーの内側コマンドを取り出し、それを独立した新しいテキストとして自分自身(_dlx_scan)へ
# 再帰的に通す(_gi_process_text と同じ考え方。車輪の再発明を避けるため既存の仕組みをそのまま
# 再利用する)。raw セグメント抽出は専用ヘルパー _dlx_raw_segments_from_folded が担う
# (_gi_raw_segments_from_folded を汎用化するのではなく、パイプ境界種別(PIPE/STOP)を追加で
# 持つ点が異なる専用ヘルパーとして新設した。理由は関数直前のコメント参照)。
# 再帰の深さは _DLX_MAX_DEPTH で有界にする(sh -c "sh -c 'sh -c ...'" のような入れ子で無限再帰に
# 落ちないため。_gi_process_text の _GI_MAX_DEPTH と同じ理由・同じ既定値だが、別の判定の
# チューニング値を誤って共有しないよう独立した変数として持つ)。
#
# known-gap(best-effort・境界ではない): バックスラッシュ行継続(fold_quotes_and_heredocs 冒頭の
# 既存 known-gap と同種)、および `sh -c "$(curl ...)"` のようなコマンド置換経由の間接実行
# (トポロジー上パイプではなくコマンド置換であり、この判定の責務は「パイプして直接実行する形」に
# 限定される。リダイレクトで一旦保存してから実行する形が別判定の責務であるのと対になる線引き)は
# この判定の対象外。raw セグメントへ復元できない入力(複数行・heredoc を伴う等)ではラッパー展開の
# 再帰を諦める(_gi_process_text と同じ既定の倒れ方。直接のパイプ連鎖判定自体は folded テキストの
# セグメント分割で行うため、複数行入力でも機能し続ける)。
[ -n "${_DLX_MAX_DEPTH:-}" ] || _DLX_MAX_DEPTH=3

# _dlx_resolve_head: strip_shell_keywords | strip_command_prefix 済みのセグメントテキスト($1)から、
# 比較用の実効先頭トークンを返す(詳細は上記コメント参照)。
_dlx_resolve_head() {
  local _seg="${1:-}"
  local _t1 _low1 _t2 _low2 _xw _xt _lowx
  _t1="$(printf '%s' "${_seg:-}" | awk '{ t=$1; sub(/^\(+/,"",t); sub(/\)+$/,"",t); n=split(t,p,"/"); print p[n] }')"
  _low1="$(printf '%s' "${_t1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$_low1" in
    sh|bash|zsh|curl|wget) printf '%s' "$_low1"; return ;;
  esac
  if [ "$_low1" = "busybox" ]; then
    _t2="$(printf '%s' "${_seg:-}" | awk '{ t=$2; sub(/^\(+/,"",t); sub(/\)+$/,"",t); n=split(t,p,"/"); print p[n] }')"
    _low2="$(printf '%s' "${_t2:-}" | tr '[:upper:]' '[:lower:]')"
    case "$_low2" in
      sh|bash|zsh|curl|wget) printf '%s' "$_low2"; return ;;
    esac
  fi
  if [ "$_low1" = "xargs" ]; then
    _xw="$(_gi_extract_wrapped "${_seg:-}")" || true
    if [ -n "${_xw:-}" ]; then
      _xt="$(printf '%s' "$_xw" | awk '{ t=$1; sub(/^\(+/,"",t); sub(/\)+$/,"",t); n=split(t,p,"/"); print p[n] }')"
      _lowx="$(printf '%s' "${_xt:-}" | tr '[:upper:]' '[:lower:]')"
      case "$_lowx" in
        sh|bash|zsh)
          # xargs の対象コマンド自身に既に完結したスクリプトが与えられている場合
          # (例 `xargs sh -c 'echo safe'`)、xargs が追加する引数は $0/$1... の位置引数に
          # なるだけで実行コードにはならない。この場合は昇格しない(_dlx_scan の再帰展開が
          # 別途その内側(例 "echo safe")を独立にスキャンして隠れた危険を拾う)。
          # 完結したスクリプトが無い場合(`xargs sh -c` 単体・`xargs sh`/`xargs bash` の
          # ように -c すら無い形)は、xargs が追加する downloaded な引数がそのまま実行対象
          # (script 文字列、または bash/sh がファイルパスとして解釈する引数)になるため昇格する。
          _xw2="$(_gi_extract_wrapped "${_xw:-}")" || true
          [ -n "${_xw2:-}" ] || { printf '%s' "$_lowx"; return; }
          ;;
      esac
    fi
  fi
  printf '%s' "$_low1"
}

# _dlx_raw_segments_from_folded: $1行目=raw(未加工)テキスト・2行目=folded
# (fold_quotes_and_heredocs 済み)テキストを受け取り、folded 側で境界(";"/単独"&"/"&&"/単独"|"/
# "|&"。"||" は非パイプ境界として2文字纏めて消費)の文字位置を求め、raw 側の**同じ文字位置**を
# 境界種別(PIPE/STOP)付きのセグメントとして切り出す(_gi_raw_segments_from_folded と同じ技法。
# raw/folded の文字位置が1:1対応するという前提も同じ。呼び出し側は raw/folded が同じ文字数・
# 単一行であることを確認してから呼ぶこと)。
# クォート外でもバックスラッシュは直後の1文字の特殊な意味を消す(shell の実際の意味論)。
# 直前の連続バックスラッシュの個数が奇数なら、その境界文字はエスケープされている(例:
# find の "-exec ... \;" の "\;" はコマンド区切りではなく find 自身へ渡るリテラル)ため
# 境界として扱わない。
_dlx_raw_segments_from_folded() {
  awk '
    function escaped(pos,    bs, j) {
      bs = 0; j = pos - 1
      while (j >= 1 && substr($0, j, 1) == "\\") { bs++; j-- }
      return (bs % 2 == 1)
    }
    NR == 1 { raw = $0; next }
    NR == 2 {
      n = length($0)
      start = 1
      boundary = "STOP"
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if ((c == ";" || c == "&" || c == "|") && escaped(i)) { continue }
        if (c == ";") {
          print boundary "\t" substr(raw, start, i - start)
          start = i + 1; boundary = "STOP"; continue
        }
        if (c == "&") {
          if (substr($0, i+1, 1) == "&") {
            print boundary "\t" substr(raw, start, i - start)
            start = i + 2; boundary = "STOP"; i++; continue
          }
          print boundary "\t" substr(raw, start, i - start)
          start = i + 1; boundary = "STOP"; continue
        }
        if (c == "|") {
          nc = substr($0, i+1, 1)
          if (nc == "|") {
            print boundary "\t" substr(raw, start, i - start)
            start = i + 2; boundary = "STOP"; i++; continue
          }
          if (nc == "&") {
            print boundary "\t" substr(raw, start, i - start)
            start = i + 2; boundary = "PIPE"; i++; continue
          }
          print boundary "\t" substr(raw, start, i - start)
          start = i + 1; boundary = "PIPE"; continue
        }
      }
      print boundary "\t" substr(raw, start, n - start + 1)
    }
  '
}

# _dlx_scan: テキスト($1・深さ$2)にダウンロード系→シェルのパイプ連鎖があれば真(exit 0)を返す。
_dlx_scan() {
  local _s_text="${1:-}"
  local _s_depth="${2:-0}"
  [ "$_s_depth" -le "${_DLX_MAX_DEPTH:-3}" ] || return 1

  local _s_folded
  _s_folded="$(printf '%s' "${_s_text:-}" | fold_quotes_and_heredocs)" || true

  # (直接判定) folded テキストをセグメント分割し、パイプ連鎖内のダウンロード→シェルを見る。
  local _s_fsegs _s_hit _s_seen_dl _s_b _s_seg _s_trim _s_head
  _s_fsegs="$(printf '%s' "${_s_folded:-}" | awk '
    function escaped(pos,    bs, j) {
      bs = 0; j = pos - 1
      while (j >= 1 && substr(text, j, 1) == "\\") { bs++; j-- }
      return (bs % 2 == 1)
    }
    BEGIN { seg = ""; boundary = "STOP"; open_pipe = 0 }
    {
      text = $0
      n = length(text)
      for (i = 1; i <= n; i++) {
        c = substr(text, i, 1)
        if ((c == ";" || c == "&" || c == "|") && escaped(i)) {
          seg = seg c
          if (c != " " && c != "\t") { open_pipe = 0 }
          continue
        }
        if (c == ";") { print boundary "\t" seg; seg=""; boundary="STOP"; open_pipe=0; continue }
        if (c == "&") {
          if (substr(text, i+1, 1) == "&") { i++ }
          print boundary "\t" seg; seg=""; boundary="STOP"; open_pipe=0; continue
        }
        if (c == "|") {
          nc = substr(text, i+1, 1)
          if (nc == "|") { i++; print boundary "\t" seg; seg=""; boundary="STOP"; open_pipe=0; continue }
          if (nc == "&") { i++; print boundary "\t" seg; seg=""; boundary="PIPE"; open_pipe=1; continue }
          print boundary "\t" seg; seg=""; boundary="PIPE"; open_pipe=1; continue
        }
        seg = seg c
        if (c != " " && c != "\t") { open_pipe = 0 }
      }
      if (!open_pipe) {
        print boundary "\t" seg
        seg=""; boundary="STOP"
      }
    }
  ')" || true

  _s_hit=""
  _s_seen_dl=""
  while IFS="$(printf '\t')" read -r _s_b _s_seg; do
    [ "$_s_b" = "STOP" ] && _s_seen_dl=""
    _s_trim="$(printf '%s' "${_s_seg:-}" | strip_shell_keywords_and_prefix)" || true
    _s_head="$(_dlx_resolve_head "${_s_trim:-}")"
    if [ -n "$_s_seen_dl" ]; then
      case "$_s_head" in
        sh|bash|zsh) _s_hit=1 ;;
      esac
    fi
    case "$_s_head" in
      curl|wget) _s_seen_dl=1 ;;
    esac
  done <<< "${_s_fsegs:-}"
  if [ -n "$_s_hit" ]; then
    return 0
  fi

  # (ラッパー展開・再帰) raw セグメントへ復元できる場合のみ試みる。
  local _s_use_raw=1
  case "$_s_text" in *$'\n'*) _s_use_raw=0 ;; esac
  [ "${#_s_text}" = "${#_s_folded}" ] || _s_use_raw=0
  [ "$_s_use_raw" = "1" ] || return 1

  local _s_rsegs _s_rb _s_rseg _s_rtrim _s_wrapped
  _s_rsegs="$(printf '%s\n%s\n' "${_s_text:-}" "${_s_folded:-}" | _dlx_raw_segments_from_folded)" || true
  while IFS="$(printf '\t')" read -r _s_rb _s_rseg; do
    _s_rtrim="$(printf '%s' "${_s_rseg:-}" | strip_shell_keywords_and_prefix)" || true
    _s_wrapped="$(_gi_extract_wrapped "${_s_rtrim:-}")" || true
    if [ -n "${_s_wrapped:-}" ] && _dlx_scan "${_s_wrapped:-}" "$((_s_depth + 1))"; then
      return 0
    fi
  done <<< "${_s_rsegs:-}"
  return 1
}

# 早期打ち切り: この判定が成立するには、いずれかのセグメントの実効先頭トークンが
# curl/wget(大小文字を区別しない。_dlx_resolve_head が比較前に小文字化する)でなければならない。
# $cmd に(大小文字を問わず)"curl"/"wget" のどちらの部分文字列も現れなければ、ラッパー展開の
# 再帰を含めても該当する組は絶対に見つからない(再帰展開が取り出す内部コマンド文字列は常に
# raw $cmd の部分文字列であり、新しい文字を生成しない。force push ブロック直前のコメントと
# 同じ根拠)。
if printf '%s' "$cmd" | grep -Ei '(^|[^A-Za-z0-9_])(curl|wget)([^A-Za-z0-9_]|$)' >/dev/null; then
  _dlx_scan "$cmd" 0 \
    && block "ダウンロードした内容を直接シェル実行しています。一旦保存し中身を確認してから実行してください。" "downloaded_content_exec"
fi

# (2) no-litter: /tmp 等の一時スクリプトを直接実行しない
# opt-out env は設けない: 保持される設定置き場が無く(settings.json の env は install/update で
# 丸ごと上書きされて消える)、必要になった場面でも使われなかった(上記ファイル冒頭コメントの
# 「対象から外したブロック」節・no-litter の項を参照)。
chk '(^|[;&|]|[[:space:]])(bash|sh|zsh|python3?|ruby|node|php)[[:space:]]+(/tmp/|/private/tmp/|/var/folders/|/private/var/folders/)' \
  && block "一時スクリプトを /tmp 等で直接実行しています(ローカルを汚さない方針)。.claude/tmp/(配布 .gitignore で追跡対象外)に置いて実行するか、使い捨てコンテナ(yosage-dev-harness-scratch)経由で。" "no_litter_tmp_exec"

# --- repo 横断: PR/issue 本文に repo 外パスを参照しない ---
# 複数リポジトリのワークスペースで、横断/一時 doc(repo外)を PR/issue が参照すると GitHub 上で壊れる。
# 省略記法(3点ドット+スラッシュ)は通す一方、直前がドットの ../ (4連続以上の先頭ドット)も同じ理由で
# 意図的に許可する: 実在パスの親ディレクトリ参照(repo ルートより上に登る)にならず、GitHub 上で壊れない。
if chk 'gh[[:space:]]+(pr|issue)[[:space:]]+(create|edit)' && chk '(^|[^.])\.\./'; then
  block "PR/issue 本文に repo 外パス(../)を参照しています。GitHub 上で壊れます。横断/一時ドキュメントの内容はインライン展開するか、耐久 URL(共有 issue/wiki/drive)を使ってください。${NO_BYPASS_MSG}" "external_ref_gh_body"
fi

# --- (B) gh pr/issue body への secret 混入防止 ---
# gh pr/issue create|edit の --body / --body-file / -b / -F 経由で secret が GitHub に出る経路を塞ぐ。
# secret パターンは harness/lib/secret-patterns.sh を source して共有(重複定義しない)。
if chk 'gh[[:space:]]+(pr|issue)[[:space:]]+(create|edit)'; then
    _sb_found=""
    _sb_label=""
    # インライン body (--body / -b): cmd 全体をスキャン(引数の値がそのまま cmd 文字列に含まれる)
    if [ -n "${SECRET_PATTERNS+x}" ]; then
      _sb_i=0
      for _sb_pat in "${SECRET_PATTERNS[@]}"; do
        if printf '%s' "$cmd" | grep -E -- "$_sb_pat" >/dev/null 2>/dev/null; then
          _sb_found=1
          _sb_label="${SECRET_LABELS[$_sb_i]:-secret}"
          break
        fi
        _sb_i=$((_sb_i+1))
      done
      # PEM private key
      if [ -z "${_sb_found:-}" ] && [ -n "${SECRET_PEM_PATTERN:-}" ]; then
        if printf '%s' "$cmd" | grep -E -- "$SECRET_PEM_PATTERN" >/dev/null 2>/dev/null; then
          _sb_found=1
          _sb_label="${SECRET_PEM_LABEL:-PEM private key}"
        fi
      fi
    fi
    # --body-file PATH / -F PATH: ファイルを読んでスキャン(best-effort)
    if [ -z "${_sb_found:-}" ] && [ -n "${SECRET_PATTERNS+x}" ]; then
      # --body-file / -F のパス抽出: greedy sed の代わりに awk でトークン境界を守る。
      # 後続オプションがある場合にパスがズレる greedy .* 問題を修正(awk でトークン境界を守る抽出に変更)。
      # スペース区切り(--body-file PATH)に加え、イコール構文(--body-file=PATH)も同じトークンで判定する
      # (完全一致 $i=="--body-file" だけだと --body-file=PATH は一致せずスキャンごと skip されてしまうため)。
      _sb_bfile=$(printf '%s' "$cmd" | awk '{for(i=1;i<=NF;i++){if($i=="--body-file"&&i<NF){print $(i+1);exit} else if($i~/^--body-file=/){print substr($i,index($i,"=")+1);exit}}}') || true
      if [ -z "${_sb_bfile:-}" ]; then
        # -F はスペース区切り(-F PATH)・イコール(-F=PATH)に加え、pflag(gh の CLI 基盤)が正規に
        # 受理する短フラグの結合形(-FPATH、区切り文字なし)も拾う。判定順は = 形が先(結合形の
        # 判定が "=" を巻き込まないよう、"=" 分岐を先に確定させてから残りを結合形として扱う)。
        _sb_bfile=$(printf '%s' "$cmd" | awk '{for(i=1;i<=NF;i++){if($i=="-F"&&i<NF){print $(i+1);exit} else if($i~/^-F=/){print substr($i,index($i,"=")+1);exit} else if($i~/^-F./){print substr($i,3);exit}}}') || true
      fi
      if [ -n "${_sb_bfile:-}" ] && [ -f "${_sb_bfile:-}" ]; then
        _sb_i=0
        for _sb_pat in "${SECRET_PATTERNS[@]}"; do
          if grep -Eq -- "$_sb_pat" "$_sb_bfile" 2>/dev/null; then
            _sb_found=1
            _sb_label="${SECRET_LABELS[$_sb_i]:-secret}"
            break
          fi
          _sb_i=$((_sb_i+1))
        done
        if [ -z "${_sb_found:-}" ] && [ -n "${SECRET_PEM_PATTERN:-}" ]; then
          if grep -Eq -- "$SECRET_PEM_PATTERN" "$_sb_bfile" 2>/dev/null; then
            _sb_found=1
            _sb_label="${SECRET_PEM_LABEL:-PEM private key}"
          fi
        fi
      fi
    fi
  if [ -n "${_sb_found:-}" ]; then
    block "gh body に secret (${_sb_label:-secret}) を検出。GitHub に secret を公開しないでください。該当する値を本文から取り除いてから再実行してください。${NO_BYPASS_MSG}" "gh_body_secret"
  fi
fi

# --- (C) worktree 隔離サブエージェントが Bash 経由で共有チェックアウト外を操作するのを防ぐ
#     (git 操作 ＋ ファイル書き込み) ---
# 背景: isolation:"worktree" で隔離した subagent が Bash 内で共有メインチェックアウトの物理パスへ
# cd(または git -C/--git-dir/--work-tree)し、そこへ git checkout -b/branch -D/stash/merge/reset/clean
# 等を実行してしまう cwd leak 事故が繰り返し観測された(プロンプト規律だけでは再発を防げなかった)。
# 発火条件: hook 入力の .cwd が割り当て worktree(.claude/worktrees/<id>)配下の時のみ有効。
# それ以外(通常のメインセッション)は no-op(メインでの正当な cross-repo cd を誤爆させない)。
# 方式: denylist ではなく「割り当て worktree からの逸脱」を検出する fail-safe。git の verb は問わない
# (mutate 系を列挙しない=将来の破壊 verb も自動カバーし、列挙漏れによる検出漏れを避ける)。
# 読み取り専用の git(log 等)も worktree 外を指せば同様に block する。worktree は親と object DB/refs を
# 共有するため、正当な参照は cd せず `git -C <割り当てworktree> log origin/<ベースブランチ>` 等で行える。
# best-effort であり境界(boundary)ではない: 以下は原理的に検知できない残余バイパス(既知の穴)。
# (訂正: 従来ここには `env -C <外> git ...` と絶対パス指定の git 呼び出しも「原理的に検知できない」
# として列挙されていたが、これは誤り。前者はそれ自体が作業ディレクトリを変える固定の構文、後者は
# 先頭トークンの basename を見れば判定できる固定の構文であり、どちらも実際には検知できる。下記の
# git 判定ロジックで実際に塞いだため、この一覧からは削除した。)
#
# この列挙は「(C) が見ている Bash 経由の git 操作の中で、コマンド文字列の静的なテキスト解析では
# 検知できない回避」に限られる。Bash を経由しない回避(Write/Edit/MultiEdit で
# 絶対パスを直接指定する等)はこの列挙の対象外であり、(C) の守備範囲にも含まれない——別セクション
# (I)(本ファイル冒頭)が担う。判定材料が「書き込み先パス1つ」であるその経路は、ここに挙げる
# Bash 側の限界(クォート・間接呼び出し・サブシェル等、テキスト解析が原理的に追えないもの)を
# 共有しない。ただし (I) にも別種の既知の穴(記号リンク経由の書き込み先)があり、無いわけでは
# ない——同じ「既知の穴」として一括りにはしないが、それぞれ別のリストを持つ((I) 側の列挙は
# (I) 自身の直前コメント参照)。
#   - subshell 内の cd: ( cd /外 && git ... )
#   - eval 経由: eval "cd /外 && git ..."
#   - 変数間接: d=/外; git -C "$d" ...
#   - スクリプトファイル経由: bash /path/to/script.sh (script.sh 内で cd/git)
#   - worktree 内に外部を指す symlink を作ってからそこへ cd する
#   - cd への変数/コマンド置換渡し: cd $VAR && git ... / cd $(git rev-parse --show-toplevel) && git ... /
#     cd $OLDPWD && git ...(cd の引数を静的展開できない場合は宛先不明。宛先不明を一律 block すると
#     worktree 内の正当な動的 cd まで誤爆する=FP 過多になるため、あえて block せずここに正直に書く
#     に留める意図的な非対応)
#   - case/select/function のパターン一致行内に同居する実コマンド(例 case $x in a) cd /外; git log ;; esac)。
#     (A) と共通の known-gap。理由・対応しない判断は strip_shell_keywords 関数直前のコメントを参照
#     (事実の重複記述を避ける)
#   - 絶対パス指定の git 呼び出しは先頭トークンの basename(末尾要素)が "git" と一致するかで
#     判定している。そのため git を含まないリネーム済みの実行ファイル名(例 /usr/local/bin/my-vcs
#     というシンボリックリンク/コピーが実体は git)は検知できない(静的なテキスト解析では
#     実体を追えないため対応不可)。
#
# --- (C) の内側でファイル書き込みも検知する(git 操作に限らない拡張) ---
# 背景: 上記は Bash 経由の "git" 呼び出しだけを見ており、シェル経由の一般的なファイル書き込み
# (出力リダイレクト・cp/mv/tee/dd 等)は worktree 隔離のどの検知にも掛からず素通りしていた
# (実測: worktree 文脈で `echo x > <共有チェックアウト>/foo` 等が exit 0 で素通ることを確認済み)。
# 新しい走査ループを独立に足すと全 Bash 呼び出しの単価が二重に乗るため、この検知は下記の
# 既存セグメントループ(fold_quotes_and_heredocs によるクォート/heredoc 折り畳み・; | & 分割・
# cd 状態追跡・env opt-out)へそのまま相乗りする。判定材料は「書き込み先パス」であり、比較ロジック
# ((I) と同じ _wt_norm_path + prefix 一致)も (I) と共有する。
#
# 対象は2種類:
#   (a) 出力リダイレクト(> / >>): git の -C/--git-dir のような「一意なフラグ」に相当する
#       構造的な抽出であり、verb を問わない(denylist ではない)。対象は disk-device-write/
#       authorized_keys 検知と同じ範囲(> ・>> のみ)。2>/&>/番号付き fd(1> 等)/
#       演算子と直前トークンが空白無しで連結した形(例 echo hi>/外)は対象外(known-gap)。
#   (b) 代表的な書き込みコマンド(cp/mv/tee/dd): 汎用の書き込みコマンドには git のような
#       「参照先を明示するフラグ」が無いため、(E)(秘密ファイル読取検知)と同じ設計判断
#       (対象コマンドを自然な形に絞る best-effort な一覧)を踏襲する。cp/mv は
#       `-t DIR`/`--target-directory=DIR`(または `--target-directory DIR`)を**含まない**、
#       かつ非オプション引数が2つ以上ある場合のみ末尾を書き込み先とみなす(1個だけの場合は
#       実行時エラーになる壊れたコマンドであり誤検知の元になるため対象にしない)。tee は
#       非オプション引数すべて(複数ファイルへ同時出力できるため)。dd は of= の値。
#       意図的に対象から外すもの(known-gap。理由付き):
#         - cp/mv の `-t DIR`/`--target-directory[=DIR]`: 付くと末尾の非オプション引数は
#           宛先ではなくソースになる(`cp -t <割り当てworktree> <共有>/file.txt` のように、
#           実際の書き込み先は worktree 内でも末尾引数はソース側の `<共有>/file.txt` になる)。
#           「非オプション引数の末尾を宛先とみなす」抽出方式のままこの形を対象に含めると、
#           素通し(宛先が実際に worktree 外を指す形を見逃す)だけでなく、**書き込み先が
#           worktree 内であるにもかかわらず block する誤遮断**を生む(誤遮断は素通しより
#           性質が悪い——正当な操作を事実と異なる理由で止める)。そのため `-t`/
#           `--target-directory` を検出したらそのセグメントの cp/mv 全体を抽出対象から外す
#           (best-effort の限界として素通りを許容し、誤遮断を避ける側へ倒す)。短いオプション
#           結合形(例 `-vt`)も対象に含める(`-` で始まり `--` でない トークンに英小文字 `t`
#           を含めば `-t` 相当とみなす。cp/mv の短いオプションで小文字 `t` を使うのは
#           `-t`(target-directory)だけであり、`-T`(no-target-directory・値を取らない)とは
#           大文字小文字で区別している)。
#         - cp/mv の空白区切りで値を取るその他のオプション(例 `-S SUFFIX`/`--suffix SUFFIX`):
#           `-t` と同型の問題を持つ——値がオプションだと知らずに末尾の非オプション扱いトークンを
#           数えるため、オプションの値の後ろに実引数が続く形(例 `cp foo.txt <共有>/dest.txt -S bak`。
#           GNU のオプション解析は位置引数の後ろに置かれたオプションを許容するため、これは正当に
#           実行できる普通の呼び出しである)で、実際の宛先(`<共有>/dest.txt`)を候補から見失い
#           素通しする(実機確認済み。`-t` のような誤遮断ではなく素通しの形で現れる——`-S` の
#           値の有無に関わらず「末尾の非オプション引数」を宛先として拾うが、値を挟むと宛先候補と
#           数える範囲がずれ、真の宛先が対象漏れになる)。`-t` と同じ理由(値を取るオプション
#           一般への対応は複雑さが増し新たなバグの温床になる)で、この PR では対応しない
#           (known-gap として正直に列挙するに留める。空白区切りの値を取るオプションを末尾付近に
#           置く形全般が対象——`-S`/`--suffix` に限らない)。
#         - ln: 単一引数(ln -s <外部>)は「リンク先の参照」であり書き込み先はカレントディレクトリの
#           ままになる。末尾引数を書き込み先とみなす方式では単一引数形を誤って block する
#           (over-blocking のリスクがあるため対象に含めない)。
#         - install/rsync/tar/curl -o/wget -O/scp: 「-t DIR」のような分離オプションでの
#           宛先指定・複数の書式(ディレクトリ宛先 vs ファイル宛先)を持ち、末尾引数だけでは
#           正しく判定できない(cp/mv と同種の問題を持つため、そもそも対象コマンドの一覧に
#           含めていない)。
#         - sed -i / perl -i(直接編集): GNU/BSD で -i の引数要否が異なり(BSD は拡張子引数が
#           必須)、スクリプト本体の引数(-e 無しなら先頭の非オプション引数)と対象ファイルの
#           判別が壊れやすい。誤って書き込み先ではない引数(スクリプト本体)を block 材料にする
#           リスクが高いため対象に含めない。
#   /dev/ 配下(/dev/null 等)は上記どちらの経路でも対象から除外する(下記 _wt_check_target 内)。
#   /dev/null へのリダイレクトは出力の抑制であり "書き込み" の実害が無い一方、Bash 呼び出しでは
#   極めて高頻度に使われる(例 `cmd > /dev/null 2>&1`)ため、除外しないと通常の正当な操作を
#   大量に誤検知する。
#
# 以前は env opt-out で git 操作の検知だけを解除できたが、解除手段
# そのものを撤去した(本ファイル冒頭「解除の手段は無い」を参照)。git 操作の
# 検知とファイル書き込み検知は、解除可否の非対称を保つ理由が無くなったため同じ扱いになる。
# $cwd はファイル冒頭で1回だけ解析済み((I) と共有する。二重解析を避ける理由は $cwd 代入直前の
# コメント参照)。
# 割り当てルートへの切り詰めは worktree-root.sh の wt_assigned_root(単一ホーム)を呼ぶ
# ((I) と同じ関数を使う。パターン一致・sed による切り詰めをここで再実装しない)。
_wt_root="$(wt_assigned_root "${cwd:-}" 2>/dev/null)"
if [ -n "${_wt_root:-}" ]; then
        # _wt_norm_path(相対パスの ../ ./ を解決した絶対パスを返す)は本ファイル冒頭の (I) セクションで
        # 唯一の家として定義済み((I) は Bash 以外の呼び出しでも動く必要があり、(C) より先に実行される
        # ため、ここで再定義せずそのまま呼べる)。二重定義を避ける(strip_command_prefix 等と同じ
        # 「単一の家を持つ」方針)。

        _wt_cur="$_wt_root"
        _wt_blocked=""
        _wt_reason=""
        _wt_reason_write=""

        # $1: 書き込み先候補の生トークン(クォート文字が残ったままの場合がある)。
        # (I) と同じ判定(_wt_norm_path で正規化 → $_wt_root の prefix 一致)を、Bash 側の
        # リダイレクト/書き込みコマンド検知(下記)から共通で呼ぶ。/dev/ 配下は対象から除外する
        # (上記コメント「/dev/ 配下は... 除外する」参照。/dev/null 等への出力抑制を誤検知しないため)。
        # 一致すれば何もしない(worktree 内 or /dev 配下)。一致しなければ _wt_blocked/_wt_reason/
        # _wt_reason_write を立てる(_wt_reason_write はループ終了後のメッセージ分岐に使う。
        # git 判定側は _wt_reason だけを立て _wt_reason_write は立てない)。
        _wt_check_target() {
          local _wct_t
          _wct_t="$(printf '%s' "${1:-}" | sed -E "s/^['\"]//; s/['\"]\$//")"
          [ -n "$_wct_t" ] || return 0
          case "$_wct_t" in
            /*)   _wct_t="$(_wt_norm_path "$_wct_t")" ;;
            '~'*) _wct_t="$(_wt_norm_path "$HOME${_wct_t#\~}")" ;;
            *)    _wct_t="$(_wt_norm_path "$_wt_cur/$_wct_t")" ;;
          esac
          case "$_wct_t" in
            "$_wt_root"|"$_wt_root"/*) return 0 ;;
            /dev|/dev/*) return 0 ;;
          esac
          _wt_blocked=1
          _wt_reason="$_wct_t"
          _wt_reason_write=1
        }
        # 早期打ち切り: このセクションが実際に block を立てるのは、書き込み検知(リダイレクト
        # ">"/">>" か cp/mv/tee/dd)か git 検知(先頭トークンの basename が "git")のいずれかが
        # 成立したときだけ(cd/pushd 追跡はどちらの検知も成立しなければ block を生まない状態
        # 遷移にすぎない)。$cmd(生テキスト)に ">"・"git"・"cp"・"mv"・"tee"・"dd" のいずれも
        # 現れなければ(force push ブロック直前のコメントと同じ根拠——fold は文字を足さない)、
        # 以降のセグメント走査は絶対に block を生まない。ゲートは1コマンドにつき grep 1回であり、
        # ゲートが開いた場合は下の走査(cd 追跡を含め)を従来どおりすべて実行する。
        # 可読性メモ: この if の中身は既存インデントのまま残し、1段深くする再インデントは
        # 行わない(この節だけ深くすると、以降の変更でここだけインデント基準がずれて見え、
        # 差分レビューの対象も無駄に膨らむ。挙動の変更が無い箇所の大量差分を避けるため)。
        if printf '%s' "$cmd" | grep -E '>|(^|[^A-Za-z0-9_])(git|cp|mv|tee|dd)([^A-Za-z0-9_]|$)' >/dev/null; then
        # クォート/heredoc を折り畳んでから(他のセクションと同じ丁寧さ。fold_quotes_and_heredocs
        # 直前のコメント参照)、; | & で分割する。折り畳まないとクォート内の ; がセグメント境界として
        # 働き、引数の文字列リテラル(例 gh issue create --body "... cd /外; git log ..." のような
        # --body 引数)が独立したセグメントに化けて誤検知(over-blocking)や current dir 状態の
        # 汚染(その文字列内の "cd" が以降の判定へ波及)を招く。
        _wt_folded="$(printf '%s' "$cmd" | fold_quotes_and_heredocs)" || true
        _wt_segs="$(printf '%s' "${_wt_folded:-}" | tr ';|&' '\n\n\n')"
        while IFS= read -r _wt_seg; do
          [ -n "${_wt_blocked:-}" ] && continue
          case "${_wt_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
          _wt_trim="$(printf '%s' "$_wt_seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
          # 先頭のシェルキーワード(if/then/fi 等)を読み飛ばし、実コマンドの先頭トークンで判定する
          # (strip_shell_keywords: 先頭トークン判定を行うチェックはすべてこれを通す共通処理。
          # 消費者を数えて列挙しない理由は strip_shell_keywords 定義直前のコメント参照)。以降の
          # cd/git 判定はすべてこの結果を使う。
          # $_wt_trim 自体には strip_command_prefix を通さない: git 側は GIT_DIR/GIT_WORK_TREE の
          # 値そのものを拾う必要があり(下の git 判定コメント参照)、strip_command_prefix を通すと
          # 前置トークンごと消えて値を握り潰してしまう。cd/pushd 判定は値を拾う必要が無いため、
          # 別変数へコピーしてから strip_command_prefix を適用する(直後の cd/pushd 判定コメント参照)。
          _wt_trim="$(printf '%s' "$_wt_trim" | strip_shell_keywords)" || true

          # cd/pushd <path>: 以降のセグメントへ引き継ぐ「現在のディレクトリ」状態を更新する。
          # 引数無しの bare "cd"(pushd も同様に扱う)は $HOME への cd と等価なので "~" を返す。
          # 前置トークン(環境変数代入 VAR=val・command/env/sudo/builtin)を読み飛ばしてから判定する
          # (strip_command_prefix: 先頭トークン判定を行うチェックはすべてこれを通す共通処理
          # (消費者を数えて列挙しない理由は strip_command_prefix 定義直前のコメント参照)。
          # cd/pushd 判定にのみ適用し、$_wt_trim
          # 自体は書き換えない=直前のコメント参照)。読み飛ばさないと `X=1 cd <外>` のような形は
          # $1 が "cd"/"pushd" と一致せず、この cd 状態追跡に反映されない(以降のセグメントの
          # worktree 外判定が誤った current dir を前提にしうる)。
          _wt_cd_trim="$(printf '%s' "$_wt_trim" | strip_command_prefix)" || true
          _wt_cdpath="$(printf '%s' "$_wt_cd_trim" | awk '{ if ($1=="cd"||$1=="pushd") { if (NF>=2) print $2; else print "~" } }')"
          if [ -n "${_wt_cdpath:-}" ]; then
            _wt_cdpath="$(printf '%s' "$_wt_cdpath" | sed -E "s/^['\"]//; s/['\"]\$//")"
            case "$_wt_cdpath" in
              /*) _wt_cur="$(_wt_norm_path "$_wt_cdpath")" ;;
              '~'*) _wt_cur="$(_wt_norm_path "$HOME${_wt_cdpath#\~}")" ;;
              *)  _wt_cur="$(_wt_norm_path "$_wt_cur/$_wt_cdpath")" ;;
            esac
            continue
          fi

          # --- Bash 経由のファイル書き込みが割り当て worktree 外を指していないか検知 ---
          # (本ファイル冒頭の「(C) の内側でファイル書き込みも検知する」コメント参照。対象・
          # known-gap の一覧はそちらが正本。ここでは抽出ロジックのみ)。
          # 抽出そのものは wt_write_targets_for_segment(単一の家。strip_shell_keywords_and_prefix
          # 定義直前のコメント参照)を呼ぶ。(a)(b) を1回の awk 呼び出しに統合している理由(単価対策)
          # も同関数のコメントを参照——別々の awk に分けるとセグメントごとに追加でプロセスが
          # 2つ立ち上がるため、1つにまとめて増分を半減させている。
          #   (a) 出力リダイレクト(> / >>)は $_wt_trim(env 代入・前置コマンドを保持したまま)の
          #       全トークンを対象にする(前置の有無に関係なく現れうるため)。
          #   (b) 代表的な書き込みコマンド(cp/mv/tee/dd)は $_wt_cd_trim(cd/pushd 判定で既に
          #       前置除去済みの文字列)を渡して判定する(strip_command_prefix を二重に呼ばない)。
          _wt_write_targets="$(wt_write_targets_for_segment "$_wt_trim" "$_wt_cd_trim")" || true
          if [ -n "${_wt_write_targets:-}" ]; then
            while IFS= read -r _wt_wt; do
              [ -n "${_wt_blocked:-}" ] && continue
              [ -n "$_wt_wt" ] || continue
              _wt_check_target "$_wt_wt"
            done <<EOF
$_wt_write_targets
EOF
          fi
          [ -n "${_wt_blocked:-}" ] && continue

          # --- git 操作の検知(以下) ---
          # git コマンドか判定し、-C/--git-dir/--work-tree(スペース区切り・=形の両方)の値を拾う。
          # 先頭の env 代入トークン(VAR=val ...)は git 呼び出しの前に付きうる(例: GIT_DIR=/x git log)。
          # これを読み飛ばして後続が git かを判定する(先頭が env 代入なだけで $1!="git" になり
          # git 呼び出しと認識できない、という検出漏れを防ぐ)。GIT_DIR/GIT_WORK_TREE は
          # --git-dir/--work-tree フラグの env 変数版であり同じ「参照先明示指定」なので同様に拾う。
          # 2トークン値分離形は正規表現では網羅困難なため awk でトークン境界を守って抽出する
          # (グローバルオプションの値が別トークンに分かれる形式を正規表現だけで扱うのは頑健でないため)。
          #
          # 上記の env 代入に加え、コマンド語の前置(command/env/sudo/builtin)も読み飛ばす
          # (`sudo git -C <外> log` 等が git 呼び出しと認識されず素通りしていたための対応)。
          # $_wt_trim には strip_command_prefix を通せない(直前のコメントの通り GIT_DIR/GIT_WORK_TREE の
          # 値そのものを保持する必要があるため)ので、同じ「値を取るオプションを表で持ち、トークン境界を
          # 守って awk で読み飛ばす」型(下記 xargs 分岐と同型)をここに直接書く。env/sudo は自身も
          # オプションを取り、しかも値を取るものがある(env -u NAME / -C DIR、sudo -u user 等)ため、
          # 代表的な値取りオプションだけを表(envval/sudoval)で持ち、それ以外の "-" 始まりトークンは
          # 単独のフラグとして読み飛ばす。この表は strip_command_prefix() 直前で定義する
          # $_GS_ENVVAL_TBL/$_GS_SUDOVAL_TBL(表の値そのものの単一の家)を展開したもの。
          # env -S/--split-string をこの表に含めない理由もそちらのコメントを参照(要旨: 値スキップでは
          # 扱えないラッパー展開であり、この表の役割と性質が異なるため)。env/sudo/command/builtin は
          # 入れ子にもなりうる(例 `sudo env GIT_DIR=x git log`)ため、前置トークンが尽きるまでループする。
          # env -C <dir>(chdir)はそれ自体が実行時の作業ディレクトリを変える固定の構文なので、
          # 値を envdir として持ち帰り、後続の bash 側で「この呼び出しに限った current dir」として使う
          # (cd と違い後続セグメントへは引き継がない永続しない変更)。
          # 絶対パス指定の git 呼び出し(/usr/bin/git 等)は、先頭トークンの末尾要素(basename)を見て
          # 判定する。
          # 安全性はこの表の網羅性に依存させない: 表に無い分離形の値取りオプション(例 sudo -T 30 /
          # -R /chroot)に遭遇したら、そのオプションが値を取るかどうかを断定できない(取るなら次の
          # トークンは値・取らないなら次のトークンがコマンド、のどちらもありうる)。断定せず
          # fallback フラグを立てて厳密なトークン位置追跡を諦め、残りのトークン列を前方から
          # 走査して basename が "git" のトークンを探す loose な扱いに切り替える(strict が
          # git と認識するものは loose も必ず認識する=上位集合。同ファイル内のグローバル
          # インストール検知の loose フォールバック(_gi_check_seg_text_loose 直前のコメント参照)
          # と同じ考え方: 表が全オプションを網羅できなくても、検知が失われる方向にではなく
          # 安全側(見つからなければ何もしない・見つかれば git として扱う)に倒れる)。
          # 結合=形(--chdir=DIR 等)は値が同一トークン内に収まるため、対象オプションがどれであれ
          # 常にちょうど1トークンで読み飛ばせる(分離形のような曖昧さが無い)。表に無い長い
          # オプションの=形もこの理由で fallback の対象にしない。
          _wt_gittarget="$(printf '%s' "$_wt_trim" | awk '
            BEGIN{
              two_tok["-c"]=1; two_tok["--namespace"]=1; two_tok["--super-prefix"]=1
              # env/sudo の値取りオプション表は strip_command_prefix() 直前で定義する
              # $_GS_ENVVAL_TBL/$_GS_SUDOVAL_TBL を展開したもの(単一の家。片方だけ更新される
              # drift を防ぐため。-D/--chdir が envdir 対象になる理由等の詳細もそちらのコメント参照)。
              '"$_GS_ENVVAL_TBL"'
              '"$_GS_SUDOVAL_TBL"'
            }
            {
              target=""; envdir=""; fallback=0
              i=1
              while (i<=NF) {
                if ($i ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
                  tok=$i
                  eq=index(tok,"=")
                  var=substr(tok,1,eq-1)
                  val=substr(tok,eq+1)
                  if (var=="GIT_DIR" || var=="GIT_WORK_TREE") { target=val }
                  i++
                  continue
                }
                if ($i=="command" || $i=="builtin") { i++; continue }
                if ($i=="env") {
                  i++
                  while (i<=NF && substr($i,1,1)=="-" && $i!="--") {
                    opt=$i
                    # --chdir=DIR の"="付き結合形(git 自身の --git-dir= と同じ扱い)。
                    # env -C/--chdir はディレクトリ変更効果を持つため、この形も envdir として拾う
                    # (拾わないと env --chdir=<外> git log のように git 自身が -C を持たない
                    # 呼び出しで、ディレクトリ変更が握り潰されて検知漏れになる)。
                    if (opt ~ /^--[A-Za-z][A-Za-z-]*=/) {
                      if (opt ~ /^--chdir=/) { envdir=substr(opt,9) }
                      i++; continue
                    }
                    if (opt in envval) {
                      if (opt=="-C" || opt=="--chdir") { envdir=$(i+1) }
                      i+=2; continue
                    }
                    fallback=1; break
                  }
                  if (fallback) break
                  if (i<=NF && $i=="--") i++
                  continue
                }
                if ($i=="sudo") {
                  i++
                  while (i<=NF && substr($i,1,1)=="-" && $i!="--") {
                    opt=$i
                    if (opt ~ /^--[A-Za-z][A-Za-z-]*=/) {
                      if (opt ~ /^--chdir=/) { envdir=substr(opt,9) }
                      i++; continue
                    }
                    if (opt in sudoval) {
                      if (opt=="-D" || opt=="--chdir") { envdir=$(i+1) }
                      i+=2; continue
                    }
                    fallback=1; break
                  }
                  if (fallback) break
                  if (i<=NF && $i=="--") i++
                  continue
                }
                break
              }
              if (fallback) {
                # loose フォールバック: どこからが実コマンドか確定できないので、残りのトークンを
                # 前方から探して basename が "git" のものを見つけたらそこを起点にする。
                # strict の上位集合であるためには、strict が拾う経路をここでも全部拾う必要がある:
                # -C/--work-tree/--git-dir(空白区切り・=形とも)と絶対パスの basename 判定は、
                # "git" を見つけた後に共有の抽出ループ(下記)へ合流するので両経路で自動的に揃う。
                # GIT_DIR/GIT_WORK_TREE の env 代入だけは違う: strict はトップレベルの while で
                # 前置トークンをすべて消費し終えるたびに VAR=val 判定へ戻るため、"git" に辿り着く
                # 前に現れる代入を全部拾えるが、ここ(fallback 突入後)は前方探索するだけなので、
                # 同じ代入判定をこのループの中でも独立に行わないと、未知オプションの後ろに来る
                # GIT_DIR=/GIT_WORK_TREE= 代入(例 sudo -T 30 GIT_DIR=<外>/.git git log)が
                # 拾われないまま通り過ぎてしまう(見つからなければ block 材料が無いので NOTGIT のまま)。
                found=0
                for (k=i; k<=NF; k++) {
                  tok=$k
                  if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
                    eq=index(tok,"=")
                    var=substr(tok,1,eq-1)
                    val=substr(tok,eq+1)
                    if (var=="GIT_DIR" || var=="GIT_WORK_TREE") { target=val }
                    continue
                  }
                  nslash=split(tok, parts, "/")
                  if (parts[nslash] == "git") { i=k; found=1; break }
                }
                if (!found) { print "NOTGIT"; exit }
              } else {
                if (i>NF) { print "NOTGIT"; exit }
                nslash=split($i, parts, "/")
                base=parts[nslash]
                if (base != "git") { print "NOTGIT"; exit }
              }
              i++
              while(i<=NF){
                tok=$i
                if (tok=="-C" || tok=="--work-tree" || tok=="--git-dir") {
                  if (i<NF) { target=$(i+1); i+=2 } else { i++ }
                  continue
                }
                if (tok ~ /^--git-dir=/)   { target=substr(tok,11); i++; continue }
                if (tok ~ /^--work-tree=/) { target=substr(tok,13); i++; continue }
                if (tok in two_tok) { i+=2; continue }
                if (substr(tok,1,1)=="-") { i++; continue }
                break
              }
              print "GIT|" target "|" envdir
            }
          ')"
          case "$_wt_gittarget" in
            NOTGIT) continue ;;
            GIT\|*)
              _wt_gitrest="${_wt_gittarget#GIT|}"
              _wt_explicit="${_wt_gitrest%%|*}"
              _wt_envdir="${_wt_gitrest#*|}"
              # env -C <dir> はこの呼び出し限りで作業ディレクトリを変える(cd と違い永続しない)。
              # git 自身の -C/--git-dir/--work-tree(または GIT_DIR/GIT_WORK_TREE)が相対パスなら
              # この一時的な base からの相対として解決する。
              if [ -n "${_wt_envdir:-}" ]; then
                case "$_wt_envdir" in
                  /*) _wt_base="$(_wt_norm_path "$_wt_envdir")" ;;
                  '~'*) _wt_base="$(_wt_norm_path "$HOME${_wt_envdir#\~}")" ;;
                  *)  _wt_base="$(_wt_norm_path "$_wt_cur/$_wt_envdir")" ;;
                esac
              else
                _wt_base="$_wt_cur"
              fi
              if [ -n "${_wt_explicit:-}" ]; then
                case "$_wt_explicit" in
                  /*) _wt_check="$(_wt_norm_path "$_wt_explicit")" ;;
                  '~'*) _wt_check="$(_wt_norm_path "$HOME${_wt_explicit#\~}")" ;;
                  *)  _wt_check="$(_wt_norm_path "$_wt_base/$_wt_explicit")" ;;
                esac
              else
                _wt_check="$_wt_base"
              fi
              case "$_wt_check" in
                "$_wt_root"|"$_wt_root"/*) : ;;
                *) _wt_blocked=1; _wt_reason="$_wt_check" ;;
              esac
              ;;
          esac
        done <<EOF
$_wt_segs
EOF
        if [ -n "${_wt_blocked:-}" ]; then
          if [ -n "${_wt_reason_write:-}" ]; then
            block "worktree 隔離サブエージェントが Bash 経由で割り当て worktree 外(${_wt_reason:-不明なパス})へファイルを書き込もうとしています。書き込み先を割り当て worktree 配下の絶対パスに直してください。これは素直な誤操作を捕まえる best-effort な網です(クォート・間接呼び出し・記号リンク経由の書き込み先等の回避は検知できません)。${NO_BYPASS_MSG}" "worktree_shared_checkout_write"
          else
            block "worktree 隔離サブエージェントが割り当て worktree 外(${_wt_reason:-不明なパス})の git チェックアウトを操作しようとしています。cd で共有チェックアウトへ移動せず、常に割り当て worktree の絶対パスで作業してください。参照が必要なら cd せず 'git -C <割り当てworktree> <verb>' で行えます(worktree は親と object DB/refs を共有するため cd 不要)。これは素直な誤操作を捕まえる best-effort な網です(subshell/eval/変数間接等の回避は検知できません)。${NO_BYPASS_MSG}" "worktree_shared_checkout_git"
          fi
        fi
        fi
      fi

# --- (I2-Bash) knowledge エントリの形をしたファイルが Bash(シェル)経由でストア外へ
# 書かれても検知されない ---
# 背景: 上記 (I2) は Write/Edit/MultiEdit ツール経由の書き込みだけを検査しており、Bash 経由の
# 書き込み(リダイレクト・cp/mv/tee/dd)は対象外だった。knowledge エントリの誤着地を検知する
# issue の受け入れ条件が名指しした worktree_shared_checkout_write と同じ解析経路((C) の
# fold_quotes_and_heredocs によるクォート/heredoc の折り畳み → ;|& でのセグメント分割 →
# cd/pushd の状態追跡 → wt_write_targets_for_segment による書き込み先抽出)へ相乗りする。
# (I2) と異なりこちらは worktree 隔離文脈に限定しない
# (ドッグフーディングの通常セッションでも同じ構造が成立するため。(I2) 直前のコメントと同じ判断
# ——(C) の外側・$_wt_root の有無に関わらず独立に走る理由もこれ)。
#
# 討議収束(このシェル経由検知の issue に付いたコメント。人間裁定)による設計:
#   - ヒアドキュメント(引用符付き delim。<<'EOF'/<<"EOF"/<<\EOF)は展開が起きないため内容が
#     確実に読める。この場合は (I2) と同じ基準(frontmatter の id:/domain:/scope:/status: が
#     すべて行頭に揃っているか)で判定する。
#   - それ以外(引用符無し delim・パイプ・他コマンドの出力・変数展開等。内容が事前に確定しない)
#     は内容を読めないので、上記討議収束の裁定どおりパスだけで警告する。ただし「書き込み先の
#     見た目が knowledge っぽいパスか」では判定しない((I2) 直前のコメントが既に否定した判定
#     であり、書き込み先パスが違うこと自体が問題なので機能しない)。代わりに、knowledge
#     エントリ自身のファイル名規約(`harness/knowledge/_entry-template.md` が定める
#     `YYYY-MM-DD-<slug>.md`。生成器 `lib/knowledge-index.sh` が id 省略時にこの形の <slug> を
#     実効 id として使う、という同じ規約)に basename が一致するかを見る——これは「書き込み先が
#     正しいか」ではなく「ファイル自身がエントリの命名規約に沿っているか」という別の signal
#     であり、(I2) 直前のコメントが機能しないとした判定(書き込み先パスの見た目で knowledge か
#     どうかを判定すること)とは異なる。この heuristic により、無関係な書き込み(日付を含まない
#     一般的なファイル名)は発火しない(受け入れ条件「正当なシェル操作(...knowledge と無関係な
#     ファイルの書き込み)で発火しないこと」に対応)。
#
# known-gap(best-effort・この検知の性質そのもの・(C) と同じ限界を継承):
#   - heredoc の内容読み取りは fold_quotes_and_heredocs とは別のスキャン(wt_heredoc_bodies)を
#     行う(fold 側は本体を捨てる設計のため復元できない)。両者は独立に $cmd を走査するため、
#     セグメント順とヒアドキュメント出現順が一致する前提に依存する。1コマンドにつき heredoc が
#     高々1つの形(issue が挙げた実例と同じ形)を主対象とし、同一 Bash 呼び出し内で複数の
#     heredoc が絡む構成の対応づけはズレうる(wt_heredoc_bodies 定義直前のコメントの known-gap
#     と同じ)。
#   - ファイル名規約による fallback は heuristic であり、日付プレフィックスを持つが knowledge と
#     無関係なファイル(例: 日次ログ)を誤検知しうる。block ではなく warn なので実害は限定的。
#   - このセクションは (C) の $_wt_root ゲートより外にあるため、$_wt_root が空でも走る。ただし
#     $cmd に書き込み系トークン(> / cp / mv / tee / dd)が無ければ早期に何もしない(下記ゲート)。
_kws_fp_re='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[A-Za-z0-9][A-Za-z0-9-]*\.md$'
if [ -n "${cmd:-}" ] \
   && printf '%s' "$cmd" | grep -E '>|(^|[^A-Za-z0-9_])(cp|mv|tee|dd)([^A-Za-z0-9_]|$)' >/dev/null; then
  _kws_folded="$(printf '%s' "$cmd" | fold_quotes_and_heredocs)" || true
  _kws_segs="$(printf '%s' "${_kws_folded:-}" | tr ';|&' '\n\n\n')"
  _kws_hdraw="$(printf '%s\n' "$cmd" | wt_heredoc_bodies)" || true

  # \001H:<0|1> / \001E ブロックを出現順に配列へ読み込む(wt_heredoc_bodies 直前のコメント参照)。
  _kws_hd_n=0
  _kws_hd_in=0
  _kws_hd_cur=""
  _kws_hd_quoted=()
  _kws_hd_body=()
  while IFS= read -r _kws_hd_line; do
    case "$_kws_hd_line" in
      $'\001H:'*)
        _kws_hd_n=$((_kws_hd_n+1))
        _kws_hd_quoted[$_kws_hd_n]="${_kws_hd_line#*H:}"
        _kws_hd_body[$_kws_hd_n]=""
        _kws_hd_in=1
        _kws_hd_cur=""
        ;;
      $'\001E')
        _kws_hd_body[$_kws_hd_n]="$_kws_hd_cur"
        _kws_hd_in=0
        ;;
      *)
        if [ "$_kws_hd_in" = "1" ]; then
          if [ -z "$_kws_hd_cur" ]; then
            _kws_hd_cur="$_kws_hd_line"
          else
            _kws_hd_cur="$_kws_hd_cur
$_kws_hd_line"
          fi
        fi
        ;;
    esac
  done <<EOF
$_kws_hdraw
EOF

  _kws_cur="${cwd:-.}"
  _kws_hd_idx=0
  while IFS= read -r _kws_seg; do
    case "${_kws_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
    _kws_trim="$(printf '%s' "$_kws_seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    _kws_trim="$(printf '%s' "$_kws_trim" | strip_shell_keywords_and_prefix)" || true

    # cd/pushd 追跡((C) の同種処理と同じロジック。単一の家にはしない——こちらは既に
    # strip_shell_keywords_and_prefix で前置トークンをまとめて剥がし済みのため、$1 がそのまま
    # cd/pushd かどうかで判定できる。(C) 側は GIT_DIR/GIT_WORK_TREE の値を保持する必要があるため
    # 前置トークンを保持した文字列も別途持ち回っており、その事情が無いこちらは1本化できる)。
    _kws_cdpath="$(printf '%s' "$_kws_trim" | awk '{ if ($1=="cd"||$1=="pushd") { if (NF>=2) print $2; else print "~" } }')"
    if [ -n "${_kws_cdpath:-}" ]; then
      _kws_cdpath="$(printf '%s' "$_kws_cdpath" | sed -E "s/^['\"]//; s/['\"]\$//")"
      case "$_kws_cdpath" in
        /*) _kws_cur="$(_wt_norm_path "$_kws_cdpath")" ;;
        '~'*) _kws_cur="$(_wt_norm_path "$HOME${_kws_cdpath#\~}")" ;;
        *)  _kws_cur="$(_wt_norm_path "$_kws_cur/$_kws_cdpath")" ;;
      esac
      continue
    fi

    # このセグメントに heredoc 演算子(<<[-]['"\]?DELIM。バックスラッシュエスケープ delim
    # (<<\DELIM)も wt_heredoc_bodies と同じく引用符相当として扱う——シェル仕様上、delim の
    # 一部が引用符化(囲み引用符・バックスラッシュのいずれか)されていれば展開は起きない)が
    # 現れるか(fold 済みテキストにも演算子トークン自体は残る。本体だけが空行化される——
    # wt_heredoc_bodies 定義直前のコメント参照)。現れれば wt_heredoc_bodies が出現順に集めた
    # 本体と対応づける(known-gap: 上部のコメント参照)。一次レビュー指摘・実機再現済み:
    # バックスラッシュを見落とすと <<\EOF がこのゲートにもマッチせず、ファイル名フォールバック
    # にすら乗らない(検知の外に落ちる)。
    _kws_is_hd=0
    _kws_hd_quoted_now=0
    _kws_hd_body_now=""
    if printf '%s' "$_kws_trim" | grep -E "<<-?[[:space:]]*(['\"]|\\\\)?[A-Za-z_][A-Za-z0-9_]*" >/dev/null; then
      _kws_hd_idx=$((_kws_hd_idx+1))
      if [ -n "${_kws_hd_body[$_kws_hd_idx]+x}" ]; then
        _kws_is_hd=1
        _kws_hd_quoted_now="${_kws_hd_quoted[$_kws_hd_idx]}"
        _kws_hd_body_now="${_kws_hd_body[$_kws_hd_idx]}"
      fi
    fi

    _kws_targets="$(wt_write_targets_for_segment "$_kws_trim" "$_kws_trim")" || true
    [ -n "${_kws_targets:-}" ] || continue
    while IFS= read -r _kws_t; do
      [ -n "$_kws_t" ] || continue
      _kws_t="$(printf '%s' "$_kws_t" | sed -E "s/^['\"]//; s/['\"]\$//")"
      case "$_kws_t" in
        /*)   _kws_abs="$(_wt_norm_path "$_kws_t")" ;;
        '~'*) _kws_abs="$(_wt_norm_path "$HOME${_kws_t#\~}")" ;;
        *)    _kws_abs="$(_wt_norm_path "$_kws_cur/$_kws_t")" ;;
      esac
      case "$_kws_abs" in /dev|/dev/*) continue ;; esac

      # ストア位置の解決は (I2) と同じ判断: 書き込み先ファイル自身の git toplevel を基準にする
      # (cwd 由来だと複数リポジトリが同居するワークスペース直下では誤る。(I2) 直前のコメント
      # 参照)。_kw_find_toplevel は (I2) が定義済みの単一の家。
      _kws_projroot="$(_kw_find_toplevel "$(dirname -- "$_kws_abs")" 2>/dev/null)"
      if [ -z "${_kws_projroot:-}" ]; then
        _kws_projroot="${CLAUDE_PROJECT_DIR:-}"
        [ -z "$_kws_projroot" ] && _kws_projroot="${cwd:-}"
      fi
      [ -n "${_kws_projroot:-}" ] || continue
      _kws_store="$(_wt_norm_path "$_kws_projroot/.claude/knowledge")"
      case "$_kws_abs" in
        "$_kws_store"|"$_kws_store"/*) continue ;;
      esac

      if [ "$_kws_is_hd" = "1" ] && [ "$_kws_hd_quoted_now" = "1" ]; then
        if printf '%s\n' "$_kws_hd_body_now" | grep -E '^id:' >/dev/null \
           && printf '%s\n' "$_kws_hd_body_now" | grep -E '^domain:' >/dev/null \
           && printf '%s\n' "$_kws_hd_body_now" | grep -E '^scope:' >/dev/null \
           && printf '%s\n' "$_kws_hd_body_now" | grep -E '^status:' >/dev/null; then
          warn "knowledge エントリの形(frontmatter に id:/domain:/scope:/status: が揃っている。引用符付きヒアドキュメントの内容から確認)をしたファイルが、Bash 経由で install 先のストア(${_kws_store})の外(${_kws_abs})へ書かれようとしています。索引の再生成・構造監査が効かず、蓄積が静かに失われます。正当な理由(テストのフィクスチャ・ドキュメントの例示等)が無ければ書き込み先をストア配下に直してください。書き込み自体は妨げません。" "kw_mislanding_shell_content"
        fi
      else
        if printf '%s' "$(basename -- "$_kws_abs")" | grep -E "$_kws_fp_re" >/dev/null; then
          warn "knowledge エントリのファイル名規約(YYYY-MM-DD-<slug>.md)に一致するファイルが、Bash 経由で install 先のストア(${_kws_store})の外(${_kws_abs})へ書かれようとしています。内容(変数展開・パイプ・他コマンドの出力・引用符無しヒアドキュメント等)は事前に確認できなかったため、ファイル名だけを根拠にした警告です。正当な理由が無ければ書き込み先をストア配下に直してください。書き込み自体は妨げません。" "kw_mislanding_shell_path"
        fi
      fi
    done <<EOF2
$_kws_targets
EOF2
  done <<EOF
$_kws_segs
EOF
fi

# --- (D) gh api 経由の PR マージ迂回防止(guard-merge) ---
# 背景: settings の Bash 許可(レビュー投稿ラッパー呼び出しのみ)を将来 drift させても、
# pr-loop の「ハーネスはマージを実行できない/マージは人間が自分の手で行う」不変を機械的に
# 守るための最後の網。gh api で pulls/<n>/merge へ変更メソッド(PUT)を投げる呼び出し、および
# gh api graphql 経由の PR マージ mutation(mergePullRequest)呼び出しをハードブロックする
# (マージ操作を実行できる経路そのものを持たない、という不変を守るため、迂回先は用意しない)。
# opt-out env は設けない: マージは人間の操作であり、Claude 側にバイパス経路を用意する必要が
# 無いため(下記(G)と同じ判断)。
# env を立てての自己承認を許すと「宣言(allow)≠実装(guard の特例)」の穴が settings 経由で
# 再び開いてしまう(このガードが守る不変そのものが破られる)。
#
# (A) と同じ丁寧さで判定する(単純な $cmd 全文への独立 grep×AND だと、クォートで隣接前提が
# 崩れて素通りしたり、無関係な複合コマンド同士の "co-occurrence" を誤って1つの呼び出しと
# 混同したりする)。手順:
#   1. fold_quotes_and_heredocs でクォート/heredoc を折り畳んでから ; | & (と改行)でセグメント分割する。
#      これによりクォートで囲まれたパス/メソッド値(例 -X "PUT" / "repos/.../merge")の隣接関係が
#      崩れない(クォート文字そのものは残るので、周辺パターンにクォート許容を入れる)。
#   2. 各セグメント単位で「gh api 呼び出し」に加え、以下いずれかが揃うかを見る(同一セグメント=
#      同一コマンドに紐づけ、無関係な複合コマンドの誤検知を防ぐ):
#        - REST: 「pulls/<任意トークン>/merge への参照」+「変更メソッド(PUT、大小文字無視)」
#        - GraphQL: 「graphql エンドポイント呼び出し」+「mergePullRequest mutation 名の出現」
#   3. pulls/ と /merge の間のトークンは数字限定にしない(変数展開 $PR 等は静的展開できないため、
#      パス構造そのものを見る)。末尾のスラッシュ・クォートは許容する。
#   4. GraphQL 側は mutation 名(文字列トークン)の静的一致で見る。動的に組み立てた query
#      (変数展開でフィールド名自体を組み立てる・heredoc 本体 <<EOF 等)は fold_quotes_and_heredocs が
#      heredoc 本体を空行化するため検知対象外になる(known-gap・best-effort。REST 側の
#      「変数展開のパス構造は見る/動的メソッド名までは追わない」と同じ位置づけ)。同様に
#      `gh api graphql --input <file>` のように query を外部ファイルから読ませる経路も、
#      コマンド文字列そのものに mutation 名が現れないため静的マッチの検知対象外(known-gap)。
# 早期打ち切り: 判定が成立するには実コマンドの先頭が必ず "gh api" でなければ
# ならない。$cmd に "api" という部分文字列が一度も現れなければ(force push ブロック直前の
# コメントと同じ根拠)、以降のセグメント走査は何も検出しない。
if printf '%s' "$cmd" | grep -E '(^|[^A-Za-z0-9_])api([^A-Za-z0-9_]|$)' >/dev/null; then
  _gm_folded=$(printf '%s' "$cmd" | fold_quotes_and_heredocs) || true
  _gm_segs=$(printf '%s' "${_gm_folded:-}" | tr ';|&' '\n\n\n') || true
  _gm_blocked=""
  while IFS= read -r _gm_seg; do
    [ -n "${_gm_blocked:-}" ] && continue
    case "${_gm_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
    # 先頭のシェルキーワード(if/then/fi 等)・前置トークン(VAR=val/command/env/sudo)を読み飛ばし、
    # 実コマンドの先頭が gh api かを見る
    # (strip_shell_keywords/strip_command_prefix とも、先頭トークン判定を行うチェックはすべて
    # これを通す共通処理(消費者を数えて列挙しない理由はそれぞれの定義直前のコメント参照)。
    # 前置トークンを読み飛ばさないと `GH_TOKEN=x gh api ...` / `command gh api ...` のような
    # 間接呼び出しで gh-api-merge 検知が素通りする)。
    _gm_seg_sh="$(printf '%s' "${_gm_seg:-}" | strip_shell_keywords_and_prefix)" || true
    if printf '%s' "${_gm_seg_sh:-}" | grep -E '^[[:space:]]*gh[[:space:]]+api([[:space:]]|$)' >/dev/null; then
      if printf '%s' "${_gm_seg:-}" | grep -E "pulls/[^/[:space:]]+/merge/?[\"']?([[:space:]]|\$)" >/dev/null \
         && printf '%s' "${_gm_seg:-}" | grep -Ei "(-X[[:space:]=]*[\"']?PUT[\"']?\b|--method[[:space:]=]+[\"']?PUT[\"']?\b)" >/dev/null; then
        _gm_blocked=1
      fi
      # REST 側の body 判定(pulls/.../merge・PUT)と同様、"gh api" 先頭判定にのみ
      # _gm_seg_sh(先頭シェルキーワード読み飛ばし後)を使い、body 側の判定は元セグメント
      # (_gm_seg)で見る(空白正規化の有無は \b 単語境界マッチには影響しないため、
      # 挙動を変えずに揃えられる)。
      if printf '%s' "${_gm_seg:-}" | grep -E '\bgraphql\b' >/dev/null \
         && printf '%s' "${_gm_seg:-}" | grep -E '\bmergePullRequest\b' >/dev/null; then
        _gm_blocked=1
      fi
    fi
  done <<< "${_gm_segs:-}"
  if [ -n "${_gm_blocked:-}" ]; then
    block "gh api 経由の PR マージ(pulls/<n>/merge への PUT、または graphql の mergePullRequest mutation)を検出。マージはハーネスの Bash からは実行できません。人間が GitHub 上または手元の gh で直接行ってください。" "gh_api_pr_merge"
  fi
fi

# --- (E) 秘密ファイルの Bash 経由読取を防ぐ(deny-Read の Bash 迂回対策) ---
# 背景: 秘密ファイル(.env 系・*.pem・*.key・id_rsa・secrets/**)の Read ツール経由の読み取りは、
# 推奨設定の見本(利用者が採る permissions.deny)で禁じられうるが、Bash(cat:*)/Bash(grep:*)/
# Bash(head:*)/Bash(find:*) が許可されていれば、cat .env / grep x .env のような
# Bash 経由の読取は塞がれていない。settings の絞り込み(前方一致 allow)に依存せず、
# guard 側で同じパターンをハードブロックする(settings が将来 drift しても不変を守る)。
#
# これは完全な禁止ではなく「うっかり」を防ぐ best-effort な網である(ファイル冒頭のコメントが
# 定める guard 全体の設計方針どおり)。cat/grep/head/tail/less/find の直接呼び出しという自然な
# 形だけを狙い撃ちしており、cp/sed/シェルのリダイレクト経由の読取、判定に掛からない書き方までは
# 塞がない。これを block() のメッセージにも明記する(守備範囲を実態より広く見せない)。
#
# 対象コマンド: cat/grep/head/tail/less/find(find -exec cat {} \; 等の間接呼び出しは、
# セグメント全体を対象パターンでスキャンするため、-name '*.env' / 検索対象パス自体が
# secrets/ 等を指す形は拾える。ただし find | xargs cat のようにパイプ先の別コマンドへ
# 委譲する形までは対象コマンドの先頭トークン判定の性質上検知できない=known-gap)。
# 他のセクションと同じ丁寧さで判定する: fold_quotes_and_heredocs でクォート/heredoc を折り畳んで
# から ; | & (と改行)でセグメント分割し、各セグメントで「対象コマンドの呼び出しか」を
# 先頭トークンで判定してから、そのセグメント全体に対して秘密パターンを検査する(全セグメント
# 走査でバイパスを防ぐ=(A) の narrowing-guard-pattern の教訓)。
# 境界判定: 各パターンは前後が英数字/アンダースコア/ドットでない位置でのみマッチさせ、
# ".environment" や "invalid_rsa" のような無関係な語(先頭側)、"id_rsa.pub" や
# "notes.pem.bak" のような別拡張子への波及(末尾側。ドットを境界として許すと部分一致で
# 誤検知するため、末尾側の境界文字集合からもドットを除外する)を避ける(FP 防止)。
# (クォートで囲まれた引数(例 cat '.env')の境界としてクォート文字自体も非英数字/非ドットとして
# 機能するため、素の引数・クォート引数の両方を同じ判定式で拾える)。secrets/ は settings の
# `**/secrets/**` glob 意図(secrets がパスセグメントであること)に合わせ、直前が空白/スラッシュ/
# クォート/先頭のいずれか(=パスセグメントの開始位置)の時だけマッチさせる("my-secrets/" のような
# 無関係な語尾一致を誤検知しない)。
# 前置トークン(VAR=val・command/env/sudo)を読み飛ばしてから先頭コマンドを判定する
# (strip_command_prefix: 先頭トークン判定を行うチェックはすべてこれを通す共通処理(消費者を
# 数えて列挙しない理由は strip_command_prefix 定義直前のコメント参照)。読み飛ばさないと
# `X=1 cat .env` / `command cat .env` / `env cat .env` のような間接呼び出しでこの機能の
# 唯一の目的が軽く無効化されてしまう)。
#
# テンプレート接尾辞(*.example/*.sample/*.template)は対象から外す: 実値を含まないテンプレート
# (.env.example 等)を編集・閲覧する日常作業まで秘密ファイルと同じ扱いでブロックすると、正当な
# 作業に解除手段が無いまま迂回が学習される(このブロックの背景となった実際の観測)。
# 判定は追跡状態(gitignore されているか)では行わない: 事故が起きた構成では対象ファイルが
# ignore されておらず、追跡状態で判定すると「追跡されている=テンプレート=読んでよい」と
# 誤判定し、最も危険な場面で fail open するため、接尾辞そのもの(ファイル名の末尾)だけで判定する。
# 接尾辞の除外は .env の拡張子チェーン(\.env(\.[A-Za-z0-9_.-]*)?)にのみ適用する: .pem/.key/id_rsa
# は境界判定が末尾のドットを既に拒否しており(直前のコメント参照)、"foo.pem.example" のような
# ドット付き拡張子の連鎖はその時点で境界不一致となり元々マッチしないため、追加の除外が要らない。
# secrets/ はディレクトリ単位の一致であり、ファイル名の拡張子を見ていない(secrets/ 配下である
# こと自体を危険とみなす設計)ため、本対応の範囲外として据え置く(secrets/ 配下のテンプレートまで
# 除外対象に広げるかどうかは、拡張子ベースの判定とは別の設計判断が要るため踏み込まない)。
# _sf_is_template_ext / _sf_env_hit / SECRET_FILE_DENY_GLOBS / sf_is_secret_path は
# harness/lib/secret-patterns.sh(唯一の置き場。上で source 済み)へ移設した。秘密ファイルの
# 一覧・判定を1か所にまとめるためここでは定義しない。

# _sf_grep_targets: grep 呼び出し($1・strip_shell_keywords|strip_command_prefix 済みで
# "grep" から始まる文字列)から、実際にファイルとして開かれる「対象」トークンだけを空白区切りで
# 再構成して返す(検索パターン引数は読取の対象ではないため秘密パターン判定から除外する)。
# 背景: 旧実装はセグメント全体のテキストに秘密パターンが「どこかに」現れたらブロックしており、
# grep の検索パターン引数の値に対象語が含まれるだけで誤ブロックしていた(実機観測: ソースコード中の
# 語を検索する grep がパターン文字列に ".env" 等を含んでいたため誤って block された。統制側で
# 2026-07-31 に複数回観測。うち1回は複合コマンドで、無関係な後続操作ごと丸ごと未実行になった)。
# grep の呼び出し規約(POSIX: grep [OPTION]... PATTERNS [FILE]...)に従い、-e/--regexp・-f/--file
# でパターンが明示指定されていない限り、オプション読み飛ばし後の最初の非オプション位置引数を
# 「検索パターン」とみなして除外する。
# クォート境界を追跡する簡易トークナイザ(シングル/ダブルクォートで囲まれた領域は内部の空白ごと
# 1トークンとして扱う)。理由: fold_quotes_and_heredocs はクォート内の ; | & だけを空白に中和する
# ため、パターン引数がこれらの文字を含む形でクォートされていると、素朴な空白分割では1つの引数が
# 複数トークンに分裂してしまい、位置ベースの除外が機能しない(実機確認: `grep -n "a\|b\|\.env" file`
# のようなパターンで、中和後の空白によりパターン全体を1引数として認識できないと除外に失敗する)。
# best-effort: -A/-B/-C/-m のようなオプション自身の値が別トークンに分離する形("-A 5")までは
# 追わない(値トークンを次の非オプション位置引数と誤認しうる known-gap。頻度が低く、値自体が
# 秘密パターン文字列と一致することも稀なため許容する)。
# 呼び出し規約から外れる/解析に失敗した場合は無出力を返す(呼び出し側が全文スキャンへ
# フォールバックする=fail-safe。block 側に倒れる既存の設計方針を踏襲。tc<1 や arr[1]!="grep" の
# 場合に該当)。
_sf_grep_targets() {
  printf '%s' "${1:-}" | awk '
    function is_pattern_flag(w) { return (w=="-e" || w=="--regexp" || w=="-f" || w=="--file") }
    function is_pattern_flag_fused(w) {
      return (w ~ /^-e./ || w ~ /^-f./ || w ~ /^--regexp=/ || w ~ /^--file=/)
    }
    {
      n = length($0)
      cur = ""; intok = 0; qc = ""; tc = 0
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (qc != "") {
          cur = cur c
          if (c == qc) { qc = "" }
          continue
        }
        if (c == "\x27" || c == "\"") { qc = c; cur = cur c; intok = 1; continue }
        if (c == " " || c == "\t") {
          if (intok) { tc++; arr[tc] = cur; cur = ""; intok = 0 }
          continue
        }
        cur = cur c; intok = 1
      }
      if (intok) { tc++; arr[tc] = cur }

      if (tc < 1 || arr[1] != "grep") { exit }

      explicit = 0
      i = 2
      while (i <= tc) {
        w = arr[i]
        if (substr(w,1,1) == "-") {
          if (is_pattern_flag(w)) { explicit = 1; i += 2; continue }
          if (is_pattern_flag_fused(w)) { explicit = 1; i++; continue }
          i++; continue
        }
        break
      }
      if (!explicit && i <= tc) { i++ }
      out = ""
      for (; i <= tc; i++) out = out (out=="" ? "" : " ") arr[i]
      print out
    }
  '
}

# 早期打ち切り: 判定が成立するには実コマンドの先頭トークンが cat/grep/head/tail/
# less/find のいずれかでなければならない。$cmd にこれらのいずれの部分文字列も現れなければ
# (force push ブロック直前のコメントと同じ根拠で、fold は文字を足さないため安全な上位集合)、
# 以降のセグメント走査は何も検出しない。
if printf '%s' "$cmd" | grep -E '(^|[^A-Za-z0-9_])(cat|grep|head|tail|less|find)([^A-Za-z0-9_]|$)' >/dev/null; then
  _sf_folded=$(printf '%s' "$cmd" | fold_quotes_and_heredocs) || true
  _sf_segs=$(printf '%s' "${_sf_folded:-}" | tr ';|&' '\n\n\n') || true
  _sf_blocked=""
  while IFS= read -r _sf_seg; do
    [ -n "${_sf_blocked:-}" ] && continue
    case "${_sf_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
    # 先頭のシェルキーワード(if/then/fi 等)・前置トークン(VAR=val/command/env/sudo)を
    # 読み飛ばし、実コマンドの先頭トークンで判定する
    # (strip_shell_keywords/strip_command_prefix とも、先頭トークン判定を行うチェックはすべて
    # これを通す共通処理。消費者を数えて列挙しない理由はそれぞれの定義直前のコメント参照)。
    _sf_seg_sh="$(printf '%s' "${_sf_seg:-}" | strip_shell_keywords_and_prefix)" || true
    if printf '%s' "${_sf_seg_sh:-}" | grep -E '^[[:space:]]*(cat|grep|head|tail|less|find)([[:space:]]|$)' >/dev/null; then
      # grep だけは検索パターン引数を除外したテキストで判定する(引数の位置を見る)。
      # 他のコマンド(cat/head/tail/less/find)は検索パターンという概念を持たず、位置引数は
      # すべてファイル/パスであるため、従来どおりセグメント全体を判定対象にする。
      _sf_scan="${_sf_seg:-}"
      if printf '%s' "${_sf_seg_sh:-}" | grep -E '^[[:space:]]*grep([[:space:]]|$)' >/dev/null; then
        _sf_gt="$(_sf_grep_targets "${_sf_seg_sh:-}")" || true
        [ -n "${_sf_gt:-}" ] && _sf_scan="$_sf_gt"
      fi
      if sf_is_secret_path "${_sf_scan:-}"; then
        _sf_blocked=1
      fi
    fi
  done <<< "${_sf_segs:-}"
  if [ -n "${_sf_blocked:-}" ]; then
    block "秘密ファイルの読み取りはガードが止めます(Read・Grep・Bash の cat 等)。ここでは cat/grep/head/tail/less/find 等の Bash 経由の読み取りを検出しました(.env系/*.pem/*.key/id_rsa/secrets/**。*.example/*.sample/*.template のテンプレートは対象外)。これは cat/grep/head/tail/less/find の直接呼び出しという自然な形だけを狙い撃ちする best-effort な網であり、完全な禁止ではありません(コピー・置換・リダイレクト経由の読取や、判定に掛からない書き方までは塞ぎません)。${NO_BYPASS_MSG}" "secret_file_read"
  fi
fi

# --- (F) git checkout による作業ツリー破棄をブロック(未コミット変更の意図しない喪失防止) ---
# 背景: Bash(git checkout:*) の実利用はブランチ切替(git checkout <branch> / git checkout -b <new>)
# のみだが、前方一致の allow は git checkout -- <path> / git checkout . (未コミット変更の破棄)まで
# 許してしまう。ブランチ切替は通し、作業ツリー破棄モードだけをハードブロックする。
# 判定方法: 前置トークン(VAR=val・command/env/sudo)を読み飛ばし(strip_command_prefix: 先頭トークン
# 判定を行うチェックはすべてこれを通す共通処理。消費者を数えて列挙しない理由は strip_command_prefix
# 定義直前のコメント参照。読み飛ばさないと `command git checkout -- foo` のような間接呼び出しが
# 素通りする)、
# git のグローバルオプションを読み飛ばしてサブコマンドが checkout かを確認し((A)/(D)と同じ
# awk 抽出)、checkout に続く各引数を見る。各引数はクォート文字(シングル/ダブル)とバックスラッシュを
# トークン中の**出現位置を問わず全て**除去してから判定する(クォート枚数・入れ子に依存しない
# 判定。1枚だけ剥がす方式だと `.""` (裸の `.` にクォートで囲った空文字列を隣接連結)や
# `"""."""` (何重にも入れ子にした空クォート)のような隣接連結/多重ネストで、実 git では
# いずれも `.` 1文字に評価されるのに未検知になる一次レビュー回帰があった。クォート文字を
# 種類・位置を問わず単純に取り除く方式なら、連結・ネストの深さによらず同じ結果になる)。
# issue の明示仕様どおり -b/-B(ブランチ作成)が含まれていれば常に許可し、それ以外で以下
# いずれかがあれば破棄モードとして block する:
#   - 独立トークンとしての "--" (パス指定の disambiguator。git checkout -- <path> / <ref> -- <path>)
#   - 独立トークンとしての "." (カレントディレクトリ全体の pathspec。ブランチ名に "." は使えないため
#     曖昧性は無い)
# known-gap(best-effort・境界ではない): git restore(checkout の後継コマンド。デフォルトで作業ツリーを
# 上書きする)・git checkout -f(強制上書き)は本ブロックの対象外(実装範囲を検証済みの
# checkout -- / checkout . の2形に絞った意図的な判断。バイパスが実際に踏まれたら別途拡張する)。
# 早期打ち切り: 判定が成立するには実コマンドが "git checkout" でなければならない。
# $cmd に "checkout" という部分文字列が一度も現れなければ(force push ブロック直前のコメントと
# 同じ根拠)、以降のセグメント走査は何も検出しない。
if printf '%s' "$cmd" | grep -E '(^|[^A-Za-z0-9_])checkout([^A-Za-z0-9_]|$)' >/dev/null; then
  _co_folded=$(printf '%s' "$cmd" | fold_quotes_and_heredocs) || true
  _co_segs=$(printf '%s' "${_co_folded:-}" | tr ';|&' '\n\n\n') || true
  _co_blocked=""
  while IFS= read -r _co_seg; do
    [ -n "${_co_blocked:-}" ] && continue
    case "${_co_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
    _co_seg_sh="$(printf '%s' "${_co_seg:-}" | strip_shell_keywords_and_prefix)" || true
    _co_result="$(printf '%s' "${_co_seg_sh:-}" | awk '
      BEGIN {
        SQ = sprintf("%c", 39)
        two_tok["-C"]=1; two_tok["-c"]=1
        two_tok["--git-dir"]=1; two_tok["--work-tree"]=1; two_tok["--namespace"]=1
        two_tok["--super-prefix"]=1
      }
      function striptoken(t,    r) {
        r = t
        gsub(/"/, "", r)
        gsub(SQ, "", r)
        gsub(/\\/, "", r)
        return r
      }
      {
        i=1
        while (i<=NF && $i ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++ }
        if (i>NF || $i!="git") { print "NOTGIT"; exit }
        i++
        while (i<=NF) {
          tok=$i
          if (tok in two_tok) { i+=2; continue }
          if (substr(tok,1,1)=="-") { i++; continue }
          break
        }
        if (i>NF || $i!="checkout") { print "NOTCHECKOUT"; exit }
        i++
        has_b=0; has_dd=0; has_dot=0
        for (; i<=NF; i++) {
          t = striptoken($i)
          if (t=="-b" || t=="-B") has_b=1
          if (t=="--") has_dd=1
          if (t==".") has_dot=1
        }
        printf "CO|%d|%d|%d\n", has_b, has_dd, has_dot
      }
    ')"
    case "${_co_result:-}" in
      CO\|*)
        _co_flags="${_co_result#CO|}"
        _co_has_b="${_co_flags%%|*}"
        _co_rest2="${_co_flags#*|}"
        _co_has_dd="${_co_rest2%%|*}"
        _co_has_dot="${_co_rest2#*|}"
        if [ "${_co_has_b:-0}" != "1" ] && { [ "${_co_has_dd:-0}" = "1" ] || [ "${_co_has_dot:-0}" = "1" ]; }; then
          _co_blocked=1
        fi
        ;;
    esac
  done <<< "${_co_segs:-}"
  if [ -n "${_co_blocked:-}" ]; then
    block "git checkout による作業ツリーの破棄(-- <path> / . )を検出。未コミットの変更を失います。ブランチ切替(git checkout <branch> / -b)は許可されています。変更を一旦退避したいだけなら 'git stash' を使ってください(元に戻せます)。${NO_BYPASS_MSG}" "git_checkout_discard"
  fi
fi

# --- (G) PR マージ操作のハードブロック(ハーネスはマージを実行できない) ---
# 背景: 以前は settings 側で「許可プロンプトを承認すればマージできる」形(permissions.ask に
# gh の pr サブコマンドのマージ操作を許可登録)だったが、許可プロンプトはコマンド文字列の実行可否を
# 問うだけで、マージ先・マージ戦略・タイミングが妥当かという判断を人間に渡していない。
# pr-loop の「すべての変更は PR を介し、人間マージで閉じる/自動マージしない」を例外なしの
# 不変にするため、gh の pr サブコマンドによる PR マージ呼び出しそのものをハードブロックする
# (settings の許可設定が将来 drift しても、この不変を機械的に守るための最後の網。(D) と同じ位置づけ)。
# opt-out env は設けない: マージは人間の操作であり、Claude 側にバイパス経路を用意する必要が無い
# (opt-out を用意すると「宣言(settings)≠実装(guard の特例)」の穴が再び開く。(D) と同じ判断)。
# 他のセクションと同じ丁寧さで判定する: fold_quotes_and_heredocs でクォート/heredoc を折り畳んでから
# ; | & (と改行)でセグメント分割し、各セグメント単位で先頭のシェルキーワード/前置トークン
# (strip_shell_keywords/strip_command_prefix とも、先頭トークン判定を行うチェックはすべて
# これを通す共通処理。消費者を数えて列挙しない理由はそれぞれの定義直前のコメント参照)を
# 読み飛ばしてから、
# 実コマンドの先頭が対象のマージ呼び出しかを判定する。この方式により、PR 本文や commit
# メッセージのテキストとして対象コマンドの文字列が引用符内に含まれるだけの場合(セグメントの
# 先頭トークンが別の実コマンド、例えば git commit 等になる)は誤検知しない。
# gh はサブコマンドの前にグローバルオプション(例 -R/--repo。OWNER/REPO 指定。値を取る)を
# 置ける一般的な呼び出し形をサポートするため、(A) が git のグローバルオプションを awk で
# 読み飛ばしてから commit サブコマンドを判定しているのと同じ型で、gh のグローバルオプションを
# 読み飛ばしてから pr/merge サブコマンド列を判定する(1トークン / 2トークン値分離の両方に対応。
# 2トークン値分離形は正規表現では網羅困難なため awk を使用。awk 不在時はコマンド not found →
# exit 1 → if 条件が偽 → ゲート非マッチ → 検知スキップ、という fail-open な best-effort)。
#
# 早期打ち切り: 判定が成立するには実コマンドが必ず gh の pr サブコマンドに続けて merge を
# 指定した形でなければならない。$cmd に "merge" という部分文字列が一度も現れなければ
# (force push ブロック直前のコメントと同じ根拠)、以降のセグメント走査は何も検出しない。
if printf '%s' "$cmd" | grep -E '(^|[^A-Za-z0-9_])merge([^A-Za-z0-9_]|$)' >/dev/null; then
  _pm_folded=$(printf '%s' "$cmd" | fold_quotes_and_heredocs) || true
  _pm_segs=$(printf '%s' "${_pm_folded:-}" | tr ';|&' '\n\n\n') || true
  _pm_blocked=""
  while IFS= read -r _pm_seg; do
    [ -n "${_pm_blocked:-}" ] && continue
    case "${_pm_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
    _pm_seg_sh="$(printf '%s' "${_pm_seg:-}" | strip_shell_keywords_and_prefix)" || true
    if printf '%s' "${_pm_seg_sh:-}" | awk '
      BEGIN {
        # two_tok: スペース区切りで値を取る gh グローバルオプションのみ(=付き1トークン形は
        # 汎用の "-" 始まりフォールバックで1トークンとして読み飛ばされるため two_tok 不要)。
        two_tok["-R"]=1; two_tok["--repo"]=1
        found=0
      }
      { i=1; if ($i!="gh") next; i++
        while(i<=NF){ if($i in two_tok){i+=2} else if(substr($i,1,1)=="-"){i++} else{break} }
        if(i<=NF && $i=="pr"){ i++
          if(i<=NF && $i=="merge"){found=1}
        }
      }
      END{exit(found?0:1)}
    ' 2>/dev/null; then
      _pm_blocked=1
    fi
  done <<< "${_pm_segs:-}"
  if [ -n "${_pm_blocked:-}" ]; then
    block "PR のマージ操作を検出。マージはハーネスの Bash からは実行できません。人間が GitHub 上または手元の gh で直接行ってください。" "pr_merge_operation"
  fi
fi

# --- (H) セッション層コミットスキャン(ワークスペース内の子リポジトリを含む唯一の secret 検査) ---
# 背景: 以前は git の commit 前フック(`.git/hooks/pre-commit`)も secret/PII をスキャンしていたが、
# プラグイン化に伴い撤去した(プラグインにすると導入先の中継先が無くなり、git のフックは Claude の
# 外で動くためプラグインの場所を知る手段が無い)。secret の検査はこのセッション内のガード
# (`git commit` の時点で対象リポジトリの staged 内容を実際に読み取って走査する)だけで行う。
#
# ハーネスが止めるのは Claude の操作だけである: このセッションの Bash 経由のコミットだけが対象で、
# 人がエディタ・別ターミナルで行うコミットは範囲外(使う人が gitleaks 等で自衛する領域)。
#
# 対象リポジトリの決定: hook 入力の cwd を基点とし、コマンド文字列内の `cd`/`pushd` による
# セグメント間のディレクトリ変更(`cd <dir> && git commit ...` のような素朴な `cd` 連結)を
# 追跡して基点を更新した上で、コマンドに -C / --git-dir があればそちらを優先する
# (_scs_analyze_commit が git 本体の呼び出し引数から抽出する)。cd/pushd の追跡は
# wt_cd_target_for_segment(extract_git_env_target 定義直後。(C) worktree 隔離ガードの
# cd/pushd 追跡ロジックと同じ判定を共有する。新しい cd 解析ロジックは発明しない)を呼ぶ。
# 追跡しないと `cd <保護リポジトリ> && git commit -m x` のような迂回が対象リポジトリ決定を
# すり抜けてしまう(hook 入力の cwd のみを見ていた場合の既知の抜け穴だった)。
# GIT_DIR/GIT_WORK_TREE の環境変数プレフィックス形(`GIT_DIR=/x git commit ...` /
# `GIT_WORK_TREE=/x git commit ...`)も対象に含める: strip_command_prefix はこれらの代入
# トークンを値ごと読み飛ばして捨てるため、strip_command_prefix を通した後の文字列からは
# 値を取り戻せない。そこで strip_command_prefix を通す**前**のセグメントに対して
# extract_git_env_target(strip_command_prefix 定義直後。値取りオプション表を共有しつつ
# (C) worktree 隔離ガードの git 判定側と同じ抽出を行う。新しい方式は発明しない)を呼び、
# 値を保持したまま拾ってから、-C/--git-dir(コマンドライン明示指定)に対する fallback として使う。
# known-gap(best-effort・境界ではない):
#   - -C を複数回指定した場合は最後の1つだけを見る(git 本来の「直前の -C からの相対」という
#     連鎖適用はしない簡略化)。
#   - cwd も -C も得られない場合(hook 入力に cwd が無い等)は対象を特定できないため走査を
#     スキップする(fail-open。他セクションの「awk 不在時は検知スキップ」と同じ位置づけ)。
#   - git 自体が使えない/対象が git リポジトリでない場合も同様に fail-open する(このとき
#     実際の git commit 自体もどのみち失敗するため実害は無い)。
#   - env/sudo 自身の未知の値取りオプション(strip_command_prefix の値取りオプション表に無いもの。
#     例 `sudo -T 30 GIT_DIR=<x>/.git git commit ...`)と env 代入プレフィックスが組み合わさると、
#     strip_command_prefix 側の best-effort(表に無いオプションは単独フラグ扱いに倒す。定義直前の
#     コメント参照)により後続の実コマンド判定がずれ、_scs_analyze_commit がそもそも「git commit
#     呼び出しである」と認識できず、このセクション自体が丸ごとスキップされる(extract_git_env_target
#     自身は同じ表を使った loose フォールバックで値を拾えても、_scs_analyze_commit 側が呼ばれない
#     ため活きない)。GIT_DIR/GIT_WORK_TREE の有無に関わらず strip_command_prefix が元々持つ
#     known-gap であり、本対応が持ち込んだ回帰ではない(実機確認: env 代入を伴わない
#     `sudo -T 30 git commit -m x` も本対応の前後で同様に走査をスキップする)。
#
# 一致した内容そのものはメッセージに出さない(件数とファイル名まで): commit 前フックは該当行を
# 数行表示するが(人間が読む出力なので妥当)、ガードのメッセージは Claude の文脈へ入るため、
# 同じことをすると秘密そのものを文脈へ載せてしまう。secret パターンは harness/lib/secret-patterns.sh
# を source して共有する((B) と同じ。重複定義しない)。
#
# --- (H-1) コミット時にステージする形(走査を素通りする経路)をブロック ---
# `git commit -a/--all` や pathspec 引数(パスを直接指定する呼び出し)は、コミットと同時に
# ステージするため、PreToolUse 時点の index(= git diff --staged が返す内容)にはまだ反映されて
# いない。これを許すと (H-2) の走査は「まだ何もステージされていない」空の index を見て
# 素通りする=静かに fail open する。手段の列挙(一括ステージ・グロブ等)ではなく「結果」
# (コミット時にステージが増える呼び出し形かどうか)で判定し、権限設定の拒否リスト(前方一致。
# 推奨設定の見本(利用者が採る拒否リスト)側で最も典型的な綴り(`git commit -a`/`git commit --all`)を安く塞ぐ)と
# 本ガード(フラグの並び順・-C の挿入・短縮オプションの融合形(-am 等)・pathspec 引数の位置に
# 依存しない完全な判定)の両方で止める。拒否リストは前方一致でしか書けないため、フラグが
# commit の直後に来ない形(例: `git commit -m x -a`)・グローバルオプションを挟む形
# (例: `git -C /repo commit -a`)・融合形(`-am`)を原理的に拾えない。これらは全て本ガードが
# 拾う(揺れで拒否リストだけを擦り抜けても、本ガードが最後の網になる)。
#
# `git commit --amend`(直前のコミットをやり直す形)は特別扱いしない: amend 単体は既存の
# staged index をそのまま使う(通常の commit と同じ)ため (H-2) の走査で従来どおり覆える。
# amend が -a/pathspec と組み合わさった場合も、本判定は --amend の有無を見ずに -a/pathspec の
# 有無だけで判定するため、組み合わせても同様に (H-1) で block される(特別なケース分けは不要)。
#
# オプション文法をどこまで追うか(スコープ): 単一ダッシュの短縮オプションクラスタ(-qm 等)は
# commit_val(後述)に列挙した値取り短縮オプション(-m/-C/-c/-F/-t)だけを認識し、クラスタ中の
# 該当文字に到達したら値(埋め込みまたは次のトークン)を読み飛ばす。commit_val に無い値取り
# オプション(--cleanup 等)がクラスタに混ざる形は対象外(best-effort・known-gap。既に単一
# トークン形でも同様に対象外であり、クラスタ形にしたことで新たに生じる制約ではない)。
# 網羅を広げるより「クラスタの最後の1文字だけが値を取りうる」という git のクラスタリング規約
# (getopt 由来。値を取らない短縮オプションはクラスタのどこにあっても素通しでよい)を正しく
# 再現することを優先した。
_scs_analyze_commit() {
  # $1: 1セグメント文字列(strip_shell_keywords | strip_command_prefix 済み)。
  # "git" から始まらない/commit サブコマンドでなければ何も出力しない(対象外)。
  # commit 呼び出しなら "COMMIT|<has_all>|<has_path>|<cdir>|<gitdir>" を1行出力する。
  # クォート境界を追跡する簡易トークナイザ((E)の _sf_grep_targets と同型: シングル/ダブル
  # クォートで囲まれた領域は内部の空白ごと1トークンとして扱う)。-m/--message の値がスペースを
  # 含む長文(このハーネス自身のコミット規約が使う heredoc 由来の複数行メッセージを含む。
  # fold_quotes_and_heredocs が既に1行へ折り畳んでいる)であっても、クォートで囲まれている限り
  # 1トークンのまま保持され、後続の commit_val テーブルで安全に1トークンだけ読み飛ばせる
  # (実機確認: 本ハーネス自身の `git commit -m "$(cat <<'EOF' ... EOF)"` 形の複数行コミットが
  # pathspec 引数と誤認されず block されないことを検証済み)。
  printf '%s' "${1:-}" | awk '
    function strip_quotes(t,    r) {
      r = t
      gsub(/"/, "", r)
      gsub(/\x27/, "", r)
      return r
    }
    {
      n = length($0)
      cur=""; intok=0; qc=""; tc=0
      for (i=1;i<=n;i++) {
        c = substr($0,i,1)
        if (qc!="") { cur=cur c; if (c==qc) qc=""; continue }
        if (c=="\x27" || c=="\"") { qc=c; cur=cur c; intok=1; continue }
        if (c==" " || c=="\t") { if (intok) { tc++; arr[tc]=cur; cur=""; intok=0 }; continue }
        cur=cur c; intok=1
      }
      if (intok) { tc++; arr[tc]=cur }

      # 絶対パス指定の git 呼び出し(/usr/bin/git 等)は先頭トークンの末尾要素(basename)が "git" と
      # 一致するかで判定する((C)worktree 隔離ブロックの絶対パス判定と同じパターンを再利用。新しい
      # 方式を発明しない)。一次レビュー実機確認: 単純な文字列完全一致(arr[1]!="git")だと
      # `/usr/bin/git commit -m x` が「git 呼び出しではない」と判定され、走査ごと素通りしていた
      # (拒否リスト(推奨設定の見本)は前方一致でしか書けず同じ揺れを拾えないため、拒否リストと
      # ガードの両方が同時に外れる=このセクション全体の設計前提が崩れる致命的な欠陥だった)。
      if (tc<1) { exit }
      nslash = split(arr[1], gitparts, "/")
      if (gitparts[nslash] != "git") { exit }

      # git グローバルオプションの読み飛ばし(スペース区切りの2トークン形。(A)/(C) と同じ表)。
      # -C/--git-dir は値を cdir/gitdir として持ち帰る(対象リポジトリ決定用。同じオプションが
      # 複数回現れた場合は最後の指定を採用する)。
      two_tok["-C"]=1; two_tok["-c"]=1
      two_tok["--git-dir"]=1; two_tok["--work-tree"]=1; two_tok["--namespace"]=1
      two_tok["--super-prefix"]=1
      cdir=""; gitdir=""
      i=2
      while (i<=tc) {
        if (arr[i]=="-C") { cdir = strip_quotes(arr[i+1]); i+=2; continue }
        if (arr[i]=="--git-dir") { gitdir = strip_quotes(arr[i+1]); i+=2; continue }
        if (arr[i] ~ /^--git-dir=/) { gitdir = strip_quotes(substr(arr[i], index(arr[i],"=")+1)); i++; continue }
        if (arr[i] in two_tok) { i+=2; continue }
        if (substr(arr[i],1,1)=="-") { i++; continue }
        break
      }
      if (i>tc || arr[i]!="commit") { exit }
      i++

      # git commit 側の値取りオプション: 値を1トークン読み飛ばす(スペース区切り形のみ。=形は
      # 元々1トークンで完結するため個別対応不要)。列挙外の値取りオプション(--cleanup 等)は
      # best-effort で非対応(その値トークンが pathspec と誤認され false positive で block
      # されうる既知の残余。列挙は harness 自身の利用実態(-m 中心)を優先した)。
      commit_val["-m"]=1; commit_val["--message"]=1
      commit_val["-C"]=1; commit_val["-c"]=1
      commit_val["-F"]=1; commit_val["--file"]=1
      commit_val["-t"]=1; commit_val["--template"]=1
      commit_val["--author"]=1; commit_val["--date"]=1
      commit_val["--fixup"]=1; commit_val["--squash"]=1
      commit_val["--reuse-message"]=1; commit_val["--reedit-message"]=1

      # commit_val のうち単一ダッシュ・単一文字のキー(-m/-C/-c/-F/-t)だけを、その1文字
      # (m/C/c/F/t)をキーにしたテーブルへ再展開する。二重管理を避けるため commit_val を
      # 機械的に走査して作る(値取り短縮オプションを増減するときは commit_val 側だけを
      # 直せばよく、このテーブルは自動で追随する)。
      for (cv_k in commit_val) {
        if (length(cv_k) == 2 && substr(cv_k, 1, 1) == "-") {
          commit_val_chars[substr(cv_k, 2, 1)] = 1
        }
      }

      has_all=0; has_path=0
      for (; i<=tc; i++) {
        t = arr[i]
        # シェルのリダイレクト演算子(<file / <<'EOF' / >out / >>out / 2>/dev/null 等)に
        # 到達したら、それ以降は git 自身の引数ではなくシェルが消費する記述なので走査を打ち切る
        # (実機回帰: `git commit -F - <<'EOF' ... EOF` のような heredoc 付き呼び出しで、
        # fold_quotes_and_heredocs 折り畳み後もヒアドキュメント開始行に残る `<<'EOF'` の
        # トークンが「-」で始まらないため pathspec 引数と誤認され、over-detection で
        # false positive block していた。fd 番号プレフィックス(2>&1 等)も拾う)。
        if (t ~ /^[0-9]*(>>?|<<?)/) { break }
        if (t in commit_val) { i++; continue }
        if (t=="-a" || t=="--all") { has_all=1; continue }
        if (t=="--") { continue }
        if (substr(t,1,1)=="-") {
          if (substr(t,2,1)!="-") {
            # 単一ダッシュの短縮オプションクラスタ(例 -qm, -aF, -Sm)を1文字ずつ読む。
            # 'a' を含めば -a 相当(git commit の短縮オプションで単独文字 'a' を持つのは
            # --all のみ)。commit_val_chars に載っている値取り短縮オプション(m/C/c/F/t)に
            # 到達したら、そこで走査を打ち切る: クラスタ内にまだ文字が残っていればそれが
            # 埋め込み値(例 -Fmsg.txt の "msg.txt")、残っていなければ次のトークンが値
            # (例 -qm "msg" の "msg")なので次のトークンを読み飛ばす。どちらの場合も、
            # 値の中身を pathspec 引数(has_path)や 'a' の有無(has_all)の判定材料にしない
            # (修正前は `t ~ /a/` でトークン全体を正規表現一致させていたため、値を取らない
            # 短縮オプションどうしの組み合わせ(-qm 等)で、値取りオプションの後続トークンを
            # 読み飛ばす処理が無く、コミットメッセージの値がそのまま pathspec 引数と誤認され
            # 正当なコミットを誤って block していた)。
            _bo_cluster = substr(t, 2)
            _bo_len = length(_bo_cluster)
            for (_bo_ci = 1; _bo_ci <= _bo_len; _bo_ci++) {
              _bo_ch = substr(_bo_cluster, _bo_ci, 1)
              if (_bo_ch == "a") { has_all = 1; continue }
              if (_bo_ch in commit_val_chars) {
                if (_bo_ci == _bo_len) { i++ }
                break
              }
            }
          }
          continue
        }
        has_path=1
      }
      printf "COMMIT|%d|%d|%s|%s\n", has_all, has_path, cdir, gitdir
    }
  '
}

# この repo(リネーム前の旧リポジトリ)自身の全履歴を実測した結果、最大の正当なコミットは 111 ファイル
# だった。閾値は正当なコミットの最大観測値に安全マージンを載せた 300(約2.7倍)とし、事故規模
# (5000+ ファイル)は大きく下回ったまま、通常の一括変更(依存更新・フォーマット一括適用等)に
# よる誤検知を避ける。実運用を見て調整可能(このコメントと共に値を変更すること)。
# この実測はマージコミット(第1親に対する差分)を母集団に含んでいない: この repo は短命
# ブランチ間のマージしかなく、実測時の最大は47ファイルに留まった。長寿命ブランチ間の
# マージは分岐後の全差分で決まるためこの閾値を容易に超えうる(以下のマージ進行中の除外を参照)。
SCS_MAX_STAGED_FILES=300

# 早期打ち切り: _scs_analyze_commit が COMMIT として認識するには、実コマンドの
# 先頭が必ず "git" で、続くサブコマンドが "commit" でなければならない。$cmd に "commit" という
# 部分文字列が一度も現れなければ(force push ブロック直前のコメントと同じ根拠)、以降のセグメント
# 走査はどのセグメントも COMMIT と判定されず、(H-1)/(H-2) いずれの block も発生しない。
# 可読性メモ: (C) セクションの早期打ち切り直前のコメントと同じ理由で、この if の中身は
# 再インデントせずそのまま残す(挙動の変更が無い箇所の差分を膨らませない)。
if printf '%s' "$cmd" | grep -E '(^|[^A-Za-z0-9_])commit([^A-Za-z0-9_]|$)' >/dev/null; then
_scs_folded=$(printf '%s' "$cmd" | fold_quotes_and_heredocs) || true
_scs_segs=$(printf '%s' "${_scs_folded:-}" | tr ';|&' '\n\n\n') || true
# セグメント間で "現在のディレクトリ" を持ち回る状態(cd/pushd 追跡用。wt_cd_target_for_segment
# 定義直前のコメント参照)。hook 入力の cwd を初期値にし、cd/pushd セグメントに遭遇するたびに
# 更新する。cwd が無ければ空文字のまま(既存の fail-open な扱いを変えない)。
_scs_cur="$(get_cwd "$input")"
while IFS= read -r _scs_seg; do
  case "${_scs_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
  # strip_command_prefix を通す前の形(_scs_seg_kw)を GIT_DIR/GIT_WORK_TREE 抽出用に残す
  # (strip_command_prefix はこれらの env 代入トークンを値ごと読み飛ばして捨てるため、通した後の
  # _scs_seg_sh からは値を取り戻せない。extract_git_env_target 定義直前のコメント参照)。
  _scs_seg_kw="$(printf '%s' "${_scs_seg:-}" | strip_shell_keywords)" || true
  _scs_seg_sh="$(printf '%s' "${_scs_seg_kw:-}" | strip_command_prefix)" || true

  # cd/pushd によるディレクトリ変更を追跡する(cd <保護リポジトリ> && git commit のような
  # 迂回を素通りさせないため。wt_cd_target_for_segment 定義直前のコメント参照)。cd/pushd
  # セグメント自身は git commit ではないので、状態を更新したら次のセグメントへ進む。
  _scs_cd_result="$(wt_cd_target_for_segment "${_scs_seg_sh:-}" "${_scs_cur:-}")"
  case "$_scs_cd_result" in
    CD\|*) _scs_cur="${_scs_cd_result#CD|}"; continue ;;
  esac

  _scs_result="$(_scs_analyze_commit "${_scs_seg_sh:-}")"
  case "${_scs_result:-}" in
    COMMIT\|*)
      IFS='|' read -r _scs_tag _scs_all _scs_path _scs_cdir _scs_gitdir <<< "$_scs_result"

      # --- (H-1) ---
      if [ "${_scs_all:-0}" = "1" ] || [ "${_scs_path:-0}" = "1" ]; then
        block "git commit -a/--all または pathspec 引数(パスを直接指定する呼び出し)を検出しました。該当する場合、コミットと同時にステージするため、コミット前の staged 内容スキャンを素通りする可能性があります(best-effort な判定であり誤検知もありえます)。git add で明示的にステージしてから git commit してください。${NO_BYPASS_MSG}" "commit_time_stage"
        continue
      fi

      # GIT_DIR/GIT_WORK_TREE の env 代入プレフィックスを拾う(コマンドライン明示の -C/--git-dir
      # が既にあればそちらを優先し、無い場合のみこの env 値を使う。extract_git_env_target 定義
      # 直前のコメント参照)。
      _scs_env_result="$(printf '%s' "${_scs_seg_kw:-}" | extract_git_env_target)" || true
      _scs_env_gd="${_scs_env_result%%|*}"
      _scs_env_gwt="${_scs_env_result#*|}"

      # --- (H-2) 対象リポジトリの決定 ---
      # $_scs_cur は上の cd/pushd 追跡で更新済みの「現在のディレクトリ」(cd が無い場合は
      # hook 入力の cwd のまま=従来どおりの get_cwd と同じ値)。
      _scs_cwd="${_scs_cur:-}"
      _scs_dir=""
      if [ -n "${_scs_cdir:-}" ]; then
        case "$_scs_cdir" in
          /*) _scs_dir="$_scs_cdir" ;;
          *)  _scs_dir="${_scs_cwd:+$_scs_cwd/}$_scs_cdir" ;;
        esac
      elif [ -n "${_scs_env_gwt:-}" ]; then
        case "$_scs_env_gwt" in
          /*) _scs_dir="$_scs_env_gwt" ;;
          *)  _scs_dir="${_scs_cwd:+$_scs_cwd/}$_scs_env_gwt" ;;
        esac
      elif [ -n "${_scs_cwd:-}" ]; then
        _scs_dir="$_scs_cwd"
      fi
      [ -n "${_scs_dir:-}" ] || continue

      _scs_gitdir_eff="${_scs_gitdir:-}"
      [ -n "${_scs_gitdir_eff:-}" ] || _scs_gitdir_eff="${_scs_env_gd:-}"
      _scs_gitdiropt=()
      [ -n "${_scs_gitdir_eff:-}" ] && _scs_gitdiropt=(--git-dir="$_scs_gitdir_eff")

      _scs_files="$(git -C "$_scs_dir" "${_scs_gitdiropt[@]+"${_scs_gitdiropt[@]}"}" diff --staged --name-only 2>/dev/null)" || true
      _scs_count=0
      if [ -n "${_scs_files:-}" ]; then
        _scs_count=$(printf '%s\n' "$_scs_files" | grep -c '[^[:space:]]') || true
      fi

      # --- マージ進行中(MERGE_HEAD)の判定 ---
      # (H-2a) が守るのは「意図しない一括ステージ」だが、マージ進行中(競合解消後の
      # `git commit`)の大量 staged は git 自身が作った正常な状態であり、そもそも
      # 「意図しない一括ステージ」ではない。かつマージコミットは2親を持つ1個のコミットで
      # 分割できないため、閾値超過時の唯一の指示(unstage して分割する)が原理的に実行不能
      # (分割すると MERGE_HEAD を失いマージ自体が成立しなくなる)。したがってマージ進行中は
      # 「マージ自身が持ち込む差分」だけを (H-2a) の対象から外す(以下)。判定は
      # `git rev-parse -q --verify MERGE_HEAD` の終了コード(0=マージ中)を使う。`-q` は
      # 「MERGE_HEAD が無い」場合の stderr を抑える。
      # (H-2b) の secret スキャンはこの判定に関与せず、マージ中も従来どおり適用され続ける
      # (競合解消時に secret を誤って取り込む経路は残るため。守りきれないのは (H-2a) の
      # 「意図しない大量ステージ」検知だけで、secret 混入の検知は諦めない)。
      # 検討したが採らなかった選択肢:
      #   - 閾値を引き上げる: 長寿命ブランチ同士のマージでは staged 件数が分岐後の全差分に
      #     比例していくらでも大きくなりうるため、どの値に上げても再発する(issue の実測:
      #     3日差の分岐で571ファイル)。値ではなく対象範囲の問題であり解決しない。
      #   - CHERRY_PICK_HEAD/REVERT_HEAD も同様に除外する: これらは(マージと違い)分割可能
      #     ——閾値超過時に「一部を unstage して分けてコミットする」という(H-2a)の指示が
      #     実行可能なまま残る。マージ固有の「指示が原理的に実行不能」という強い理由が
      #     無いため、今回は対象を MERGE_HEAD だけに絞る。
      _scs_is_merge=""
      git -C "$_scs_dir" "${_scs_gitdiropt[@]+"${_scs_gitdiropt[@]}"}" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && _scs_is_merge=1

      # マージ中は「マージ自身が持ち込む差分」だけを閾値の対象から外し、それ以外の
      # staged(マージと無関係な一括 `git add`)は引き続き検知する。免除の粒度をマージ
      # 進行中フラグ一本にすると、マージ中に無関係な大量ステージを追加しても丸ごと
      # 素通りしてしまう(一次レビューで実測: 正当なマージ(差分5ファイル)に無関係な
      # 350ファイルを追加ステージしても block されないことを確認)。
      #
      # 「マージ自身が持ち込む差分」の計算: マージ進行中に何も追加ステージしていない
      # 状態で `git diff --staged --name-only` に現れるファイルは、マージ相手
      # (MERGE_HEAD)が merge-base から変更したファイルの集合と一致する(HEAD 側だけが
      # 変更したファイルは、マージでは HEAD の内容のまま index に入るため index と HEAD
      # の間に差分が生じず、そもそも staged 一覧に現れない)。したがって
      # `git diff --name-only <merge-base> <MERGE_HEAD の各コミット>` の和集合を
      # 「マージが持ち込む範囲」とみなし、実際の staged 一覧からこの範囲を差し引いた
      # 残りだけを閾値判定の対象にする。競合解消で手動編集した内容が両親のどちらとも
      # 一致しなくても、そのファイル自体は「両親のどちらかが merge-base から変更した」
      # 集合に含まれるため、この計算から漏れない。
      #
      # octopus マージ(3つ以上の親)では `.git/MERGE_HEAD` に複数行(各追加の親のコミット
      # id)が入る。`git rev-parse --verify MERGE_HEAD` は先頭行しか返さないため、この
      # 計算では `--absolute-git-dir` で解決した実ファイルを直接読んで全行を拾う。
      #
      # 計算失敗の扱い: `merge-base` は共通祖先を持たない履歴(例:
      # `--allow-unrelated-histories` によるマージ)では失敗する(実機確認: exit 1・
      # 出力なし)。計算が失敗すると `_scs_mh_expected` にその親の分の差分が入らず、結果と
      # して staged 全件が「マージと無関係」として扱われ block されうる。倒れる向きは
      # 安全側(見逃すより誤って止める方へ倒れる)だが、この block が「正当な一括ステージを
      # 検知した」のか「差分の計算そのものが失敗した」のかは、`_scs_scan_count` だけを
      # 見ても区別できない。マージが分割不能なコミットである以上、マージ中に詰んだのに
      # 指示どおりの対処ができない状態は避けたいので、狭い条件とはいえ同じ状態へ気づけない
      # まま戻ることは避ける。`_scs_mh_calc_failed` に計算失敗の事実を残し、block
      # メッセージで両者を区別する。
      _scs_mh_expected=""
      _scs_mh_calc_failed=""
      if [ -n "${_scs_is_merge:-}" ] && [ "${_scs_count:-0}" -gt 0 ] 2>/dev/null; then
        _scs_mh_gitdir="$(git -C "$_scs_dir" "${_scs_gitdiropt[@]+"${_scs_gitdiropt[@]}"}" rev-parse --absolute-git-dir 2>/dev/null)" || true
        if [ -n "${_scs_mh_gitdir:-}" ] && [ -f "$_scs_mh_gitdir/MERGE_HEAD" ]; then
          while IFS= read -r _scs_mh_parent; do
            [ -n "${_scs_mh_parent:-}" ] || continue
            if _scs_mh_base="$(git -C "$_scs_dir" "${_scs_gitdiropt[@]+"${_scs_gitdiropt[@]}"}" merge-base HEAD "$_scs_mh_parent" 2>/dev/null)" && [ -n "${_scs_mh_base:-}" ]; then
              if _scs_mh_diff="$(git -C "$_scs_dir" "${_scs_gitdiropt[@]+"${_scs_gitdiropt[@]}"}" diff --name-only "$_scs_mh_base" "$_scs_mh_parent" 2>/dev/null)"; then
                [ -n "${_scs_mh_diff:-}" ] && _scs_mh_expected="${_scs_mh_expected:+$_scs_mh_expected$'\n'}$_scs_mh_diff"
              else
                _scs_mh_calc_failed=1
              fi
            else
              _scs_mh_calc_failed=1
            fi
          done < "$_scs_mh_gitdir/MERGE_HEAD"
        else
          # MERGE_HEAD があるはず(_scs_is_merge=1)なのに git-dir 解決やファイル読み取りが
          # できない=想定外の状態。計算失敗として扱う(fail-safe: 全 staged を「無関係」と
          # みなす側に倒しつつ、その旨をメッセージで区別できるようにする)。
          _scs_mh_calc_failed=1
        fi
      fi

      # マージ範囲を差し引いた後の staged 件数(マージ中でなければ元の全件数と同じ)。
      # `_scs_mh_expected` が空(マージ中でない・MERGE_HEAD が読めない等の fail-safe 経路
      # を含む)なら grep -f には何もパターンが無く、全 staged ファイルがそのまま
      # 「マージと無関係」として残る=従来どおりの閾値判定に自然に帰着する。
      _scs_scan_files="$_scs_files"
      if [ -n "${_scs_mh_expected:-}" ]; then
        _scs_scan_files="$(printf '%s\n' "$_scs_files" | grep -Fxv -f <(printf '%s\n' "$_scs_mh_expected") 2>/dev/null)" || true
      fi
      _scs_scan_count=0
      if [ -n "${_scs_scan_files:-}" ]; then
        _scs_scan_count=$(printf '%s\n' "$_scs_scan_files" | grep -c '[^[:space:]]') || true
      fi

      # --- (H-2a) staged 件数の閾値(マージ中はマージが持ち込んだ分を除いた件数で判定) ---
      if [ "${_scs_scan_count:-0}" -gt "$SCS_MAX_STAGED_FILES" ] 2>/dev/null; then
        if [ -n "${_scs_mh_calc_failed:-}" ]; then
          block "マージ進行中(MERGE_HEAD あり)ですが、マージが持ち込んだ差分の計算に失敗したため(共通の祖先を持たない履歴のマージ等が原因でありえます)、staged されたファイルをすべて「マージと無関係」とみなして数えたところ閾値(${SCS_MAX_STAGED_FILES})を超えました(${_scs_scan_count}件)。これは正当な一括ステージの誤検知ではなく、差分計算自体が失敗した際のフェイルセーフです。マージが正当であれば、この計算の失敗そのものを報告してください(unstage しての回避は本来不要な操作です)。${NO_BYPASS_MSG}" "commit_staged_count_threshold"
        elif [ -n "${_scs_is_merge:-}" ]; then
          block "マージ進行中(MERGE_HEAD あり)ですが、マージが持ち込んだ差分を除いても staged されたファイル数(${_scs_scan_count})が閾値(${SCS_MAX_STAGED_FILES})を超えています。マージと無関係な一括ステージの可能性があります。'git reset HEAD <path>...' でマージと無関係な分を unstage してから再度コミットしてください。${NO_BYPASS_MSG}" "commit_staged_count_threshold"
        else
          block "staged されたファイル数(${_scs_scan_count})が閾値(${SCS_MAX_STAGED_FILES})を超えています。意図しない一括ステージの可能性があります。'git reset HEAD <path>...' で一部を unstage し、閾値以下の単位に分けてコミットしてください。${NO_BYPASS_MSG}" "commit_staged_count_threshold"
        fi
        continue
      fi

      # --- (H-2b) staged 内容の secret パターンスキャン(追加行のみ) ---
      if [ "${_scs_count:-0}" -gt 0 ] 2>/dev/null && [ -n "${SECRET_PATTERNS+x}" ]; then
        _scs_diff="$(git -C "$_scs_dir" "${_scs_gitdiropt[@]+"${_scs_gitdiropt[@]}"}" diff --staged --unified=0 2>/dev/null)" || true
        _scs_added="$(printf '%s\n' "${_scs_diff:-}" | grep -E '^\+[^+]')" || true
        _scs_hit=""
        if [ -n "${_scs_added:-}" ]; then
          for _scs_pat in "${SECRET_PATTERNS[@]}"; do
            if printf '%s\n' "$_scs_added" | grep -E -- "$_scs_pat" >/dev/null 2>/dev/null; then _scs_hit=1; break; fi
          done
          if [ -z "${_scs_hit:-}" ] && [ -n "${SECRET_PEM_PATTERN:-}" ]; then
            printf '%s\n' "$_scs_added" | grep -E -- "$SECRET_PEM_PATTERN" >/dev/null 2>/dev/null && _scs_hit=1
          fi
        fi
        if [ -n "${_scs_hit:-}" ]; then
          # 一致した内容そのものは出さない: どのファイルが一致したかだけを個別に特定する
          # (全体で一致ありと分かってからのみファイル単位に絞り込むため、通常(一致なし)の
          # コミットでは per-file の追加 git 呼び出しは発生しない)。
          _scs_hit_files=""
          _scs_hit_count=0
          while IFS= read -r _scs_f; do
            [ -n "${_scs_f:-}" ] || continue
            _scs_fdiff="$(git -C "$_scs_dir" "${_scs_gitdiropt[@]+"${_scs_gitdiropt[@]}"}" diff --staged --unified=0 -- "$_scs_f" 2>/dev/null | grep -E '^\+[^+]')" || true
            _scs_fmatch=""
            if [ -n "${_scs_fdiff:-}" ]; then
              for _scs_pat in "${SECRET_PATTERNS[@]}"; do
                if printf '%s\n' "$_scs_fdiff" | grep -E -- "$_scs_pat" >/dev/null 2>/dev/null; then _scs_fmatch=1; break; fi
              done
              if [ -z "${_scs_fmatch:-}" ] && [ -n "${SECRET_PEM_PATTERN:-}" ]; then
                printf '%s\n' "$_scs_fdiff" | grep -E -- "$SECRET_PEM_PATTERN" >/dev/null 2>/dev/null && _scs_fmatch=1
              fi
            fi
            if [ -n "${_scs_fmatch:-}" ]; then
              _scs_hit_count=$((_scs_hit_count+1))
              _scs_hit_files="${_scs_hit_files:+$_scs_hit_files, }$_scs_f"
            fi
          done <<< "$_scs_files"
          block "staged 内容に secret パターンへの一致を検出しました(${_scs_hit_count} 件: ${_scs_hit_files})。一致した内容そのものは表示していません。該当ファイルから secret を取り除いて git add し直してから再度コミットしてください。${NO_BYPASS_MSG}" "commit_secret_scan"
        fi
      fi
      ;;
  esac
done <<< "${_scs_segs:-}"
fi

# --- (J) 既定ブランチ/main 等の保護ブランチへの直接 git commit をブロック ---
# 背景: CLAUDE.md は「既定ブランチ/main へ直接コミットしない(作業ブランチ→PR経由)」と明記するが、
# これは規約(読んで守る前提)であって guard.sh による機械的な遮断ではなかった。実際に、統制側が
# harness update 後の生成物差分を、作業ブランチを切らず既定ブランチへ直接 commit & push して
# しまう事故が発生した(内容自体は低リスクで実害は無かったが、規約違反そのものは防げなかった)。
#
# 検出: (A) 節(git commit --no-verify バイパス防止)が持つ awk トークナイザ判定と同じロジックの
# 実体である _scs_analyze_commit((H) セッション層コミットスキャン節で定義済み。本節では書き換えず
# そのまま呼ぶ)を再利用し、セグメントが「git [グローバルオプション] commit」の形かを判定する。
# 新しい抽出方式は作らない。
#
# 対象リポジトリの決定: (H) 節と同じ考え方(hook 入力の cwd を基点に、`cd`/`pushd` によるセグメント
# 間のディレクトリ変更を追跡して基点を更新した上で、コマンドラインの -C/--git-dir、無ければ
# GIT_DIR/GIT_WORK_TREE の env 代入プレフィックスを優先する)を踏襲する。
# extract_git_env_target/get_cwd/wt_cd_target_for_segment は (H) 節の外(本ファイル前方)で
# 定義された共有ヘルパーであり、(H) 節自体を書き換えずにそのまま呼べる。
#
# 保護ブランチ集合: lib/branch-protection.sh の BP_ALWAYS_PROTECTED(main/master固定)を参照する
# (値を重複定義しない。source は本ファイル冒頭(secret-patterns.sh 直後)で行い、この節では
# 読むだけ)。GitHub 既定ブランチは lib/base-branch.sh の bb_origin_head(origin/HEAD の指す先。
# `/` を含む名前も丸ごと)で取得できる場合のみ追加で判定する。取得できない場合(ref 未設定な clone・origin remote 無し等)は
# この判定をスキップし、main/master 固定判定のみを適用する fail-open な best-effort とする
# ((H) 節「対象を特定できない場合は走査をスキップする」と同じ位置づけ)。
#
# 解除の手段は無い(本ファイル冒頭を参照)。
#
# known-gap: セグメント検出・対象リポジトリ決定は (A)/(H) と同じ経路を通るため、それらが
# 既に抱える known-gap(strip_shell_keywords/strip_command_prefix/fold_quotes_and_heredocs
# 定義直前のコメント参照)をそのまま継承する。本節固有の追加 known-gap は無い。
if printf '%s' "$cmd" | grep -E '(^|[^A-Za-z0-9_])commit([^A-Za-z0-9_]|$)' >/dev/null; then
  _bpc_folded=$(printf '%s' "$cmd" | fold_quotes_and_heredocs) || true
  _bpc_segs=$(printf '%s' "${_bpc_folded:-}" | tr ';|&' '\n\n\n') || true
  # セグメント間で "現在のディレクトリ" を持ち回る状態(cd/pushd 追跡用。(H) 節の同名変数
  # ($_scs_cur)と同じ役割・wt_cd_target_for_segment 定義直前のコメント参照)。
  _bpc_cur="$(get_cwd "$input")"
  while IFS= read -r _bpc_seg; do
    case "${_bpc_seg:-}" in *[![:space:]]*) : ;; *) continue ;; esac
    _bpc_seg_kw="$(printf '%s' "${_bpc_seg:-}" | strip_shell_keywords)" || true
    _bpc_seg_sh="$(printf '%s' "${_bpc_seg_kw:-}" | strip_command_prefix)" || true

    # cd/pushd によるディレクトリ変更を追跡する((H) 節と同じロジック。wt_cd_target_for_segment
    # 定義直前のコメント参照)。cd/pushd セグメント自身は git commit ではないので、状態を
    # 更新したら次のセグメントへ進む。
    _bpc_cd_result="$(wt_cd_target_for_segment "${_bpc_seg_sh:-}" "${_bpc_cur:-}")"
    case "$_bpc_cd_result" in
      CD\|*) _bpc_cur="${_bpc_cd_result#CD|}"; continue ;;
    esac

    _bpc_result="$(_scs_analyze_commit "${_bpc_seg_sh:-}")"
    case "${_bpc_result:-}" in
      COMMIT\|*)
        IFS='|' read -r _bpc_tag _bpc_all _bpc_path _bpc_cdir _bpc_gitdir <<< "$_bpc_result"

        # GIT_DIR/GIT_WORK_TREE の env 代入プレフィックスを拾う(コマンドライン明示の
        # -C/--git-dir が既にあればそちらを優先し、無い場合のみこの env 値を使う。
        # extract_git_env_target 定義直前のコメント参照)。
        _bpc_env_result="$(printf '%s' "${_bpc_seg_kw:-}" | extract_git_env_target)" || true
        _bpc_env_gd="${_bpc_env_result%%|*}"
        _bpc_env_gwt="${_bpc_env_result#*|}"
        # $_bpc_cur は上の cd/pushd 追跡で更新済みの「現在のディレクトリ」(cd が無い場合は
        # hook 入力の cwd のまま=従来どおりの get_cwd と同じ値)。
        _bpc_cwd="${_bpc_cur:-}"

        _bpc_dir=""
        if [ -n "${_bpc_cdir:-}" ]; then
          case "$_bpc_cdir" in
            /*) _bpc_dir="$_bpc_cdir" ;;
            *)  _bpc_dir="${_bpc_cwd:+$_bpc_cwd/}$_bpc_cdir" ;;
          esac
        elif [ -n "${_bpc_env_gwt:-}" ]; then
          case "$_bpc_env_gwt" in
            /*) _bpc_dir="$_bpc_env_gwt" ;;
            *)  _bpc_dir="${_bpc_cwd:+$_bpc_cwd/}$_bpc_env_gwt" ;;
          esac
        elif [ -n "${_bpc_cwd:-}" ]; then
          _bpc_dir="$_bpc_cwd"
        fi
        # cwd も -C も得られない場合は対象を特定できないため走査をスキップする(fail-open)。
        [ -n "${_bpc_dir:-}" ] || continue

        _bpc_gitdir_eff="${_bpc_gitdir:-}"
        [ -n "${_bpc_gitdir_eff:-}" ] || _bpc_gitdir_eff="${_bpc_env_gd:-}"
        _bpc_gitdiropt=()
        [ -n "${_bpc_gitdir_eff:-}" ] && _bpc_gitdiropt=(--git-dir="$_bpc_gitdir_eff")

        # git 自体が使えない/対象が git リポジトリでない場合も fail-open する(このとき実際の
        # git commit 自体もどのみち失敗するため実害は無い。(H) 節と同じ判断)。
        _bpc_branch="$(git -C "$_bpc_dir" "${_bpc_gitdiropt[@]+"${_bpc_gitdiropt[@]}"}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || true
        [ -n "${_bpc_branch:-}" ] || continue

        _bpc_protected=""
        # BP_ALWAYS_PROTECTED は lib/branch-protection.sh の source に失敗すると未定義のまま
        # 残りうる(本ファイル冒頭の source が fail-open のため)。set -u 下で未定義配列を直接
        # 展開すると script が落ちるため、${VAR+x} で存在確認してから展開する。
        if [ -n "${BP_ALWAYS_PROTECTED+x}" ]; then
          for _bpc_fixed in "${BP_ALWAYS_PROTECTED[@]}"; do
            [ "$_bpc_branch" = "$_bpc_fixed" ] && _bpc_protected=1
          done
        fi

        if [ -z "${_bpc_protected:-}" ]; then
          _bpc_default_branch="$(bb_origin_head "$_bpc_dir" "${_bpc_gitdir_eff:-}")" || true
          if [ -n "${_bpc_default_branch:-}" ]; then
            [ "$_bpc_branch" = "$_bpc_default_branch" ] && _bpc_protected=1
          fi
        fi

        if [ -n "${_bpc_protected:-}" ]; then
          block "保護ブランチ('${_bpc_branch}')へ直接 git commit しようとしています。作業ブランチを切ってからコミットしてください: 'git checkout -b <type>/<name>' → 変更をコミット → PR を作成。${NO_BYPASS_MSG}" "commit_protected_branch"
        fi
        ;;
    esac
  done <<< "${_bpc_segs:-}"
fi

exit 0
