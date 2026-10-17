echo "== detect-stack.sh =="
d="$(mktemp -d)"; touch "$d/package.json";  out_has "node 検出"    "node"    "$(bash "$H/lib/detect-stack.sh" "$d")"; rm -rf "$d"
d="$(mktemp -d)"; touch "$d/pyproject.toml";out_has "python 検出"  "python"  "$(bash "$H/lib/detect-stack.sh" "$d")"; rm -rf "$d"
d="$(mktemp -d)"; touch "$d/pubspec.yaml";  out_has "flutter 検出" "flutter" "$(bash "$H/lib/detect-stack.sh" "$d")"; rm -rf "$d"

echo "== commit-trailer-notice.sh: commit 時点での Co-Authored-By 署名トレーラ欠落に気づかせる(論点2) =="
# ハードブロックしない(トレーラの要否はリポジトリの所有・開示宣言の有無で分岐し、このフックは
# 機械的に判定できないため)。additionalContext による気づかせのみを検証する。
_ctn_dir="$(mktemp -d)"
gitc -C "$_ctn_dir" init -q
gitc -C "$_ctn_dir" commit -q --allow-empty -m "initial"
json_cmd_cwd_helper() { python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }

gitc -C "$_ctn_dir" commit -q --allow-empty -m "no trailer here"
_ctn_out1="$(json_cmd_cwd_helper "git commit -q --allow-empty -m 'no trailer here'" "$_ctn_dir" | bash "$H/hooks/commit-trailer-notice.sh" 2>&1)"; _ctn_code1="$?"
out_has "トレーラ欠落コミット: additionalContext で気づかせる" "additionalContext" "$_ctn_out1"
out_has "トレーラ欠落コミット: ルール commit への参照を案内する" "ルール commit" "$_ctn_out1"
exit_is "トレーラ欠落コミット: 非ブロッキング(exit 0)" 0 "$_ctn_code1"

gitc -C "$_ctn_dir" commit -q --allow-empty -m "$(printf 'subject\n\nCo-Authored-By: Test Model <noreply@example.com>')"
_ctn_out2="$(json_cmd_cwd_helper "git commit -q --allow-empty -m 'x'" "$_ctn_dir" | bash "$H/hooks/commit-trailer-notice.sh" 2>&1)"
out_is_empty "トレーラ有りコミット: 無反応" "$_ctn_out2"

_ctn_out3="$(json_cmd_cwd_helper "git status" "$_ctn_dir" | bash "$H/hooks/commit-trailer-notice.sh" 2>&1)"
out_is_empty "commit を含まないコマンド: 無反応(前置フィルタ)" "$_ctn_out3"

# fail-safe: commit 失敗等で HEAD が古いままの場合(直近判定の外)は警告しない(誤った古い
# コミットへ繰り返し警告することを防ぐ)。
GIT_COMMITTER_DATE="2020-01-01T00:00:00" gitc -C "$_ctn_dir" commit -q --allow-empty -m "old" --date="2020-01-01T00:00:00"
_ctn_out4="$(json_cmd_cwd_helper "git commit -q --allow-empty -m 'old'" "$_ctn_dir" | bash "$H/hooks/commit-trailer-notice.sh" 2>&1)"
out_is_empty "直近でない(古い)コミットは対象外(fail-safe)" "$_ctn_out4"

rm -rf "$_ctn_dir"

# hooks.json の配線確認(PostToolUse に Bash マッチャで commit-trailer-notice.sh がある)。
_ctn_hooks="$(cat "$H/hooks/hooks.json")"
out_has "hooks.json: PostToolUse(Bash) に commit-trailer-notice.sh の配線がある" "commit-trailer-notice.sh" "$_ctn_hooks"

echo "== grounding-check.sh (設計doc の path:line 引用検証) =="
d="$(mktemp -d)"; mkdir -p "$d/.docs" "$d/src"; printf 'a\nb\nc\n' > "$d/src/x.ts"
printf '# 設計\n- src/x.ts:2 を踏襲\n- src/nope.ts:9 を参照\n' > "$d/.docs/dd.md"
o="$(json_file "$d/.docs/dd.md" "$d" | CLAUDE_PROJECT_DIR="$d" bash "$H/hooks/grounding-check.sh" 2>&1)"
out_has   "存在しない引用を検知" "nope.ts:9" "$o"
out_hasnt "実在引用は素通り"     "x.ts:2"    "$o"
# 設計doc でない普通ファイルは無反応
o="$(json_file "$d/src/x.ts" "$d" | CLAUDE_PROJECT_DIR="$d" bash "$H/hooks/grounding-check.sh" 2>&1)"
out_hasnt "非設計docは無反応" "grounded-design" "$o"

