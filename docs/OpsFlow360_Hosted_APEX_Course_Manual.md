# OpsFlow 360 — Hosted Oracle APEX Course Manual

**Student level:** Junior Oracle APEX developer  
**Current foundation:** PL/SQL blocks, variables, `%TYPE`, and `%ROWTYPE`  
**Study pace:** 8 hours per week  
**Total guided project effort:** 208 hours  
**Runtime:** Oracle-hosted APEX workspace; no local Oracle Database  
**Delivery style:** 19 numbered patches, `P00` through `P18`

## 1. What you are building

OpsFlow 360 is one connected enterprise operations application. It combines:

1. Service requests and incident tickets.
2. SLA deadlines, warnings, pauses, breaches, and escalations.
3. Company assets, custody, transfers, repairs, and retirement.
4. Purchase requests, multi-level approvals, purchase orders, receiving, and
   stock movements.
5. Knowledge articles and secure attachments.
6. Role-aware dashboards, audit logs, notifications, REST services, PWA
   behavior, and an Arabic/RTL demonstration.

The application is intentionally stronger than a basic CRUD portfolio app.
Every visible feature must be supported by a database rule, PL/SQL contract,
authorization rule, test, and exportable artifact.

## 2. The environment model

### What is hosted by Oracle

- Oracle Database
- Oracle APEX engine
- ORDS/web listener
- APEX workspace and parsing schema
- Application runtime

You do not install or configure these locally for this course.

### What stays on your computer

- Downloaded patch `.sql` files
- APEX application exports
- Markdown evidence and screenshots
- Git repository or files uploaded through the GitHub website

This local folder is source control and evidence only. It is not a database
runtime.

### The four browser tools you will learn

| Tool | Use it for | Do not use it for |
|---|---|---|
| SQL Scripts | Ordered DDL, package, seed, and migration scripts | Ad-hoc experiments that should not be retained |
| SQL Commands | Short queries and controlled test calls | Large multi-file installation patches |
| Object Browser | Inspect columns, constraints, indexes, data, dependencies, and generated DDL | Unrecorded manual production changes |
| App Builder | Pages, regions, items, processes, validations, Shared Components, security, workflows, and exports | Replacing database constraints or business APIs |

Oracle documents SQL Scripts as the stored multi-statement script tool, SQL
Commands as the ad-hoc command tool, and Object Browser as the object inspection
and editing tool. We will use each deliberately instead of treating SQL
Workshop as one undifferentiated screen.

## 3. How every patch will be taught

No patch will be supplied as unexplained code. Every patch uses the same cycle:

1. **Vocabulary** — define each new Oracle/APEX term.
2. **Business reason** — state the real rule the feature must protect.
3. **Design** — show the data, transaction, UI, and security decisions before
   implementation.
4. **Build** — provide the exact SQL or exact App Builder clicks and property
   values.
5. **Read the code** — explain important statements and why alternatives were
   not used.
6. **Positive test** — prove a permitted operation succeeds.
7. **Negative test** — prove invalid input is rejected.
8. **Authorization/tampering test** — prove the server rejects a forbidden or
   modified request, not merely hides a button.
9. **Regression test** — rerun earlier critical flows.
10. **Inspect** — use Object Browser or App Builder utilities to see the created
    components and dependencies.
11. **Export** — download database/APEX source changed by the patch.
12. **Evidence** — save results, screenshots, and decisions.
13. **Rollback** — document how to undo the patch safely.
14. **Stop gate** — do not begin the next patch until acceptance passes.

When you return the evidence, the next lesson will start by reviewing mistakes
and explaining corrections. This prevents copying nineteen large scripts
without understanding them.

## 4. Patch roadmap — all learning and deliverables

The hours total 208, matching a 26-week plan at 8 hours per week. Estimates are
learning time, not deadlines.

### P00 — Hosted workspace baseline (2 hours)

**Learn:** workspace, parsing schema, App Builder, SQL Workshop, SQL Scripts,
SQL Commands, Object Browser, migrations, evidence, and exports.

**Build:** nothing in the database or App Builder. Run a read-only environment
check, record versions/NLS/time zone, check invalid objects and `OF_` name
collisions, and establish the project folder.

**Pass:** exact environment is known; seven checks run; unexpected objects are
understood; no credentials are saved.

### P01 — Domain model, ERD, and schema contract (8 hours)

