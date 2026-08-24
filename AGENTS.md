# Agent Instructions

This project uses [tk](https://github.com/h2oai/tk) (installed via `go install github.com/lo5/tk@latest`) for ticket-based state and context across sessions.

See [AGENT_INSTRUCTIONS.md](./AGENT_INSTRUCTIONS.md) for the full command reference.

## Workflow

- Multi-session or dependent work is tracked as markdown tickets in `.tickets/`
- Implementation plans belong in `.plans/`
- Run `tk ready` to find unblocked work, `tk start <id>` to claim it, and `tk close <id>` when done
- File new tickets with `tk new` for follow-up or discovered work before ending a session
