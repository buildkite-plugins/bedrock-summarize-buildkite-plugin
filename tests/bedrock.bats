#!/usr/bin/env bats

# shellcheck disable=SC2030,SC2031,SC2016 # Bats subshells and literal Markdown fixtures

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"
  source "$PWD/lib/plugin.bash"
  export BUILDKITE_BUILD_ID="bedrock-test-${BATS_TEST_NUMBER}-$$"
  export BUILDKITE_JOB_ID="$BUILDKITE_BUILD_ID"
  export BUILDKITE_PIPELINE_SLUG="test-pipeline"
  export BUILDKITE_ORGANIZATION_SLUG="test-org"
  export BUILDKITE_BUILD_NUMBER=42
  export BUILDKITE_COMMAND_EXIT_STATUS=1
  export BUILDKITE_API_TOKEN="test-token"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/annotations" "$TMPDIR"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  printf '%s\n' 'failed command output' > "$BATS_TEST_TMPDIR/logs"
  printf '%s\n' '{"content":[{"type":"text","text":"# Analysis\n\nCheck `config`."}]}' > "$BATS_TEST_TMPDIR/response"

  # An executable (not a shell function) catches payloads passed through argv.
  cat > "$BATS_TEST_TMPDIR/bin/aws" <<'AWS'
#!/bin/bash
set -euo pipefail
case "$*" in
  *list-foundation-models*) echo '- anthropic.claude-3-7-sonnet-20250219-v1:0' ;;
  *list-inference-profiles*) echo '- us.anthropic.claude-3-7-sonnet-20250219-v1:0' ;;
  *get-caller-identity*|*get-foundation-model*) echo '{}' ;;
  *invoke-model*)
    touch "$BATS_TEST_TMPDIR/invoked"
    printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/aws-args"
    response="${@: -1}"
    while [ "$1" != --body ]; do shift; done
    body="$2"
    [[ "$body" == fileb://* ]]
    request="${body#fileb://}"
    printf '%s' "$request" > "$BATS_TEST_TMPDIR/request-path"
    [ "$(stat -c %a "$request")" = 600 ]
    cp "$request" "$BATS_TEST_TMPDIR/request"
    if [ "${CANCEL_AWS:-false}" = true ]; then
      kill -TERM "$PPID"
      exit 0
    fi
    if [ "${FAIL_AWS:-false}" = true ]; then exit 1; fi
    cp "$BATS_TEST_TMPDIR/response" "$response"
    ;;
  *) exit 1 ;;
esac
AWS
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'CURL'
#!/bin/bash
case "${@: -1}" in
  */log) jq -Rs '{content: .}' < "$BATS_TEST_TMPDIR/logs" ;;
  *) echo '{}' ;;
esac
CURL
  cat > "$BATS_TEST_TMPDIR/bin/buildkite-agent" <<'AGENT'
#!/bin/bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/annotation-calls"
if [ "${FAIL_ANNOTATION:-false}" = true ]; then
  cat > /dev/null
  exit 1
fi
while [ "$1" != --context ]; do shift; done
cat > "$BATS_TEST_TMPDIR/annotation"
cp "$BATS_TEST_TMPDIR/annotation" "$BATS_TEST_TMPDIR/annotations/$2"
AGENT
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
}

teardown() {
  rm -f /tmp/claude_bedrock_{response,debug}_"${BUILDKITE_JOB_ID}"_* \
    "/tmp/buildkite_logs_${BUILDKITE_JOB_ID}.txt" \
    "/tmp/ai_success_${BUILDKITE_JOB_ID}.md" \
    "/tmp/ai_error_${BUILDKITE_JOB_ID}.md"
}

@test "Extracts every text block, preserving Markdown and excluding non-text blocks" {
  cat > "$BATS_TEST_TMPDIR/response" <<'JSON'
{"content":[{"type":"thinking","thinking":"private","signature":"secret"},{"type":"text","text":"# Analysis\n\n`code` and **bold**"},{"type":"redacted_thinking","data":"hidden"},{"type":"tool_use","text":"not analysis"},{"type":"text","text":"| A | B |\n|---|---|\n| 1 | 2 |"}]}
JSON
  run extract_claude_response "$BATS_TEST_TMPDIR/response"
  assert_success
  assert_output $'# Analysis\n\n`code` and **bold**\n\n| A | B |\n|---|---|\n| 1 | 2 |'
}

@test "Preserves legacy string responses" {
  for response in '{"completion":"Legacy answer"}' '{"content":"Legacy answer"}'; do
    printf '%s' "$response" > "$BATS_TEST_TMPDIR/response"
    run extract_claude_response "$BATS_TEST_TMPDIR/response"
    assert_success
    assert_output 'Legacy answer'
  done
}

