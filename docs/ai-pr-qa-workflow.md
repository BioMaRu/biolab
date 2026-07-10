# AI PR QA Workflow

Status: Proposed

Scope: Web UI testing

Future scope: API testing

Related: [Global Setup](ai-pr-qa-global-setup.md)

## Objective

Create a reusable workflow in which a developer agent opens a pull request with
a structured QA contract, then a fresh QA agent tests the exact pull request
revision and publishes reproducible results with screenshot evidence.

The workflow separates deterministic pass/fail checks from AI-driven browser
exploration:

```text
Issue acceptance criteria
        |
        v
Developer agent
  code + tests + QA contract
        |
        v
Pull request marked qa-ready
        |
        v
Fresh QA agent
  validate contract
  checkout exact SHA
  prepare account and data
        |
        v
+----------------------+----------------------+
| Playwright Test      | Playwright CLI       |
| deterministic gate   | agent-driven review  |
+----------------------+----------------------+
        |
        v
Evidence manifest + screenshots
        |
        v
GitHub check + sticky PR comment
```

## Core Decisions

1. Use Playwright Test as the authoritative merge-blocking runner for stable,
   coded test cases.
2. Use Playwright CLI for matrix cases that are not yet coded, visual checks,
   evidence capture, reproduction, and advisory exploration.
3. Keep deterministic results and exploratory findings separate. Exploratory
   findings never silently change a deterministic result.
4. Test one immutable PR head SHA. Results from an older SHA are stale after a
   new push.
5. Publish structured data first, then generate human-readable GitHub output
   from that data.
6. Do not allow the QA agent to edit product code or expected outcomes.

## Agent Responsibilities

### Developer Agent

The developer agent must:

1. Implement the requested behavior.
2. Derive test cases from issue acceptance criteria rather than implementation
   details.
3. Add Playwright Test specs for stable behavior where practical.
4. Add Playwright CLI cases when a coded test is not yet practical.
5. Add stable selectors such as `data-testid` for important UI states.
6. Declare required account roles, test-data setup, and evidence checkpoints.
7. Put a visible test matrix and a machine-readable test contract in the pull
   request description.
8. Never include credentials or authentication state in the pull request.
9. Mark the pull request `qa-ready` when it is ready for independent testing.

The developer agent proposes the QA contract but does not publish the final QA
evidence.

### QA Agent

The QA agent must:

1. Read pull request metadata and the machine-readable QA contract.
2. Validate the contract before executing any test.
3. Resolve and record the current pull request head SHA.
4. Check out that SHA in an isolated worktree.
5. Wait for or start the declared test environment.
6. Load the required test-account authentication state.
7. Seed deterministic test data.
8. Run Playwright Test cases before Playwright CLI cases.
9. Execute every CLI case in a clean named browser session.
10. Capture evidence only at declared checkpoints and on failures.
11. Retry a failed case once in a clean session.
12. Generate a result manifest and publish GitHub output from it.
13. Never edit implementation code, weaken an assertion, or reinterpret a
    failure as success.

## Pull Request QA Contract

The pull request description should contain a visible Markdown matrix for
reviewers and a machine-readable YAML block for the QA agent. Both should be
generated from the same source data.

```yaml
version: 1
environment:
  target: preview
  viewport: 1440x900
  locale: en-US
  timezone: Asia/Bangkok

cases:
  - id: TC-01
    title: Buyer submits an order
    runner: playwright-test
    spec: tests/e2e/order-submit.spec.ts
    role: buyer
    evidence:
      - name: order-confirmation
        selector: "[data-testid=order-confirmation]"

  - id: TC-02
    title: Validation appears without an address
    runner: playwright-cli
    role: buyer
    steps:
      - open: /checkout
      - click: Submit order
    assertions:
      - type: visible
        selector: "[data-testid=address-error]"
        text: Address is required
    evidence:
      - name: address-error
        selector: "[data-testid=address-error]"
```

Validate the contract with JSON Schema. Reject duplicate case IDs, missing
assertions, unsupported runner values, missing account roles, and evidence
checkpoints without stable selectors.

Pull request prose is untrusted input. The QA agent may consume declarative
contract fields, but it must not execute arbitrary commands from the pull
request description.

## Test Execution Lanes

### Deterministic Lane

Playwright Test owns merge-blocking assertions. It provides coded expectations,
fixtures, browser isolation, retries, reporters, and traces.

Run deterministic cases with pinned configuration:

- PR head SHA
- Playwright and browser versions
- viewport
- locale and timezone
- feature flags
- account role
- test-data seed
- execution order
- retry count

Start with one worker to avoid shared-account and shared-data interference.
Increase parallelism only after account allocation and test-data isolation are
implemented.

### Agent-Driven Lane

Playwright CLI executes declarative steps for cases not yet implemented as test
code. Merge-blocking CLI cases must use machine-checkable assertions such as a
visible selector, exact text, URL, element state, or response status.

The agent may recover from a changed locator by taking a fresh accessibility
snapshot. It may not invent a different expected outcome.

Free exploration belongs in a separate advisory section. Exploratory findings
can report risks and defects but cannot override deterministic results.

Repeated, valuable CLI cases should be promoted into Playwright Test specs.