# jq 非在(python3 フォールバック)でも非ブロッキング(exit 0)を維持する。
# pyenv shim 回避で実体を解決(notify.sh 等と同型の手法)。
nojq_gc="$(mktemp -d)"
realpy_gc="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"
# grounding-check.sh の外部依存を過不足なく反映する(tr は total 行数の空白除去に使用、sed は
# path:line 抽出の前処理(URL 除去)に使用。grounding-check.sh:38 の抽出ロジック参照)
for t in bash cat grep sort wc printf tr sed; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$nojq_gc/$t"; done
[ -n "$realpy_gc" ] && ln -sf "$realpy_gc" "$nojq_gc/python3"
o="$(json_file "$d/.docs/dd.md" "$d" | CLAUDE_PROJECT_DIR="$d" PATH="$nojq_gc" bash "$H/hooks/grounding-check.sh" 2>&1)"; rc=$?
exit_is "jq非在(python3): 非ブロッキング(exit 0)" 0 "$rc"
out_has   "jq非在(python3): additionalContext に不在引用を含む" "nope.ts:9" "$o"
out_hasnt "jq非在(python3): 実在引用は素通り"                   "x.ts:2"    "$o"

# jq/python3 両欠でも無処理で非ブロッキング(exit 0)を維持する。
# 注意: 両欠だと file_path の抽出(jq/python3 いずれかが必要)自体ができず、grounding-check.sh の
# 早期 exit 0(file_path 未取得時)で止まる。jq/python3 フォールバック後段(で追加した出力コード)
# には到達しない。それでも「両欠でも非ブロッキングを維持する」という主張自体は真であり、
# この早期 exit 経路を検証する意図でテストを据え置く(レビュー指摘への回答)。
noboth_gc="$(mktemp -d)"
for t in bash cat grep sort wc printf tr sed; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$noboth_gc/$t"; done
o="$(json_file "$d/.docs/dd.md" "$d" | CLAUDE_PROJECT_DIR="$d" PATH="$noboth_gc" bash "$H/hooks/grounding-check.sh" 2>&1)"; rc=$?
exit_is "jq/python3両欠: 無処理でも非ブロッキング(exit 0)" 0 "$rc"
rm -rf "$nojq_gc" "$noboth_gc" "$d"

echo "== grounding-check.sh: name:number 誤検知回避 =="
d="$(mktemp -d)"; mkdir -p "$d/.docs" "$d/src"; printf 'a\nb\nc\n' > "$d/src/x.ts"
printf '# 設計\n- docker-compose.yml:5000 でアクセス可能\n- http://localhost:5000/docs/index.md:20 を参照\n- src/x.ts:2 を踏襲\n- src/x.ts:9999 を参照\n' > "$d/.docs/dd.md"
o="$(json_file "$d/.docs/dd.md" "$d" | CLAUDE_PROJECT_DIR="$d" bash "$H/hooks/grounding-check.sh" 2>&1)"
out_hasnt "docker-compose.yml:5000(ポート表記) は誤検知しない" "docker-compose.yml:5000" "$o"
out_hasnt "URL 内の name:port は誤検知しない"                    "index.md:20"             "$o"
out_hasnt "正当な path:line 引用は従来通り素通り"                "x.ts:2"                  "$o"
out_has   "真の hallucination 引用(実在ファイルの行数超過)は従来通り検知" "x.ts:9999" "$o"
rm -rf "$d"

