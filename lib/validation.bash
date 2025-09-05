#!/bin/bash
set -euo pipefail

# Configuration validation function
# Returns 0 if validation passes, non-zero if validation fails
function validate_configuration() {
  local model="$1"
  local inference_profile="$2"
  local trigger="$3"
  local analysis_level="$4"
  local compare_builds="$5"
  local buildkite_api_token="$6"
  
  local errors=0
  
  # Validate model
  bedrock_models=()

  # List available Bedrock models
  while IFS= read -r line; do
      bedrock_models+=("$line")
  done < <(aws --query "modelSummaries[*].modelId" bedrock list-foundation-models --output yaml | sed 's/^- //')

  # Check if the requested model is valid
  if [[ ! " ${bedrock_models[*]} " =~ " ${model} " ]]; then
      echo "❌ Error: $model is not valid Bedrock model."
  fi
  
  # Validate inference profile
  inference_profiles=()

  # List available Bedrock inference profiles
  while IFS= read -r line; do
      inference_profiles+=("$line")
  done < <(aws --query "inferenceProfileSummaries[*].inferenceProfileId" bedrock list-inference-profiles --output yaml | sed 's/^- //')

  # Check if the requested inference profile is valid
  if [[ ! " ${inference_profiles[*]} " =~ " ${inference_profile} " ]]; then
      echo "❌ Error: $inference_profile is not valid Bedrock inference profile."
  fi
  
  # Validate trigger
  if [[ ! "${trigger}" =~ ^(on-failure|always|manual)$ ]]; then
    echo "❌ Error: trigger must be one of: on-failure, always, manual. Got: ${trigger}" >&2
    errors=$((errors + 1))
  fi
  
  # Validate analysis_level
  if [[ ! "${analysis_level}" =~ ^(step|build)$ ]]; then
    echo "❌ Error: analysis_level must be one of: step, build. Got: ${analysis_level}" >&2
    errors=$((errors + 1))
  fi
  
  # Check for Buildkite API token when build level analysis is requested
  if [ "${analysis_level}" = "build" ] && [ "${buildkite_api_token}" = "" ] && [ -z "${BUILDKITE_API_TOKEN:-}" ]; then
    echo "⚠️ Warning: build-level analysis works best with a Buildkite API token" >&2
    echo "   Set buildkite_api_token or ensure BUILDKITE_API_TOKEN environment variable is available" >&2
  fi
  
  # Check for Buildkite API token when build comparison is enabled
  if [ "${compare_builds}" = "true" ] && [ "${buildkite_api_token}" = "" ] && [ -z "${BUILDKITE_API_TOKEN:-}" ]; then
    echo "⚠️ Warning: build comparison requires a Buildkite API token" >&2
    echo "   Set buildkite_api_token or ensure BUILDKITE_API_TOKEN environment variable is available" >&2
  fi
  
  return ${errors}
}

# Check for required tools
# Returns 0 if all tools are available, non-zero otherwise
function validate_tools() {
  local errors=0
  
  # Check for curl
  if ! command -v curl >/dev/null 2>&1; then
    echo "❌ Error: curl is required but not installed" >&2
    errors=$((errors + 1))
  fi
  
  # Check for jq
  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ Error: jq is required but not installed" >&2
    errors=$((errors + 1))
  fi
  
  # Check for aws
  if ! command -v aws >/dev/null 2>&1; then
    echo "❌ Error: aws is required but not installed" >&2
    errors=$((errors + 1))
  else
    # Validate AWS access
    if ! aws sts get-caller-identity 2>&1; then
      echo "❌ Error: AWS access not configured!" >&2
      errors=$((errors + 1))
    fi
  fi

  return ${errors}
}