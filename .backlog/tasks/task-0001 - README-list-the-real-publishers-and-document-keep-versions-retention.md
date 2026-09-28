---
id: TASK-0001
title: 'README: list the real publishers and document keep-versions retention'
status: Done
assignee: []
created_date: '2026-09-26 19:32'
updated_date: '2026-09-26 20:14'
labels:
  - docs
dependencies: []
modified_files:
  - README.md
priority: low
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two README fixes, done together since they sit side by side.

1. Publishers line: the README says packages are "pushed here by `rsvalerio/ops` on release", which is wrong today. List the actual publishers: my-cloud, oxydraw and ops (once ops adopts forge's publish-deb-dist).

2. Retention: forge's `apt-pool-push` prunes versions beyond the newest N per package+arch (`keep-versions`; publish-deb-dist defaults to 3). forge's docs/consuming.md ("Retention") documents it, but this README, which is what apt users read, does not say that old versions leave the pool, that `apt install <pkg>=<old>` stops working once they do, or when to run `scripts/squash-history.sh`. Users who pin an exact version lose it silently.

Moved from forge TASK-0011 (plus the apt half of forge TASK-0007).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README lists the actual publishers (my-cloud, oxydraw, ops)
- [x] #2 README states the retention window per package+arch and its effect on pinned installs
- [x] #3 README says when to run scripts/squash-history.sh
<!-- AC:END -->

## Implementation Notes
<!-- SECTION:NOTES:BEGIN -->
my-cloud (`build-deb.yaml`) and oxydraw (`publish-deb.yml`) commit straight into `pool/` with git and don't prune. Only forge `apt-pool-push` publishers apply `keep-versions`, which means ops once it adopts publish-deb-dist. The README says so in a per-publisher table. It also warns that `squash-history.sh run` prunes the pool to the single newest version, and tells readers to run `squash` alone to keep the retention window.
<!-- SECTION:NOTES:END -->