echo "== grounding-check.sh: 絶対パス参照の先頭 / 保持 =="
d="$(mktemp -d)"; mkdir -p "$d/.docs" "$d/src"; printf 'a\nb\nc\n' > "$d/src/x.ts"
printf '# 設計\n- %s を参照\n- %s を参照(行数超過)\n' "$d/src/x.ts:2" "$d/src/x.ts:9999" > "$d/.docs/dd.md"
o="$(json_file "$d/.docs/dd.md" "$d" | CLAUDE_PROJECT_DIR="$d" bash "$H/hooks/grounding-check.sh" 2>&1)"
out_hasnt "絶対パスの実在引用(先頭 / 保持)は素通り"   "$d/src/x.ts:2"    "$o"
out_has   "絶対パスの行数超過引用(先頭 / 保持)は検知" "$d/src/x.ts:9999" "$o"
rm -rf "$d"

echo "== grounding-check.sh: スキーム省略 host:port/path の name:number 誤検知回避 =="
d="$(mktemp -d)"; mkdir -p "$d/.docs"
printf '# 設計\n- localhost:5000/docs/index.md:20 を参照\n' > "$d/.docs/dd.md"
o="$(json_file "$d/.docs/dd.md" "$d" | CLAUDE_PROJECT_DIR="$d" bash "$H/hooks/grounding-check.sh" 2>&1)"
out_hasnt "スキーム省略 host:port/path 内の index.md:20 は誤検知しない" "index.md:20"   "$o"
out_hasnt "スキーム省略 host:port/path 内の docs/index.md は誤検知しない" "docs/index.md" "$o"
rm -rf "$d"

echo "== grounding-check.sh: 解決基点は編集対象ファイル自身が属するリポジトリのルート =="

# 再現構成(観測2相当): 複数リポジトリが同居するワークスペースのルートを基準ディレクトリとする
# セッションから、その配下にある別リポジトリ(member)の中の設計ドキュメントを編集し、member の
# ルートから見て実在するパスを path:line で参照する。フックプロセスの作業ディレクトリ・
# CLAUDE_PROJECT_DIR・入力JSONの cwd をすべてワークスペースのルート($ws)に揃える。
ws="$(mktemp -d)"; mkdir -p "$ws/member/.docs" "$ws/member/src"
(cd "$ws/member" && git init -q && git config user.email t@example.com && git config user.name t)
printf 'a\nb\nc\n' > "$ws/member/src/x.ts"
printf '# 設計\n- src/x.ts:2 を踏襲\n- src/nope.ts:9 を参照\n' > "$ws/member/.docs/dd.md"
o="$(json_file "$ws/member/.docs/dd.md" "$ws" | (cd "$ws" && CLAUDE_PROJECT_DIR="$ws" bash "$H/hooks/grounding-check.sh") 2>&1)"
out_hasnt "member repo 内の実在引用は、ワークスペース基準でも誤って警告されない" "x.ts:2"   "$o"
out_has   "member repo 内の不在引用は、ワークスペース基準でも従来通り検知される" "nope.ts:9" "$o"
rm -rf "$ws"

# 回帰(観測1相当): worktree で隔離した作業者(フックプロセスの作業ディレクトリ・入力JSONの cwd は
# worktree 自身、CLAUDE_PROJECT_DIR だけが起動時のまま古いセッションルートを指す)でも、
# worktree 内の実在引用は従来通り警告されない(この構成は本来1段目の cwd 相対チェックで当たって
# いたが、その1段目を外した後も git リポジトリルート解決で同じ結果になることを固定する)。
sess="$(mktemp -d)"; wt="$(mktemp -d)"; mkdir -p "$wt/.docs" "$wt/src"
(cd "$wt" && git init -q && git config user.email t@example.com && git config user.name t)
printf 'a\nb\nc\n' > "$wt/src/x.ts"
printf '# 設計\n- src/x.ts:2 を踏襲\n- src/nope.ts:9 を参照\n' > "$wt/.docs/dd.md"
o="$(json_file "$wt/.docs/dd.md" "$wt" | (cd "$wt" && CLAUDE_PROJECT_DIR="$sess" bash "$H/hooks/grounding-check.sh") 2>&1)"
out_hasnt "worktree隔離(CLAUDE_PROJECT_DIRは古いセッションルート)でも実在引用は素通り" "x.ts:2"   "$o"
out_has   "worktree隔離でも不在引用は従来通り検知される"                                 "nope.ts:9" "$o"
rm -rf "$sess" "$wt"

