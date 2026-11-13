# Changelog

## 0.1.0

- First release: Hermes Agent v0.23.1 for ops work with Hibira Approvals built in.
- Terminal commands that change things wait for approval (`mcp-approval-gate hook hermes`, fail-closed). Ops rules cover curl writes, docker/systemctl restarts and the agent's own config files.
- Modules switched on by their settings: Cloudflare (wrangler), AWS CLI v2, Google Cloud CLI, Grafana, Prometheus, Elasticsearch and Kibana MCP servers, and databases through DBHub. Every MCP server is wrapped by the approval gate.
- Skills: `hibira-approvals` and `ops-investigate` (look, report, adjust, verify).
- Bring your own model key: `HERMES_PROVIDER`, `HERMES_MODEL`, `HERMES_BASE_URL`.
