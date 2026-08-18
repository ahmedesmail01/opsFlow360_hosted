# P00 — Hosted Workspace Baseline and Environment

**Estimated learning time:** 90–120 minutes  
**Risk:** Low; the supplied SQL is read-only  
**Database mutation:** None  
**APEX mutation:** None  
**Execution environment:** Oracle-hosted APEX workspace in your browser

## 1. Goal

Establish a verified Oracle/APEX workspace, understand the browser development
tools, fix the product boundary, and create an evidence format before any table
or APEX page is created.

P00 deliberately creates nothing. If a later patch fails, this baseline tells
us whether the problem came from the environment, a pre-existing object, or
our own change.

## 2. What you will learn

### Workspace

An APEX workspace is a development boundary. It contains developers,
applications, workspace files, and mappings to one or more Oracle schemas. It
is not the same thing as an APEX application.

### Parsing schema

The parsing schema is the Oracle schema whose objects and privileges an APEX
application uses when it executes SQL and PL/SQL. OpsFlow tables, views, and
packages will live there. If a workspace maps multiple schemas, we must select
the intended schema consistently.

### SQL Scripts

SQL Scripts stores and runs a sequence of SQL statements and PL/SQL blocks. It
is the correct browser tool for our ordered patch files because the script and
its results remain visible in SQL Workshop.

### SQL Commands

SQL Commands runs short, ad-hoc SQL or PL/SQL. We will use it for verification
and focused tests, not as the only copy of a database migration.

### Object Browser

Object Browser displays tables, columns, constraints, indexes, packages,
dependencies, errors, and generated DDL. It is excellent for inspection and
learning. We avoid unrecorded manual changes because they cannot be reproduced
in another workspace.

### App Builder

App Builder creates and edits APEX applications. It contains pages, regions,
items, processes, validations, Dynamic Actions, Shared Components, security,
workflows, and application export tools. We will not create the app in P00.

### Migration and evidence

A migration is an ordered, versioned database change. Evidence is the saved
output that proves the change and its tests behaved as expected. “It worked on
my screen” is not evidence unless the relevant result is recorded.

## 3. Prerequisites

You need:

1. An Oracle APEX developer account for your hosted workspace.
2. A browser that can download `.sql` and `.md` files.
3. Access to **App Builder** and **SQL Workshop**.
4. The extracted `opsflow360` course folder.
5. A source-control method: local Git or the GitHub web interface. This stores
   downloaded source only; it does not run Oracle locally.

You do **not** need a local Oracle Database, SQLcl, SQL Developer, Docker, a
wallet, ORDS, Java, or a database password for P00.

## 4. Step 1 — Sign in and identify the safe environment details

1. Open the Oracle APEX sign-in page supplied for your workspace.
2. Enter the workspace name, developer username, and password.
3. Sign in.
4. On the Workspace home page, locate **App Builder** and **SQL Workshop**.
5. Record the workspace name in your evidence file.
6. Record only the URL host, for example `apex.oracle.com`. Do not copy the full
   authenticated URL because it can contain session identifiers or private
   paths.
7. Classify the hosted platform:
   - `apex.oracle.com` when the host is the public Oracle APEX evaluation and
     learning service.
   - `OCI APEX Service` when the workspace belongs to an Oracle Cloud APEX
     Service instance.
   - `Other hosted APEX` when another organization administers the instance.

If **App Builder** or **SQL Workshop** is missing, stop and record exactly what
is visible. The workspace administrator may have disabled that capability or
your account may not be a developer account.

## 5. Step 2 — Tour SQL Workshop without changing anything

1. Select **SQL Workshop**.
2. Confirm these tools are visible:
   - Object Browser
   - SQL Commands
   - SQL Scripts
   - Utilities
   - RESTful Services, when enabled by the instance
3. Open **Object Browser**.
4. Observe the schema selector. Record the selected schema name.
5. Browse one existing object only if objects already exist. Do not edit it.
6. Return to SQL Workshop.
7. Open **SQL Commands** and observe the schema displayed above the editor. Do
   not run a statement yet.
8. Return and open **SQL Scripts**. This is where P00 will run.

Why this matters: the same workspace can sometimes map more than one schema.
Running a patch in the wrong selected schema creates objects in the wrong
place, even though the APEX sign-in was correct.

## 6. Step 3 — Read and accept the product boundary

Read these files completely in this order:

1. `README.md`
2. `docs/project-charter.md`
3. `docs/decisions/ADR-0001-product-scope.md`
4. `docs/OpsFlow360_Hosted_APEX_Course_Manual.md`

You should be able to explain:

- Why OpsFlow 360 is one connected product rather than four unrelated demos.
- The six roles and what each role can do.
- The ticket, purchase, asset, and SLA lifecycles.
- Why package APIs and database constraints protect rules that the UI alone
  cannot protect.
- What is explicitly out of scope.

Do not add a new module during P00. Scope changes require a later recorded
architecture decision.

## 7. Step 4 — Prepare the evidence file

