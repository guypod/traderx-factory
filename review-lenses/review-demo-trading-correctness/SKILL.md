---
name: review-demo-trading-correctness
description: Review TraderX demo trading changes for synthetic-only behavior, order validation, API/event contract preservation, and consistent financial state transitions. Use as one lens in a code review run.
---

# Review lens: Demo Trading Correctness

Review changes to TraderX demo trading flows for whether synthetic orders, positions, accounts, and events remain internally consistent and safely bounded.

## Scope

- **Synthetic boundary:** Demo flows must not introduce real broker, payment, account, or unsupported live market-data integrations, or language that implies real trading. Approved reference-price bootstrap such as state 008 yfinance startup open/close retrieval is fine when it feeds documented synthetic tick generation and is not a live trading dependency.
- **Order validation:** Side, ticker/security, account, and quantity inputs must reject invalid or ambiguous values before they can create partial state.
- **State consistency:** Order, trade, account, and position changes must preserve lifecycle order, quantity conservation, and idempotent handling across services.
- **API and event contracts:** Request/response schemas, message subjects, payload fields, and failure behavior must remain compatible unless specs and acceptance criteria explicitly change them.

## Method

Start at the changed trading endpoint, UI action, message handler, or persistence update. Follow the order through validation, API/event boundaries, processing, position/account updates, and user-visible status.

## Threshold

Report a change when an invalid synthetic trade can be accepted, a failure can leave silent partial financial state, quantity or lifecycle invariants can be broken, or a contract can change without matching spec coverage.

Do not report intentionally stubbed demo behavior that is clearly synthetic, documented reference-price bootstrap for synthetic data generation, isolated display-only copy changes that do not imply real trading or real account effects, or validation already enforced at an earlier boundary that all callers must use.

## Reporting

- Name the invalid input, transition, or contract edge and the path it can take.
- State the inconsistent state or user-visible false outcome that can result.
- Point to the boundary where validation, rollback, idempotency, or spec/contract coverage should be added.