@test "Rejects malformed, missing, and non-text responses" {
  for response in 'not JSON' '{}' '{"content":[{"type":"thinking","signature":"secret"}]}' \
    '{"content":[{"type":"text","text":"  \n"}]}' '{"content":{"text":"wrong shape"}}'; do
    printf '%s' "$response" > "$BATS_TEST_TMPDIR/response"
    run extract_claude_response "$BATS_TEST_TMPDIR/response"
    assert_failure
    assert_output --partial 'Error:'
    refute_output --partial 'secret'
  done
  run extract_claude_response "$BATS_TEST_TMPDIR/missing"
  assert_failure
  assert_output --partial 'Error:'
}

@test "Large prompts cross both jq and AWS boundaries without truncation" {
  head -c 160000 /dev/zero | tr '\0' x > "$BATS_TEST_TMPDIR/prompt"
  printf '\nLast failure: "quoted" \\ path\t日本語\nend' >> "$BATS_TEST_TMPDIR/prompt"
  run call_bedrock_api model profile "$(cat "$BATS_TEST_TMPDIR/prompt")"
  assert_success
  jq -j '.messages[0].content' "$BATS_TEST_TMPDIR/request" > "$BATS_TEST_TMPDIR/actual"
  cmp "$BATS_TEST_TMPDIR/prompt" "$BATS_TEST_TMPDIR/actual"
  [ ! -e "$(cat "$BATS_TEST_TMPDIR/request-path")" ]
}

@test "JSON escaping cannot overflow the AWS argument limit" {
  head -c 80000 /dev/zero | tr '\0' '"' > "$BATS_TEST_TMPDIR/prompt"
  run call_bedrock_api model profile "$(cat "$BATS_TEST_TMPDIR/prompt")"
  assert_success
  jq -j '.messages[0].content' "$BATS_TEST_TMPDIR/request" > "$BATS_TEST_TMPDIR/actual"
  cmp "$BATS_TEST_TMPDIR/prompt" "$BATS_TEST_TMPDIR/actual"
  [ ! -e "$(cat "$BATS_TEST_TMPDIR/request-path")" ]
}

