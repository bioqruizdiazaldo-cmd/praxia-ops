# Governance — A Practice Guide

A working method for building software with AI agents: how decisions get made, how work gets verified, who approves what, and what evidence remains afterwards.

This is the English edition of the [governance section](../README.md). The Spanish version is the primary one and carries additional material — checklists, templates, and the agent working agreement. What follows is the transferable core.

---

## Why the method is the asset

A system is specific. It runs on particular infrastructure, with particular credentials, solving one person's problems. None of that travels.

The method does.

These documents came out of twenty-two days of building an agentic system quickly, and then finding — one at a time — the holes that building quickly leaves behind: a `.env` file holding a live token inside a cloud-synced folder; three database migrations that sat undeployed for five days because nobody looked at the server, only at the repository; 125 laboratory workflows sharing a runtime with 25 production ones; a finished component that scored 2 out of 7 against a declared bar of 7 out of 7 and was not shipped.

Every rule here has a scar attached. That is the point. These are not best practices copied from a book; they are controls that exist because something specific went wrong.

The sentence that sets the boundary:

> *"AI agents can propose, implement and verify work. They do not become the accountable owner of risk, access, or the release decision."*

---

## Contents

| Document | What it covers |
|---|---|
| [SDLC_AI.md](SDLC_AI.md) | The nine lifecycle stages, their gates, and who approves each one |
| [NO_CODE_VERSIONING.md](NO_CODE_VERSIONING.md) | Versioning visual workflows that have no readable diff |
| [PUBLICATION_POLICY.md](PUBLICATION_POLICY.md) | What can be published from a private system, and how to sanitise it |

Additional material, Spanish only:

| Document | What it covers |
|---|---|
| [Acuerdo de trabajo con agentes](../acuerdo-de-trabajo-con-agentes.md) | The AI Working Agreement in full, with an agent-assignment template |
| [Checklists](../checklists/) | Definition of ready, definition of done, release checklist |
| [Templates](../plantillas/) | Requirement, plan, ADR, test report, release, rollback, incident |

---

## The evidence vocabulary

Five labels. Every claim in this documentation belongs to exactly one of them, and most documents close with a table declaring which.

This is not tidiness. It is what allows a reader to know how much weight each sentence carries. The rule behind it:

> *"An explicit gap is preferable to completing the story with an undemonstrable narrative."*

| Label | Meaning | How it is obtained |
|---|---|---|
| **Verified** | Inspected and observed | A database query, a runtime read, a test run, a code review |
| **Owner-confirmed** | Asserted by the accountable person, with no artefact behind it | A statement about something known but never recorded |
| **Inferred** | Reasonably deduced from what was verified | An engineering conclusion, not an observation |
| **Pending verification** | Needed, and not checked | The gap is declared, not filled |
| **Incomplete history** | The trail exists but is broken or partial | There is evidence that something happened, and not of what exactly |

### One example of each

**Verified** — As of 2026-08-03 the runtime holds 217 registered workflows, 25 active and 25 archived. This came from a read-only inspection and can be counted again.

**Owner-confirmed** — No test run in the shared runtime has affected a production workflow to date. There is no log proving this, precisely because nothing happened. It is recorded as what it is: a statement, not a measurement. And it is not treated as a control — the absence of an incident is not a control.

**Inferred** — Without off-site backups, losing the VPS means losing the financial data. Nobody has lost the VPS. It follows from two verified facts: the backups live on the server they protect, and only the memory layer is replicated elsewhere.

**Pending verification** — The exact status of the 46 laboratory workflows that were not classified in the 2026-07-25 inventory. They are known to exist and not known to be anything in particular. Writing the number is better than writing "the rest are old tests".

**Incomplete history** — Production ran three migrations behind from 31 July, discovered on 5 August. What is known: *what* was missing and *when* it surfaced. What is not: whether anything failed silently against the outdated schema during those five days. That part of the story does not exist and is not reconstructed by hand.

### Practical rule

If you cannot decide which label a sentence deserves, the sentence is not ready to be written.

---

## How these documents fit together

The working agreement is the constitution. The lifecycle is the procedure. The checklists are the gates. The templates are the evidence.

An agent operating under this method reads freely, writes on request, and never decides. A human decides — by name, in writing, per release.

---

## A caveat

These documents describe a real system with a single operator and twenty-two days of history. **They are not an industry standard and are not presented as one.**

Adopting them without adapting them would repeat the exact mistake the method warns against: taking on a shape without the problem that justifies it. That already happened once in this project — a knowledge base was built with 57 empty folders because the structure was created before the material existed.

> Last verified: 2026-08-05