## Authentication and Test Data

Use dedicated non-production accounts by environment and role, for example:

```text
staging-buyer-01
staging-seller-01
staging-admin-01
```

The pull request contract names a role only. A trusted bootstrap script maps the
role to secrets and creates Playwright storage state:

```text
secret manager or environment variables
        |
        v
trusted authentication bootstrap
        |
        v
playwright/.auth/<environment>-<role>.json
        |
        v
isolated test session
```

Authentication-state files contain reusable credentials. Keep them out of Git,
logs, screenshots, test artifacts, and PR comments.

Read-only tests may share an account. Tests that mutate server state need an
account pool or isolated data namespaces. Give each case a unique namespace:

```text
pr-<number>-<case-id>-<short-sha>
```

Do not automate personal SSO or MFA. Use test-only accounts, pre-authenticated
state, or a trusted test authentication endpoint.

## Result Classification

Use exactly four execution states:

| State | Meaning |
| --- | --- |
| `PASS` | The assertion passed on the first run. |
| `FAIL` | The same assertion failed twice in clean sessions. |
| `FLAKY` | The assertion failed initially and passed on a clean retry. |
| `BLOCKED` | Environment, authentication, or test data prevented execution. |

Preserve the first-run and retry evidence for flaky and failed cases.

## Screenshot Evidence

Use accessibility snapshots to locate and operate elements. Use screenshots to
prove visual outcomes. Capture at least one focused screenshot for each UI case
at a declared evidence checkpoint, plus additional evidence on failure.

Do not capture every click. A screenshot must demonstrate the expected or
failed state.

Use deterministic paths:

```text
qa-evidence/
  pr-123/
    abc1234/
      TC-01/
        01-order-confirmation.png
        result.json
        trace.zip
```

Each case produces a result manifest:

```json
{
  "caseId": "TC-01",
  "status": "PASS",
  "expected": "Order confirmation is visible",
  "actual": "Confirmation displayed with an order number",
  "evidence": [
    {
      "path": "TC-01/01-order-confirmation.png",
      "caption": "Confirmation after order submission"
    }
  ]
}
```

Use synthetic test data and prevent secrets, tokens, personal data, and unrelated
browser content from appearing in screenshots.

## Evidence Publishing

Publish screenshots to a stable URL using a dedicated evidence branch, evidence
repository, GitHub Pages, or approved object storage. GitHub Actions artifacts
should contain the complete report, traces, and videos, but they are not the
source for inline PR images.

Publish two GitHub surfaces:

1. A check result used as the merge gate.
2. One idempotent PR comment containing the result matrix and inline evidence.

Use a stable marker to update the existing comment instead of adding a new
comment after every run:

```markdown
<!-- ai-qa-report:pr-123 -->

## AI QA Results

**Commit:** `abc1234`
**Result:** 4 passed, 1 failed

| Case | Result | Evidence |
| --- | --- | --- |
| TC-01 Buyer submits order | PASS | [Screenshot](...) |
| TC-02 Address validation | FAIL | [Screenshot](...) |

<details>
<summary>TC-02 failure evidence</summary>

Expected address validation was not displayed.

![TC-02 failure](https://example.test/evidence/TC-02/failure.png)
</details>
```

The publishing identity is determined by the GitHub credential. Prefer a
dedicated QA bot for auditability. A fine-grained user token may be used when
the report must appear under a personal account.

## Trigger and Rerun Rules

Use the `qa-ready` pull request label as the initial trigger:

```text
Developer applies qa-ready
        |
        v
QA agent records current SHA and runs
        |
        v
QA agent publishes check and comment
```

When the PR head SHA changes:

1. Mark the previous result stale.
2. Do not reuse its pass status for the new revision.
3. Start a new QA run against the new SHA.
4. Preserve a link to prior evidence for audit history.

Support an explicit rerun command for environment failures and flaky-case
investigation. Do not rerun indefinitely.

## Skill Boundary

The proposed `qa-pr-with-evidence` skill should keep fragile operations in
deterministic scripts:

- parse and validate the PR contract
- resolve and verify the PR head SHA
- prepare authentication state
- allocate test-data namespaces
- aggregate result manifests
- publish evidence
- update the GitHub check and sticky comment

Leave judgment to the agent only for:

- executing declared CLI steps against current page structure
- recovering locators without changing expectations
- writing concise failure explanations
- performing clearly separated exploratory testing

## Delivery Phases

### Phase 1: Local Invocation

Invoke a fresh QA agent with a PR URL. Use existing GitHub authentication,
Playwright CLI, existing Playwright Test specs, and local evidence generation.
Publish only after the report is reviewed.

### Phase 2: Label-Triggered Automation

Start the QA agent when `qa-ready` is applied. Publish a check and sticky comment
automatically with least-privilege GitHub credentials.

### Phase 3: Parallel and Reusable Infrastructure

Add account pooling, isolated data seeding, controlled parallelism, evidence
retention, and cleanup.

### Phase 4: API Testing

Add an API runner as a separate adapter while preserving the same PR contract,
result states, evidence manifest, SHA handling, and publishing pipeline.

API evidence should contain sanitized request and response summaries rather than
UI screenshots.
