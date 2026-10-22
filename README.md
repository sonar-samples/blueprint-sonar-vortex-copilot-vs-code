# How to set up Sonar Vortex in VS Code with GitHub Copilot

## TL;DR Overview

- [Sonar Vortex](https://www.sonarsource.com/products/sonar-vortex/) connects VS Code with GitHub Copilot to SonarQube's full analysis engine, supplying your project's coding guidelines and architectural constraints to the agent before it writes code, then verifying every file it changed before it replies.
- Vortex fits teams running GitHub Copilot in the VS Code Agents Window against a codebase SonarQube already analyzes in CI, who want project standards enforced during generation rather than after a pull request triggers a pipeline.
- Verification inside the agent loop returns CI-depth findings in seconds, so the agent corrects its own output before a human opens a diff.
- The [SonarQube](https://www.sonarsource.com/products/sonarqube/) plugin for GitHub Copilot installs from the `awesome-copilot` marketplace in the VS Code Agents Window, contributes dedicated `sonar-*` skills and a selectable `sonarqube-reviewer` agent, and its `sonar-integrate` skill wires up the SonarQube MCP Server, secrets detection, Sonar Vortex context, and a managed Vortex analysis protocol.

[Sonar Vortex](https://www.sonarsource.com/products/sonar-vortex/) delivers project context to AI coding agents and runs [SonarQube](https://www.sonarsource.com/products/sonarqube/) analysis inside the agent's loop, and in VS Code with GitHub Copilot you enable it through the [SonarQube plugin](https://github.com/sonarsource/sonarqube-agent-plugins). Coding agents generate code without knowledge of a project's established standards, architectural boundaries, or issue history, and typically nothing verifies their output until CI runs after a pull request. This blueprint configures Vortex to supply context before the agent writes and trigger verification as it writes: installing and activating the plugin, running the integration, reviewing what the integration configured, guiding the agent with context and constraints, verifying the agentic loop on a real edit, and running multi-file DEEP analysis. Every example in this guide runs against a fork of [aws-cli](https://github.com/aws/aws-cli), a large Python codebase analyzed in SonarQube ([Cloud](https://www.sonarsource.com/products/sonarqube/cloud/) in the case of this blueprint) through CI.

## When to use this

You want VS Code with GitHub Copilot to abide by your project's existing coding standards and catch issues as it writes code, not after a PR triggers CI. Reach for this blueprint when:

- You run GitHub Copilot in the VS Code Agents Window against a codebase SonarQube already analyzes.
- You want the agent following your project's conventions instead of generic language defaults.
- You want issues surfaced inside the agentic coding loop rather than by a CI-blocked pull request.

Three Sonar integrations touch VS Code, but this blueprint covers the SonarQube plugin running in the **Agents Window**. If you're working from the terminal instead, see [How to set up Sonar Vortex in GitHub Copilot CLI](https://www.sonarsource.com/resources/library/how-to-set-up-sonar-vortex-in-github-copilot-cli/). If you want on-the-fly analysis in the editor without any CLI setup, reach for [SonarQube for IDE](https://docs.sonarsource.com/sonarqube-for-vs-code/).

## What you'll achieve

- The SonarQube plugin for GitHub Copilot installed from the `awesome-copilot` marketplace, with `sonar-*` skills and the `sonarqube-reviewer` agent available in the Agents Window, and the SonarQube MCP Server running in a container via `sonar run mcp`.
- Sonar Vortex context delivering coding guidelines, architectural constraints, and semantic code navigation to the agent before it writes, plus dependency health checks where [SonarQube Advanced Security](https://www.sonarsource.com/products/sonarqube/advanced-security/) is enabled.
- A managed Vortex analysis protocol that runs `sonar analyze agentic --depth DEEP` across every file the agent changed before it replies, plus a `preToolUse` secrets hook that denies reads when credentials are detected.

## Architecture

![](https://assets-eu-01.kc-usercontent.com:443/ef593040-b591-0198-9506-ed88b30bc023/9e70c788-5779-421a-9702-a244905b8705/vortex-vscode-3.png)

The integration splits across two layers.

The plugin layer contributes skills and an agent, but owns no runtime infrastructure. It installs from the `awesome-copilot` marketplace, which is registered by default, so there's no marketplace to add first. The source bundle lives at `.github/plugin/` in [SonarSource/sonarqube-agent-plugins](https://github.com/SonarSource/sonarqube-agent-plugins). It ships `sonar-*` skills and the `sonarqube-reviewer` agent.

The SonarQube CLI layer does the work. Starting with CLI 1.9, it installs the integration globally, into `~/.copilot/` in your user home, rather than into a single project. The same MCP registration, hooks, and instructions then apply to every project you open in VS Code. `sonar auth login` holds your authenticated session in the OS keychain. `sonar run mcp` starts the SonarQube MCP Server container, which VS Code talks to over stdio. The secrets hook script is a short shell wrapper that calls `sonar hook copilot-pre-tool-use`, so it reuses that same keychain session, and `sonar context` powers Vortex context.

What makes the analysis fast enough to sit in a coding loop is that it recomputes nothing. A CI run stores your project's dependencies, compiled artifacts, type information, and build configuration, tagged by project key and branch. Vortex restores that context on demand, so a check returns in seconds at the same depth as a full scan.

Vortex context doesn't travel the MCP path. It runs through a local `sonar context` daemon over a Unix domain socket on Linux and macOS, or a named pipe on Windows, which gives it direct filesystem access. Its tools won't appear in your MCP tool list, and that's expected rather than a sign of a broken install.

Vortex covers the Guide and Verify stages of Sonar's [Agent Centric Development Cycle](https://www.sonarsource.com/agent-centric-development/). It guides the agent with project-aware context and constraints, then verifies the agentic loop's output with CI-level precision.

## Prerequisites

- VS Code with GitHub Copilot enabled, running in agent mode
- On Copilot Business or Copilot Enterprise, an administrator must enable the **MCP servers in Copilot** policy before any MCP server will load
- SonarQube Cloud or [Server](https://www.sonarsource.com/products/sonarqube/server/) on [Enterprise, or Team with an annual plan](https://www.sonarsource.com/plans-and-pricing/), and, optionally, a [Sonar Vortex](https://www.sonarsource.com/products/sonar-vortex/) subscription active for your organization
- A container runtime running: Docker, Podman, or nerdctl. The MCP server runs as a container
- (Optional) [SonarQube CLI](https://cli.sonarqube.com/) (`sonar`) 1.9.0 or later. The `sonar-integrate` skill installs or self-updates it, so you can skip this going in. Version 1.9 removed project-level installation, so the integration is always global

To follow along exactly, fork [aws/aws-cli](https://github.com/aws/aws-cli), import it into SonarQube (Cloud in the case of this guide) with CI-based analysis, and analyze it on a long lived branch. Vortex analysis restores the CI analysis context and Vortex context combines SonarQube project data with the local semantic nav.

## Step 1 — Install and activate the plugin

Open the **Agents Window** in VS Code. Navigate to **Plugins** and search for `sonarqube` in the marketplace.

![](https://assets-eu-01.kc-usercontent.com:443/ef593040-b591-0198-9506-ed88b30bc023/a08c0071-a924-4a9b-bff9-7694794ba0f9/vortex-vscode-2.png)

Click **Install**. When VS Code asks you to trust plugins from `github/awesome-copilot#marketplace`, select **Trust**. Then open **Skills** and look at what the plugin brought with it. Multiple skills ship with the plugin:

![](https://assets-eu-01.kc-usercontent.com:443/ef593040-b591-0198-9506-ed88b30bc023/a7d498a5-c527-44ef-84a5-20e07099b0bb/vortex-vscode-6.png)

The plugin is loaded at this point, but nothing is wired to your project yet.

## Step 2 — Configure the integration

Open a new agent session from your project. Under **Agent**, select the default **Agent** *or* **sonarqube-reviewer**, and invoke any of the installed skills with a slash:

![](https://assets-eu-01.kc-usercontent.com:443/ef593040-b591-0198-9506-ed88b30bc023/ae3eca16-5e22-448c-9382-b2da270943fd/vortex-vscode-7.png)

Now run the integration skill:

```
/sonarqube:sonar-integrate
```

The skill walks four checks:

1. **CLI check.** Verifies the SonarQube CLI is installed and runs `sonar self-update`. If the CLI isn't on your machine, it shows the install commands and waits for you to confirm before running one.
2. **Auth check.** Runs `sonar auth status`. If you're already authenticated to SonarQube, it skips ahead.
3. **Auth login.** Select your region (EU or US), enter your organization key, and complete browser-based authentication. The token lands in your OS keychain. The skill hands this step back to you deliberately, because `sonar auth login` opens a browser.
4. **Integration.** The CLI discovers your project (organization, project key, and token validity), then asks where to integrate. SonarQube CLI 1.9 offers only **Global (user home, applies across projects)**. It then asks whether to install each feature: the pre-tool-use secrets hook, the prompt-secrets instructions, Vortex, and the MCP server. Answer **Yes** to all four and press Enter to install. The skill runs `sonar integrate copilot --non-interactive` under the hood.

The summary confirms what was configured:

![](https://assets-eu-01.kc-usercontent.com:443/ef593040-b591-0198-9506-ed88b30bc023/2c4eb1ed-899c-42f6-88ca-7622780a2497/vortex-vscode-8.png)

Restart VS Code before continuing.

## Step 3 — Review what the integration configured

Five artifacts landed in `~/.copilot/` in your user home. Nothing is written to your project, so there is no per-project config to commit or maintain.

**`~/.copilot/mcp-config.json`** registers the MCP server for every project:

```json
{
  "mcpServers": {
    "sonarqube": {
      "command": "sonar",
      "args": ["run", "mcp"]
    }
  }
}
```

The server starts through the CLI rather than a raw `docker run`, which is how the CLI detects your container runtime and hands off the keychain session. Because the registration is global, it carries no project key.

**`~/.copilot/hooks/hooks.json`** registers the hooks. There are three: a `preToolUse` hook for secrets detection, plus `sessionStart` and `subagentStart` hooks that inject Vortex context when a session or subagent begins. The CLI writes each `bash` path as an absolute path to your home directory. The secrets entry looks like this:

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "timeoutSec": 60,
        "bash": "/Users/<you>/.copilot/hooks/sonar-secrets/build-scripts/pretool-secrets.sh"
      }
    ]
  }
}
```

The two context hooks sit alongside it in the same `hooks` object. Both run `session-start-vortex.sh`, so there's nothing to edit for them either:

```bash
#!/bin/bash
if ! command -v sonar &> /dev/null; then
  exit 0
fi
sonar hook agent-session-start --agent copilot
```

**The secrets hook script** is a few lines, and it exits quietly when the CLI isn't on `PATH`:

```bash
#!/bin/bash
if ! command -v sonar &> /dev/null; then
  exit 0
fi
sonar hook copilot-pre-tool-use
```

**`~/.copilot/instructions/sonarqube.instructions.md`** carries two blocks. The first, `sonar:begin:copilot-prompt-secrets`, tells the agent to scan prompt text for credentials before acting, corroborate with `sonar analyze secrets --stdin` when it's uncertain, refuse the request on a hit, and advise you to rotate the credential.

The second, `sonar:begin:sonarqube-agentic-analysis-protocol`, is titled "Vortex analysis protocol" and governs end-of-turn verification:

```
Trigger: the moment before you send your final reply for the turn.

Preferred: pass every path you modified this turn in a single invocation
(repeat --file for each path)... For end-of-turn analysis, always pass
--depth DEEP — even when you changed only one file — so cross-file
findings are included.
```

Which produces a command shaped like this:

```bash
sonar analyze agentic --depth DEEP --file <path1> --file <path2>
```

No `--project` flag appears. Since the instructions are global, the project key is auto-detected from whichever project you're working in.

One thing worth noting about the skill count: at the time of writing, it stays at nine. Earlier CLI versions installed a tenth skill at `.github/skills/sonar-context-augmentation/SKILL.md` to deliver context. From 1.8.0 that skill is gone, replaced by the `sessionStart` and `subagentStart` hooks above.

## Step 4 — Guide the agent with project-aware context and constraints

You don't invoke Vortex context directly. Give the agent a natural language prompt and watch it arrive on its own.

```
what are the coding guidelines for this project?
```

![](https://assets-eu-01.kc-usercontent.com:443/ef593040-b591-0198-9506-ed88b30bc023/9a428c05-33c0-4be3-b9fc-0bfd8198ca7f/vortex-vscode-4.png)

Nine guidelines come back, and they belong to this codebase rather than to [Python](https://www.sonarsource.com/knowledge/languages/python/) generally. Five are Python rules: remove unused local variables, don't hard-code credentials, avoid empty functions and methods, don't create temporary files in publicly writable directories, and don't set world-accessible file permissions. Three cover GitHub Actions: don't use `read-all` or `write-all` permissions, don't execute Python package manager scripts during installation, and lock Python dependencies to verified versions. The last is general: commit the Python dependency lock file to source control.

Each one derives from this project's real SonarQube issue history, filtered by what the agent is about to do. Guidelines get selected two ways, from the nature of the prompt itself and from historical issues in the files the agent plans to touch.

Now the second query:

```
show me the top-level architecture of this project
```

![](https://assets-eu-01.kc-usercontent.com:443/ef593040-b591-0198-9506-ed88b30bc023/c8e53789-a215-4015-937c-a7728fbdea32/vortex-vscode-9.png)

It comes back with a single Python CLI package: `bin/` for launchers and shell completion scripts, `awscli/` for the main application package, `tests/` organized into unit, integration, functional, and dependency suites, and `doc/` for docs and build files. Inside `awscli/` it identifies `clidriver.py` as the component that builds parsers, loads plugins, and dispatches commands, with `plugin.py` and `handlers.py` forming an event-driven extension system and `customizations/` holding service-specific CLI extensions. It closes with the core flow:

```
aws → awscli.__main__ → awscli.clidriver.main() → botocore session +
plugins/customizations → command execution/output formatting
```

Four capability categories back these answers. Intelligent guidelines come from issue history. Architectural awareness exposes the current dependency graph and any constraints you've defined. Semantic navigation resolves call stacks, class hierarchies, and references using abstract syntax trees and control flow rather than keyword matching. Third-party dependency guidance assesses vulnerabilities, supply-chain malware, and license compliance before a package gets added, where [SonarQube Advanced Security](https://www.sonarsource.com/products/sonarqube/advanced-security/) is available.

## Step 5 — Verify the agentic loop

One prompt exercises the whole loop. What follows is a walkthrough from this project, so your findings may differ.

```
Add s3_helper.py at the project root with an upload_with_retry(
bucket, key, file_path, max_retries=3
) function.

Implement a small boto3-based S3 upload helper using the standard upload_file
transfer API. Retry transient upload failures with exponential backoff, log each
attempt, and raise a clear error after all retries fail. Keep the public function
signature as specified. Include a TODO for adding metric emission later.
```

Before touching the filesystem, the agent searches for the project's Python coding guidelines and reviews several files.

![](https://assets-eu-01.kc-usercontent.com:443/ef593040-b591-0198-9506-ed88b30bc023/d6a7ca6a-534d-48a2-8a3d-8b3529aed6e5/vortex-vscode-1.png)

Then it writes `s3_helper.py` with `upload_with_retry(bucket, key, file_path, max_retries=3)`, retrying transient botocore and S3 errors with exponential backoff, logging each attempt, and raising `S3UploadFailedError` with a clear message once retries are exhausted. It includes the metric-emission TODO you asked for, and verifies its work:

```
python -m unittest tests.unit.test_s3_helper
```

Following the managed instructions protocol, it then runs analysis on its own output and gets one finding back:

```
Vortex analysis:
• s3_helper.py • 1 issue
• line 74: Add the 'ExpectedBucketOwner' to the 'ExtraArgs' parameter to
  verify S3 bucket ownership. (python:S7608)
```

`python:S7608` raises when an S3 operation runs without verifying bucket ownership. Without `ExpectedBucketOwner`, a naming collision or a dynamically constructed bucket name can send the upload to a bucket in a different AWS account, which matters most in multi-account setups where bucket names look alike.

The fix adds an optional keyword parameter, which widens the signature the prompt told it to keep. The agent called that deviation out rather than making it silently, and every call written against the original four arguments still behaves the same:

```python
def upload_with_retry(bucket, key, file_path, max_retries=3,
                      expected_bucket_owner=None):
    ...
    extra_args = {}
    if expected_bucket_owner is not None:
        extra_args["ExpectedBucketOwner"] = expected_bucket_owner
```

Then it re-runs analysis on the same scope, and the file comes back clean.

![](https://assets-eu-01.kc-usercontent.com:443/ef593040-b591-0198-9506-ed88b30bc023/6de9e3d4-9601-4500-8c86-edf425fac0d9/vortex-vscode-5.png)

Analysis runs at the end of the turn rather than after each edit. Before replying, the agent must run one DEEP analysis across all files it changed, fix findings on lines it touched, and re-run analysis until clean or only pre-existing findings on untouched lines remain. And the division of labor holds throughout. Vortex flagged, the model decided and fixed, inside a single turn, with nobody reviewing a diff in between.

## Step 6 — Run multi-file DEEP analysis

Single-file analysis won't catch issues that only appear across boundaries. Pass repeated `--file` flags to widen the scope:

```bash
sonar analyze agentic --file awscli/clidriver.py --file s3_helper.py --file awscli/customizations/s3/subcommands.py
```

```
!  awscli/clidriver.py · 1 issue
[1] line 289  Complete the task associated to this "TODO" comment.  python:S1135
!  s3_helper.py · 1 issue
[1] line 27  Complete the task associated to this "TODO" comment.  python:S1135
!  awscli/customizations/s3/subcommands.py · 10 issues
[1] line 903  Define a constant instead of duplicating this literal "%s\nError: Invalid argument type" 3 times.  python:S1192
[2] line 555  Define a constant instead of duplicating this literal 's3://' 8 times.  python:S1192
[3] line 771  Define a constant instead of duplicating this literal "<S3Uri>" 4 times.  python:S1192
[4] line 429  Using HTTP protocol is insecure. Use HTTPS instead.  python:S5332
[5] line 925  Complete the task associated to this "TODO" comment.  python:S1135
[6] line 1096  Refactor this function to reduce its Cognitive Complexity from 24 to the 15 allowed.  python:S3776
[7] line 1248  Either merge this branch with the identical one on line "1230" or change one of the implementations.  python:S1871
[8] line 1474  Refactor this function to reduce its Cognitive Complexity from 16 to the 15 allowed.  python:S3776
[9] line 1510  Use the opposite operator ("!=") instead.  python:S1940
[10] line 1594  Replace the unused local variable "bucket" with "_".  python:S1481

3 files analyzed · 3 with issues · 12 issues found · DEEP analysis
```

The `s3_helper.py` finding is the intentional TODO from Step 5. The `subcommands.py` findings are pre-existing issues in the upstream codebase, which is exactly the category the protocol tells the agent to leave alone unless you ask.

Four things govern this command:

- Two or more `--file` flags activate DEEP automatically. You don't need to pass `--depth`.
- `--depth` accepts `STANDARD`, the single-file default, and `DEEP`.
- `--project` and `--branch` are inferred from your project configuration when you run inside the project directory.
- Large change sets trigger a confirmation prompt; pass `--force` to skip it.

## Verify the setup

Run these in order to confirm that every layer is live:

```bash
sonar auth status               # authentication and connectivity
sonar system status             # Vortex subscription and usage
sonar --version                 # 1.9.0 or later
docker ps --filter "ancestor=sonarsource/sonarqube-mcp"
```

`sonar system status` is the fastest answer to *"why isn't Vortex installing?"* A genuine entitlement loss surfaces as an unhealthy status, while hitting a usage limit stays healthy. `sonar analyze agentic --staged` reports usage-limit exhaustion separately, which is what distinguishes an active but depleted subscription from one that was never entitled.

Then, in a fresh VS Code agent session, confirm all three layers:

- **Context is injecting.** Ask an architecture question rather than a coding task: *"What is the current architecture of the project? Limit the answer to the top-level blocks."* A module graph means context arrived. A generic answer, a refusal, or an answer derived only from files the agent just read means it didn't.
- **Analysis runs.** Make a real edit, then confirm the agent runs a `DEEP` pass before its final reply and groups findings by severity. The managed instructions direct this rather than a hook enforcing it, so you're confirming the agent followed them.
- **Secrets detection fires.** Put a credential-shaped value in a throwaway file and ask the agent to read it. The `preToolUse` hook blocks the read before it reaches the model. Obvious placeholders like `EXAMPLE_TOKEN` get filtered by the scanner's entropy check and won't trigger it, so the value has to look plausible. Delete the file afterward.

Your user home should now carry these artifacts, and your project directory should carry none of them:

| **Path** | **Contents** |
|---|---|
| `~/.copilot/mcp-config.json` | MCP server registration pointing at `sonar run mcp` |
| `~/.copilot/hooks/hooks.json` | `preToolUse` secrets hook, plus `sessionStart` and `subagentStart` context hooks |
| `~/.copilot/hooks/sonar-secrets/build-scripts/pretool-secrets.sh` | Hook script calling `sonar hook copilot-pre-tool-use` |
| `~/.copilot/hooks/sonar-vortex/build-scripts/session-start-vortex.sh` | Hook script calling `sonar hook agent-session-start --agent copilot` to inject Vortex context |
| `~/.copilot/instructions/sonarqube.instructions.md` | Prompt-secrets protocol and Vortex analysis protocol blocks |

## What to know

- Vortex analysis restores context collected and stored during prior CI analysis, including dependencies, compiled artifacts, type information, and build configuration. Vortex context draws coding guidelines from Sonar rules and historical project issues. Its current architecture graph comes from SonarQube Architecture analysis, while intended architectural constraints are user-defined (not derived from analysis). For Java projects analyzed through Automatic Analysis, only basic results come back.
- Language coverage differs per capability. Vortex analysis spans 25 languages including Python, but taint analysis is limited to Java, JavaScript, TypeScript, C#, and VB.NET, and semantic navigation to Java, C#, JavaScript, TypeScript, Python, and Rust.
- Re-running `sonar integrate copilot` is idempotent and it's your recovery path. Running it interactively lets you keep or remove individual features, and Vortex context and analysis come out as one unit.

## Next steps

- [How to set up Sonar Vortex in GitHub Copilot CLI](https://www.sonarsource.com/resources/library/how-to-set-up-sonar-vortex-in-github-copilot-cli/)
- [How to set up Sonar Vortex in Claude Code](https://www.sonarsource.com/resources/library/sonar-vortex-with-claude-code/)
- [How to set up Sonar Vortex in Codex](https://www.sonarsource.com/resources/library/how-to-set-up-sonar-vortex-in-codex/)
- [Introducing Sonar Vortex and the SonarQube Remediation Agent](https://www.sonarsource.com/blog/introducing-sonar-vortex/)
- [The future is AC/DC: the Agent Centric Development Cycle](https://www.sonarsource.com/blog/the-future-is-ac-dc-the-agent-centric-development-cycle/)

Consult the docs:

- [What is Sonar Vortex?](https://docs.sonarsource.com/agent-centric-development-cycle/inside-your-agent-the-agentic-loop/sonar-vortex)
- [Sonar Vortex analysis](https://docs.sonarsource.com/agent-centric-development-cycle/inside-your-agent-the-agentic-loop/sonar-vortex-analysis)
- [Sonar Vortex context](https://docs.sonarsource.com/agent-centric-development-cycle/inside-your-agent-the-agentic-loop/sonar-vortex-context)
- [Checking your Vortex setup](https://docs.sonarsource.com/agent-centric-development-cycle/inside-your-agent-the-agentic-loop/how-to-guides/check-vortex-setup)
- [SonarQube CLI](https://docs.sonarsource.com/agent-centric-development-cycle/inside-your-agent-the-agentic-loop/how-to-guides/check-vortex-setup)
- [SonarQube MCP Server: VS Code with GitHub Copilot](https://docs.sonarsource.com/sonarqube-mcp-server/setup/quickstart-guides/vs-code)
- [SonarQube agent plugins](https://github.com/SonarSource/sonarqube-agent-plugins)

## Repository contents

The `config/` directory holds the files from [Step 3](#step-3--review-what-the-integration-configured), laid out as they appear under `~/.copilot/` after `sonar integrate copilot` runs. They are reference copies. Running `/sonarqube:sonar-integrate` generates the real ones, with your home directory path in `hooks.json`.

| Path | Contents |
|---|---|
| [`config/mcp-config.json`](config/mcp-config.json) | MCP server registration pointing at `sonar run mcp` |
| [`config/hooks/hooks.json`](config/hooks/hooks.json) | `preToolUse` secrets hook entry |
| [`config/hooks/sonar-secrets/build-scripts/pretool-secrets.sh`](config/hooks/sonar-secrets/build-scripts/pretool-secrets.sh) | Hook script calling `sonar hook copilot-pre-tool-use` |
| [`config/hooks/sonar-vortex/build-scripts/session-start-vortex.sh`](config/hooks/sonar-vortex/build-scripts/session-start-vortex.sh) | Hook script calling `sonar hook agent-session-start --agent copilot` |