# 単一リポジトリ構成(ワークスペースでない場合)は git 解決の基点と CLAUDE_PROJECT_DIR が
# 一致するため、従来どおり動作する(退行防止)。
single="$(mktemp -d)"; mkdir -p "$single/.docs" "$single/src"
(cd "$single" && git init -q && git config user.email t@example.com && git config user.name t)
printf 'a\nb\nc\n' > "$single/src/x.ts"
printf '# 設計\n- src/x.ts:2 を踏襲\n- src/nope.ts:9 を参照\n' > "$single/.docs/dd.md"
o="$(json_file "$single/.docs/dd.md" "$single" | CLAUDE_PROJECT_DIR="$single" bash "$H/hooks/grounding-check.sh" 2>&1)"
out_hasnt "単一リポジトリ構成: 実在引用は従来通り素通り" "x.ts:2"   "$o"
out_has   "単一リポジトリ構成: 不在引用は従来通り検知"   "nope.ts:9" "$o"
rm -rf "$single"

# 編集対象ファイルが git リポジトリの外にある場合: `git rev-parse` が失敗するため、
# 従来の解決基準(CLAUDE_PROJECT_DIR → 入力JSONのcwd → フックプロセスのPWD)へフォールバックする。
nogit="$(mktemp -d)"; mkdir -p "$nogit/.docs" "$nogit/src"
printf 'a\nb\nc\n' > "$nogit/src/x.ts"
printf '# 設計\n- src/x.ts:2 を踏襲\n- src/nope.ts:9 を参照\n' > "$nogit/.docs/dd.md"
o="$(json_file "$nogit/.docs/dd.md" "$nogit" | CLAUDE_PROJECT_DIR="$nogit" bash "$H/hooks/grounding-check.sh" 2>&1)"
out_hasnt "gitリポジトリ外: CLAUDE_PROJECT_DIRへフォールバックし実在引用は素通り" "x.ts:2"   "$o"
out_has   "gitリポジトリ外: フォールバック下でも不在引用は検知"                 "nope.ts:9" "$o"
rm -rf "$nogit"

echo "== doc-drift-check.sh =="
d="$(mktemp -d)"
( cd "$d" && git init -q && git checkout -q -b main && mkdir src .docs \
  && echo x > src/a.py && echo d > .docs/a.md && gitc add -A && gitc commit -qm base \
  && git checkout -q -b feat && echo y >> src/a.py && gitc commit -qam code-only )
out_has "コードのみ変更で FINDINGS" "FINDINGS" "$(cd "$d" && bash "$H/lib/doc-drift-check.sh" main 2>&1)"
( cd "$d" && echo "更新" >> .docs/a.md && gitc commit -qam docs-too )
out_has "docs も更新で OK" "RESULT: OK" "$(cd "$d" && bash "$H/lib/doc-drift-check.sh" main 2>&1)"
rm -rf "$d"

echo "== sync-labels.sh --dry-run =="
# 実 gh を叩かず、PATH 上のスタブ gh(repo view で owner/repo を返し、label create の全引数を
# argv.log へ記録する)で検証する。
sl_bin="$(mktemp -d)"; sl_log="$(mktemp -d)"
cat > "$sl_bin/gh" <<'SLSTUB'
#!/usr/bin/env bash
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  if [ "${SL_STUB_REPO_VIEW_FAIL:-0}" = "1" ]; then
    echo "stub: gh repo view failed" >&2
    exit 1
  fi
  printf '%s\n' "${SL_STUB_NWO:-stub-owner/stub-repo}"
  exit 0
fi
if [ "$1" = "label" ] && [ "$2" = "create" ]; then
  # 呼び出し形は `gh label create -R <NWO> <name> --color ... --description ... --force`
  # なので、ラベル名は $5 に来る($3=-R, $4=NWO)。
  if [ -n "${SL_STUB_ARGS_NUL_LOG:-}" ]; then
    # gh に実際に渡った引数を、NUL 区切りで(改行/タブを含む値でも壊れない形で)記録する。
    printf '%s\0' "$@" > "$SL_STUB_ARGS_NUL_LOG"
  fi
  if [ "$5" = "${SL_STUB_FAIL_LABEL:-}" ]; then
    echo "${SL_STUB_FAIL_MSG:-stub: gh label create failed}" >&2
    exit 1
  fi
  printf '%s\n' "$*" >> "$SL_ARGV_LOG"
  exit 0
