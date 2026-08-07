#!/usr/bin/env bats

# shellcheck disable=SC2030,SC2031 # Disable warnings for variable modifications in BATS subshells

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  export BUILDKITE_COMMAND_EXIT_STATUS='1'
  export BUILDKITE_BUILD_ID='test-build-123'
  export BUILDKITE_JOB_ID='test-job-456'
  export BUILDKITE_PIPELINE_SLUG='test-pipeline'
  export BUILDKITE_BUILD_NUMBER='42'
  export BUILDKITE_BRANCH='main'
  export BUILDKITE_COMMIT='abc123'
  export BUILDKITE_LABEL='Test Job'
  export BUILDKITE_BUILD_URL='https://buildkite.com/test/test-pipeline/builds/42'

  # shellcheck disable=SC2329  # Mock command for BATS test; intentional redefinition
  aws() {
    case "$*" in
      *"list-foundation-models"*)
        cat << 'EOF'
- anthropic.claude-3-7-sonnet-20250219-v1:0
EOF
        ;;
      *"list-inference-profiles"*)
        cat << 'EOF'
- us.anthropic.claude-3-7-sonnet-20250219-v1:0
EOF
        ;;
      *"get-caller-identity"*)
        echo '{"Account": "123456789012"}'
        ;;
      *)
        return 0
        ;;
    esac
    return 0
  }
  export -f aws

  mkdir -p /tmp/test-bin
  cat > /tmp/test-bin/aws << 'EOF'
#!/bin/bash
aws "$@"
EOF
  chmod +x /tmp/test-bin/aws
  export PATH="/tmp/test-bin:$PATH"

  stub curl \
    "* : echo '200'"
  stub jq \
    "* : echo 'Mock analysis from Claude'"
  source "$PWD/lib/plugin.bash"
}

teardown() {
  rm -f "/tmp/test-bin/aws"
  unstub curl || true
  unstub jq || true
  unstub buildkite-agent || true
}

@test "Annotation context is shared across the build by default" {
  run annotation_context "build" "false"

  assert_success
  assert_output 'claude-analysis-test-build-123'
}

@test "Annotation context is unique per job when scoped to the job" {
  run annotation_context "job" "false"

  assert_success
  assert_output 'claude-analysis-test-job-456'
}

@test "Annotation context falls back to the build when there is no job id" {
  unset BUILDKITE_JOB_ID

  run annotation_context "job" "false"

  assert_success
  assert_output 'claude-analysis-test-build-123'
}

@test "Annotation context is randomised when multiple annotations are allowed" {
  first="$(annotation_context "build" "true")"
  second="$(annotation_context "build" "true")"

  [ "${first}" != "${second}" ]
  [[ "${first}" == claude-analysis-test-build-123-* ]]
  [[ "${second}" == claude-analysis-test-build-123-* ]]
}

@test "Annotation context keeps the job scope when multiple annotations are allowed" {
  run annotation_context "job" "true"

  assert_success
  assert_output --regexp '^claude-analysis-test-job-456-[0-9a-f]+$'
}

@test "Plugin annotates at build scope by default" {
  # A four-argument plan also proves no --scope flag is passed, which keeps the
  # plugin working on agents older than v3.112.0
  # shellcheck disable=SC2016 # the expansions are evaluated by the stub, not here
  stub buildkite-agent \
    'annotate --style * --context * : echo "annotated --style $3 --context $5 scope=${BUILDKITE_ANNOTATION_SCOPE}"'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Annotation Scope: build'
  assert_output --partial 'annotated --style error --context claude-analysis-test-build-123 scope=build'
}

@test "Plugin annotates at job scope when configured" {
  export BUILDKITE_PLUGIN_BEDROCK_SUMMARIZE_ANNOTATION_SCOPE='job'

  # shellcheck disable=SC2016 # the expansions are evaluated by the stub, not here
  stub buildkite-agent \
    'annotate --style * --context * : echo "annotated --context $5 scope=${BUILDKITE_ANNOTATION_SCOPE}"'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Annotation Scope: job'
  assert_output --partial 'annotated --context claude-analysis-test-job-456 scope=job'
}

@test "Plugin pins the scope over one set in the job environment" {
  export BUILDKITE_ANNOTATION_SCOPE='job'

  # shellcheck disable=SC2016 # the expansions are evaluated by the stub, not here
  stub buildkite-agent \
    'annotate --style * --context * : echo "annotated --context $5 scope=${BUILDKITE_ANNOTATION_SCOPE}"'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'annotated --context claude-analysis-test-build-123 scope=build'
}

@test "Plugin adds a unique context when multiple annotations are allowed" {
  export BUILDKITE_PLUGIN_BEDROCK_SUMMARIZE_ALLOW_MULTIPLE_ANNOTATIONS='true'

  # shellcheck disable=SC2016 # $5 is expanded by the stub, not here
  stub buildkite-agent \
    'annotate --style * --context * : echo "annotated --context $5"'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Multiple Annotations: ENABLED'
  assert_output --regexp 'annotated --context claude-analysis-test-build-123-[0-9a-f]+'
}

@test "Plugin rejects an invalid annotation scope" {
  export BUILDKITE_PLUGIN_BEDROCK_SUMMARIZE_ANNOTATION_SCOPE='pipeline'

  run "$PWD"/hooks/post-command

  assert_failure
  assert_output --partial 'annotation_scope must be one of: build, job'
}
