#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  # Common test variables
  export BUILDKITE_BUILD_ID='test-build-123'
  export BUILDKITE_JOB_ID='test-job-456'
  export BUILDKITE_PIPELINE_SLUG='test-pipeline'

  # Mock aws command for all tests
  # shellcheck disable=SC2329  # Mock command for BATS test; intentional redefinition
  aws() {
    case "$*" in
      *"list-foundation-models"*)
        # Return mock Bedrock models in the format expected by sed 's/^- //'
        cat << 'EOF'
- anthropic.claude-3-5-sonnet-20241022-v2:0
- anthropic.claude-3-sonnet-20240229-v1:0
- anthropic.claude-3-haiku-20240307-v1:0
- amazon.titan-text-express-v1
EOF
        ;;
      *"list-inference-profiles"*)
        # Return mock inference profiles in the format expected by sed 's/^- //'
        cat << 'EOF'
- us.anthropic.claude-3-5-sonnet-20241022-v2:0
- us.anthropic.claude-3-sonnet-20240229-v1:0
- us.anthropic.claude-3-haiku-20240307-v1:0
EOF
        ;;
      *"get-caller-identity"*)
        # Return mock AWS identity JSON
        echo '{"UserId": "AIDACKCEVSQ6C2EXAMPLE", "Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/testuser"}'
        ;;
      *)
        # Default case - just return success
        return 0
        ;;
    esac
    return 0
  }

  # Load validation functions
  source "$PWD/lib/validation.bash"
}

@test "Validate configuration succeeds with valid inputs" {
  run validate_configuration "anthropic.claude-3-sonnet-20240229-v1:0" "us.anthropic.claude-3-sonnet-20240229-v1:0" "on-failure" "step" "false" ""

  assert_success
  refute_output --partial "Error"
}

@test "Validate configuration fails with invalid model" {
  run validate_configuration "invalid-model" "us.anthropic.claude-3-sonnet-20240229-v1:0" "on-failure" "step" "false" ""

  assert_failure  # Function should return error code now
  assert_output --partial "Error: invalid-model is not valid Bedrock model"
}

@test "Validate configuration fails with invalid inference profile" {
  run validate_configuration "anthropic.claude-3-sonnet-20240229-v1:0" "invalid-profile" "on-failure" "step" "false" ""

  assert_failure  # Function should return error code now
  assert_output --partial "Error: invalid-profile is not valid Bedrock inference profile"
}

@test "Validate configuration fails with invalid trigger" {
  run validate_configuration "anthropic.claude-3-sonnet-20240229-v1:0" "us.anthropic.claude-3-sonnet-20240229-v1:0" "invalid-trigger" "step" "false" ""

  assert_failure
  assert_output --partial "Error: trigger must be one of: on-failure, always, manual"
}

@test "Validate configuration fails with invalid analysis level" {
  run validate_configuration "anthropic.claude-3-sonnet-20240229-v1:0" "us.anthropic.claude-3-sonnet-20240229-v1:0" "on-failure" "invalid-level" "false" ""

  assert_failure
  assert_output --partial "Error: analysis_level must be one of: step, build"
}

@test "Validate configuration warns about missing API token for build level" {
  run validate_configuration "anthropic.claude-3-sonnet-20240229-v1:0" "us.anthropic.claude-3-sonnet-20240229-v1:0" "on-failure" "build" "false" ""

  assert_success
  assert_output --partial "Warning: build-level analysis works best with a Buildkite API token"
}

@test "Validate configuration warns about missing API token for build comparison" {
  run validate_configuration "anthropic.claude-3-sonnet-20240229-v1:0" "us.anthropic.claude-3-sonnet-20240229-v1:0" "on-failure" "step" "true" ""

  assert_success
  assert_output --partial "Warning: build comparison requires a Buildkite API token"
}

@test "Validate tools succeeds with available tools" {
  # Mock commands
  # shellcheck disable=SC2329  # Mock command for BATS test; intentional redefinition
  command() {
    return 0
  }

  run validate_tools

  assert_success
  refute_output --partial "Error"
}

@test "Validate tools fails when curl is missing" {
  # Mock commands
  # shellcheck disable=SC2329  # Mock command for BATS test; intentional redefinition
  command() {
    if [[ "$*" == *"curl"* ]]; then
      return 1
    fi
    return 0
  }

  run validate_tools

  assert_failure
  assert_output --partial "Error: curl is required"
}

@test "Validate tools fails when jq is missing" {
  # Mock commands
  # shellcheck disable=SC2317,SC2329
  command() {
    if [[ "$*" == *"jq"* ]]; then
      return 1
    fi
    return 0
  }

  run validate_tools

  assert_failure
  assert_output --partial "Error: jq is required"
}

@test "Validate tools fails when aws is missing" {
  # Mock commands
  # shellcheck disable=SC2317
  command() {
    if [[ "$*" == *"aws"* ]]; then
      return 1
    fi
    return 0
  }

  run validate_tools

  assert_failure
  assert_output --partial "Error: aws is required"
}