fi
exit 0
SLSTUB
chmod +x "$sl_bin/gh"

sl_root="$(mktemp -d)"

# (引数なし): usage エラーで exit 2。
bash "$H/lib/sync-labels.sh" >/dev/null 2>&1
exit_is "sync-labels.sh: 引数なしは exit 2(使い方を表示)" 2 "$?"

# (存在しないディレクトリ): 同じく exit 2 扱い。
bash "$H/lib/sync-labels.sh" --dry-run "$sl_root/does-not-exist" >/dev/null 2>&1
exit_is "sync-labels.sh: 存在しないディレクトリは exit 2" 2 "$?"

# (a) プロジェクトのファイルが無い → 標準9個だけが出る。
sl_out_a="$(SL_ARGV_LOG="$sl_log/argv-a.log" PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" --dry-run "$sl_root" 2>&1)"
out_has   "sync-labels.sh(a): 標準ラベル feat が出る"    "feat"    "$sl_out_a"
out_has   "sync-labels.sh(a): 書き込み先(owner/repo)を表示"  "stub-owner/stub-repo" "$sl_out_a"
out_hasnt "sync-labels.sh(a): プロジェクト固有 scope:api は出ない" "scope:api" "$sl_out_a"
sl_count_a="$(printf '%s\n' "$sl_out_a" | grep -c '^would upsert')"
if [ "$sl_count_a" = "9" ]; then ok "sync-labels.sh(a): 標準9個だけが出る(実測 ${sl_count_a})"; else ng "sync-labels.sh(a): 標準9個だけが出る(実測 ${sl_count_a})"; fi

# (b) プロジェクト固有ファイルに scope:api を追加、既存名 feat は色違いで上書き。
mkdir -p "$sl_root/.claude"
printf '[{"name":"scope:api","color":"ededed","description":"API 関連"},{"name":"feat","color":"000000","description":"上書き済み"}]' \
  > "$sl_root/.claude/yosage-dev-harness-labels.json"
sl_out_b="$(SL_ARGV_LOG="$sl_log/argv-b.log" PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" --dry-run "$sl_root" 2>&1)"
out_has "sync-labels.sh(b): プロジェクト固有 scope:api が増える" "scope:api" "$sl_out_b"
sl_feat_line="$(printf '%s\n' "$sl_out_b" | grep '^would upsert.*: feat ')"
out_has   "sync-labels.sh(b): feat はプロジェクト側の色(000000)で上書きされる" "000000" "$sl_feat_line"
out_hasnt "sync-labels.sh(b): feat は標準側の色(0e8a16)のままではない" "0e8a16" "$sl_feat_line"
sl_count_b="$(printf '%s\n' "$sl_out_b" | grep -c '^would upsert')"
if [ "$sl_count_b" = "10" ]; then ok "sync-labels.sh(b): 標準9個+scope:api=10個(実測 ${sl_count_b})"; else ng "sync-labels.sh(b): 標準9個+scope:api=10個(実測 ${sl_count_b})"; fi

# 実適用(--dry-run 無し)でも upsert の全呼び出しに -R <owner/repo> が付く。
: > "$sl_log/argv-b.log"
SL_ARGV_LOG="$sl_log/argv-b.log" PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" "$sl_root" >/dev/null 2>&1
sl_argv_lines="$(wc -l < "$sl_log/argv-b.log" | tr -d ' ')"
sl_argv_r_lines="$(grep -c -- '-R stub-owner/stub-repo' "$sl_log/argv-b.log")"
if [ -n "$sl_argv_lines" ] && [ "$sl_argv_lines" = "$sl_argv_r_lines" ]; then
  ok "sync-labels.sh: 全 upsert 呼び出しに -R <owner/repo> が付く(${sl_argv_r_lines}/${sl_argv_lines})"
else
  ng "sync-labels.sh: 全 upsert 呼び出しに -R <owner/repo> が付く(${sl_argv_r_lines}/${sl_argv_lines})"
fi

