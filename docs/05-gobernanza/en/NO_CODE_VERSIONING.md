# Versioning No-Code Workflows

How to version something that has no readable diff, lives inside a runtime, and can be changed by dragging a node.

The objective, in one line:

> *"Versioned code and workflows should be the source of truth; the runtime should represent a deployment."*

Today it is the other way around. This document describes how that gets inverted.

---

## The problem

A developer changing a function has a three-line diff, a reviewer who understands it in thirty seconds, a history that says when and why, and a revert command.

Someone changing a visual workflow has a canvas, a save button, and a JSON file of several thousand lines that nobody will read.

Five specific failures, all observed in a real system:

| Problem | What it actually caused |
|---|---|
| The artefact lives in the runtime, not in a file | Five days of divergence between what the repository claimed and what was running |
| The JSON has no useful diff | Workflow changes go unreviewed. Approval happens by looking at the canvas, or not at all |
| No branches, no environments | 125 laboratory workflows sharing a runtime with 25 production ones |
| The name is the only metadata | Two workflows labelled as tests were serving real traffic |
| Credentials are embedded | A naive export publishes credential identifiers |

---

## The canonical artefact

**The canonical artefact is the exported, normalised, version-controlled JSON. It is not what sits in the runtime.**

Three consequences have to be accepted for this to mean anything:

- If runtime and repository disagree, **the repository wins**, and the divergence is an incident rather than a curiosity.
- A change made directly on the production canvas does not exist until it is exported and committed. Until then it is an unrecorded patch.
- Deploying means **importing** the artefact, not editing in place.

Every artefact ships with its manifest. Neither is useful alone: JSON without a manifest cannot be reviewed, and a manifest without JSON cannot be deployed.

---

## The minimum manifest — eleven fields

| # | Field | Question it answers |
|---|---|---|
| 1 | **Stable logical name** | Which workflow is this, regardless of what the canvas calls it today? |
| 2 | **Owner** | Who answers for it? A person — not a team, not "AI" |
| 3 | **Environment** | dev, staging or production |
| 4 | **Lifecycle state** | Where in the lifecycle does it sit? |
| 5 | **Input and output contract** | What does it accept, what does it return, and which states are possible? |
| 6 | **Dependencies** | Which workflows, APIs and tables does it need? |
| 7 | **Credentials by symbolic reference** | Which credentials, by logical name — never by identifier or value |
| 8 | **Data classification** | Public, internal, sensitive or prohibited? |
| 9 | **Provenance review** | Who wrote it, who reviewed it, which agent took part? |
| 10 | **Test evidence** | Which tests did it pass, with what result? |
| 11 | **Rollback artefact** | Which version does it revert to, and where is it? |

**Why eleven and not two.** Each field answers a question somebody asked and could not answer. Field 4 exists because of the laboratory workflows. Field 7 exists because a naive export leaks credential identifiers. Field 11 exists because a release without a rollback is not a release. Field 1 exists because canvas names drift while the workflow stays the same.

---

## The lifecycle

```
draft → test → staging → production → deprecated → archived
```

| State | Meaning | May be active |
|---|---|---|
| `draft` | Under construction, incomplete by definition | **No** |
| `test` | Complete, under verification, synthetic fixtures only | **No** |
| `staging` | Verified, awaiting release; imported inactive first | In staging only |
| `production` | In use, carrying real traffic | **Yes** |
| `deprecated` | Superseded; still running through a declared transition window | Yes, with an end date |
| `archived` | Out of service, retained as history | **No** |

### The rule that gets broken most

**A workflow in `test` may never be active in production.**

In the real system this rule was broken in the worst possible way: the runtime-wide error handler — the single mechanism that captures and reports every failure — carries `[TEST]` in its name and has been active and critical since 2026-07-23.

It is the perfect illustration of the underlying problem: **the name was the only metadata, and the name lies.** With a manifest, field 4 would read `production` and the name would be irrelevant.

The risk is not aesthetic. It is that the next runtime cleanup deletes, by name pattern, the only alerting mechanism in the system. That very nearly happened: an inventory pass found **two workflows carrying real traffic** among those that looked like disposable tests.

---