1. Open `docs/test-evidence/P00-evidence-template.md`.
2. Make a copy named `P00-evidence.md` in the same folder.
3. Fill only the details already known:
   - workspace name
   - URL host only
   - hosted platform classification
   - App Builder visible: Yes/No
   - SQL Workshop visible: Yes/No
4. Leave database/APEX versions blank until the script runs.
5. Never place passwords, cookies, session IDs, REST credentials, or full
   authenticated URLs in the file or screenshots.

## 8. Step 5 — Inspect the P00 SQL file before running it

Open `database/migrations/P00_environment_check.sql` in a text editor.

Verify these facts:

1. The header says `P00 - Baseline and Environment`.
2. It targets `Oracle APEX SQL Workshop -> SQL Scripts`.
3. It contains only `SELECT` statements.
4. It contains no `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, `INSERT`, `UPDATE`,
   `DELETE`, `MERGE`, `COMMIT`, or `EXECUTE IMMEDIATE` statement.
5. It contains seven checks named `01_...` through `07_...`.

This inspection is a professional habit. Never run a migration solely because
its filename looks safe.

## 9. Step 6 — Upload the read-only script

1. From the Workspace home page, select **SQL Workshop**.
2. Select **SQL Scripts**.
3. Click **Upload**.
4. Choose `database/migrations/P00_environment_check.sql`.
5. Set the script name to `P00_environment_check`.
6. Confirm the file character set is Unicode/UTF-8 when that option is shown.
7. Click **Upload**.
8. Locate the uploaded script in the SQL Scripts list.
9. Open the script editor using the script name or edit icon.
10. Compare its first and last statements with your local copy. This confirms
    the upload was not truncated.
11. Return to the SQL Scripts list.

Uploading does not execute the SQL. At this point the database is unchanged.

## 10. Step 7 — Run the script

1. Click **Run** for `P00_environment_check`.
2. Review the Run Script page.
3. Confirm the correct schema is selected.
4. Confirm the script contains seven read-only statements.
5. Click **Run Now**.
6. Wait until the script status is **Complete**.
7. Open **View Results** or the result icon.
8. Select the detailed view when a Detail/Summary choice is offered.
9. Confirm every statement has a success status.

If the status is **Failed**, do not guess and do not rerun repeatedly. Copy the
first exact ORA/APEX error, the statement number, and the schema name into the
evidence file.

## 11. Step 8 — Understand all seven results

### `01_IDENTITY`

Record:

- `PARSING_SCHEMA` — the current database user/schema for SQL Workshop.
- `DATABASE_NAME` — the database name visible to the session.
- `CURRENT_SCHEMA` — normally the same as `PARSING_SCHEMA` here.
- `SESSION_USER` — the authenticated database session user.
- `SESSION_LANGUAGE` — combined language/territory/character-set context.
- `SESSION_TIMEZONE` — important for future SLA deadlines.
- `CHECKED_AT` — the timestamp of this baseline.

If `PARSING_SCHEMA` and `CURRENT_SCHEMA` differ, stop and send both values. We
must understand the mapping before creating objects.

### `02_DATABASE_VERSION`

Record `DATABASE_MAJOR_VERSION` and `DATABASE_RELEASE` exactly. Database
features and syntax depend on the database version, not the APEX version.

### `03_APEX_VERSION`

Record `APEX_VERSION` exactly. The public documentation may show a different
release from the one installed in your hosted workspace; later clicks and
available features will follow the value you actually have.

### `04_OBJECT_BASELINE`

This groups your existing schema objects by type. Record the result even if the
schema is empty. It gives us a before-count for tables, indexes, packages,
views, sequences, and other objects.

### `05_INVALID_OBJECTS`

Expected result: zero rows. If rows exist, list every object name/type/status.
Do not drop, recompile, or repair an unknown object in P00. It may belong to an
existing application.

### `06_EXISTING_OF_OBJECTS`

Expected result: zero rows. OpsFlow objects use the `OF_` prefix. If rows exist,
stop before P01/P02; we must determine whether this is an earlier OpsFlow
installation or an unrelated naming collision.

### `07_NLS_SETTINGS`

Record all values. NLS defaults affect how strings are converted to dates,
timestamps, and numbers, and how text comparisons sort. Later patches will use
explicit conversions where a stored rule must not depend on session defaults.

## 12. Step 9 — Fallback when SQL Scripts rejects one statement

Use this only after recording the SQL Scripts error.

1. Open `P00_environment_check.sql` locally.
2. Open **SQL Workshop → SQL Commands**.
3. Paste the first `SELECT` statement only, ending with its semicolon removed if
   the editor requests a single statement without it.
4. Click **Run**.
5. Save the result.
6. Repeat for all seven statements, one at a time.
7. Record which statement failed and its exact error.

Do not omit a failed check. A permission limitation is useful environment
evidence and will affect later patch design.

## 13. Step 10 — Save the SQL evidence

1. Save a screenshot of the SQL Scripts status and results page.
2. Make sure no username, email, session token, or full authenticated URL is
   exposed.
3. Copy each statement result into `P00-evidence.md`, or save it as a separate
   text/PDF result and list its filename.
4. For zero-row checks, write `0 rows returned`; do not leave the field blank.
5. Record every exception under **Exceptions or blockers**.

## 14. Step 11 — Establish source control without a local database

Choose one method.

### Method A — Local Git, recommended

This does not install Oracle locally. It only versions your downloaded files.

From the extracted `opsflow360` folder:

```bash
git init
git switch -c patch/P00-hosted-baseline
git status --short
```

If the folder is already a Git repository, skip `git init` and create only the
branch.

Check that no `.env`, wallet, connection file, password, credential, or session
URL is present. Then, after all P00 checks pass:

```bash
git add .
git status --short
git commit -m "chore(P00): establish hosted APEX baseline"
git rev-parse --short HEAD
git status --short
```

The final `git status --short` should have no output.

### Method B — GitHub website

1. Create a private or public repository named `opsflow360`.
2. Do not add a second README when uploading this existing folder.
3. Upload the project files using **Add file → Upload files**.
4. Review the file list for secrets before committing.
5. Use commit message `chore(P00): establish hosted APEX baseline`.
6. Record the resulting commit hash or commit URL in the evidence file.

For a public portfolio, never upload credentials or screenshots containing
private workspace details.

## 15. Step 12 — Capture the project file tree

If you use local Git, run one of these commands from `opsflow360`.

Linux/macOS/Git Bash:

```bash
find . -maxdepth 3 -type f | sort
```

Windows PowerShell:

```powershell
Get-ChildItem -Recurse -File | ForEach-Object FullName
```

If you use GitHub web only, capture the repository file list after the commit.
Paste the tree/list into `P00-evidence.md`.

## 16. Step 13 — P00 acceptance checklist

P00 passes only when all applicable boxes can be checked:

- [ ] Signed in to the intended hosted APEX workspace.
- [ ] App Builder opens.
- [ ] SQL Workshop opens.
- [ ] Object Browser, SQL Commands, and SQL Scripts are visible.
- [ ] The intended schema is recorded.
- [ ] All four project/scope documents were read.
- [ ] The uploaded P00 script matches the local source.
- [ ] All seven checks ran or every permission error is recorded.
- [ ] Database and APEX versions are exact.
- [ ] NLS values and session time zone are recorded.
- [ ] Invalid objects are zero or fully documented.
- [ ] Existing `OF_` objects are zero.
- [ ] No secret or session identifier is in evidence/source control.
- [ ] Project tree is recorded.
- [ ] Commit hash/URL is recorded, or source-control setup is the only declared
      blocker.

## 17. Rollback

The database and APEX application need no rollback because P00 creates or
changes no Oracle object.

The uploaded SQL Script is only a saved script in SQL Workshop. You may keep it
for evidence. If you delete it, the database still remains unchanged.

Correct evidence/source files with a new commit. Do not rewrite published Git
history simply to hide a harmless documentation correction.

## 18. Stop gate — send these results before P01

Do not create tables and do not create the APEX application yet. Send:

1. Hosted platform: `apex.oracle.com`, `OCI APEX Service`, or other.
2. APEX version.
3. Oracle Database major/release.
4. Workspace name; you may partially mask it if it is sensitive.
5. Parsing schema name; you may partially mask it if it is sensitive.
6. Session time zone.
7. Whether invalid objects appeared, with names/types if any.
8. Whether existing `OF_` objects appeared, with names/types if any.
9. Source-control method and commit hash/URL, or the exact blocker.
10. The exact error and statement number for any failed check.

After review, P01 will teach the domain glossary, normalization, cardinality,
state-transition matrices, and complete ERD/schema contract before any DDL is
allowed.

## 19. Common mistakes and why they are mistakes

- **Creating tables from Quick SQL immediately:** fast generation hides design
  decisions we need to learn and review first.
- **Using Object Browser for undocumented changes:** another workspace cannot
  reproduce a click that was never exported as SQL.
- **Building forms directly on tables first:** page DML can spread business
  rules across many pages instead of one testable package API.
- **Treating a hidden navigation entry as security:** a user can still attempt a
  direct URL or modified request.
- **Rerunning partially successful DDL blindly:** Oracle DDL commits, so the
  second attempt may fail differently or leave a mixed version.
- **Saving full authenticated URLs:** they can expose session details and make
  public evidence unsafe.
- **Skipping zero-row evidence:** zero rows is the expected proof for collision
  and invalid-object checks, not a missing result.

## 20. Official reading for P00

- SQL Workshop:
  https://docs.oracle.com/en/database/oracle/apex/26.1/aeutl/getting-started.html
- SQL Scripts:
  https://docs.oracle.com/en/database/oracle/apex/26.1/aeutl/sql-scripts.html
- Viewing SQL Script results:
  https://docs.oracle.com/en/database/oracle/apex/26.1/aeutl/viewing-sql-script-results.html
- Object Browser:
  https://docs.oracle.com/en/database/oracle/apex/26.1/aeutl/understanding-object-browser.html

The documentation links use APEX 26.1 because it is the current course
reference. Your recorded workspace version remains authoritative for later UI
instructions.