**Learn:** entities, attributes, one-to-many and many-to-many relationships,
optional/mandatory relationships, candidate keys, surrogate keys,
normalization through third normal form, reference data, transactions, and
state machines.

**Build:** domain glossary, ERD, table catalogue, column/data-type contract,
relationship matrix, ticket/purchase/asset transition matrices, audit rules,
and deletion/retention rules. No tables yet.

**Pass:** every field has a reason; every relationship has cardinality; every
state transition identifies actor, precondition, result, and forbidden paths.

### P02 — Core schema, constraints, and indexes (14 hours)

**Learn:** Oracle data types, identity/key strategy, primary/foreign/unique/check
constraints, nullability, timestamp choices, constraint naming, indexes,
foreign-key indexing, DDL transactions, install order, and idempotent
verification.

**Build:** ordered table DDL, constraints, sequences/identity behavior selected
in P01, verified indexes, comments, installation script, validation script, and
development-only cleanup script.

**Pass:** clean install succeeds; duplicate/invalid/orphan data fails for the
correct reason; all objects are valid; the schema matches the contract.

### P03 — Reference data, demo data, SQL, and reporting views (8 hours)

**Learn:** deterministic seed data, `MERGE`, joins, aggregates, analytic
functions, `CASE`, date/timestamp handling, views, and query test data.

**Build:** departments, locations, roles, priorities, categories, statuses, SLA
policies, believable demo users/data, and initial reporting views.

**Pass:** seed reruns safely; reports reconcile with base tables; data covers
normal, boundary, and exception cases.

### P04 — Security, audit, error, and utility PL/SQL packages (14 hours)

**Learn:** package specifications/bodies, public versus private routines,
exceptions, `raise_application_error`, invoker/definer rights, transaction
ownership, autonomous transaction tradeoffs, application context, audit design,
and error correlation IDs.

**Build:** foundational `OF_*_API` packages for current actor/role checks,
authorization assertions, auditing, error handling, and shared constants.

**Pass:** permitted and forbidden calls behave correctly; audit data cannot be
silently falsified by browser input; package APIs are documented and valid.

### P05 — Ticket lifecycle API vertical slice (18 hours)

**Learn:** API-driven DML, locking, atomic transactions, optimistic concurrency,
transition validation, ownership, history, comments, SLA deadline creation,
and package tests.

**Build:** create draft, edit draft, submit, triage, assign, start, wait, resume,
resolve, close, cancel, and reopen routines with history and SLA integration.

**Pass:** the full lifecycle succeeds; every forbidden transition fails; two
sessions cannot silently overwrite the same ticket; history reconciles.

### P06 — Asset lifecycle API (12 hours)

**Learn:** temporal history, exclusive active relationships, custody rules,
status derivation, repair flows, and cross-module validation.

**Build:** register, reserve, assign, transfer, return, send to repair, return
from repair, mark lost, and retire asset routines.

**Pass:** one asset cannot have two active custodians; every transfer is
auditable; invalid lifecycle moves fail.

### P07 — Procurement, receiving, and inventory API (18 hours)

**Learn:** header/detail transactions, calculated totals, approval thresholds,
purchase orders, partial receipts, inventory ledgers, atomic stock movement,
and double-processing prevention.

**Build:** purchase request header/items, submit, approval routing, approve,
reject, procurement review, order creation, partial/full receipt, and close.

**Pass:** totals cannot be trusted from the UI; required approvals cannot be
bypassed; repeat receipt attempts do not duplicate stock.

### P08 — APEX application shell, authentication, and authorization (12 hours)

**Learn:** Create App Wizard, Universal Theme, application definition,
authentication schemes, authorization schemes, Access Control concepts,
Shared Components, navigation, application items, application processes,
error handling, Session State Protection, and build options.

**Build:** the OpsFlow 360 application shell, sign-in behavior, role-aware
navigation, shared authorization schemes, global page, application error
handler, app settings, and placeholder dashboards.

**Pass:** all six roles receive only intended access; direct page URLs and
altered session state are tested; the first full application export is saved.

### P09 — Employee self-service portal (12 hours)

**Learn:** forms, interactive reports, cards, faceted search, page items,
validations, computations, Dynamic Actions, processes, branches, friendly error
messages, and calling PL/SQL APIs from APEX.

**Build:** create/edit/submit ticket, My Requests, ticket detail/timeline,
comments, assigned assets, purchase-request entry, and knowledge search.

**Pass:** the employee sees only permitted rows; page processes call packages;
tampered owner/status/price values fail server-side.

