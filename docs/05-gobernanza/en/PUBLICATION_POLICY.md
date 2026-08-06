# Publication Policy

What can be published from a private system, what cannot, and how it gets reviewed before it is too late.

This policy governs everything that leaves private infrastructure for anywhere public: a repository, a post, a talk, a portfolio, an example in a commercial proposal.

---

## The root rule

> *"Public artefacts must teach a reusable principle without exposing the private system the lesson came from."*

Everything else follows from that sentence. If an artefact teaches nothing, it is not worth publishing. If it teaches something but exposes the system, it gets rewritten until it teaches the same thing without exposing anything. If that proves impossible, it does not get published.

---

## Permitted

- **Original templates and checklists**, written here rather than copied.
- **Fictional examples**, invented to illustrate and declared as invented.
- **Synthetic datasets** with the shape of real data and none of its values.
- **Conceptual diagrams**: architecture, flows, state machines, data models.
- **Clean-room implementations** — code rewritten from the design, not lifted from production.
- **Verified public references, with attribution.** Other people's work is cited, not absorbed.
- **SQL schemas with table and column names.** A table name is not a secret; its contents are.
- **Contracts, state machines, decisions and chronology.** This is the method, and the method is the point.
- **Aggregate metrics**: "554 tests", "217 workflows", "343 of 362 executions succeeded".

---

## Prohibited

| Category | Examples |
|---|---|
| **Secrets and credentials** | Tokens, API keys, passwords, private keys, signing secrets, SSH key paths, credential identifiers |
| **Real personal, financial, medical or tax data** | Amounts, receipts, tax identifiers, balances, diagnoses, names and ages of family members |
| **Private communications and documents** | Email, chats, calendar events, cloud files, memory contents |
| **Raw backups, logs and exports** | Database dumps, unsanitised workflow exports, execution histories |
| **Internal identifiers and exploitable topology** | Server addresses, real hostnames, chat identifiers, container names with ports, absolute server paths |
| **Claims without evidence** | Asserting tests, adoption, customers or publication that did not happen |

The last row is the most underestimated. Inventing a customer or inflating a number is not a privacy problem; it is a truthfulness problem, and it contaminates everything else. If 90% of a document is verifiable and 10% is invented, the whole thing stops being trustworthy.

---

## Six review gates

Taken in order. Any failure stops publication.

**1. Provenance.** Where did this come from? Every artefact declares its origin: written from scratch, reconstructed from the design, or derived from a private artefact. The third case is the dangerous one and demands extra care at gate 2. An artefact whose origin nobody remembers does not get published — doubt is a no.

**2. Secret and personal-data scanning.** An explicit search, not a casual read. At minimum: tokens and keys, addresses and hostnames, email addresses, chat identifiers, credential identifiers, absolute server paths, personal names, and numbers that could be amounts or document identifiers. Run against the final artefact, and run even when the artefact is "obviously" clean — the `.env` file holding a live token inside a synced folder was obviously clean too, until somebody looked.

**3. Licensing.** Own licence declared. Nothing from third parties without permission or a compatible licence. Fragments of other people's documentation are quoted and attributed, not absorbed.

**4. Technical accuracy.** Every claim carries an evidence level: Verified, Owner-confirmed, Inferred, Pending verification, Incomplete history. A gap is declared as a gap — *"an explicit gap is preferable to completing the story with an undemonstrable narrative."*

**5. Human approval.** A named person who read the final artefact. Not an agent, not a pipeline, not approval inherited from an earlier version. Publishing is one of the actions that always require a human.

**6. Release review.** Working links, declared version, cut-off date, and consistency with everything else already published. A document that contradicts another published document is an accuracy problem, not a style problem.

---

## Renaming is not anonymisation

> *"Changing a person's name is not sufficient anonymisation."*

Replacing one first name with another protects nobody if the document also says that the person is the author's partner, a physician, and a collaborator on a shared content project. Re-identification does not need the name; it needs the combination of attributes.

The same holds for technical detail. Hiding the IP address while publishing the hostname, the provider, the region and the plan is hiding nothing.

What actually works:

| Instead of | Write |
|---|---|
| A changed name | The **role**: "the system owner", "the second user" |
| A disguised amount | A **synthetic value declared as synthetic**, or an aggregate metric |
| An altered hostname | A placeholder, or the description: "the dashboard subdomain" |
| A real case "lightly" modified | An **invented** case that illustrates the same principle |
| Data you do not have | An explicit *pending verification* marker |

The practical test: **if someone who knows the author can reconstruct the real value from the artefact, anonymisation failed.**

---

## Correction procedure

If sensitive content turns out to be already published. Order matters: stop the exposure first, investigate afterwards.

**1. Contain — minutes.** Unpublish or make private. Immediately. Do not edit in place while the content is exposed. For a public repository, make it private before touching history.

