# OpsFlow 360 — Project Charter

**Status:** Accepted for implementation  
**Baseline date:** 18 August 2026  
**Target platform:** Hosted Oracle APEX workspace with Oracle Database and PL/SQL  
**Delivery method:** Numbered, evidence-driven patches

The development database is not installed locally. Ordered SQL and PL/SQL
patches are executed through APEX SQL Workshop, application work is performed
through App Builder, and exports are downloaded after every accepted patch.

## 1. Problem statement

Employees often use email, spreadsheets, and disconnected messages to request
IT or operational help, obtain equipment, and request purchases. Operations
teams then lose ownership, deadlines, approval history, and asset custody.

OpsFlow 360 provides a single, auditable portal for those connected processes.
It is designed as a credible enterprise portfolio application, not as a generic
CRUD demonstration.

## 2. Portfolio objective

The finished application must provide verifiable evidence that its developer
can:

1. Design a normalized Oracle schema with deliberate constraints and indexes.
2. Implement business transactions through package-based PL/SQL APIs.
3. Build accessible, responsive APEX pages and reusable shared components.
4. Apply authentication, role authorization, row-level rules, and Session State
   Protection.
5. Build approvals with APEX Workflows and Human Tasks.
6. Implement scheduled SLA checks using APEX Automations.
7. consume and expose REST/JSON services safely.
8. Test database logic and record performance evidence.
9. Export and install the application in a clean environment.

## 3. Actors and permissions

| Role | Primary responsibilities |
|---|---|
| Employee | Create and track own requests; comment; view assigned assets; read published knowledge articles |
| Service Agent | Triage, assign, investigate, communicate, resolve, and close tickets |
| Procurement Officer | Review approved purchase requests; create orders; record receipts |
| Manager | Approve or reject requests for employees within managed departments |
| Operations Admin | Configure users, departments, categories, SLAs, locations, and assets; see operational dashboards |
| Auditor | Read-only access to records, history, approvals, errors, and audit reports |

Authorization must be enforced on pages, components, processes, queries, and
PL/SQL APIs. Navigation visibility alone is not security.

## 4. Core workflows

### 4.1 Service request

`Draft → Submitted → Triaged → In Progress → Waiting on User → Resolved → Closed`

- Reopen is allowed only during a configured period.
- Cancellation and rejection require a reason.
- Every state change creates history.
- Ownership and status supplied by the browser are never trusted without
  server-side authorization and transition checks.

### 4.2 Purchase request

`Draft → Submitted → Manager Approval → Procurement Review → Approved → Ordered → Partially Received / Received → Closed`

- Low-value requests require manager approval.
- High-value requests require manager and operations approval.
- Totals and routing thresholds are server-calculated.
- Receiving goods and recording stock movements are one atomic transaction.

### 4.3 Asset

`In Stock → Reserved → Assigned → In Repair → Retired / Lost`

- An asset can have at most one active employee assignment.
- Assignment, transfer, return, repair, and retirement remain historically
  auditable.

### 4.4 SLA

- Category and priority determine first-response and resolution targets.
- Waiting states may pause the resolution clock.
- Scheduled monitoring warns before breach and escalates after breach.
- Retry-safe processing prevents duplicate notifications.

## 5. In scope

- Organization and user profiles
- Service catalog, requests, comments, attachments, and history
- SLA policies, deadlines, pauses, warnings, and escalations
- Asset types, assets, locations, assignments, repairs, and custody history
- Purchase request header/items, approvals, purchase orders, receipts, and
  inventory movements
- Knowledge article authoring, review, publication, and search
- Role-aware APEX dashboards and reports
- Audit/error logging and secure file handling
- One inbound and one outbound REST/JSON use case
- Installable, responsive PWA behavior and an Arabic core-flow demonstration
- Automated PL/SQL tests, security checks, measured SQL tuning, and deployment
  exports

## 6. Explicitly out of scope for the portfolio release

- Payroll, accounting ledger, tax, or bank reconciliation
- Real payment processing
- Full supplier-contract management
- Full ITIL implementation
- Native iOS or Android applications
- Multi-tenant SaaS billing
- Production integration with a real employer's private systems
- Generative AI as a dependency of a core workflow

These exclusions keep the project finishable while preserving a strong
enterprise story.

## 7. Quality attributes

### Security

- Least privilege and deny-by-default authorization
- Bind variables for runtime values
- Escaped output and validated file uploads
- No credentials, wallets, tokens, or personal data in source control
- Protected sensitive APEX items and tested direct-URL access

### Integrity

- Primary, foreign, unique, check, and not-null constraints define rules that
  must remain true regardless of UI.
- APIs validate state transitions and actor permissions.
- Multi-table operations define one transaction owner.

### Maintainability

- Public package specifications are the application contract.
- Repeated rules are not copied into page processes.
- Configuration is stored in tables or application settings, not magic values.
- Every database and APEX change is exportable and versioned.

### Performance

- Prefer set-based SQL over row-by-row processing.
- Index foreign keys and verified access paths deliberately.
- Dashboard metrics reconcile with detail queries.
- Tuning claims require before-and-after evidence.

### Accessibility and globalization

- Keyboard access, labels, meaningful validation, contrast, and responsive
  behavior are acceptance concerns.
- The core employee workflow will be demonstrated in English and Arabic/RTL.

## 8. Definition of done for every patch

A patch is done only when:

1. Its source is repeatable from a clean starting point.
2. Every stated positive and negative test passes.
3. Applicable authorization and tampering tests pass.
4. Existing completed flows still pass a regression check.
5. No unexpected invalid database objects remain.
6. APEX changes are exported when the patch contains APEX work.
7. Evidence and the changelog are updated.
8. The patch has one reviewed Git commit.

## 9. Final success measures

- Clean database installation succeeds without manual object repair.
- Clean APEX import runs against the installed schema.
- Six roles pass a documented permission matrix.
- Core package test suites have zero unexpected failures.
- At least one measured report or transaction shows a documented performance
  improvement.
- The README, ERD, screenshots, test report, architecture decisions, and demo
  script allow a reviewer to evaluate the project without private guidance.
