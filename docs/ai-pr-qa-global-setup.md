# AI PR QA Global Setup

Status: Proposed

Scope: Reusable web UI QA across repositories

Related: [AI PR QA Workflow](ai-pr-qa-workflow.md)

## Objective

Install the `qa-pr-with-evidence` capability once, then use it from fresh Codex
or Claude agents against any approved web repository. Keep global behavior,
repository-specific commands, and PR-specific test cases in separate layers.

```text
Global skill and tools
        +
Trusted repository configuration
        +
PR-specific QA contract
        |
        v
Repeatable QA execution
```

The global installation must not add Node, Playwright, or web infrastructure to
BioLab itself. These tools belong to the developer environment and target web
repositories.

## Installation Layers

### Global Layer

Install once per workstation:

- the `qa-pr-with-evidence` skill
- Playwright CLI
- a Chromium browser managed by Playwright
- GitHub CLI authentication
- global non-secret defaults
- protected authentication-state storage

### Repository Layer

Each approved repository provides:

- `.qa/config.yaml`
- a local, version-pinned `@playwright/test` dependency when deterministic
  tests are supported
- stable UI selectors
- test-data setup and cleanup hooks
- an evidence publishing policy

### Pull Request Layer

Each pull request provides:

- a visible human-readable test matrix
- a machine-readable QA contract
- account roles, never credentials
- deterministic assertions
- declared screenshot checkpoints

## Verified Workstation State

The following state was verified on July 10, 2026:

| Component | State |
| --- | --- |
| Node | Installed, `v24.8.0` |
| npm | Installed, `11.6.0` |
| GitHub CLI | Installed, `2.86.0` |
| Playwright CLI | Installed globally, `0.1.14` |
| Codex skills | `~/.codex/skills` links to `~/.claude/skills` |
| GitHub authentication | Configured account `BioMaRu`, token invalid |

The GitHub credential is the current setup blocker. Re-authenticate before the
skill attempts to read or publish pull request data:

```bash
gh auth login --hostname github.com
```

Do not store the resulting token in the skill, repository configuration, PR
description, or test artifacts.

## Global Skill Location

Create the skill at:

```text
~/.claude/skills/qa-pr-with-evidence/
```

The existing symlink makes the same installation available to Codex:

```text
~/.codex/skills/qa-pr-with-evidence
```

Proposed skill contents:

```text
qa-pr-with-evidence/
  SKILL.md
  agents/
    openai.yaml
  scripts/
    inspect-pr.mjs
    validate-contract.mjs
    run-qa.mjs
    build-report.mjs
    publish-report.mjs
  references/
    contract-schema.json
    repo-config-schema.json
  assets/
    pr-comment-template.md
```

Keep `SKILL.md` focused on orchestration and safety rules. Put fragile,
repeatable behavior in scripts and detailed schemas in `references/`.

## Global Tool Setup

Playwright CLI is a workstation-level agent tool:

```bash
npm install --global @playwright/cli@latest
playwright-cli install-browser chromium
```

Do not silently update it during a QA run. Record its version in each report so
runs remain auditable.

Playwright Test belongs to each target repository and must be pinned by that
repository's lockfile. The global skill should detect and run the repository's
existing command rather than install or upgrade test dependencies.

## Runtime Directories

Use global paths outside target repositories:

```text
~/.config/qa-pr/config.json
~/.config/qa-pr/auth/
~/.cache/qa-pr/runs/
```

Responsibilities:

| Path | Content |
| --- | --- |
| `~/.config/qa-pr/config.json` | Non-secret defaults and repository allowlist |
| `~/.config/qa-pr/auth/` | Sensitive Playwright storage-state files |
| `~/.cache/qa-pr/runs/` | Temporary worktrees, manifests, and evidence |

Example global configuration:

```json
{
  "defaultBrowser": "chromium",
  "defaultViewport": {
    "width": 1440,
    "height": 900
  },
  "retryCount": 1,
  "workers": 1,
  "evidenceProvider": "repository-branch",
  "allowedRepositories": [
    "OWNER/example-web"
  ]
}
```

Global configuration must not contain passwords, tokens, storage-state data, or
other reusable credentials.

## Authentication-State Storage

Store authentication state by application host, environment, and role:

```text
~/.config/qa-pr/auth/
  app.example.test/
    staging/
      buyer.json
      seller.json
      admin.json
```

Restrict file permissions to the current user. Never commit, print, attach, or
publish these files. Treat them as credentials because they may contain cookies
and local storage that can impersonate a test account.

The skill should receive a role such as `buyer` from the PR contract, then map
that role to a trusted state file. A PR must never choose an arbitrary state-file
path.

## Repository Configuration

Each target repository should provide a trusted configuration file:

```text
.qa/config.yaml
```

Example:

