# ADR 0003: A dedicated Developer Edition org instead of scratch orgs

- **Status:** accepted
- **Date:** 2026-10-23

## Context

The kickoff asks for the subject to deploy to a **scratch org**, and for `tools/difftest` to run
anonymous Apex in one. At kickoff, the available Dev Hub had all of its active scratch-org slots in
use by other work. More generally:

- scratch orgs expire after at most 30 days and use up daily and active allocations;
- difftest will run many anonymous-Apex batches over the life of the project, and its results are
  easier to compare over time against one stable org;
- a Dev Hub is often a production org, and pointing project automation at it is a bad idea.

## Decision

Use a **dedicated Developer Edition org**, with local alias `afv-dev`, for deploying subjects,
running their Apex tests, and difftest.

- The org is used **only** by this project. No other triggers, flows, validation rules or managed
  packages may be installed on the objects we model. Anything installed there changes what
  "reality" means for difftest.
- CI authenticates with an SFDX auth URL stored as the repository secret `SF_AUTH_URL`. The Apex
  job is skipped when the secret is absent (forks, or before the secret is set).
- Pull-request CI uses `sf project deploy validate` (check-only, runs tests, changes nothing). Only
  `main` actually deploys, so the org always reflects `main`.
- Scratch orgs stay supported. The project includes `config/project-scratch-def.json`, and
  `make apex-deploy ORG=<scratch alias>` works the same way.

## Consequences

- A Developer Edition org counts as a production org for deployment, so every deploy runs tests and
  needs 75% coverage. That is a useful gate.
- The org is long-lived, so it can drift through manual changes. Difftest records the org's API
  version with every run, and the platform model names the API version it was validated against.
- Developer Edition orgs can be deactivated after long inactivity. CI keeps this one in regular use.