## The ten-step pipeline

From a canvas change to a recorded release.

| # | Step | Purpose | Fails when |
|---|---|---|---|
| 1 | **Export** | Pull the JSON out of the runtime | The JSON is hand-edited instead of exported |
| 2 | **Normalise** | Stable key order, volatile fields stripped | Skipped — the diff becomes useless |
| 3 | **Scan for secrets** | Tokens, credential identifiers, internal hostnames, chat identifiers, email addresses | The team relies on eyeballing the preview |
| 4 | **Validate structure** | Orphan nodes, unterminated branches, credentials referenced by identifier, forgotten disabled nodes | It is assumed that a canvas that looks right is right |
| 5 | **Test contracts with synthetic fixtures** | Synthetic inputs, expected outputs | Real data is used |
| 6 | **Import into isolated staging, inactive** | Exist before running | It is imported active |
| 7 | **Review the visual graph** | A human looks at the imported canvas | Approval happens by reading the JSON |
| 8 | **Publish after approval** | Activate in production | Activation precedes approval |
| 9 | **Record the deployed hash** | Know exactly which version is running | Not recorded — drift returns |
| 10 | **Verify and retain the rollback** | Confirm it works, keep the previous artefact | The previous artefact is discarded |

Step 7 is neither optional nor automatable. **A human has to look at the graph**, because some errors are only visible on the canvas: a branch left dangling, a node wired to the wrong successor, a conditional whose outputs are swapped. No JSON linter will tell you that the "approved" branch is connected to the rejection node.

---

## The real problem with workflow JSON diffs

This is where no-code versioning is won or lost. Without normalisation, version control stops being useful: **every save produces an enormous diff even when nothing meaningful changed**, and when everything changes, nothing gets reviewed.

### What pollutes the diff

| Noise | Where it comes from |
|---|---|
| **Node coordinates** | Dragging a node two pixels changes its position. Semantically: nothing |
| **Timestamps** | Created, updated and version fields change on every save |
| **Key order** | Serialisation does not guarantee stable ordering between exports |
| **Node and connection order** | Arrays can be reordered without the graph changing |
| **Internal identifiers** | Generated identifiers that change on reimport |
| **Pinned test data** | Sample data attached to nodes during development. Often real data, too |
| **Credential metadata** | The visible credential name and its identifier travel inside the node |
| **UI configuration** | Notes, colours, sticky-note dimensions |

Unnormalised, the result is this: you change one line of a prompt and the diff shows four hundred. The reviewer opens it, sees the flood, and approves without reading. That is worse than not reviewing at all, because it leaves a record of a review that did not happen.

### How to normalise

A deterministic normalisation step, run before committing. Always the same, so that two exports of the same workflow produce byte-identical files.

1. **Sort keys alphabetically** in every object, at every level.
2. **Sort nodes** by stable logical name — not by identifier, which can change — and connections by source node.
3. **Strip volatile fields**: creation and update timestamps, version identifiers, instance identifiers.
4. **Round or drop coordinates.** Rounding to a coarse grid preserves the rough layout without generating noise; dropping is cleaner if the canvas re-flows on import.
5. **Always strip pinned test data.** It is noise, and it is a data risk — development fixtures are often real records.
6. **Replace credentials with symbolic references**: the identifier and the display name come out; a stable logical name goes in.
7. **Enforce stable formatting**: fixed indentation, no trailing whitespace, a single trailing newline.

With that, the diff for "I changed the prompt text" is the prompt text. And a diff that can be read is a diff that gets reviewed.

### What else normalisation buys

- **Detection of unintended changes.** If the diff shows something you did not expect, someone else touched the workflow.
- **Secret scanning that actually works.** Pattern matching over a normalised file is reliable; over raw JSON with embedded sample data, it is not.
- **A stable hash.** Step 9 — recording the deployed hash — only makes sense if the same workflow always hashes the same.
- **Environment comparison.** Do staging and production match? With normalisation that is a diff. Without it, it is opening two canvases and squinting.

### What normalisation does not solve

**The diff is still not semantic.** It shows that a parameter changed, not that the flow can now reach the email-sending node without passing through the approval step. That is what step 7 is for.