# (c') <repo-root> が GitHub のリポジトリに結び付かない → exit 1。
sl_notlinked="$(mktemp -d)"
SL_STUB_REPO_VIEW_FAIL=1 PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" --dry-run "$sl_notlinked" >/dev/null 2>&1
exit_is "sync-labels.sh(c'): GitHub リポジトリに結び付かない <repo-root> は exit 1" 1 "$?"
rm -rf "$sl_notlinked"

# (d) 旧名 .claude/github/labels.local.json だけを置いた場合 → 読まれない(標準9個だけ)。
sl_old="$(mktemp -d)"
mkdir -p "$sl_old/.claude/github"
printf '[{"name":"scope:old","color":"111111","description":"旧名(読まれない)"}]' \
  > "$sl_old/.claude/github/labels.local.json"
sl_out_d="$(PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" --dry-run "$sl_old" 2>&1)"
out_hasnt "sync-labels.sh(d): 旧名 github/labels.local.json は読まれない" "scope:old" "$sl_out_d"
sl_count_d="$(printf '%s\n' "$sl_out_d" | grep -c '^would upsert')"
if [ "$sl_count_d" = "9" ]; then ok "sync-labels.sh(d): 標準9個だけが出る(実測 ${sl_count_d})"; else ng "sync-labels.sh(d): 標準9個だけが出る(実測 ${sl_count_d})"; fi
rm -rf "$sl_old"

# 2回目: --dry-run を2回続けて同じ出力(冪等)。
sl_out_b2="$(SL_ARGV_LOG="$sl_log/argv-b2.log" PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" --dry-run "$sl_root" 2>&1)"
if [ "$sl_out_b" = "$sl_out_b2" ]; then ok "sync-labels.sh: --dry-run を2回続けて同じ出力"; else ng "sync-labels.sh: --dry-run を2回続けて同じ出力"; fi

# (e) プロジェクト固有ファイルが不正な JSON(構文エラー) → ファイル名 + jq の診断(行・列)を
#     含むメッセージを出して exit 1。
sl_badproj="$(mktemp -d)"
mkdir -p "$sl_badproj/.claude"
printf '{not valid json' > "$sl_badproj/.claude/yosage-dev-harness-labels.json"
sl_out_e="$(PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" --dry-run "$sl_badproj" 2>&1)"
sl_rc_e=$?
exit_is "sync-labels.sh(e): プロジェクト固有 JSON(構文エラー)なら exit 1" 1 "$sl_rc_e"
out_has "sync-labels.sh(e): 不正ファイル名を含むメッセージ" "yosage-dev-harness-labels.json" "$sl_out_e"
out_has "sync-labels.sh(e): jq の診断(行・列)を含むメッセージ" "line" "$sl_out_e"
rm -rf "$sl_badproj"

