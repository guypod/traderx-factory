---
name: review-speckit-source-of-truth
description: Review SpecKit-governed TraderX changes for whether implementation follows numbered feature specs, preserves generated-source boundaries, and carries required state evidence. Use as one lens in a code review run.
---

# Review lens: SpecKit Source of Truth

Review TraderX changes for whether the diff keeps the numbered SpecKit feature pack as the implementation authority.

## Scope

- **Feature origin:** Implementation, pipeline, template, generated, or documentation changes must trace to a numbered `specs/NNN-*` feature pack with `spec.md`, `plan.md`, and `tasks.md` updates when requirements, acceptance, or implementation scope changes.
- **Generated boundary:** Durable behavior must be changed in canonical specs, templates, generators, or pipeline scripts, not only by persistent hand-edits under `generated/`.
- **State compatibility:** Changes must preserve earlier states and baseline API/event contracts, or include explicit spec impact and acceptance updates for the compatibility change.
- **Evidence gates:** Changes that affect state generation, learning docs, contracts, or runtime behavior must preserve the repository's root gates, mapped feature checks, and evidence expectations.

## Method

Start from changed implementation, template, pipeline, or generated-state paths and work outward to the corresponding `specs/NNN-*` pack, generation script, and validation path. For generated output, identify whether the same change is represented in its canonical source. For workflow or validation-script edits, compare the checks that ran before and after the change; follow removed gate invocations into their scripts to establish what acceptance or consistency checks disappear and whether another mandatory path still runs them.

For removed CI commands, inspect the invoked script and enumerate lost checks, then search the remaining mandatory workflows for equivalent invocations. Treat deletion-only hunks as a behavior change: absence of new application lines does not make lost validation harmless. In this repository the aggregate coverage script chains learning parity, generated-state artifacts, lifecycle contracts and documentation drift checks; establish whether these remain enforced rather than assuming conformance tests cover them.

## Threshold

Report a change when it changes behavior, contracts, generated artifacts, or state delivery without the matching numbered spec/plan/tasks source, when generated output is the only durable source of truth, or when a previously mandatory evidence gate is removed or bypassed and its checks are not preserved on another mandatory path. A green pipeline that no longer validates required state/spec consistency is a loss of enforcement even if the application code is unchanged.

Do not report wording-only documentation edits that do not alter requirements, generated snapshots that are clearly regenerated from changed canonical sources, or mechanical formatting that leaves SpecKit contracts unchanged, or gate consolidation that demonstrably preserves the same checks.

## Reporting

- Name the changed path and the missing or inconsistent SpecKit source path.
- State whether the fix belongs in `spec.md`, `plan.md`, `tasks.md`, a template, a generator, or a validation script.
- When prior-state or contract compatibility is at risk, name the state or contract boundary that needs explicit impact and acceptance coverage.