Normalisation makes the diff **legible**. Visual review makes it **comprehensible**. Both are required.

---

## Credentials by symbolic reference

**Rule: versioned JSON never contains a credential identifier, a credential value, or a name that reveals infrastructure.**

It contains a logical name — `gmail_owner`, `telegram_bot_primary`, `postgres_memory` — which the destination environment resolves against its own credential store.

Three reasons:

1. **Security.** A credential identifier in a public repository teaches the reader nothing and helps anyone mapping the system.
2. **Portability.** The same artefact imports into dev, staging and production, each resolving against its own credentials. Without this, separate environments are not possible.
3. **Rotation.** Rotating one credential should not require re-versioning fourteen workflows.

A corollary for multi-tenant scaling: **if two agents resolve the same symbolic name to the same credential, they are not two agents.** The isolation is decorative.

---

## Test workflows that must not stay active

Observed state: **125 of 217 workflows carrying laboratory naming.**

> *"The production environment has also been used as a laboratory and historical archive, because it retains numerous test workflows, candidates and backups."*

### Why it happens

Not carelessness — the logical consequence of having no staging environment. If the only place to test is production, testing happens in production. And because deleting is frightening, with good reason, they accumulate.

### Why it is dangerous

| Risk | Detail |
|---|---|
| **Silent execution** | A test workflow with an active trigger keeps running. It can send messages, write rows, or burn tokens |
| **Duplication** | Two versions of the same flow active at once: work done twice, or overwritten |
| **Noise that suppresses vigilance** | Nobody audits a list of 217 items. A list nobody audits is a list where anything can hide |
| **Deletion by mistake** | The inverse risk, and the one that nearly materialised |

### The rules

1. A workflow in `test` is **never** activated in production.
2. A test workflow **always** uses synthetic fixtures, never real data.
3. A test workflow carries a **declared expiry date** in its manifest.
4. Cleanup proceeds **by classification, not by name pattern**.
5. Before deleting: verify traffic, do not read the name.

Rules 4 and 5 come from a real inventory that classified 79 workflows into three classes: 73 safely deletable, 4 uncertain, and **2 active with real traffic despite test-looking names**. Deleting by pattern would have broken production.

---

## Rollback is a release activity

**A rollback is not an emergency plan. It is an artefact produced during the release, before it is needed.**

A release without a prepared rollback is incomplete, even when it goes well.

| Moment | Action |
|---|---|
| **Before** | Export the running version. Store it with its hash. Verify the file can be reimported |
| **During** | Record the hash of what is being deployed |
| **After** | Verify it works. **Retain the previous artefact** rather than discarding it |
| **If reverting** | Import the previous artefact, verify, record the rollback |

The real system practised this early, in artisanal form: an orchestrator backup explicitly labelled *"before the papers subagent"*, and a memory gate installed *with a prior rollback saved*. Saving the "before" and naming it after what came next is a workable version of step 10, and it worked.

What is missing is the record: today the rollback exists as a file, not as a release entry with an identifier, an approver and a hash.

---

## Adoption status

Honesty before aspiration:

| Practice | Status |
|---|---|
| Manifest defined | **Yes** — template written |
| Manifest applied to all active workflows | **No** — partial coverage |
| Workflow exports under version control | **No.** Yes for application code and SQL migrations |
| JSON normalisation | **No** — pending |
| Secret scanning in the pipeline | **No** — not automated |
| Separate environments | **No** |
| Rollback retained | **Partial** — as labelled backups, without a formal record |
| Deployed hash recorded | **No** |

The method is written; adoption is halfway. Saying so is part of the method.

---

## Evidence level

| Claim | Level |
|---|---|
| The eleven fields, the lifecycle and the ten-step pipeline | Verified (governance baseline, 2026-08-03) |
| 125 of 217 laboratory workflows; the three inventory classes | Verified |
| `[TEST]` in the name of the active error handler | Verified |
| Labelled backups and the memory-gate rollback | Verified |
| The list of diff-noise sources and the normalisation procedure | Inferred — engineering practice; no normaliser is implemented in this system yet |
| Adoption status | Verified |

> Last verified: 2026-08-05
