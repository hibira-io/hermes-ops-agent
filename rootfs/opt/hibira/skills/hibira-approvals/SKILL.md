---
name: hibira-approvals
description: How changes are approved in this deployment. Read before any command or tool call that changes infrastructure, data or settings.
version: 0.1.0
author: Hibira
license: MIT
metadata:
  hermes:
    tags: [approvals, safety, ops]
    category: devops
---

# Changes wait for approval

In this deployment, a second person approves changes in Hibira Approvals.
Reading is never blocked: logs, metrics, `describe`/`list`/`get` commands,
searches and queries run straight away. Commands and tool calls that change
something (scale, restart, stop, delete, deploy, purge, write, `terraform apply`,
SQL writes, API calls with POST/PUT/PATCH/DELETE) wait for that person.

## What happens

- The terminal command or MCP tool call is sent to the approvers' inbox with
  the exact command, why it waits, and the folder and host it runs on.
- **Approved**: it runs once, exactly as written.
- **Rejected**: you get the approver's name and comment. Stop. Do not run it
  again, and do not reach the same result another way (another CLI, a script,
  a raw API call, editing config files). Tell the user what was rejected and why.
- **Still waiting**: you are told nobody has answered yet. Tell the user it is
  waiting. When they say it was approved, run exactly the same command again.
- **Not connected**: the message tells the user to connect the container to an
  Approvals workspace once (`mcp-approval-gate login`). Pass that on.

## How to ask well

Approvers decide from the command alone, so make it easy to read:

1. Investigate first and show the user what you found.
2. Propose one specific change and say what it will do and how to undo it.
3. Run one change per command. Avoid chaining unrelated changes with `&&`.
4. Prefer the provider's CLI over raw API calls; it reads better in the inbox.
5. After it runs, verify the effect (metrics, status, logs) and report back.

Never edit `config.yaml`, `shell-hooks-allowlist.json` or `~/.config/hibira/`
to get around a decision.