**2. Assess exposure — first hour.** What exactly was exposed, since when, and is there any signal that it was accessed — views, clones, forks, cached copies. **Assume it was seen.** A public repository is indexable, cloneable and archivable by third parties within minutes; absence of evidence of access is not evidence of absence.

**3. Invalidate the secret — first hours.** If a secret was exposed, **the secret is dead**, even if the artefact was live for five minutes. Rotate tokens, keys and passwords. Revoke OAuth grants. Anything that cannot be rotated is permanently compromised and must be treated that way. This step does not depend on the outcome of step 2. Deleting the file does not invalidate the token; it only hides it.

**4. Clean the trail.** Rewrite version-control history where necessary — a file deleted in a later commit is still in the history. Forks and clones cannot be cleaned, which is why step 3 is not optional. Request cache removal where possible, and verify that the clean version is the only one available.

**5. Notify.** If third-party data was involved, tell the third party. Not doing so out of embarrassment makes it worse. Meet any applicable legal obligation. Always inform the system owner.

**6. Document.** An incident record with timeline, root cause, scope, actions and a new control.

**7. Add the control.** An incident with no new control repeats. A new pattern in the gate-2 scan, an entry in the ignore file, an added step in the release checklist.

---

## How this repository was sanitised

The concrete steps, so the procedure can be audited and repeated.

**1. A single source of truth was fixed before anything was written.** A verified-facts document was produced from a real inspection of the system, and all documentation was written **only from it**. The private vault was not consulted during drafting. The effect: what is not in the source cannot appear in the repository, because the writer does not have it. Sanitisation stops depending on per-sentence discipline and becomes a property of the process.

**2. The prohibition list was written before the first file.** Enumerated explicitly: server address, real hostnames, chat identifiers, email addresses, credential identifiers, SSH key paths, names and ages of family members, tax identifiers, real financial figures, tokens. Prohibiting before writing is cheap; reviewing afterwards is expensive and done badly.

**3. The permitted list was written with equal detail.** Architecture, SQL schemas with table and column names, contracts, state machines, decisions, chronology, aggregate metrics. A policy that only says "no" produces empty documentation.

**4. The account handle is a literal placeholder.** A single substitution point at publication time, rather than an identity scattered across forty files.

**5. Every example is synthetic and says so.** The SQL artefacts carry a notice stating they are a didactic synthetic reconstruction, not production dumps — and they specify the extent of the fidelity: table, column, state and function names faithful to the real system; exact types, sample data and some constraints reconstructed. Saying "this is synthetic" without saying **in what respect** leaves the reader guessing what to trust.

**6. The SQL was rewritten, not copied.** Clean-room implementation from the verified design. It teaches the same principles — the invariant enforced in the database, the role without delete permission, the read-only transaction — without being production code.

**7. Workflow identifiers are omitted or abbreviated.** Even though they are opaque and grant no access. General criterion: if an identifier teaches the reader nothing, it is not there.

**8. Technical debt is published, not hidden.** All ten open items are written with names and dates. Two reasons — the honest one is that it is what makes the rest credible; the operational one is that written debt gets fixed while hidden debt gets carried. With one limit: publish **that** the weakness exists, never **how to exploit it**. "Insecure defaults exist in the MCP server when environment variables are absent" is a finding; publishing the default values would be an exploit.

**9. Every document declares its evidence levels** in a closing table, so a reader can tell what was measured from what was deduced.

**10. A final pass against the six gates**: declared provenance, secret scan, licensing, accuracy with evidence levels, named human approval, and cross-document consistency.

### Deliberately left out

| Omitted | Why |
|---|---|
| The concrete content of the tax-compliance skills | The method is published, the tax procedure is not |
| Chat identifiers, email addresses, family names | Prohibited, no exceptions |
| Server address, hostname, network topology | Teaches nothing, helps map the system |
| Credential identifiers | Internal identifiers with no didactic value |
| Amounts, balances, receipts | Personal financial data |
| The values of the insecure MCP defaults | The finding is published; the exploit is not |

---

## Before publishing anything

Three questions. If any answer is uncomfortable, it is not ready.

1. **What does this teach?** If the answer is "that I did something", do not publish it. A public artefact is teaching material, not a trophy.
2. **What does it reveal?** Walk the six prohibited categories one by one, not from memory.
3. **Would this be a problem in five years?** Personal data does not expire, and the repository persists.

---

## Evidence level

| Claim | Level |
|---|---|
| Root rule, permitted and prohibited lists, the six gates, the anonymisation note | Verified (existing policy, 2026-08-03) |
| The ten sanitisation steps applied to this repository | Verified |
| The seven-step correction procedure | Inferred — an extension; not yet exercised against a real publication incident |
| That no prohibited data remains in the repository | Owner-confirmed, pending a final automated scan |

> Last verified: 2026-08-05