@test "Request construction failure stops before invoking Bedrock and cleans up" {
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/jq"
  chmod +x "$BATS_TEST_TMPDIR/bin/jq"
  run call_bedrock_api model profile prompt
  assert_failure
  assert_output --partial 'Error: Failed to prepare Bedrock request'
  [ ! -e "$BATS_TEST_TMPDIR/invoked" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "Bedrock failure cleans up the private request file" {
  export FAIL_AWS=true
  run call_bedrock_api model profile prompt
  assert_failure
  assert_output --partial 'Error: Bedrock API call failed'
  [ -s "$BATS_TEST_TMPDIR/request-path" ]
  [ ! -e "$(cat "$BATS_TEST_TMPDIR/request-path")" ]
}

@test "Terminating the Bedrock invocation cleans up its request file" {
  export CANCEL_AWS=true
  run bash -c 'source lib/plugin.bash; response=$(call_bedrock_api model profile prompt)'
  assert_failure 143
  [ -s "$BATS_TEST_TMPDIR/request-path" ]
  [ ! -e "$(cat "$BATS_TEST_TMPDIR/request-path")" ]
}

@test "Request cleanup preserves the caller's EXIT trap" {
  run bash -c '
    source lib/plugin.bash
    trap "echo caller-cleanup" EXIT
    call_bedrock_api model profile prompt
    [ ! -e "$(cat "$BATS_TEST_TMPDIR/request-path")" ]
    echo caller-continued
  '
  assert_success
  assert_output --partial 'caller-continued'
  assert_output --partial 'caller-cleanup'
}

@test "Hook passes the default and configured read timeout to AWS" {
  local timeout
  for timeout in 3600 137; do
    if [ "$timeout" = 3600 ]; then
      unset BUILDKITE_PLUGIN_BEDROCK_SUMMARIZE_TIMEOUT
    else
      export BUILDKITE_PLUGIN_BEDROCK_SUMMARIZE_TIMEOUT="$timeout"
    fi
    run "$PWD/hooks/post-command"
    assert_success
    run awk '/^--cli-read-timeout$/ { getline; print }' "$BATS_TEST_TMPDIR/aws-args"
    assert_output "$timeout"
  done
}

@test "Hook annotates extracted Markdown through the real large-log analysis path" {
  head -c 160000 /dev/zero | tr '\0' x > "$BATS_TEST_TMPDIR/logs"
  printf '\nFAILURE AT END\n' >> "$BATS_TEST_TMPDIR/logs"
  printf '%s\n' '{"content":[{"type":"thinking","signature":"secret"},{"type":"text","text":"# Analysis\n\nCheck `config`."}]}' > "$BATS_TEST_TMPDIR/response"
  run "$PWD/hooks/post-command"
  assert_success
  assert_output --partial 'AI Analysis Complete'
  grep -F '# Analysis' "$BATS_TEST_TMPDIR/annotation"
  grep -F 'Check `config`.' "$BATS_TEST_TMPDIR/annotation"
  run grep -E 'signature|secret|"type"' "$BATS_TEST_TMPDIR/annotation"
  assert_failure 1
  jq -e --rawfile logs "$BATS_TEST_TMPDIR/logs" \
    '.messages[0].content | contains($logs | rtrimstr("\n"))' "$BATS_TEST_TMPDIR/request"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/annotation-calls")" -eq 1 ]
}

@test "Hook retains exactly the last 500 of 800 large log lines and includes the footer" {
  export BUILDKITE_PLUGIN_BEDROCK_SUMMARIZE_MAX_LOG_LINES=500
  local padding line
  padding=$(printf '%0360d' 0)
  : > "$BATS_TEST_TMPDIR/logs"
  : > "$BATS_TEST_TMPDIR/expected"
  for ((line=1; line<=800; line++)); do
    printf 'LOG-%04d %s\n' "$line" "$padding" >> "$BATS_TEST_TMPDIR/logs"
    if ((line>=301)); then
      printf 'LOG-%04d %s\n' "$line" "$padding" >> "$BATS_TEST_TMPDIR/expected"
    fi
  done

  # The API may return content with or without a final newline.
  for ending in newline no-newline; do
    if [ "$ending" = no-newline ]; then
      printf '%s' "$(cat "$BATS_TEST_TMPDIR/logs")" > "$BATS_TEST_TMPDIR/logs"
    fi
    run "$PWD/hooks/post-command"
    assert_success
    assert_output --partial 'AI Analysis Complete'
    jq -j '.messages[0].content | split("Step Logs (last 500 lines):\n```\n")[1] | split("\n```")[0]' \
      "$BATS_TEST_TMPDIR/request" > "$BATS_TEST_TMPDIR/retained"
    [ "$(grep -c '^LOG-' "$BATS_TEST_TMPDIR/retained")" -eq 500 ]
    [ "$(cat "$BATS_TEST_TMPDIR/retained")" = "$(cat "$BATS_TEST_TMPDIR/expected")" ]
    [ "$(wc -c < "$BATS_TEST_TMPDIR/retained")" -gt 131072 ]
    grep -F 'Generated by anthropic.claude-3-7-sonnet-20250219-v1:0 via Bedrock at ' "$BATS_TEST_TMPDIR/annotation"
  done
}

@test "Hook reports API and parse failures without a success annotation or failing the job" {
  for failure in api parse; do
    rm -f "$BATS_TEST_TMPDIR/annotation-calls"
    if [ "$failure" = api ]; then
      export FAIL_AWS=true
    else
      export FAIL_AWS=false
      printf '%s\n' '{"content":[{"type":"thinking","signature":"secret"}]}' > "$BATS_TEST_TMPDIR/response"
    fi
    run "$PWD/hooks/post-command"
    assert_success
    assert_output --partial 'AI analysis failed'
    refute_output --partial 'Analysis completed'
    refute_output --partial 'AI Analysis Complete'
    grep -F 'AI Analysis Failed' "$BATS_TEST_TMPDIR/annotation"
    grep -F -- '--style warning' "$BATS_TEST_TMPDIR/annotation-calls"
    [ "$(wc -l < "$BATS_TEST_TMPDIR/annotation-calls")" -eq 1 ]
    run grep -F 'secret' "$BATS_TEST_TMPDIR/annotation"
    assert_failure 1
  done
}

@test "Annotation upload failures do not fail a successful user command" {
  export BUILDKITE_COMMAND_EXIT_STATUS=0
  export BUILDKITE_PLUGIN_BEDROCK_SUMMARIZE_TRIGGER=always
  export FAIL_ANNOTATION=true
  local failure
  for failure in false true; do
    export FAIL_AWS="$failure"
    run "$PWD/hooks/post-command"
    assert_success
    assert_output --partial 'Warning: failed to create annotation'
  done
}

@test "A failed analysis in another job preserves the build's successful annotation" {
  local context="claude-analysis-${BUILDKITE_BUILD_ID}"
  run "$PWD/hooks/post-command"
  assert_success
  cp "$BATS_TEST_TMPDIR/annotations/$context" "$BATS_TEST_TMPDIR/success-annotation"

  # Clean the first job's temporary files before simulating a different job.
  teardown
  export BUILDKITE_JOB_ID="${BUILDKITE_BUILD_ID}-other"
  export FAIL_AWS=true
  run "$PWD/hooks/post-command"
  assert_success
  cmp "$BATS_TEST_TMPDIR/success-annotation" "$BATS_TEST_TMPDIR/annotations/$context"
  grep -F 'AI Analysis Failed' "$BATS_TEST_TMPDIR/annotations/${context}-error"
}
