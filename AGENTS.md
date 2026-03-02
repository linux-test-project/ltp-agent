# Agent Configuration Repository

This repository is the **source of truth for agent behavior**. It contains
project entry points, mandatory coding rules, and loadable skills that drive
an AI coding assistant. There is no executable code here — all files are
Markdown, read at runtime by the agent.

## Rules

- **LTP**: Any time the user asks about or requests something related to LTP,
  you **must** read `agents/ltp/ltp.md` before responding.
