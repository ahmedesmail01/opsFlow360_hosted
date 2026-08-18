# OpsFlow 360

OpsFlow 360 is an enterprise operations portal built with Oracle APEX and
PL/SQL. It connects service requests, SLA tracking, company assets,
procurement approvals, stock movements, knowledge articles, notifications,
audit history, dashboards, and REST integrations in one believable product.

This repository is deliberately built in numbered patches. A patch is complete
only when its positive, negative, security, and regression checks pass and its
evidence is saved.

## Current status

- Project decision: accepted
- Development environment: hosted Oracle APEX workspace (browser-based)
- Current patch: `P00 — Baseline and Environment`
- Database DDL executed: no
- APEX application created: no
- Next patch after P00 acceptance: `P01 — ERD and Schema Contract`

Start with [docs/patches/P00-baseline-and-environment.md](docs/patches/P00-baseline-and-environment.md).

Read the complete learning sequence in
[docs/OpsFlow360_Hosted_APEX_Course_Manual.md](docs/OpsFlow360_Hosted_APEX_Course_Manual.md).

## Hosted development workflow

The Oracle Database and APEX runtime are hosted by Oracle. Development uses:

- **SQL Workshop → SQL Scripts** for ordered database patches.
- **SQL Workshop → SQL Commands** for short verification queries.
- **SQL Workshop → Object Browser** for inspecting objects and generated DDL.
- **App Builder** for application pages and Shared Components.
- Browser downloads for SQL script results and APEX exports.

No local Oracle Database is required. A local project folder is still kept for
downloaded source, evidence, and Git history; it is not an application runtime.

## Product modules

1. Service desk and ticket lifecycle
2. SLA policy, deadline, and escalation management
3. Asset register, assignment, transfer, repair, and retirement
4. Purchase requests, approvals, purchase orders, receiving, and inventory
5. Knowledge base and secure attachments
6. Role-aware dashboards, notifications, audit, REST, and PWA support

## Planned roles

- Employee
- Service Agent
- Procurement Officer
- Manager
- Operations Admin
- Auditor

## Architecture rule

APEX pages are the presentation layer. Business rules live in versioned
`OF_*_API` PL/SQL packages and are also enforced by database constraints where
appropriate. Hiding a button is never treated as authorization.

## Repository map

```text
opsflow360/
├── apex/
│   ├── application/          # Full APEX exports
│   └── component-patches/    # Small component exports when useful
├── database/
│   ├── ddl/                  # Final object source
│   ├── migrations/           # Ordered, one-time patch scripts
│   ├── packages/             # Package specifications and bodies
│   ├── seed/                 # Deterministic demo/reference data
│   ├── tests/                # SQL and utPLSQL tests
│   └── views/                # Reporting views
├── docs/
│   ├── decisions/            # Architecture Decision Records
│   ├── patches/              # Exact patch instructions
│   └── test-evidence/        # Results, screenshots, and acceptance records
├── scripts/                  # Export, install, and validation helpers
├── CHANGELOG.md
└── README.md
```

## Patch discipline

For every patch:

1. Create `patch/PNN-short-name`.
2. Export or back up affected application/database objects.
3. Run only that patch.
4. Test valid, invalid, unauthorized, and regression paths.
5. Save evidence without credentials or personal data.
6. Export changed APEX components and database source.
7. Commit only after every acceptance criterion passes.

## Naming rules

- Database objects: `OF_` prefix and plural table names.
- Primary keys: `ID`.
- Foreign keys: `<singular_parent>_ID`.
- Business timestamps: `TIMESTAMP WITH LOCAL TIME ZONE`.
- Boolean-compatible columns: `CHAR(1)` constrained to `Y` or `N`.
- Public PL/SQL packages: `<module>_API`.
- Migration files: `PNN_description.sql`.
- APEX page items: `P<page>_<purpose>`.

## Release target

The final portfolio release must install in a clean environment from versioned
database scripts plus an APEX export. It must include an ERD, test evidence,
security review, performance comparison, screenshots, and a short demo script.
