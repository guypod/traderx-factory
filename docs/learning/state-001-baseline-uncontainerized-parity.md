---
title: "State 001: Simple App - Base Uncontainerized App"
---

# State 001 Learning Guide

## Position In Learning Graph

- Previous state(s): none
- Dotted-line parent(s): none
- Next state(s): [002-edge-proxy-uncontainerized](/docs/learning/state-002-edge-proxy-uncontainerized)

## Convergence Metadata

- Convergence state: `no`
- Convergence level: `none`
- Lineage role: `prelude`
- Nearest previous convergence: `none`
- Nearest next convergence: `none`

## Rendered Code

- Generated branch: [code/generated-state-001-baseline-uncontainerized-parity](https://github.com/finos/traderX/tree/code/generated-state-001-baseline-uncontainerized-parity)
- Authoring branch (spec source): [main](https://github.com/finos/traderX/tree/main)

## Code Comparison With Previous State

- No previous-state compare link for this state.

## Plain-English Code Delta

- **Code focus:** Establishes the full baseline service set and Angular UI in a local multi-process runtime.
- **Runtime behavior:** Uses explicit host ports and direct cross-origin service calls.
- **Learning takeaway:** This is the reference implementation all later state diffs are measured against.

## Check Prerequisites

Run this read-only doctor before generating or building. It installs nothing, starts nothing,
reports every missing or incompatible tool with guidance, and exits non-zero on blockers.

Supported toolchain: a JDK 21+ (`java` and `javac` from the same JDK, not a JRE),
Node.js `^20.19 || ^22.12 || >=24` with npm, .NET SDK 9.x (with the .NET and ASP.NET Core 9 runtimes),
`rsync`, `nc` (netcat), `jq` and `curl`.

```bash
./scripts/doctor-base-uncontainerized-prerequisites.sh
```

Run order: prerequisite doctor, then generation, then `--build-only`, then start.

## Run This State

```bash
CORS_ALLOWED_ORIGINS=http://localhost:18093 ./scripts/start-base-uncontainerized-generated.sh
```

## Canonical Spec Links

- State spec pack: [/specs/baseline-uncontainerized-parity](/specs/baseline-uncontainerized-parity)
- Architecture: [/specs/baseline-uncontainerized-parity/system/architecture](/specs/baseline-uncontainerized-parity/system/architecture)
- Flows / topology: [/specs/baseline-uncontainerized-parity/system/end-to-end-flows](/specs/baseline-uncontainerized-parity/system/end-to-end-flows)
- Research: [link](/specs/baseline-uncontainerized-parity/research)
- Data model: [link](/specs/baseline-uncontainerized-parity/data-model)
- Quickstart: [link](/specs/baseline-uncontainerized-parity/quickstart)