### P10 — Service desk and operations consoles (14 hours)

**Learn:** interactive grids versus interactive reports, master-detail pages,
facets, smart filters, modal dialogs, bulk operations, refresh behavior,
server-side conditions, and performance-aware region SQL.

**Build:** triage queue, agent work queue, ticket workspace, SLA board, asset
console, procurement queue, configuration pages, and audit viewer.

**Pass:** queues reconcile with APIs/views; bulk actions validate every row;
auditor pages are read-only; unauthorized actions remain blocked.

### P11 — APEX Workflows and Human Tasks (14 hours)

**Learn:** workflow definitions, activities, variables, transitions, human-task
definitions, participants, due dates, outcomes, task details, task inbox, and
workflow versioning.

**Build:** purchase approval workflow with manager and conditional operations
approval, task inbox, task details, approve/reject outcomes, and API callbacks.

**Pass:** participant selection is correct; high-value routing cannot be
bypassed; repeated outcomes are safe; workflow history matches business state.

### P12 — Dashboards and SLA analytics (10 hours)

**Learn:** KPI definitions, charts, calendar/timeline options, aggregates,
conditional aggregation, analytic SQL, drill-downs, saved report settings,
data freshness, and accessible chart alternatives.

**Build:** employee, agent, manager, procurement, admin, and auditor dashboards;
SLA risk/breach analytics; asset and procurement KPIs.

**Pass:** every KPI has a documented formula and detail query; totals reconcile;
role filters cannot be bypassed.

### P13 — Automations and notifications (8 hours)

**Learn:** APEX Automations, schedules, query actions, execution logs,
retry-safe processing, warning/escalation rules, email configuration limits,
in-app notifications, and time-zone safety.

**Build:** upcoming-SLA warning, SLA breach escalation, stale waiting-ticket
reminder, overdue approval reminder, and retry-safe notification records.

**Pass:** reruns do not duplicate notifications; failures are logged; test
execution is safe; all time calculations use explicit rules.

### P14 — REST, ORDS, and JSON integration (12 hours)

**Learn:** REST semantics, HTTP methods/status codes, JSON generation/parsing,
ORDS modules/templates/handlers, REST Data Sources, credentials, allow lists,
timeouts, validation, pagination, and integration error handling.

**Build:** one secured inbound OpsFlow API and one outbound REST Data Source;
JSON mapping, integration log, safe mock/test endpoint, and API documentation.

**Pass:** valid requests work; missing/invalid credentials and payloads fail
safely; secrets are never exported; integration failures do not corrupt data.

### P15 — Attachments, knowledge base, and search (8 hours)

**Learn:** BLOB storage, MIME/type/size validation, filename safety, download
authorization, temporary APEX files, article versioning, publication workflow,
and search design.

**Build:** secure ticket attachments, authorized download process, knowledge
article draft/review/publish lifecycle, categories, and searchable library.

**Pass:** disguised/oversized files fail; direct download URLs cannot expose
another user's file; unpublished content is hidden from employees.

### P16 — PWA, Arabic/RTL, accessibility, and responsive UX (8 hours)

**Learn:** PWA settings, installability, icons, responsive Universal Theme,
globalization, translation mappings, RTL behavior, labels, keyboard navigation,
focus, contrast, semantic status, and accessible validation.

**Build:** installable PWA settings, responsive core pages, Arabic translation
of the employee ticket flow, RTL review, accessibility fixes, and device tests.

**Pass:** core flow works on mobile and desktop; Arabic/RTL does not break
layout; keyboard and screen-reader-oriented checks pass.

### P17 — Security, automated testing, and performance hardening (12 hours)

**Learn:** threat modeling, least privilege, injection/XSS/CSRF concepts,
Session State Protection, URL tampering, authorization coverage, utPLSQL or a
hosted-compatible test harness, execution plans, statistics, index evidence,
and before/after performance measurement.

**Build:** role/page/component permission matrix, security test suite, package
regression suite, direct URL/item tampering tests, invalid-object check,
performance baselines, and justified tuning changes.

**Pass:** zero unexplained security failures; all core tests pass; no invalid
objects remain; performance claims include measurements rather than adjectives.

### P18 — Release, deployment, documentation, demo, and CV evidence (4 hours)

**Learn:** full application export/import, supporting-object installation,
release notes, semantic versions, clean-environment verification, demo design,
portfolio storytelling, and honest CV metrics.

