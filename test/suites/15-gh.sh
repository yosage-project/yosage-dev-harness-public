echo "== scratch.sh =="
bash "$H/lib/scratch.sh" >/dev/null 2>&1;        exit_is "コマンド無しは usage エラー" 2 "$?"
bash "$H/lib/scratch.sh" --help >/dev/null 2>&1; exit_is "--help は exit 0"           0 "$?"

echo "== gh-review.sh: PR レビューを1回の review 送信にまとめるラッパー =="
# 実 gh を叩かず、PATH 上のスタブ gh(引数を argv.log へ・stdin を stdin.log へ記録)で検証する。
ghrbin="$(mktemp -d)"; ghrlog="$(mktemp -d)"
cat > "$ghrbin/gh" <<'GHSTUB'
#!/usr/bin/env bash
# self-authored フォールバックの検証用に、gh api のサブコマンドで応答を出し分ける:
#   api user            -> 認証ユーザの login を返す(GHR_STUB_LOGIN。既定は非対称な "ghr-actor")
#   api .../pulls/<n>    -> PR 作成者の login を返す(GHR_STUB_AUTHOR。既定は非対称な "ghr-other")
#   api .../pulls/<n>/reviews -> 従来どおり argv/stdin を記録する(review 投稿)
# api .../pulls/<n>/comments -> 返信の投稿先。argv/stdin を記録する。GHR_STUB_COMMENTS_FAIL=1
#     を立てると、review comment id 以外への返信(GitHub API がエラーを返すケース)を模して非ゼロ終了する。
# api graphql -> resolve(でページング対応)用。引数中に "resolveReviewThread" を含めば
#     mutation 呼び出し、含まなければ(reviewThreads を引く) thread id 解決の query 呼び出しとみなす。
#     呼び出し種別を $GHR_GRAPHQL_LOG へ1行("lookup"/"mutation")追記する(呼び出し回数の検証用)。
#     $GHR_GRAPHQL_ARGV_LOG を指定すると、呼び出しごとの全引数(1行・空白区切り)も追記する
#     (pageSize 等、実際に渡された値の検証用)。
#     query: 引数中の "cursor=null"(1ページ目)/ "cursor=<値>"(2ページ目以降)からページ番号を判定する。
#       - GHR_STUB_MULTI_PAGE=1 のとき、1ページ目は hasNext=true・endCursor=$GHR_STUB_NEXT_CURSOR
#         (既定 PAGE2CURSOR)を返し、cursor=$GHR_STUB_NEXT_CURSOR で呼ばれた2ページ目は hasNext=false
#         を返す(2ページに跨る走査を模す)。GHR_STUB_SAFETY_LOOP=1 のときは常に hasNext=true・
#         endCursor=LOOP を返し続ける(安全上限ページ数への到達を模す)。どちらも指定しなければ
#         1ページ目で hasNext=false(従来どおり単一ページ)。
#       - 引数中に ".databaseId == ${GHR_STUB_THREAD_COMMENT_ID}" を含み、かつ現在のページ番号が
#         $GHR_STUB_MATCH_PAGE(既定 1)と一致すれば found に $GHR_STUB_THREAD_NODE_ID(既定 PRRT_stub)
#         を入れる(実 gh --jq の select 一致を模す。ページ不一致なら見つからない扱い)。
#       - GHR_STUB_INNER_CAP=1 で innerCap:true を返す(スレッド内コメント一覧が上限に達している
#         スレッドがあった、を模す)。
#       - GHR_STUB_GRAPHQL_LOOKUP_FAIL=1 で非ゼロ終了(権限不足等の模擬)。
#     mutation: GHR_STUB_GRAPHQL_MUTATION_FAIL=1 で非ゼロ終了(権限不足等の模擬)。
#       成功時は $GHR_STUB_MUTATION_ISRESOLVED(既定 true)を1行出力する。
#   repo view --json owner,name -> --repo 未指定時の owner/repo 解決先。GHR_STUB_REPO_VIEW_FAIL=1 で
#     非ゼロ終了。既定は owner=stub-owner, name=stub-repo。
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  if [ "${GHR_STUB_REPO_VIEW_FAIL:-0}" = "1" ]; then
    echo "stub: gh repo view failed" >&2
    exit 1
  fi
  printf '{"name":"%s","owner":{"login":"%s"}}\n' "${GHR_STUB_REPO_VIEW_NAME:-stub-repo}" "${GHR_STUB_REPO_VIEW_OWNER:-stub-owner}"
  exit 0
