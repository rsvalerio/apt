---
id: TASK-0002
title: 'README: update retention table once my-cloud and oxydraw publish via apt-pool-push'
status: Triage
assignee: []
created_date: '2026-09-26 22:44'
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
The README's retention table says my-cloud and oxydraw have no retention because they push into pool/ with plain git. Two tasks move them to forge's apt-pool-push with keep-versions: 3: my-cloud TASK-3 and oxydraw TASK-0251. When each one lands, change its row to 'newest 3 per arch' and fix the pool/ publisher list if the workflow names change. Once all three publishers prune, merge the table into a single sentence.

No manual pool cleanup is needed. Each package's old versions are pruned the next time that package publishes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The retention table lists the actual keep-versions setting for every publisher
- [ ] #2 No row says 'none' for a publisher that now prunes
<!-- AC:END -->
