# Agent Instructions

This project uses [tk](https://github.com/h2oai/tk) (installed via `go install github.com/lo5/tk@latest`) for ticket-based state and context across sessions.

See [AGENT_INSTRUCTIONS.md](./AGENT_INSTRUCTIONS.md) for the full command reference.

## Workflow

- Multi-session or dependent work is tracked as markdown tickets in `.tickets/`
- Implementation plans belong in `.plans/`
- Run `tk ready` to find unblocked work, `tk start <id>` to claim it, and `tk close <id>` when done
- File new tickets with `tk new` for follow-up or discovered work before ending a session

## Plans

- Store Cursor implementation plans in `.plans/` (git-tracked source of truth)
- When a plan is created or you start implementing one, copy it from `~/.cursor/plans/` into `.plans/` (use the `export-cursor-plans` skill / `sync-plan.sh`)
- Link `tk` tickets to the plan path in the ticket description
- Do not rely on `~/.cursor/plans/` alone — that store is local to the machine
