# COMMENT-ETIQUETTE.md

> **Core Directive:** Code explains *how*; comments explain *why*. If code can be refactored to be self-explanatory, refactor it—do not comment it.

---

## 1. Core Principles (Intent Over Mechanics)

* **Document the Rationale:** Explain business constraints, algorithm choices, architectural trade-offs, and non-obvious domain logic. Assume the reader understands programming syntax.
* **Prioritize Self-Documenting Code:** Choose descriptive identifier names, extract focused helper functions, and replace magic numbers with named constants before writing comments.
* **Eliminate Syntax Echoes:** Never state what the syntax is literally doing (e.g., ban `// increment counter`).
* **Highlight Gotchas & Edge Cases:** Document third-party library bugs, platform-specific workarounds, concurrency assumptions, and performance trade-offs.
* **Strict Action Tags Only:** Standardize on tracked action tags (`TODO`, `FIXME`, `HACK`). Every tag must include an issue or ticket identifier (e.g., `// TODO(SEC-402): Add rate-limiting`).

---

## 2. Maintenance & Hygiene

* **Zero Dead Code:** Never commit commented-out code blocks. Rely on Git history for archaeology and recovery.
* **Atomic Synchronization:** Update or remove comments in the same commit/PR as the corresponding code changes. Stale comments are active misinformation.
* **Standardized Docstrings:** Document public APIs, interfaces, and exported functions using language standards (PEP 257, JSDoc, Rustdoc, Godoc). Always specify:
* Parameter constraints and invariants
* Return structures and types
* Thrown exceptions and error conditions
* Side effects (I/O, database mutations, network calls)



---

## 3. Strict LLM & AI Generation Guardrails

* **No Diff or Changelog Narration:** Never write commit messages, author metadata, or change logs in source comments (e.g., banned: `// Added by AI to handle edge case` or `// Updated logic for v2`). Put change reasoning in Git commits and PR descriptions.
* **Zero Conversational Fluff:** Strip out conversational lead-ins, mechanical step-by-step narration, or token-filler explanations.
* **Ban Phantom & Placeholder Stubs:** Never emit placeholder comments (e.g., `// TODO: Implement error handling here`, `// Logic goes here`). Write the complete implementation or raise an explicit `NotImplementedError`.
* **Validate Inferred Contracts:** Cross-check AI-generated docstrings to ensure parameter types, exceptions, and structural contracts reflect reality, not hallucinations.
* **Preserve Institutional Context:** During automated refactors, never strip existing human-authored architectural warnings, edge-case rationale, or domain notes unless the underlying requirement has been deprecated.

---

## 4. Reference Contrasts

### Narration vs. Rationale

```javascript
// BAD: Echoing syntax mechanics
// Loop through users and filter active ones
const active = users.filter(u => u.status === 'ACTIVE');

// GOOD: Self-documenting code (no comment required)
const activeUsers = users.filter(isUserActive);

```

### Workarounds vs. Noise

```javascript
// BAD: Changelog / author commentary inside source
// Fixed null pointer bug found during testing by Alex
if (config?.timeout) { ... }

// GOOD: Documenting external constraint / workaround
// Upstream proxy terminates idle connections at 30s; enforce client timeout at 25s
if (config?.timeout) { ... }

```

### Action Tags

```javascript
// BAD: Untracked and ambiguous
// TODO: fix this later

// GOOD: Actionable, attributed, and tracked
// TODO(AUTH-118): Migrate to asymmetric JWT verification once KMS key rotation lands

```