```yaml
version: 1

application:
  baseUrlEnvironment: QA_BASE_URL
  healthPath: /health
  startCommand: npm run dev

playwright:
  config: playwright.config.ts
  project: chromium
  workers: 1

authentication:
  roles:
    buyer:
      stateFile: buyer.json
    seller:
      stateFile: seller.json

evidence:
  provider: repository-branch
  branch: qa-evidence
```

Executable commands must come from the base branch's trusted configuration. If
a PR changes `.qa/config.yaml`, require explicit review before running the new
commands.

Validate repository configuration with `repo-config-schema.json`. Reject
unknown commands, paths outside the repository, unsupported evidence providers,
and authentication roles that are not globally configured.

## Repository Onboarding Checklist

Before a repository can use the global skill:

1. Add it to the global allowlist.
2. Add and validate `.qa/config.yaml`.
3. Confirm its local Playwright Test command when tests exist.
4. Add stable `data-testid` selectors for important UI outcomes.
5. Provision disposable non-production accounts by role.
6. Generate protected authentication-state files.
7. Define deterministic test-data setup and cleanup.
8. Select and verify an evidence provider.
9. Run one dry-run PR without publishing.
10. Review the generated report before enabling automatic publication.

## Invocation

Manual invocation is the first delivery mode:

```text
Use $qa-pr-with-evidence on
https://github.com/OWNER/REPOSITORY/pull/123
and publish the results.
```

The skill must then:

1. Verify that the repository is allowlisted.
2. Read PR metadata using the GitHub CLI or GitHub connector.
3. Parse and validate the QA contract.
4. Resolve and record the exact PR head SHA.
5. Load trusted repository configuration from the base branch.
6. Create an isolated worktree under the run cache.
7. Prepare the declared test role and data namespace.
8. Run deterministic and agent-driven cases.
9. Generate structured result manifests.
10. Preview the report before the publisher updates GitHub.

## Evidence Provider

Keep evidence storage behind a provider interface. Supported rollout options:

| Provider | Use |
| --- | --- |
| `artifact-only` | Initial dry runs without inline PR images |
| `repository-branch` | Simple GitHub-hosted screenshots per repository |
| `github-pages` | Browsable reports and stable image URLs |
| `object-storage` | Organization-scale retention and access control |

Start with `repository-branch` for controlled repositories. Keep evidence off
the feature branch and use deterministic paths based on repository, PR number,
head SHA, and case ID.

Artifacts may store complete HTML reports, traces, and videos. Inline PR images
must use a stable URL supplied by the configured evidence provider.

## Security Separation

The tested PR contains untrusted code. Do not expose the GitHub publishing
credential to its build, server, Playwright Test, or browser process.

```text
Untrusted test process
  receives disposable test-account access
  produces local result files
        |
        v
Trusted publisher process
  receives GitHub publishing access
  validates result files
  updates the check and PR comment
```

Global safety rules:

- Reject fork PRs by default.
- Reject repositories and authors outside configured allowlists.
- Use disposable accounts with minimum privileges.
- Do not run new commands introduced by a PR without review.
- Keep personal GitHub credentials out of test subprocesses.
- Sanitize screenshots, logs, traces, request data, and error output.
- Apply a run timeout and a bounded retry count.
- Never allow the QA agent to edit product code during verification.

## Publishing Identity

For local manual runs, the publisher can use the active `gh` account after the
user explicitly requests publication.

For automatic organization-wide runs, prefer a dedicated GitHub App or QA bot.
It provides clearer audit history and avoids giving a personal token to shared
automation. Use least-privilege access limited to pull requests, checks, and the
selected evidence destination.

## Rollout

### Stage 1: Local Global Skill

Install the skill globally, repair GitHub authentication, install Chromium, and
test one approved repository through explicit manual invocation.

### Stage 2: Repository Standard

Adopt `.qa/config.yaml`, the PR QA contract schema, account roles, evidence
paths, and result manifests across additional repositories.

### Stage 3: Label-Triggered Automation

Use a `qa-ready` label to invoke the QA agent. Keep publication credentials in a
trusted publisher process and mark prior results stale after a new PR commit.

### Stage 4: Organization Workflow

Move common automation into a reusable GitHub workflow and use a dedicated
GitHub App. Repositories provide only the trusted adapter configuration and test
implementation.

### Stage 5: API Adapter

Add API testing as a separate runner while reusing repository allowlists, PR
contracts, result states, SHA handling, evidence manifests, and GitHub
publishing.

## Global Readiness Checklist

- [ ] GitHub CLI authentication is valid.
- [ ] Chromium is installed for Playwright CLI.
- [ ] The global skill is installed and validated.
- [ ] Global directories have restrictive permissions.
- [ ] At least one repository is allowlisted.
- [ ] The repository configuration passes schema validation.
- [ ] Test accounts and storage state are available.
- [ ] The evidence provider renders images in a PR comment.
- [ ] A dry run completes without publishing.
- [ ] A reviewed run publishes one idempotent comment and one check result.