# (f) 標準ラベル側(labels.json)が不正な JSON(構文エラー) → 同様にファイル名を含むメッセージを
#     出して exit 1。
sl_badbase_H="$(mktemp -d)"
cp -R "$H"/* "$sl_badbase_H/"
printf '{not valid json' > "$sl_badbase_H/github/labels.json"
sl_root_f="$(mktemp -d)"
sl_out_f="$(PATH="$sl_bin:$PATH" bash "$sl_badbase_H/lib/sync-labels.sh" --dry-run "$sl_root_f" 2>&1)"
sl_rc_f=$?
exit_is "sync-labels.sh(f): 標準ラベル JSON(構文エラー)なら exit 1" 1 "$sl_rc_f"
out_has "sync-labels.sh(f): 不正ファイル名を含むメッセージ" "labels.json" "$sl_out_f"
rm -rf "$sl_badbase_H" "$sl_root_f"

# (g) プロジェクト固有ファイルが空 → (構文的には正しいが)配列ではないので exit 1。
sl_empty="$(mktemp -d)"
mkdir -p "$sl_empty/.claude"
printf '' > "$sl_empty/.claude/yosage-dev-harness-labels.json"
sl_out_g="$(PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" --dry-run "$sl_empty" 2>&1)"
sl_rc_g=$?
exit_is "sync-labels.sh(g): プロジェクト固有 JSON が空なら exit 1" 1 "$sl_rc_g"
out_has "sync-labels.sh(g): 不正ファイル名を含むメッセージ" "yosage-dev-harness-labels.json" "$sl_out_g"
rm -rf "$sl_empty"

# (h) プロジェクト固有ファイルが配列でない(単一オブジェクト) → exit 1。
sl_notarr="$(mktemp -d)"
mkdir -p "$sl_notarr/.claude"
printf '{"name":"feat","color":"000000"}' > "$sl_notarr/.claude/yosage-dev-harness-labels.json"
sl_out_h="$(PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" --dry-run "$sl_notarr" 2>&1)"
sl_rc_h=$?
exit_is "sync-labels.sh(h): プロジェクト固有 JSON が配列でないなら exit 1" 1 "$sl_rc_h"
out_has "sync-labels.sh(h): 不正ファイル名を含むメッセージ" "yosage-dev-harness-labels.json" "$sl_out_h"
rm -rf "$sl_notarr"

# (i) JSON 検査は NWO 解決(gh repo view)より前に行われる(fail-fast):
#     不正 JSON かつ gh repo view が失敗する状況でも、出るのは JSON 側のエラーだけ。
sl_order="$(mktemp -d)"
mkdir -p "$sl_order/.claude"
printf '{not valid json' > "$sl_order/.claude/yosage-dev-harness-labels.json"
sl_out_i="$(SL_STUB_REPO_VIEW_FAIL=1 PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" --dry-run "$sl_order" 2>&1)"
out_has   "sync-labels.sh(i): JSON検査が先(JSONエラーが出る)" "yosage-dev-harness-labels.json" "$sl_out_i"
out_hasnt "sync-labels.sh(i): JSON検査が先(NWO解決エラーは出ない)" "GitHub リポジトリを特定できません" "$sl_out_i"
rm -rf "$sl_order"

# (j) 1件の適用(gh label create)が失敗しても、他のラベルの適用は続き、失敗した
#     ラベル名を標準エラーに出して非ゼロ終了する(sl_root は (b) の状態=標準9個+scope:api=10個)。
: > "$sl_log/argv-j.log"
sl_out_j="$(SL_ARGV_LOG="$sl_log/argv-j.log" SL_STUB_FAIL_LABEL="scope:api" PATH="$sl_bin:$PATH" bash "$H/lib/sync-labels.sh" "$sl_root" 2>&1)"
sl_rc_j=$?
if [ "$sl_rc_j" -ne 0 ]; then
  ok "sync-labels.sh(j): 1件失敗すると非ゼロ終了(実測 ${sl_rc_j})"
else
  ng "sync-labels.sh(j): 1件失敗すると非ゼロ終了(実測 ${sl_rc_j})"
fi
out_has "sync-labels.sh(j): 失敗したラベル名を標準エラーに出す" "scope:api" "$sl_out_j"
out_has "sync-labels.sh(j): gh の実際の標準エラーをメッセージに含める" "stub: gh label create failed" "$sl_out_j"
sl_ok_count_j="$(printf '%s\n' "$sl_out_j" | grep -c '^ok: ')"
if [ "$sl_ok_count_j" = "9" ]; then
  ok "sync-labels.sh(j): 失敗した1件以外(9件)は適用が続く(実測 ${sl_ok_count_j})"
else
  ng "sync-labels.sh(j): 失敗した1件以外(9件)は適用が続く(実測 ${sl_ok_count_j})"
fi
sl_argv_j_lines="$(wc -l < "$sl_log/argv-j.log" | tr -d ' ')"
if [ "$sl_argv_j_lines" = "9" ]; then
  ok "sync-labels.sh(j): 失敗したラベルは gh label create の成功記録に残らない(実測 ${sl_argv_j_lines})"
else
  ng "sync-labels.sh(j): 失敗したラベルは gh label create の成功記録に残らない(実測 ${sl_argv_j_lines})"
fi

# (k) 値の往復: description にバックスラッシュ・タブ・改行・シングルクォートを含むラベルでも、
#     gh に実際に渡る引数(ラベル名・description)が元の値と完全に一致する(@sh + eval)。
sl_special_H="$(mktemp -d)"
cp -R "$H"/* "$sl_special_H/"
sl_special_desc=$'back\\slash tab\ttab2\nline2 quote\x27s'
jq -n --arg desc "$sl_special_desc" \
  '[{name:"weird:name",color:"abcdef",description:$desc}]' \
  > "$sl_special_H/github/labels.json"
sl_root_k="$(mktemp -d)"
sl_argsnul_dir_k="$(mktemp -d)"; sl_argsnul_k="$sl_argsnul_dir_k/args.nul"
PATH="$sl_bin:$PATH" SL_STUB_ARGS_NUL_LOG="$sl_argsnul_k" bash "$sl_special_H/lib/sync-labels.sh" "$sl_root_k" >/dev/null 2>&1
sl_rc_k=$?
if [ "$sl_rc_k" = "0" ]; then
  ok "sync-labels.sh(k): 特殊文字を含むラベルの適用は成功する"
else
  ng "sync-labels.sh(k): 特殊文字を含むラベルの適用は成功する(実測rc=${sl_rc_k})"
fi
sl_args_k=()
while IFS= read -r -d '' a; do sl_args_k+=("$a"); done < "$sl_argsnul_k"
if [ "${sl_args_k[4]:-}" = "weird:name" ]; then
  ok "sync-labels.sh(k): ラベル名が元の値のまま gh に渡る"
else
  ng "sync-labels.sh(k): ラベル名が元の値のまま gh に渡る(実測 <${sl_args_k[4]:-}>)"
fi
if [ "${sl_args_k[8]:-}" = "$sl_special_desc" ]; then
  ok "sync-labels.sh(k): description(バックスラッシュ/タブ/改行/引用符)が元の値のまま gh に渡る"
else
  ng "sync-labels.sh(k): description(バックスラッシュ/タブ/改行/引用符)が元の値のまま gh に渡る(実測 <${sl_args_k[8]:-}>)"
fi
rm -rf "$sl_special_H" "$sl_root_k" "$sl_argsnul_dir_k"

# (k') 値の往復: description が空文字列でも、そのまま空文字列として渡る(ずれない)。
sl_emptydesc_H="$(mktemp -d)"
cp -R "$H"/* "$sl_emptydesc_H/"
printf '[{"name":"empty-desc","color":"abcdef","description":""}]' > "$sl_emptydesc_H/github/labels.json"
sl_root_k2="$(mktemp -d)"
sl_argsnul_dir_k2="$(mktemp -d)"; sl_argsnul_k2="$sl_argsnul_dir_k2/args.nul"
PATH="$sl_bin:$PATH" SL_STUB_ARGS_NUL_LOG="$sl_argsnul_k2" bash "$sl_emptydesc_H/lib/sync-labels.sh" "$sl_root_k2" >/dev/null 2>&1
sl_args_k2=()
while IFS= read -r -d '' a; do sl_args_k2+=("$a"); done < "$sl_argsnul_k2"
if [ "${sl_args_k2[4]:-}" = "empty-desc" ] && [ "${sl_args_k2[8]:-}" = "" ]; then
  ok "sync-labels.sh(k'): 空文字列の description でも name/description がずれない"
else
  ng "sync-labels.sh(k'): 空文字列の description でも name/description がずれない(実測 name=<${sl_args_k2[4]:-}> desc=<${sl_args_k2[8]:-}>)"
fi
rm -rf "$sl_emptydesc_H" "$sl_root_k2" "$sl_argsnul_dir_k2"

# (l) 壊れた要素: .name がオブジェクト等(文字列でない)なら、gh へ渡す前に非ゼロ終了する。
sl_brokenname_H="$(mktemp -d)"
cp -R "$H"/* "$sl_brokenname_H/"
printf '[{"name":{"x":1},"color":"abcdef"}]' > "$sl_brokenname_H/github/labels.json"
sl_root_l="$(mktemp -d)"
PATH="$sl_bin:$PATH" bash "$sl_brokenname_H/lib/sync-labels.sh" --dry-run "$sl_root_l" >/dev/null 2>&1
sl_rc_l=$?
if [ "$sl_rc_l" -ne 0 ]; then
  ok "sync-labels.sh(l): .name がオブジェクト等の壊れた要素は非ゼロ終了する(実測rc=${sl_rc_l})"
else
  ng "sync-labels.sh(l): .name がオブジェクト等の壊れた要素は非ゼロ終了する(実測rc=${sl_rc_l})"
fi
rm -rf "$sl_brokenname_H" "$sl_root_l"

rm -rf "$sl_bin" "$sl_log" "$sl_root"