fi
if [ "$1" = "api" ]; then
  case "$2" in
    user)
      if [ "${GHR_STUB_USER_FAIL:-0}" = "1" ]; then
        exit 1
      fi
      printf '{"login":"%s"}\n' "${GHR_STUB_LOGIN:-ghr-actor}"
      exit 0
      ;;
    */pulls/*/reviews)
      printf '%s\n' "$@" > "$GHR_ARGV_LOG"
      cat > "$GHR_STDIN_LOG"
      exit 0
      ;;
    */pulls/*/comments)
      if [ "${GHR_STUB_COMMENTS_FAIL:-0}" = "1" ]; then
        cat >/dev/null
        echo '{"message":"Unprocessable Entity"}' >&2
        exit 1
      fi
      printf '%s\n' "$@" > "$GHR_ARGV_LOG"
      cat > "$GHR_STDIN_LOG"
      exit 0
      ;;
    */pulls/*)
      if [ "${GHR_STUB_AUTHOR_FAIL:-0}" = "1" ]; then
        exit 1
      fi
      printf '{"user":{"login":"%s"}}\n' "${GHR_STUB_AUTHOR:-ghr-other}"
      exit 0
      ;;
    graphql)
      if [ -n "${GHR_GRAPHQL_ARGV_LOG:-}" ]; then
        printf '%s\n' "$*" >> "$GHR_GRAPHQL_ARGV_LOG"
      fi
      is_mutation=0
      for a in "$@"; do
        case "$a" in
          *resolveReviewThread*) is_mutation=1 ;;
        esac
      done
      if [ "$is_mutation" = "1" ]; then
        printf 'mutation\n' >> "${GHR_GRAPHQL_LOG:-/dev/null}"
        if [ "${GHR_STUB_GRAPHQL_MUTATION_FAIL:-0}" = "1" ]; then
          echo '{"errors":[{"message":"stub mutation failure"}]}' >&2
          exit 1
        fi
        printf '%s\n' "${GHR_STUB_MUTATION_ISRESOLVED:-true}"
        exit 0
      else
        printf 'lookup\n' >> "${GHR_GRAPHQL_LOG:-/dev/null}"
        if [ "${GHR_STUB_GRAPHQL_LOOKUP_FAIL:-0}" = "1" ]; then
          echo '{"errors":[{"message":"stub lookup failure"}]}' >&2
          exit 1
        fi
        # cursor=null(1ページ目) / cursor=<値>(2ページ目以降)からページ番号を判定する。
        page_no=0
        cursor_val=""
        for a in "$@"; do
          case "$a" in
            cursor=null) page_no=1 ;;
            cursor=*) cursor_val="${a#cursor=}" ;;
          esac
        done
        if [ "$page_no" != "1" ] && [ -n "$cursor_val" ] && [ "$cursor_val" = "${GHR_STUB_NEXT_CURSOR:-PAGE2CURSOR}" ]; then
          page_no=2
        fi
        match=0
        for a in "$@"; do
          case "$a" in
            *".databaseId == ${GHR_STUB_THREAD_COMMENT_ID:-__none__}"*) match=1 ;;
          esac
        done
        found="null"
        if [ "$match" = "1" ] && [ "$page_no" = "${GHR_STUB_MATCH_PAGE:-1}" ]; then
          found="\"${GHR_STUB_THREAD_NODE_ID:-PRRT_stub}\""
        fi
        if [ "${GHR_STUB_SAFETY_LOOP:-0}" = "1" ]; then
          has_next="true"; end_cursor="LOOP"
        elif [ "${GHR_STUB_MULTI_PAGE:-0}" = "1" ] && [ "$page_no" = "1" ]; then
          has_next="true"; end_cursor="${GHR_STUB_NEXT_CURSOR:-PAGE2CURSOR}"
        else
          has_next="false"; end_cursor=""
        fi
        inner_cap="${GHR_STUB_INNER_CAP:-false}"
        printf '{"found":%s,"hasNext":%s,"endCursor":"%s","innerCap":%s}\n' \
          "$found" "$has_next" "$end_cursor" "$inner_cap"
        exit 0
      fi
      ;;
  esac
fi
printf '%s\n' "$@" > "$GHR_ARGV_LOG"
cat > "$GHR_STDIN_LOG"
GHSTUB
chmod +x "$ghrbin/gh"

_ghr_json='{"body":"サマリ本文","event":"COMMENT","comments":[{"path":"a.py","line":12,"body":"🔴 Must / 客観的欠陥: 例1"},{"path":"b.py","line":3,"body":"🟢 Nit / 価値トレードオフ: 例2"}]}'

: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_json" | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>&1
exit_is "gh-review.sh: stdin 経由の投稿は exit 0" 0 "$?"
_ghr_argv="$(cat "$ghrlog/argv.log" 2>/dev/null)"
out_has "gh-review.sh: gh api を呼ぶ" "api" "$_ghr_argv"
out_has "gh-review.sh: repos/{owner}/{repo}/pulls/123/reviews を叩く" "repos/{owner}/{repo}/pulls/123/reviews" "$_ghr_argv"
out_has "gh-review.sh: --input - でJSONをstdin投入する(1回の呼び出し)" "--input" "$_ghr_argv"
_ghr_stdin="$(cat "$ghrlog/stdin.log" 2>/dev/null | tr -d '\n' | sed -E 's/[[:space:]]+/ /g')"
out_has "gh-review.sh: body(サマリ)を含む"        "サマリ本文" "$_ghr_stdin"
out_has "gh-review.sh: comments[].path を含む"    '"path": "a.py"' "$_ghr_stdin"
out_has "gh-review.sh: comments[].line を含む"    '"line": 12' "$_ghr_stdin"
out_has "gh-review.sh: comments[].body(欠陥/トレードオフラベル込み)を含む" "客観的欠陥" "$_ghr_stdin"
if [ "$(printf '%s' "$_ghr_argv" | grep -c '^api$')" = "1" ]; then ok "gh-review.sh: gh 呼び出しは1回(1回の review 送信)"; else ng "gh-review.sh: gh 呼び出しは1回のはずが複数/0回"; fi

# --repo 指定時は owner/repo をパスへ直接埋め込む(gh api に -R/--repo フラグは無い。)
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_json" | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --repo o/r >/dev/null 2>&1
_ghr_argv_repo="$(cat "$ghrlog/argv.log" 2>/dev/null)"
out_has   "gh-review.sh: --repo 指定時は repos/o/r/pulls/123/reviews をパスへ直接埋め込む" "repos/o/r/pulls/123/reviews" "$_ghr_argv_repo"
out_hasnt "gh-review.sh: --repo 指定時でも -R は渡さない(gh api に -R は無い)" "-R" "$_ghr_argv_repo"

# --repo 値の形式検証: owner/repo 形以外は gh api を呼ぶ前に非ゼロ終了で落ちる。
# 各ケースについて「gh を呼んでいない」ことも確認し、検証がエンドポイント結合の前で
# 止まっていることを担保する。
for _ghr_bad in "noslash" "a/b/c" "" "/bar" "foo/" "foo bar/baz" "foo/bar baz" "../foo" "foo/.." "owner/.."; do
  : > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
  printf '%s' "$_ghr_json" | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
    bash "$H/lib/gh-review.sh" 123 --repo "$_ghr_bad" >/dev/null 2>&1
  exit_is "gh-review.sh: --repo=[${_ghr_bad}](owner/repo形式外)は exit 1" 1 "$?"
  if [ -s "$ghrlog/argv.log" ]; then ng "gh-review.sh: --repo=[${_ghr_bad}]は形式検証で落ちて gh を呼ばない"; else ok "gh-review.sh: --repo=[${_ghr_bad}]は形式検証で落ちて gh を呼ばない"; fi
done

# 正しい owner/repo 形は従来どおり通る(非回帰)。
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_json" | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --repo foo/bar >/dev/null 2>&1
exit_is "gh-review.sh: --repo=foo/bar(正しいowner/repo形)は exit 0" 0 "$?"

# --repo 未指定時の挙動は不変(プレースホルダのまま gh api を呼ぶ)。
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_json" | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>&1
_ghr_argv_norepo="$(cat "$ghrlog/argv.log" 2>/dev/null)"
out_has "gh-review.sh: --repo 未指定時は repos/{owner}/{repo}/pulls/123/reviews のまま(不変)" "repos/{owner}/{repo}/pulls/123/reviews" "$_ghr_argv_norepo"

# --file 経由でも同様に投稿できる
_ghr_file="$(mktemp)"; printf '%s' "$_ghr_json" > "$_ghr_file"
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --file "$_ghr_file" >/dev/null 2>&1
exit_is "gh-review.sh: --file 経由の投稿は exit 0" 0 "$?"
out_has "gh-review.sh: --file 経由でも body を含む" "サマリ本文" "$(cat "$ghrlog/stdin.log" 2>/dev/null)"
rm -f "$_ghr_file"

# 異常系: PR番号無し・非数値は usage エラー(exit 1)
bash "$H/lib/gh-review.sh" >/dev/null 2>&1;        exit_is "gh-review.sh: PR番号無しは usage エラー" 1 "$?"
bash "$H/lib/gh-review.sh" abc >/dev/null 2>&1;     exit_is "gh-review.sh: 非数値PR番号は usage エラー" 1 "$?"
bash "$H/lib/gh-review.sh" 123 --file /no/such/file >/dev/null 2>&1
exit_is "gh-review.sh: 存在しない --file は exit 1" 1 "$?"

# event バリデーション: APPROVE はマージ人間ゲートの不変を守るため拒否する(レビュー指摘)。
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' '{"body":"x","event":"APPROVE","comments":[]}' | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>&1
exit_is "gh-review.sh: event=APPROVE は拒否(exit 1)" 1 "$?"
if [ -s "$ghrlog/argv.log" ]; then ng "gh-review.sh: APPROVE拒否時は gh を呼ばない"; else ok "gh-review.sh: APPROVE拒否時は gh を呼ばない"; fi

: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' '{"body":"x","event":"REQUEST_CHANGES","comments":[]}' | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>&1
exit_is "gh-review.sh: event=REQUEST_CHANGES は許可" 0 "$?"

: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' '{"body":"x","comments":[]}' | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>&1
exit_is "gh-review.sh: event省略時は既定COMMENTで許可" 0 "$?"

# self-authored 検出 ＋ 自動フォールバック: 投稿者自身が作成した PR に REQUEST_CHANGES
# で投稿すると GitHub API が 422 を返し投稿全体が無言に失われるため、event を COMMENT へ
# 自動フォールバックする。判定不能時も同じ理由で安全側フォールバック(投稿を通す)を選ぶ。
_ghr_json_rc='{"body":"サマリ本文","event":"REQUEST_CHANGES","comments":[{"path":"a.py","line":12,"body":"🔴 Must / 客観的欠陥: 例1"}]}'

# self-authored(認証ユーザ==PR作成者)+ REQUEST_CHANGES -> 実送信 event は COMMENT へ落ちる
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"; : > "$ghrlog/stderr.log"
printf '%s' "$_ghr_json_rc" | GHR_STUB_LOGIN="same-user" GHR_STUB_AUTHOR="same-user" \
  GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh: self-authored な REQUEST_CHANGES でも exit 0(フォールバックして投稿成立)" 0 "$?"
_ghr_stdin_rc="$(cat "$ghrlog/stdin.log" 2>/dev/null)"
out_has   "gh-review.sh: self-authored -> 実送信 event は COMMENT へフォールバック" '"event": "COMMENT"' "$_ghr_stdin_rc"
out_hasnt "gh-review.sh: self-authored -> REQUEST_CHANGES のままでは送らない"       '"event": "REQUEST_CHANGES"' "$_ghr_stdin_rc"
out_has   "gh-review.sh: self-authored フォールバックの理由を stderr に通知する"    "COMMENT" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# self-authored でない(認証ユーザ!=PR作成者)+ REQUEST_CHANGES -> REQUEST_CHANGES のまま送る
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_json_rc" | GHR_STUB_LOGIN="user-a" GHR_STUB_AUTHOR="user-b" \
  GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>&1
exit_is "gh-review.sh: 別ユーザ作成PRへの REQUEST_CHANGES は exit 0" 0 "$?"
out_has "gh-review.sh: self-authored でなければ REQUEST_CHANGES を維持" '"event": "REQUEST_CHANGES"' "$(cat "$ghrlog/stdin.log" 2>/dev/null)"

# 判定不能(gh api user が失敗) -> 安全側でCOMMENTへフォールバックして投稿を通す(無言喪失を避ける)
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"; : > "$ghrlog/stderr.log"
printf '%s' "$_ghr_json_rc" | GHR_STUB_USER_FAIL=1 \
  GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh: 判定不能(認証ユーザ取得失敗)でも exit 0(安全側フォールバックで投稿成立)" 0 "$?"
out_has "gh-review.sh: 判定不能(認証ユーザ取得失敗) -> COMMENTへ安全側フォールバック" '"event": "COMMENT"' "$(cat "$ghrlog/stdin.log" 2>/dev/null)"
out_has "gh-review.sh: 判定不能の理由を stderr に通知する" "判定に失敗" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# 判定不能(PR作成者の取得が失敗) -> 同様に安全側でCOMMENTへフォールバック
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"; : > "$ghrlog/stderr.log"
printf '%s' "$_ghr_json_rc" | GHR_STUB_AUTHOR_FAIL=1 \
  GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh: 判定不能(PR作成者取得失敗)でも exit 0(安全側フォールバックで投稿成立)" 0 "$?"
out_has "gh-review.sh: 判定不能(PR作成者取得失敗) -> COMMENTへ安全側フォールバック" '"event": "COMMENT"' "$(cat "$ghrlog/stdin.log" 2>/dev/null)"

# フォールバック再シリアライズ(.event = "COMMENT")が失敗した場合は非ゼロ終了する。
# 既存の payload 構築(:99-117)と同様、この上書きにもガードが要る。jq が壊れた/失敗する状況を
# 直接再現するのは難しいので、フォールバック呼び出し(引数が ".event = \"COMMENT\"" のとき)
# だけ失敗させ、他の呼び出しは実物の jq へ委譲する差し替え jq スタブで検証する。
_ghr_real_jq="$(command -v jq 2>/dev/null || true)"
if [ -n "$_ghr_real_jq" ]; then
  cat > "$ghrbin/jq" <<JQSTUB
#!/usr/bin/env bash
if [ "\$1" = '.event = "COMMENT"' ]; then
  echo "gh-review.sh test stub: forced jq failure for fallback re-serialize" >&2
  exit 1
fi
exec "$_ghr_real_jq" "\$@"
JQSTUB
  chmod +x "$ghrbin/jq"

  : > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"; : > "$ghrlog/stderr.log"
  printf '%s' "$_ghr_json_rc" | GHR_STUB_LOGIN="same-user" GHR_STUB_AUTHOR="same-user" \
    GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
    bash "$H/lib/gh-review.sh" 123 >/dev/null 2>"$ghrlog/stderr.log"
  exit_is "gh-review.sh: フォールバック再シリアライズ失敗(jq)時は非ゼロ終了する(空/不完全bodyをPOSTしない)" 1 "$?"
  if [ -s "$ghrlog/argv.log" ]; then
    ng "gh-review.sh: フォールバック再シリアライズ失敗(jq)時は gh api(reviews投稿)を呼ばない"
  else
    ok "gh-review.sh: フォールバック再シリアライズ失敗(jq)時は gh api(reviews投稿)を呼ばない"
  fi
  out_has "gh-review.sh: フォールバック再シリアライズ失敗(jq)時に理由をstderr通知" "再構築に失敗" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
  rm -f "$ghrbin/jq"
fi

# --reply-to: 既存レビュースレッドへの返信モード。
# 返信は review 投稿とは別エンドポイント(POST .../comments、in_reply_to 付き)へ変換される。
_ghr_reply_json='{"body":"訂正の返信本文"}'

: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_reply_json" | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --reply-to 999 >/dev/null 2>&1
exit_is "gh-review.sh --reply-to: 返信投稿は exit 0" 0 "$?"
_ghr_reply_argv="$(cat "$ghrlog/argv.log" 2>/dev/null)"
out_has "gh-review.sh --reply-to: repos/{owner}/{repo}/pulls/123/comments を叩く(reviewsではない)" "repos/{owner}/{repo}/pulls/123/comments" "$_ghr_reply_argv"
_ghr_reply_stdin="$(cat "$ghrlog/stdin.log" 2>/dev/null | tr -d '\n' | sed -E 's/[[:space:]]+/ /g')"
out_has "gh-review.sh --reply-to: body(返信本文)を含む" "訂正の返信本文" "$_ghr_reply_stdin"
out_has "gh-review.sh --reply-to: in_reply_to に返信先idを含む" '"in_reply_to": 999' "$_ghr_reply_stdin"
out_hasnt "gh-review.sh --reply-to: event は含めない(返信は review ではない)" '"event"' "$_ghr_reply_stdin"

# --repo 指定時は返信モードでも owner/repo をパスへ直接埋め込む(review モードと同じ扱い)。
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_reply_json" | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --reply-to 999 --repo o/r >/dev/null 2>&1
out_has "gh-review.sh --reply-to --repo: repos/o/r/pulls/123/comments をパスへ直接埋め込む" "repos/o/r/pulls/123/comments" "$(cat "$ghrlog/argv.log" 2>/dev/null)"

# --repo の owner/repo 形式検証は返信モードでも同じ扱い(gh api を呼ぶ前に非ゼロ終了で落ちる)。
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_reply_json" | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --reply-to 999 --repo noslash >/dev/null 2>&1
exit_is "gh-review.sh --reply-to: --repo=noslash(owner/repo形式外)は exit 1" 1 "$?"
if [ -s "$ghrlog/argv.log" ]; then ng "gh-review.sh --reply-to: --repo形式検証で落ちて gh を呼ばない"; else ok "gh-review.sh --reply-to: --repo形式検証で落ちて gh を呼ばない"; fi

# --reply-to は数値限定(review comment id 相当の形式検証)。
bash "$H/lib/gh-review.sh" 123 --reply-to abc >/dev/null 2>&1
exit_is "gh-review.sh: --reply-to が非数値なら usage エラー" 1 "$?"

# 返信モードで event が渡されたら無視せずエラーで終了する(受け入れ条件)。
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"; : > "$ghrlog/stderr.log"
printf '%s' '{"body":"x","event":"COMMENT"}' | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --reply-to 999 >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --reply-to: event 指定は exit 1(無視しない)" 1 "$?"
if [ -s "$ghrlog/argv.log" ]; then ng "gh-review.sh --reply-to: event 指定時は gh を呼ばない"; else ok "gh-review.sh --reply-to: event 指定時は gh を呼ばない"; fi
out_has "gh-review.sh --reply-to: event 指定エラーの理由を stderr に出す" "event" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# 返信先が review comment id でない場合(issue comment id 等): GitHub API 側がエラーを返す
# ケースを模し、成功したように見えず非ゼロ終了することを確認する(受け入れ条件)。
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_reply_json" | GHR_STUB_COMMENTS_FAIL=1 GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --reply-to 999 >/dev/null 2>&1
exit_is "gh-review.sh --reply-to: review comment id でない返信先は成功したように見えず非ゼロ終了する" 1 "$?"

# 既存の review 投稿(--reply-to 無し)の挙動・引数互換は変わらない(非回帰)。
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"
printf '%s' "$_ghr_json" | GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 >/dev/null 2>&1
exit_is "gh-review.sh: --reply-to 無しの既存 review 投稿は非回帰で exit 0" 0 "$?"
out_has "gh-review.sh: --reply-to 無しは従来どおり reviews エンドポイントを叩く(非回帰)" "repos/{owner}/{repo}/pulls/123/reviews" "$(cat "$ghrlog/argv.log" 2>/dev/null)"

# --resolve: 既存レビュースレッドの resolve モード。
# review comment id(REST) -> reviewThreads query でスレッド id 解決 -> resolveReviewThread
# mutation、という2回の GraphQL 呼び出しに変換される(返信の1回POSTとは別経路)。

# 正常系(--repo 指定): lookup 1回 + mutation 1回、成功メッセージに thread id を含む。
: > "$ghrlog/graphql.log"
GHR_STUB_THREAD_COMMENT_ID=555 GHR_STUB_THREAD_NODE_ID="PRRT_test1" GHR_GRAPHQL_LOG="$ghrlog/graphql.log" \
  PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 555 --repo o/r </dev/null >"$ghrlog/stdout.log" 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: 正常系は exit 0" 0 "$?"
out_has "gh-review.sh --resolve: 成功メッセージに解決した thread id を含む" "PRRT_test1" "$(cat "$ghrlog/stdout.log" 2>/dev/null)"
_ghr_resolve_graphql="$(cat "$ghrlog/graphql.log" 2>/dev/null)"
if [ "$(printf '%s' "$_ghr_resolve_graphql" | grep -c '^lookup$')" = "1" ] && [ "$(printf '%s' "$_ghr_resolve_graphql" | grep -c '^mutation$')" = "1" ]; then
  ok "gh-review.sh --resolve: GraphQL 呼び出しは lookup 1回 + mutation 1回(計2回。返信の1回POSTとは別経路)"
else
  ng "gh-review.sh --resolve: GraphQL 呼び出し回数が想定と異なる(記録: ${_ghr_resolve_graphql})"
fi

# --repo 未指定時は `gh repo view` 経由で owner/repo を解決してから成立する。
: > "$ghrlog/graphql.log"
GHR_STUB_REPO_VIEW_OWNER="stub-owner" GHR_STUB_REPO_VIEW_NAME="stub-repo" \
  GHR_STUB_THREAD_COMMENT_ID=777 GHR_STUB_THREAD_NODE_ID="PRRT_test2" GHR_GRAPHQL_LOG="$ghrlog/graphql.log" \
  PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 777 </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: --repo 未指定でも gh repo view 経由で成立する(exit 0)" 0 "$?"

# --repo 未指定時のリポジトリ解決(gh repo view)自体が失敗したら非ゼロ終了する。
GHR_STUB_REPO_VIEW_FAIL=1 PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 1 </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: gh repo view 失敗時は exit 1" 1 "$?"

# 存在しない id(スレッドが見つからない) -> 成功したように見えず非ゼロ終了する(受け入れ条件)。
PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 999 --repo o/r </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: 存在しない review comment id は exit 1" 1 "$?"
out_has "gh-review.sh --resolve: 存在しない id の理由を stderr に出す" "見つかりません" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# 権限不足(スレッド id 解決の GraphQL query 自体が失敗) -> 成功したように見えず非ゼロ終了する。
GHR_STUB_GRAPHQL_LOOKUP_FAIL=1 PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 1 --repo o/r </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: スレッド検索(GraphQL)失敗時は exit 1(権限不足等)" 1 "$?"

# 権限不足(resolveReviewThread mutation 自体が失敗) -> 成功したように見えず非ゼロ終了する。
GHR_STUB_THREAD_COMMENT_ID=1 GHR_STUB_THREAD_NODE_ID="PRRT_test3" GHR_STUB_GRAPHQL_MUTATION_FAIL=1 \
  PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 1 --repo o/r </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: resolveReviewThread(mutation)失敗時は exit 1(権限不足等)" 1 "$?"

# mutation の HTTP 応答は成功でも isResolved=true を確認できない場合は成功とみなさない(応答だけで判定しない)。
GHR_STUB_THREAD_COMMENT_ID=1 GHR_STUB_THREAD_NODE_ID="PRRT_test4" GHR_STUB_MUTATION_ISRESOLVED="false" \
  PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 1 --repo o/r </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: mutation 応答が isResolved=true でなければ exit 1" 1 "$?"

# resolve は冪等(実機観測: 既に resolved なスレッドへ resolveReviewThread を再度呼んでも
# isResolved:true のまま成功する。 実装時に実 PR で確認済み)。同じ入力への複数回呼び出しが
# いずれも成功することを、同じスタブ応答(isResolved:true)への複数回呼び出しで表す。
GHR_STUB_THREAD_COMMENT_ID=1 GHR_STUB_THREAD_NODE_ID="PRRT_test5" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 1 --repo o/r </dev/null >/dev/null 2>&1
exit_is "gh-review.sh --resolve: 冪等呼び出し1回目は exit 0" 0 "$?"
GHR_STUB_THREAD_COMMENT_ID=1 GHR_STUB_THREAD_NODE_ID="PRRT_test5" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 1 --repo o/r </dev/null >/dev/null 2>&1
exit_is "gh-review.sh --resolve: 冪等呼び出し2回目(既に resolve 済み相当)も exit 0" 0 "$?"

# --resolve は数値限定(review comment id 相当の形式検証)。
bash "$H/lib/gh-review.sh" 123 --resolve abc </dev/null >/dev/null 2>&1
exit_is "gh-review.sh: --resolve が非数値なら usage エラー" 1 "$?"

# --reply-to と --resolve は別モードなので同時指定を拒否する。
bash "$H/lib/gh-review.sh" 123 --reply-to 1 --resolve 2 </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh: --reply-to と --resolve の同時指定は exit 1" 1 "$?"
out_has "gh-review.sh: --reply-to/--resolve 同時指定エラーの理由を stderr に出す" "同時に指定できません" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# --resolve と --file の同時指定は黙って --file を無視せずエラーで終了する(一次レビュー指摘)。
# resolve モードは JSON 入力を取らないため、--file を渡しても何も読まれず無視されてしまう経路が
# あった。--reply-to への event キー混入と同じ理由(黙って無視すると呼び出し側が「指定した内容が
# 使われた」と誤認しうる)で、明示的にエラーにする。
_ghr_resolve_file="$(mktemp)"; printf '%s' '{"body":"無視されるはずの本文"}' > "$_ghr_resolve_file"
: > "$ghrlog/graphql.log"; : > "$ghrlog/stderr.log"
GHR_STUB_THREAD_COMMENT_ID=1 GHR_STUB_THREAD_NODE_ID="PRRT_test6" GHR_GRAPHQL_LOG="$ghrlog/graphql.log" \
  PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 1 --repo o/r --file "$_ghr_resolve_file" </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: --file 併用は exit 1(黙って無視しない)" 1 "$?"
out_has "gh-review.sh --resolve: --file 併用エラーの理由を stderr に出す" "--file を指定できません" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
if [ -s "$ghrlog/graphql.log" ]; then
  ng "gh-review.sh --resolve: --file 併用エラー時は GraphQL を呼ばない(usage 検証で先に落ちる)"
else
  ok "gh-review.sh --resolve: --file 併用エラー時は GraphQL を呼ばない(usage 検証で先に落ちる)"
fi
rm -f "$_ghr_resolve_file"

# --resolve は JSON 入力(stdin)を読まない(パイプ元が無くてもハングしない)。/dev/null を明示せず
# 呼んでも(このテストランナー自身の stdin を継承しても)完結することを、既存の </dev/null 付きの
# 各テストが実質的に示している(resolve 経路の中で cat 等の stdin 読み取りが行われないため)。

# --resolve: スレッド一覧のページング。
# 先頭ページに対象が無く、cursor で2ページ目まで辿って初めて見つかる状況を作り、
# 実際にページ境界(hasNextPage=true -> 次カーソルで再クエリ)を踏ませて確認する。
: > "$ghrlog/graphql.log"
GHR_STUB_MULTI_PAGE=1 GHR_STUB_THREAD_COMMENT_ID=888 GHR_STUB_THREAD_NODE_ID="PRRT_page2" GHR_STUB_MATCH_PAGE=2 \
  GHR_RESOLVE_PAGE_SIZE=2 GHR_GRAPHQL_LOG="$ghrlog/graphql.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 888 --repo o/r </dev/null >"$ghrlog/stdout.log" 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: 1ページ目に無く2ページ目で見つかる場合も exit 0(ページ境界を実際に跨いだ)" 0 "$?"
out_has "gh-review.sh --resolve: 2ページ目で解決した thread id を成功メッセージに含む" "PRRT_page2" "$(cat "$ghrlog/stdout.log" 2>/dev/null)"
_ghr_page_graphql="$(cat "$ghrlog/graphql.log" 2>/dev/null)"
if [ "$(printf '%s' "$_ghr_page_graphql" | grep -c '^lookup$')" = "2" ] && [ "$(printf '%s' "$_ghr_page_graphql" | grep -c '^mutation$')" = "1" ]; then
  ok "gh-review.sh --resolve: 2ページ分の lookup(計2回)+ mutation 1回を実際に呼んだ(1ページ目で打ち切っていない)"
else
  ng "gh-review.sh --resolve: ページングで期待した呼び出し回数にならない(記録: ${_ghr_page_graphql})"
fi

# 2ページ目にも対象が無ければ(hasNextPage=false で打ち切り)、通常どおり「見つかりません」で exit 1。
: > "$ghrlog/graphql.log"
GHR_STUB_MULTI_PAGE=1 GHR_STUB_THREAD_COMMENT_ID=999999 GHR_GRAPHQL_LOG="$ghrlog/graphql.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 42 --repo o/r </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: 全ページ走査しても見つからなければ exit 1" 1 "$?"
out_has "gh-review.sh --resolve: 全ページ走査後に見つからない場合も理由をstderrに出す" "見つかりません" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
_ghr_page_graphql2="$(cat "$ghrlog/graphql.log" 2>/dev/null)"
if [ "$(printf '%s' "$_ghr_page_graphql2" | grep -c '^lookup$')" = "2" ]; then
  ok "gh-review.sh --resolve: 見つからない場合も全2ページを走査してから諦める(1ページ目で誤って打ち切らない)"
else
  ng "gh-review.sh --resolve: 見つからない場合の走査ページ数が想定と異なる(記録: ${_ghr_page_graphql2})"
fi

# ページサイズは環境変数(GHR_RESOLVE_PAGE_SIZE / GHR_RESOLVE_COMMENT_PAGE_SIZE)で上書きできる
# (実際のGitHub側の上限=100件を検証で再現する代わりに、境界値そのものを小さくして同じ経路を通す)。
# gh へ実際に渡される pageSize/commentPageSize の値で、上書きが空振りしていないことを確認する。
: > "$ghrlog/graphql-argv.log"
GHR_RESOLVE_PAGE_SIZE=3 GHR_RESOLVE_COMMENT_PAGE_SIZE=5 GHR_STUB_THREAD_COMMENT_ID=1 GHR_STUB_THREAD_NODE_ID="PRRT_sizecheck" \
  GHR_GRAPHQL_ARGV_LOG="$ghrlog/graphql-argv.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 1 --repo o/r </dev/null >/dev/null 2>&1
out_has "gh-review.sh --resolve: GHR_RESOLVE_PAGE_SIZE の上書きが実際に gh へ渡る(pageSize=3)" "pageSize=3" "$(cat "$ghrlog/graphql-argv.log" 2>/dev/null)"
out_has "gh-review.sh --resolve: GHR_RESOLVE_COMMENT_PAGE_SIZE の上書きが実際に gh へ渡る(commentPageSize=5)" "commentPageSize=5" "$(cat "$ghrlog/graphql-argv.log" 2>/dev/null)"

# スレッド内コメント一覧(内側)は引き続きページングしない(で採らなかった側)。
# 上限に達しているスレッドが検出され、かつ見つからない場合は「id誤り」と区別できる専用メッセージになる。
GHR_STUB_INNER_CAP=1 PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 424242 --repo o/r </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: スレッド内コメント上限到達の疑いがあっても exit 1(成功したように見えない)" 1 "$?"
out_has "gh-review.sh --resolve: 上限到達の疑いは『id誤り』と断定しない専用メッセージ" "断定できません" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# 上限到達の疑いが無い(通常の)見つからないケースでは、上の専用メッセージを出さない
# (誤検知していないことの確認。上の2件のメッセージが常に同じ文言に丸められていないかの空振りチェック)。
PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 424242 --repo o/r </dev/null >/dev/null 2>"$ghrlog/stderr.log"
out_hasnt "gh-review.sh --resolve: 通常の見つからないケースでは『断定できません』を出さない(誤検知していない)" "断定できません" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# スレッド一覧の走査には安全弁(上限ページ数)があり、常に hasNextPage=true を返す異常応答でも
# 無限ループせず、通常の「見つからない」とは別の専用メッセージで exit 1 する(境界を実際に踏む)。
: > "$ghrlog/graphql.log"
GHR_STUB_SAFETY_LOOP=1 GHR_GRAPHQL_LOG="$ghrlog/graphql.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --resolve 1 --repo o/r </dev/null >/dev/null 2>"$ghrlog/stderr.log"
exit_is "gh-review.sh --resolve: 走査の安全上限に達したら無限ループせず exit 1" 1 "$?"
out_has "gh-review.sh --resolve: 安全上限到達の理由をstderrに出す(id誤りとは別扱い)" "安全上限" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
_ghr_safety_pages="$(cat "$ghrlog/graphql.log" 2>/dev/null | grep -c '^lookup$')"
if [ "$_ghr_safety_pages" -ge 2 ] && [ "$_ghr_safety_pages" -le 100 ]; then
  ok "gh-review.sh --resolve: 安全上限は有限回のページ走査で打ち切る(記録: ${_ghr_safety_pages}回)"
else
  ng "gh-review.sh --resolve: 安全上限のページ走査回数が想定外(記録: ${_ghr_safety_pages}回)"
fi

echo "== gh-review.sh: 組織境界の識別子の警告(ブロックしない・設定ファイルを使わない) =="
# 設定ファイルは使わず、git remote から自組織を動的に導出する。自組織 = 現在地から上へ辿って
# 見つかる、最も外側の git リポジトリの owner。実際のワークスペース構成(ワークスペースの
# リポジトリ自身がまず git リポジトリで、その配下=子ディレクトリにメンバーリポジトリが
# 同居する)を再現するフィクスチャで検証する(親ディレクトリの兄弟ではなく、子ディレクトリで
# あることが重要。 のレビューで判明した実装漏れ: 旧実装は「現在のリポジトリの親の兄弟」を
# 走査しており、実際のワークスペースでは何も拾えていなかった)。
# ワークスペース内には別 owner が所有するメンバーリポジトリ(受託構成での客先リポジトリ相当)も
# 同居させ、その owner が「自組織」へ誤って吸収されないこと(そのリポジトリへの投稿でも
# きちんと警告が出ること)を検証する。
ghi_ws="$(mktemp -d)"
(cd "$ghi_ws" && git init -q && git remote add origin git@github.com:ghi-acme/workspace-repo.git)
ghi_own="$ghi_ws/own-member"; ghi_other="$ghi_ws/other-member"
mkdir -p "$ghi_own" "$ghi_other"
(cd "$ghi_own" && git init -q && git remote add origin https://github.com/ghi-acme/own-member.git)
(cd "$ghi_other" && git init -q && git remote add origin https://github.com/ghi-client/other-member.git)

# 観測1: 自組織(同じ owner)への投稿では、本文に自組織の識別子が含まれていても警告しない。
: > "$ghrlog/stderr.log"
(cd "$ghi_own" && printf '%s' '{"body":"社内向け own-member の話","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo ghi-acme/workspace-repo >/dev/null 2>"$ghrlog/stderr.log")
out_hasnt "gh-review.sh: 自組織(同じowner)への投稿では識別子を含んでいても警告しない" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# 観測2(最重要・ で判明した穴の直接の回帰): 別 owner が所有するメンバーリポジトリ
# (ghi-client/other-member)への投稿では、本文に自組織(ghi-acme)の識別子が含まれていれば
# 警告が出る。旧実装はワークスペースに同居するリポジトリの owner を無差別に「自組織」として
# 拾っていたため、この宛先(ghi-client)も自組織の一員とみなされ、検査が丸ごと無効化されていた。
: > "$ghrlog/argv.log"; : > "$ghrlog/stdin.log"; : > "$ghrlog/stderr.log"
(cd "$ghi_own" && printf '%s' '{"body":"レビュー結果に ghi-acme の内部情報への言及があります","event":"COMMENT","comments":[]}' | \
  GHR_ARGV_LOG="$ghrlog/argv.log" GHR_STDIN_LOG="$ghrlog/stdin.log" PATH="$ghrbin:$PATH" \
  bash "$H/lib/gh-review.sh" 123 --repo ghi-client/other-member >/dev/null 2>"$ghrlog/stderr.log")
exit_is "gh-review.sh: 別ownerのメンバーリポジトリへの投稿に識別子を含んでいても exit 0(ブロックしない)" 0 "$?"
out_has "gh-review.sh: 別ownerのメンバーリポジトリへの投稿かつ識別子を含む本文は stderr に警告する(穴の回帰)" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
out_hasnt "gh-review.sh: 警告メッセージに一致した語そのものは出さない" "ghi-acme" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
out_has "gh-review.sh: 警告メッセージに投稿先(owner/repo)を含む" "ghi-client/other-member" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
if [ -s "$ghrlog/argv.log" ]; then ok "gh-review.sh: 警告があっても投稿は実行される(ブロックしない)"; else ng "gh-review.sh: 警告時に投稿が止まっている(ブロックしてはいけない)"; fi

# 観測3: 別 owner のメンバーリポジトリの「中で作業しているとき」(cwd がそのリポジトリ)も、
# そこへの投稿で警告が出る(cwd の owner が自組織へ吸収されない。自組織は cwd の owner ではなく
# 最も外側のリポジトリの owner で決まるため)。
: > "$ghrlog/stderr.log"
(cd "$ghi_other" && printf '%s' '{"body":"ghi-acme の話です","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo ghi-client/other-member >/dev/null 2>"$ghrlog/stderr.log")
out_has "gh-review.sh: 別ownerのメンバーリポジトリ内で作業していても、そこへの投稿で警告が出る(自組織へ吸収されない)" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# 観測3b(レビュー2巡目で判明した欠陥の回帰): cwd がワークスペースリポジトリ自身の
# ときも、自組織を導出できる。旧実装は最も外側のリポジトリの探索候補に自分自身を含めておらず、
# 上に他のリポジトリが無いと「外側のリポジトリなし」= 検査しないと扱っていたため、ワークスペース
# 管理者がまさに作業する位置(cwd = ワークスペースリポジトリ自身)で検査が丸ごと無効化されていた。
: > "$ghrlog/stderr.log"
(cd "$ghi_ws" && printf '%s' '{"body":"ghi-acme の内部情報を含む本文","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo ghi-client/other-member >/dev/null 2>"$ghrlog/stderr.log")
out_has "gh-review.sh: cwdがワークスペースリポジトリ自身でも、別ownerメンバーへの投稿で識別子を含む本文は警告する(レビュー2巡目の穴の回帰)" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
: > "$ghrlog/stderr.log"
(cd "$ghi_ws" && printf '%s' '{"body":"ghi-acme workspace-repo の話","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo ghi-acme/own-member >/dev/null 2>"$ghrlog/stderr.log")
out_hasnt "gh-review.sh: cwdがワークスペースリポジトリ自身のとき、自組織への投稿では警告しない" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# 観測4: 外部組織への投稿でも、本文に自組織の識別子が含まれていなければ警告しない
# (誤検知が実務を妨げないことの確認)。
: > "$ghrlog/stderr.log"
(cd "$ghi_own" && printf '%s' '{"body":"識別子を含まないクリーンな本文","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo external-org/ext-repo >/dev/null 2>"$ghrlog/stderr.log")
out_hasnt "gh-review.sh: 外部組織への投稿でも識別子を含まない本文は警告しない" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# --repo 未指定時(gh の暗黙解決で現在のリポジトリへ投稿する)は宛先が常に自分自身なので、
# 越境しようがなく警告しない。
: > "$ghrlog/stderr.log"
(cd "$ghi_own" && printf '%s' '{"body":"ghi-acme について書いた本文","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 >/dev/null 2>"$ghrlog/stderr.log")
out_hasnt "gh-review.sh: --repo 未指定時は暗黙に自分自身が宛先なので警告しない" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# サマリ本文だけでなく、インラインコメント本文(comments[].body)側の識別子も検出対象。
: > "$ghrlog/stderr.log"
(cd "$ghi_own" && printf '%s' '{"body":"サマリはクリーン","event":"COMMENT","comments":[{"path":"a.py","line":1,"body":"ghi-acme の内部ツール名を含むコメント"}]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo external-org/ext-repo >/dev/null 2>"$ghrlog/stderr.log")
out_has "gh-review.sh: インラインコメント本文に含まれる識別子も検出対象" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# --reply-to(返信モード)の本文も検出対象。
: > "$ghrlog/stderr.log"
(cd "$ghi_own" && printf '%s' '{"body":"弊社 ghi-acme の話です"}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --reply-to 999 --repo external-org/ext-repo >/dev/null 2>"$ghrlog/stderr.log")
out_has "gh-review.sh --reply-to: 返信本文の識別子も検出対象" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# 観測5: 単発構成(現在のリポジトリの上に他の git リポジトリが無い=ワークスペースを持たない)
# では、自分自身が「最も外側のリポジトリ」になる(特別分岐は無い)。したがって:
#   - 無関係な本文では警告しない(識別子が本文に無いため)。
#   - 自分自身への投稿(宛先owner=自分のowner)では、自分の名前を書いても警告しない
#     (従来と同じ結果になる)。
#   - 別組織への投稿で、本文に自分自身の名前が含まれていれば警告する(自分の組織の識別子を
#     他所へ出さない、という目的そのものであり、単発構成でも保護対象になる)。
ghi_solo_ws="$(mktemp -d)"; ghi_solo="$ghi_solo_ws/solo-repo"; mkdir -p "$ghi_solo"
(cd "$ghi_solo" && git init -q && git remote add origin git@github.com:solo-org/solo-repo.git)
: > "$ghrlog/stderr.log"
(cd "$ghi_solo" && printf '%s' '{"body":"何の関係もない文章です","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo other-org/x >/dev/null 2>"$ghrlog/stderr.log")
out_hasnt "gh-review.sh: 単発構成でも無関係な本文では警告しない" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
: > "$ghrlog/stderr.log"
(cd "$ghi_solo" && printf '%s' '{"body":"solo-repo の話です","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo solo-org/solo-repo >/dev/null 2>"$ghrlog/stderr.log")
out_hasnt "gh-review.sh: 単発構成でも自分自身への投稿では警告しない" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"
: > "$ghrlog/stderr.log"
(cd "$ghi_solo" && printf '%s' '{"body":"solo-repo の話です","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo other-org/x >/dev/null 2>"$ghrlog/stderr.log")
out_has "gh-review.sh: 単発構成では自分自身が最も外側になるため、別組織への投稿で自分の名前を書くと警告する(レビュー2巡目で修正)" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# git リポジトリの外(cwd がそもそも git 管理下にない)でも exit 0 のまま警告しない(fail open)。
ghi_nongit="$(mktemp -d)"
: > "$ghrlog/stderr.log"
(cd "$ghi_nongit" && printf '%s' '{"body":"ghi-acme について","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo other-org/x >/dev/null 2>"$ghrlog/stderr.log")
exit_is "gh-review.sh: git リポジトリの外でも exit 0(fail open)" 0 "$?"
out_hasnt "gh-review.sh: git リポジトリの外では警告しない(導出材料が無い)" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

# 設定ファイルを使わない(git remote から動的に導出する)ため、外側のリポジトリに remote が無く
# owner を導出できない場合は fail open で警告せず exit 0 のまま続行する(検出不能を理由に
# 投稿を止めない)。
ghi_norem_ws="$(mktemp -d)"
(cd "$ghi_norem_ws" && git init -q)
ghi_norem_member="$ghi_norem_ws/member"; mkdir -p "$ghi_norem_member"
(cd "$ghi_norem_member" && git init -q && git remote add origin git@github.com:ghi-acme/member.git)
: > "$ghrlog/stderr.log"
(cd "$ghi_norem_member" && printf '%s' '{"body":"ghi-acme の話","event":"COMMENT","comments":[]}' | \
  PATH="$ghrbin:$PATH" bash "$H/lib/gh-review.sh" 123 --repo other-org/x >/dev/null 2>"$ghrlog/stderr.log")
exit_is "gh-review.sh: 外側のリポジトリにremoteが無い場合もexit 0(fail open)" 0 "$?"
out_hasnt "gh-review.sh: 外側のリポジトリのremoteが解決できない場合は警告しない(誤検知しない)" "警告" "$(cat "$ghrlog/stderr.log" 2>/dev/null)"

rm -rf "$ghi_ws" "$ghi_solo_ws" "$ghi_nongit" "$ghi_norem_ws"

rm -rf "$ghrbin" "$ghrlog"

_pl_body="$(cat "$H/rules/pr-loop.md" 2>/dev/null)"
out_has  "pr-loop.md: レビュー投稿はラッパー(gh-review.sh)経由に一本化" "gh-review.sh" "$_pl_body"
out_hasnt "pr-loop.md: 生の gh api pulls/.../reviews 呼び出しを直接指示しない" "gh api repos/{owner}/{repo}/pulls" "$_pl_body"
out_has  "pr-loop.md: スレッド返信は --reply-to 経由に一本化" "--reply-to" "$_pl_body"
out_has  "pr-loop.md: 返信は冪等ではない旨を明記" "冪等" "$_pl_body"
out_has  "pr-loop.md: self-authored 時は COMMENT へ自動フォールバックする旨を明記" "自動フォールバックする" "$_pl_body"
out_has  "pr-loop.md: resolve は --resolve 経由に一本化" "--resolve" "$_pl_body"
out_hasnt "pr-loop.md: 生の gh api graphql コマンド例を直接指示しない" "gh api graphql -f query" "$_pl_body"

# 手順3(指摘対応): 対になった箇所の再走査とラウンド上限の扱い
out_has  "pr-loop.md: 修正した側が対になる箇所を再走査する旨を明記" "識別子の一致に頼らず再走査する" "$_pl_body"
out_has  "pr-loop.md: 識別子非依存の走査が要る理由(一般語での言及)を明記" "「どちらも」「両方」のような一般語で対象を指す記述に注意する" "$_pl_body"
out_has  "pr-loop.md: 3ラウンド目以降は継続可否を人へ上げる旨を明記" "3ラウンド目以降は、受信点がそのラウンドで出た内容を添えて継続可否を人へ上げる" "$_pl_body"
out_has  "pr-loop.md: 新しい欠陥が出ないラウンドが1回あれば閉じる旨を明記" "新しい欠陥が出ないラウンドが1回あれば、そこで閉じる" "$_pl_body"
out_has  "pr-loop.md: ラウンド上限の停滞扱いを agent-watchdog へ名前参照" "[[agent-watchdog]]" "$_pl_body"
out_hasnt "pr-loop.md: agent-watchdog のストール判定文言を再記述していない" "止まっていたら切る" "$_pl_body"
# 一次レビュー指摘対応: 「ラウンド」と agent-watchdog の再投入カウンタが別物であることを明記
out_has  "pr-loop.md: ラウンド(レビュー往復回数)と agent-watchdog の再投入カウンタが別物である旨を明記" "が無進捗時に数える再投入カウンタとは別物・別の閾値" "$_pl_body"
# 一次レビュー指摘対応: 新設2点がラベル分岐の枝ではなく対応全体に課される工程であることを明記
out_has  "pr-loop.md: 新設2点がラベル分岐の枝ではない旨を明記" "対応そのものに次の2点が課されている（ラベル分岐の枝ではない）" "$_pl_body"

echo "== gh-subissue-link.sh: Epic⇔Sub-issue リンク・Epic本文更新をこの1本に封じ込める(refactor) =="
# 実 gh を叩かず、PATH 上のスタブ gh(呼び出しを call.log へ・addSubIssue の結果を linked ファイルへ
# 反映)で検証する。addSubIssue mutation は「呼び出しが成功しても実際には紐づかない」ケースを
# GHS_LINK_FAIL_ONCE(1回だけ)/GHS_NEVER_LINK(常に)で再現し、検証クエリでの欠け再リンク
# ループ・ハードゲートの両方を実挙動に近い形でテストする。
gslbin="$(mktemp -d)"; gsldir="$(mktemp -d)"
cat > "$gslbin/gh" <<'GHSSTUB'
#!/usr/bin/env bash
# gh-subissue-link.sh のテスト用 gh スタブ(実 gh を叩かない)。
#   issue view <n> [--repo <repo>] --json id -q .id -> "ID_<n>" を返す。
#   issue edit <n> [--repo <repo>] --body-file <path> -> 呼び出しを $GHS_CALL_LOG に記録する。
#   api graphql(addSubIssue mutation) -> $GHS_STATE_DIR/linked に Sub-issue 番号を追記する。
#     $GHS_NEVER_LINK に列挙された番号は常に追記しない(ハードゲートの検証用)。
#     $GHS_LINK_FAIL_ONCE に列挙された番号は最初の1回だけ追記をスキップする
#     (mutation 呼び出しは成功するが実際には紐づかない → 再リンクで成功する経路の検証用)。
#   api graphql(subIssues 検証クエリ) -> $GHS_STATE_DIR/linked の中身を改行区切りで返す。
log() { printf '%s\n' "$*" >> "$GHS_CALL_LOG"; }

if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  shift 2
  if [ "$1" = "--repo" ]; then log "REPO=$2"; shift 2; fi
  num="$1"
  log "issue view $num"
  echo "ID_${num}"
  exit 0
fi

if [ "$1" = "issue" ] && [ "$2" = "edit" ]; then
  shift 2
  epic="$1"; shift
  if [ "$1" = "--repo" ]; then log "REPO=$2"; shift 2; fi
  log "issue edit $epic $*"
  exit 0
fi

if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  argv="$*"
  case "$argv" in
    *addSubIssue*)
      sub_id="$(printf '%s' "$argv" | grep -oE 'sub=ID_[0-9]+' | sed 's/sub=ID_//')"
      log "addSubIssue $sub_id"
      skip=0
      case " ${GHS_NEVER_LINK:-} " in *" $sub_id "*) skip=1 ;; esac
      if [ "$skip" = "0" ]; then
        marker="$GHS_STATE_DIR/failed_once_${sub_id}"
        case " ${GHS_LINK_FAIL_ONCE:-} " in
          *" $sub_id "*)
            if [ ! -f "$marker" ]; then : > "$marker"; skip=1; fi
            ;;
        esac
      fi
      if [ "$skip" = "0" ]; then
        grep -qxF "$sub_id" "$GHS_STATE_DIR/linked" 2>/dev/null || echo "$sub_id" >> "$GHS_STATE_DIR/linked"
      fi
      echo '{"data":{"addSubIssue":{"subIssue":{"number":'"$sub_id"'}}}}'
      exit 0
      ;;
    *subIssues*)
      cnt_file="$GHS_STATE_DIR/verify_count"
      cnt=0
      [ -f "$cnt_file" ] && cnt="$(cat "$cnt_file")"
      cnt=$((cnt+1))
      echo "$cnt" > "$cnt_file"
      log "verify-query#${cnt}"
      cat "$GHS_STATE_DIR/linked" 2>/dev/null
      exit 0
      ;;
  esac
fi

log "UNHANDLED $*"
exit 1
GHSSTUB
chmod +x "$gslbin/gh"

gsl_reset() { rm -rf "$gsldir"; gsldir="$(mktemp -d)"; : > "$gsldir/call.log"; : > "$gsldir/linked"; }

# 異常系: usage エラー
bash "$H/lib/gh-subissue-link.sh" >/dev/null 2>&1; exit_is "gh-subissue-link.sh: 引数無しは usage エラー" 1 "$?"
bash "$H/lib/gh-subissue-link.sh" bogus 1 2 >/dev/null 2>&1; exit_is "gh-subissue-link.sh: 未知のサブコマンドは usage エラー" 1 "$?"
bash "$H/lib/gh-subissue-link.sh" link abc 1 2 >/dev/null 2>&1; exit_is "gh-subissue-link.sh: link の非数値 Epic 番号は usage エラー" 1 "$?"
bash "$H/lib/gh-subissue-link.sh" link 100 >/dev/null 2>&1; exit_is "gh-subissue-link.sh: link の Sub-issue 番号無しは usage エラー" 1 "$?"
bash "$H/lib/gh-subissue-link.sh" link 100 abc >/dev/null 2>&1; exit_is "gh-subissue-link.sh: link の非数値 Sub-issue 番号は usage エラー" 1 "$?"
bash "$H/lib/gh-subissue-link.sh" update-body 100 >/dev/null 2>&1; exit_is "gh-subissue-link.sh: update-body の --body-file 無しは usage エラー" 1 "$?"
bash "$H/lib/gh-subissue-link.sh" update-body 100 --body-file /no/such/file >/dev/null 2>&1
exit_is "gh-subissue-link.sh: 存在しない --body-file は exit 1" 1 "$?"

# 正常系: 全て初回で紐づく(再リンク不要)
gsl_reset
GHS_STATE_DIR="$gsldir" GHS_CALL_LOG="$gsldir/call.log" PATH="$gslbin:$PATH" \
  bash "$H/lib/gh-subissue-link.sh" link 100 201 202 >/dev/null 2>&1
exit_is "gh-subissue-link.sh: link は全て初回で揃えば exit 0" 0 "$?"
_gsl_log="$(cat "$gsldir/call.log")"
out_has "gh-subissue-link.sh: Epic の node ID を解決する" "issue view 100" "$_gsl_log"
out_has "gh-subissue-link.sh: Sub-issue 201 の node ID を解決する" "issue view 201" "$_gsl_log"
out_has "gh-subissue-link.sh: Sub-issue 202 の node ID を解決する" "issue view 202" "$_gsl_log"
out_has "gh-subissue-link.sh: Sub-issue 201 を addSubIssue でリンクする" "addSubIssue 201" "$_gsl_log"
out_has "gh-subissue-link.sh: Sub-issue 202 を addSubIssue でリンクする" "addSubIssue 202" "$_gsl_log"
if [ "$(printf '%s\n' "$_gsl_log" | grep -c '^verify-query#')" = "1" ]; then
  ok "gh-subissue-link.sh: 全て初回で揃えば検証クエリは1回のみ"
else
  ng "gh-subissue-link.sh: 全て初回で揃えば検証クエリは1回のみのはず"
fi

# --repo 指定時は gh issue view へ --repo をそのまま渡す
gsl_reset
GHS_STATE_DIR="$gsldir" GHS_CALL_LOG="$gsldir/call.log" PATH="$gslbin:$PATH" \
  bash "$H/lib/gh-subissue-link.sh" link 100 --repo o/r 201 >/dev/null 2>&1
out_has "gh-subissue-link.sh: --repo 指定時は gh issue view へ渡す" "REPO=o/r" "$(cat "$gsldir/call.log")"

# --repo 不正形式は gh を呼ぶ前に exit 1(gh-review.sh と同じ検証)
for _gsl_bad in "noslash" "a/b/c" "" "/bar" "foo/" "../foo"; do
  gsl_reset
  GHS_STATE_DIR="$gsldir" GHS_CALL_LOG="$gsldir/call.log" PATH="$gslbin:$PATH" \
    bash "$H/lib/gh-subissue-link.sh" link 100 --repo "$_gsl_bad" 201 >/dev/null 2>&1
  exit_is "gh-subissue-link.sh: --repo=[${_gsl_bad}](owner/repo形式外)は exit 1" 1 "$?"
  if [ -s "$gsldir/call.log" ]; then
    ng "gh-subissue-link.sh: --repo=[${_gsl_bad}]は形式検証で落ちて gh を呼ばない"
  else
    ok "gh-subissue-link.sh: --repo=[${_gsl_bad}]は形式検証で落ちて gh を呼ばない"
  fi
done

# 欠けがあれば再リンクして最終的に揃う(mutation は成功するが実際には紐づかないケースの再リンク経路)
gsl_reset
GHS_STATE_DIR="$gsldir" GHS_CALL_LOG="$gsldir/call.log" GHS_LINK_FAIL_ONCE="202" PATH="$gslbin:$PATH" \
  bash "$H/lib/gh-subissue-link.sh" link 100 201 202 >/dev/null 2>"$gsldir/stderr.log"
exit_is "gh-subissue-link.sh: 初回で欠けても再リンクして最終的に exit 0" 0 "$?"
_gsl_log2="$(cat "$gsldir/call.log")"
if [ "$(printf '%s\n' "$_gsl_log2" | grep -c '^addSubIssue 202$')" -ge 2 ]; then
  ok "gh-subissue-link.sh: 欠けた Sub-issue 202 は再リンクされる(addSubIssue 2回以上)"
else
  ng "gh-subissue-link.sh: 欠けた Sub-issue 202 は再リンクされるはず"
fi
out_has "gh-subissue-link.sh: 再リンクの旨を stderr に通知する" "再リンクします" "$(cat "$gsldir/stderr.log")"

# 揃わない場合はハードゲートで非ゼロ終了・報告する(黙って進めない。epic-create-issues/SKILL.md
# 手順3のハードゲートと同じ意図)
gsl_reset
GHS_STATE_DIR="$gsldir" GHS_CALL_LOG="$gsldir/call.log" GHS_NEVER_LINK="202" PATH="$gslbin:$PATH" \
  bash "$H/lib/gh-subissue-link.sh" link 100 201 202 >/dev/null 2>"$gsldir/stderr.log"
exit_is "gh-subissue-link.sh: 何度再リンクしても揃わない場合は非ゼロ終了(ハードゲート)" 1 "$?"
out_has "gh-subissue-link.sh: 揃わない旨を stderr に報告する" "回再リンクしても" "$(cat "$gsldir/stderr.log")"

# update-body: Epic 本文更新は gh issue edit --body-file 経由に絞る(任意フィールド編集は許さない)
gsl_reset
_gsl_body_file="$(mktemp)"; printf 'updated body' > "$_gsl_body_file"
GHS_STATE_DIR="$gsldir" GHS_CALL_LOG="$gsldir/call.log" PATH="$gslbin:$PATH" \
  bash "$H/lib/gh-subissue-link.sh" update-body 100 --body-file "$_gsl_body_file" >/dev/null 2>&1
exit_is "gh-subissue-link.sh: update-body は exit 0" 0 "$?"
out_has "gh-subissue-link.sh: update-body は gh issue edit --body-file を呼ぶ" "issue edit 100 --body-file $_gsl_body_file" "$(cat "$gsldir/call.log")"
rm -f "$_gsl_body_file"

# update-body でも --repo 指定時は gh issue edit へ --repo をそのまま渡す
gsl_reset
_gsl_body_file2="$(mktemp)"; printf 'updated body' > "$_gsl_body_file2"
GHS_STATE_DIR="$gsldir" GHS_CALL_LOG="$gsldir/call.log" PATH="$gslbin:$PATH" \
  bash "$H/lib/gh-subissue-link.sh" update-body 100 --repo o/r --body-file "$_gsl_body_file2" >/dev/null 2>&1
out_has "gh-subissue-link.sh: update-body --repo 指定時は gh issue edit へ渡す" "REPO=o/r" "$(cat "$gsldir/call.log")"
rm -f "$_gsl_body_file2"

# update-body でも --repo 不正形式は gh を呼ぶ前に exit 1(link と対称の検証)
gsl_reset
_gsl_body_file3="$(mktemp)"; printf 'updated body' > "$_gsl_body_file3"
GHS_STATE_DIR="$gsldir" GHS_CALL_LOG="$gsldir/call.log" PATH="$gslbin:$PATH" \
  bash "$H/lib/gh-subissue-link.sh" update-body 100 --repo noslash --body-file "$_gsl_body_file3" >/dev/null 2>&1
exit_is "gh-subissue-link.sh: update-body --repo=noslash(owner/repo形式外)は exit 1" 1 "$?"
if [ -s "$gsldir/call.log" ]; then
  ng "gh-subissue-link.sh: update-body --repo 不正形式は形式検証で落ちて gh を呼ばない"
else
  ok "gh-subissue-link.sh: update-body --repo 不正形式は形式検証で落ちて gh を呼ばない"
fi
rm -f "$_gsl_body_file3"

rm -rf "$gslbin" "$gsldir"

# epic-create-issues/SKILL.md がラッパー呼び出しへ一本化されていること(生の gh api graphql /
# gh issue edit を手順書に生埋めしていない)
_eci_body="$(cat "$H/skills/epic-create-issues/SKILL.md" 2>/dev/null)"
out_has   "epic-create-issues/SKILL.md: link サブコマンドを呼ぶ" "yosage-dev-harness-gh-subissue-link link" "$_eci_body"
out_has   "epic-create-issues/SKILL.md: update-body サブコマンドを呼ぶ" "yosage-dev-harness-gh-subissue-link update-body" "$_eci_body"
out_hasnt "epic-create-issues/SKILL.md: 生の gh api graphql を手順書に生埋めしていない" "gh api graphql" "$_eci_body"
out_hasnt "epic-create-issues/SKILL.md: 生の gh issue edit を手順書に生埋めしていない" "gh issue edit" "$_eci_body"
# 手順3(Sub-issueリンクのハードゲート)が非ゼロ終了した場合、手順4(Epic本文
# 更新)以降へ進んではいけないことが明示されていなかった(「報告する」としか書かれておらず、
# 停止すべきことが読み手に伝わらない)。この関門の遵守だけが、epic-implement 側の番号一覧の
# 完全性照合・絞り込みの安全性を支えているため、停止条件として明記する。
out_has "epic-create-issues/SKILL.md: 手順3の非ゼロ終了は停止条件であり手順4以降へ進まない旨を明記" "そのまま手順4（Epic 本文更新）以降へ進まない" "$_eci_body"

