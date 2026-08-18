# ADR-0001: Build an Integrated Enterprise Operations Platform

- **Status:** Accepted
- **Date:** 2026-08-18

## Context

A portfolio project for a junior Oracle APEX developer must be finishable but
also prove more than report-and-form generation. It should create visible
evidence of Oracle SQL, PL/SQL, APEX security, workflow, automation,
integration, testing, and deployment skills.

## Decision

Build OpsFlow 360: one connected operations platform covering service requests,
SLAs, assets, procurement approvals, inventory movements, and a knowledge base.
Deliver a small usable vertical slice first, then expand it through numbered
patches.

The first portfolio release is a single-organization application. It is not a
multi-tenant SaaS product.

## Alternatives considered

| Alternative | Reason not selected as the flagship |
|---|---|
| Basic inventory | Good SQL exercise, but too easy to present as simple CRUD |
| Clinic booking | Demonstrates scheduling, but overlaps common tutorial projects and introduces sensitive-data distractions |
| E-commerce | Familiar, but its strongest concerns are payments and storefront UX rather than APEX-native enterprise workflow |
| Help desk only | Strong and finishable, but narrower than the connected asset and procurement story |

## Consequences

### Positive

- One demo connects user requests, approvals, operational work, and audit.
- The domain naturally exercises APEX Workflows, Human Tasks, Automations,
  Access Control, REST Data Sources, reports, dashboards, and PWA behavior.
- PL/SQL packages can own meaningful state transitions and transactions.

### Negative

- Scope can expand uncontrollably.
- The complete product cannot be built safely as one patch.

### Controls

- Use the explicit out-of-scope list in the project charter.
- Require acceptance evidence before moving to the next patch.
- Build the service-request vertical slice before procurement and assets.