**Build:** final ordered database installer, APEX export, configuration guide,
ERD, architecture notes, permission matrix, test report, screenshots, five- to
seven-minute demo script, README, and CV/project bullets.

**Pass:** clean installation is reproducible; no secret is present; another
reviewer can understand and run the application using the documentation.

## 5. Patch dependencies

- P00 must pass before schema design starts.
- P01 must be accepted before any DDL in P02.
- P02–P04 establish integrity and reusable infrastructure.
- P05 is the first complete database vertical slice.
- P08 creates APEX only after the ticket API exists.
- P09–P10 call APIs; they do not duplicate lifecycle DML in page processes.
- P11–P15 extend workflows, analytics, automation, and integration.
- P16–P17 harden experience, security, testing, and performance.
- P18 releases only after all earlier acceptance gates pass.

## 6. Hosted-workspace operating procedure

### Run an ordered database patch

1. Sign in to the correct workspace.
2. Select **SQL Workshop**.
3. Select **SQL Scripts**.
4. Upload the patch file.
5. Give it the exact patch name, such as `P02_core_schema`.
6. Open it and confirm the header, patch number, and target schema.
7. Click **Run** and then **Run Now**.
8. Open the detailed result.
9. Check each statement status and inspect the first error, if any.
10. Do not repeatedly rerun a partially successful DDL patch until its
    documented recovery steps are followed.
11. Save the result and run the patch validation script.

### Run a short test query

1. Open **SQL Workshop → SQL Commands**.
2. Ensure the displayed schema is the parsing schema recorded in P00.
3. Paste only the test statement specified in the lesson.
4. Keep row limits and autocommit behavior as stated by the patch.
5. Click **Run**.
6. Copy the statement and result to that patch's evidence file.

### Inspect a created database object

1. Open **SQL Workshop → Object Browser**.
2. Select the parsing schema, if the workspace maps more than one schema.
3. Filter using the `OF_` object name.
4. Inspect columns, constraints, indexes, dependencies, errors, DDL, and sample
   queries as required.
5. Do not use a manual Object Browser edit when the change belongs in a
   versioned migration.

### Export an APEX application after an accepted APEX patch

1. Open **App Builder**.
2. Select the OpsFlow 360 application.
3. Use **Export/Import → Export** or **Workspace Utilities → Export**, depending
   on the navigation shown by the installed APEX release.
4. Export the application as a readable SQL file; later patches may also use a
   split export when supported by the chosen workflow.
5. Download the export and store it under `apex/application/`.
6. Never place workspace credentials, REST credentials, or secrets in the
   repository.
7. Record the application ID, APEX version, export time, and patch number.

## 7. Rules that prevent tutorial-level architecture

1. A hidden button is usability, not authorization.
2. A page validation is user feedback, not the only integrity rule.
3. The browser cannot choose ownership, approval requirement, total, status,
   SLA deadline, or audit actor without server validation.
4. Page processes call packaged APIs for business transactions.
5. Database constraints protect facts that must always be true.
6. Every multi-table business action has one transaction owner.
7. `COMMIT` is not scattered through helper procedures.
8. Dynamic SQL is avoided unless a real requirement justifies it, and bind
   variables are used for values.
9. Every role is tested using both the UI and direct access/tampering attempts.
10. Every patch produces source, tests, evidence, and rollback instructions.

## 8. What to do now

Do only `P00`. Open `docs/patches/P00-baseline-and-environment.md` and complete
every step. Return the seven requested results and any screenshots/errors.
P01 will then turn the product charter into the ERD and schema contract without
creating tables prematurely.

## 9. Official references used by this course

- SQL Workshop overview:
  https://docs.oracle.com/en/database/oracle/apex/26.1/aeutl/getting-started.html
- SQL Scripts behavior:
  https://docs.oracle.com/en/database/oracle/apex/26.1/aeutl/sql-scripts.html
- Object Browser:
  https://docs.oracle.com/en/database/oracle/apex/26.1/aeutl/understanding-object-browser.html
- Create Application Wizard:
  https://docs.oracle.com/en/database/oracle/apex/26.1/htmdb/running-the-create-app-wizard.html
- App Builder export/import:
  https://docs.oracle.com/en/database/oracle/apex/26.1/htmdb/exporting-and-importing-from-app-builder.html

The exact APEX version is discovered in P00. If the hosted workspace is not on
26.1, later UI directions will be adjusted to that recorded release.
