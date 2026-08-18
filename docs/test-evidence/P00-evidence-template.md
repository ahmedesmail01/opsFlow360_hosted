# P00 Acceptance Evidence

Copy this file to `P00-evidence.md`, fill it in, and keep secrets and personal
data out of the evidence.

## 1. Environment

| Check | Recorded value |
|---|---|
| APEX version | |
| Oracle Database major/release | |
| Workspace name | |
| Parsing schema | |
| Database name | |
| Session time zone | |
| Workspace URL host only | Example: `apex.oracle.com`; never paste tokens or full authenticated URLs |
| Hosted platform | apex.oracle.com / OCI APEX Service / other hosted APEX |
| App Builder visible | Yes / No |
| SQL Workshop visible | Yes / No |
| SQL execution tool | APEX SQL Workshop → SQL Scripts |
| Source-control method | Local Git / GitHub web / pending |
| Git version, if local Git is used | |

## 2. Baseline results

| Test | Expected | Actual | Pass? |
|---|---|---|---|
| Environment script completes | No unexpected error | | |
| App Builder access | Visible and opens | | |
| SQL Workshop access | SQL Scripts, SQL Commands, and Object Browser open | | |
| Invalid objects | Zero rows, or every pre-existing invalid object documented | | |
| Existing `OF_` objects | Zero rows before implementation | | |
| Repository structure | Matches README map | | |
| Secrets review | No credentials, tokens, wallets, or `.env` files tracked | | |

## 3. Evidence files

- [ ] Full output from `P00_environment_check.sql`
- [ ] Screenshot of the APEX Workspace home page showing App Builder and SQL
      Workshop, with account information and URL tokens hidden
- [ ] Detailed result for each of the seven SQL statements
- [ ] Repository tree output
- [ ] `git status` output after commit
- [ ] Commit hash

## 4. Commands and results

```text
Paste: Git version, or write "GitHub web method" / "source control pending"
```

```text
Paste: repository tree output
```

```text
Paste: git status --short, if local Git is used
```

```text
Paste: git rev-parse --short HEAD, or the GitHub commit URL/hash
```

## 5. Exceptions or blockers

Record any mismatch, error, permission limitation, or unsupported feature. Do
not mark P00 complete until it is either fixed or explicitly accepted with a
reason.

## 6. Result

- [ ] P00 accepted
- [ ] P00 blocked

Reviewed on:  
Reviewer notes:
