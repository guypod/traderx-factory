---
name: review-runtime-integration-accessible-learning
description: Review TraderX runtime, UI, and learning-doc changes for local integration truthfulness, accessible interactions, and accurate demo guidance. Use as one lens in a code review run.
---

# Review lens: Runtime Integration and Accessible Learning

Review changes that affect TraderX local runtime, browser flows, health/readiness, UI accessibility, or learning guidance for whether the demo remains truthful and usable.

## Scope

- **Runtime integration:** Ports, CORS, startup order, ingress, health/readiness, and local configuration must match the selected state contract. Baseline uncontainerized paths should not require ingress; edge, compose, or Kubernetes states may require ingress when their specs say so.
- **Fallback truthfulness:** SPA or static fallbacks must not mask missing assets, development-only endpoints, broken API routes, or false service readiness.
- **Accessible interaction:** Trade-ticket and learning UI changes must preserve keyboard operation, focus flow, label association, useful inline feedback, and screen-reader-relevant state.
- **Learning accuracy:** Docs, status text, and demo context must match the current state, name limitations clearly, and avoid claiming verification that the change did not perform.

## Method

Start at changed runtime scripts, UI routes/components, health/status paths, or learning docs. Trace how a local user reaches the feature, how failures are surfaced, and whether documentation matches the implemented state.

## Threshold

Report a change when local runtime can appear healthy while a required path for the selected state is broken, a dev-only or fallback path can look like success, an interactive flow becomes inaccessible or silent on error, or docs/status claim behavior or verification not supported by the change.

Do not report cosmetic copy changes that remain accurate, generated docs that match updated state artifacts, or accessibility patterns already provided by unchanged shared components.

## Reporting

- Name the route, script, component, or doc claim and the condition that makes it misleading or inaccessible.
- State what a local user or learner would incorrectly see or be unable to do.
- Identify the concrete fix: route failure, readiness signal, inline error, label/focus behavior, or doc/status wording.
