# Bedrock Summarize Buildkite Plugin 

AI-powered build analysis and error diagnosis using Large Language Models (LLMs) provided by Amazon Bedrock. You can use any LLM offered by Amazon Bedrock, provided it is enabled on your AWS account. This plugin automatically analyzes build failures, provides root cause analysis, and suggests actionable fixes through Buildkite annotations.

## Features

- 🤖 **Intelligent Build Analysis**: AI analyzes build logs to identify root causes of failures
- 📋 **Buildkite Annotations**: Creates rich annotations with analysis results and suggested fixes
- ⚡ **Smart Triggering**: Configurable triggers (on-failure, always, manual)
- 🔧 **Actionable Insights**: Provides specific steps to resolve issues and prevent future failures
- 🎯 **Context-Aware**: Understands build context including branch, commit, and job information

## Requirements

- **curl**: For API requests
- **jq**: For JSON processing
- **AWS CLI**: Must be installed on agents and set up with access to AWS Bedrock
- **Bedrock**: Your AWS account needs access to Amazon Bedrock, and your desired model(s) must be enabled

## Quick Start

1. Add the plugin to your pipeline like this:

```yaml
steps:
  - label: "🧪 Run tests"
    command: "npm test"
    plugins:
      - bedrock-summarize#v1.0.0: ~
```

## Configuration Options

### Optional

#### `buildkite_api_token` (string)

Buildkite API token for fetching job logs directly from the Buildkite API. This improves analysis by providing the exact failing job logs. If not specified, the plugin will look for `BUILDKITE_API_TOKEN` in the environment.

#### `model` (string)

Bedrock model to use for analysis. Default: `anthropic.claude-3-7-sonnet-20250219-v1:0`

#### `inference_profile` (string)

Bedrock inference profile to use for analysis. Default: `us.anthropic.claude-3-7-sonnet-20250219-v1:0`

#### `trigger` (string)

When to trigger AI analysis. Options: `on-failure`, `always`, `manual`. Default: `on-failure`

- `on-failure`: Only analyze when the build step fails
- `always`: Analyze every build (success or failure)
- `manual`: Only when `BEDROCK_ANALYZE=true` environment variable is set or commit message contains `[bedrock-analyze]`

#### `analysis_level` (string)

Level at which to analyze logs. Options: `step`, `build`. These require `buildkite_api_token` to be set in order to fetch job logs, else we default to available environment variables. Default: `step`

- `step`: Analyze only the current step's logs
- `build`: Analyze logs from all jobs in the entire build

#### `max_log_lines` (integer)

Maximum number of log lines to send to the LLM for analysis. Default: `1000`

#### `custom_prompt` (string)

Additional context or instructions to include in the analysis prompt.

#### `timeout` (integer)

Timeout in seconds for Bedrock API requests. Default: `60`

#### `annotate` (boolean)

Whether to create Buildkite annotations with the analysis results. Default: `true`

#### `agent_file` (boolean or string)

Include project context from an agent file in the analysis. Default: `false`

- `true`: Include `AGENT.md` from the repository root
- `false`: Don't include any agent context
- `"path/to/file.md"`: Include the specified file

The agent file should contain project-specific context like architecture details, common issues, coding standards, or troubleshooting guides that help LLMs provide more relevant analysis.

#### `compare_builds` (boolean)

Enable build time comparison analysis. When enabled, the LLM will analyze build time trends by comparing the current build duration against recent builds. Default: `false`

#### `comparison_range` (integer)

Number of previous builds to compare against for build time analysis. Only used when `compare_builds` is `true`. Default: `5`

## Examples

### Basic Usage - Analyze Failed Tests

```yaml
steps:
  - label: "🧪 Run tests"
    command: "npm test"
    plugins:
      - bedrock-summarize#v1.0.0
```

When tests fail, the LLM will analyze the output and create an annotation with:
- Root cause analysis
- Key error explanations
- Suggested fixes
- Prevention strategies

### Build-Level Analysis

```yaml
steps:
  - label: "🔍 Analyze entire build"
    command: "npm test"
    plugins:
      - bedrock-summarize#v1.0.0:
          buildkite_api_token: "$$BUILDKITE_API_TOKEN"
          analysis_level: "build"
          trigger: "always"
```

With `analysis_level: "build"`, the LLM will analyze logs from all jobs in the build, providing insights across the entire pipeline.

### Always Analyze Builds

```yaml
steps:
  - label: "🏗️ Build application"
    command: "npm run build"
    plugins:
      - bedrock-summarize#v1.0.0:
          trigger: "always"
          custom_prompt: "Focus on build performance and optimization opportunities"
```

### Manual Analysis with Custom Context

```yaml
steps:
  - label: "🚀 Deploy to staging"
    command: "./deploy.sh staging"
    env:
      BEDROCK_ANALYZE: "true"  # Trigger manual analysis
    plugins:
      - bedrock-summarize#v1.0.0:
          trigger: "manual"
          custom_prompt: "This is a deployment script. Focus on infrastructure and configuration issues."
          max_log_lines: 2000
```

### Build Time Analysis

```yaml
steps:
  - label: "🏗️ Build with performance tracking"
    command: "npm run build"
    plugins:
      - bedrock-summarize#v1.0.0:
          compare_builds: true
          comparison_range: 10
          custom_prompt: "Focus on build performance trends and identify any performance regressions"
```

When `compare_builds` is enabled, the LLM will:
- Compare current build time against the last N builds (configurable via `comparison_range`)
- Identify performance trends and anomalies
- Suggest optimizations for slow builds
- Highlight significant performance changes

### Multiple Steps with Different Configurations

```yaml
steps:
  - label: "🔍 Lint code"
    command: "npm run lint"
    plugins:
      - bedrock-summarize#v1.0.0:
          custom_prompt: "Focus on code quality and style issues"

  - label: "🧪 Run tests"
    command: "npm test"
    plugins:
      - bedrock-summarize#v1.0.0:
          custom_prompt: "Focus on test failures and coverage issues"

  - label: "🏗️ Build production"
    command: "npm run build:prod"
    plugins:
      - bedrock-summarize#v1.0.0:
          trigger: "always"
          custom_prompt: "Focus on build optimization and bundle analysis"
```

## Compatibility

| Elastic Stack | Agent Stack K8s | Hosted (Mac) | Hosted (Linux) | Notes |
| :-----------: | :-------------: | :----------: | :------------: | :---- |
| ✅ | ✅ | ✅ | ✅ |   |

- ✅ Fully compatible assuming requirements are met

## ⚒ Developing

Run tests with

```bash
docker compose run --rm tests
```

## 👩‍💻 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

Please follow the existing code style and include tests for any new features.

## 📜 License

The package is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
