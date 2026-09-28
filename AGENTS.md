# AGENTS.md

Signed APT repository for rsvalerio packages, served from GitHub Pages. See
[README.md](README.md) for how the pool, publishing, retention and signing work.

## Backlog

Backlog tasks live in `.backlog/tasks/` and are configured by the `[backlog]`
section in `.ops.toml`. Manage them with `ops backlog` (native,
Backlog.md-compatible), not the external `backlog` CLI, which does not read
`.ops.toml` and reports "No Backlog.md project found" here. Do not hand-edit
task files: field types and marker layout are load-bearing for the triage and
wave skills.

```bash
ops backlog task list --plain
ops backlog task view TASK-0001 --plain
ops backlog task edit TASK-0001 -s "In Progress"
ops backlog task edit TASK-0001 --check-ac 1 --append-notes "..." -s Done
ops backlog search <keyword>
```

Task ids take the full `TASK-NNNN` form (`ops backlog task view 1` does not
resolve).
