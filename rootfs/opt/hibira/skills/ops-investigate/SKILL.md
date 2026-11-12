---
name: ops-investigate
description: Investigate an incident or a question about Cloudflare, AWS, GCP, Grafana, Prometheus, Elasticsearch/Kibana or a database, then propose and make a reviewed adjustment.
version: 0.1.0
author: Hibira
license: MIT
metadata:
  hermes:
    tags: [ops, sre, incident, cloudflare, aws, gcp, grafana, prometheus, elasticsearch, kibana]
    category: devops
---

# Investigate, then adjust

Work in this order. Reads run straight away; changes wait for approval
(see the `hibira-approvals` skill).

## 1. Scope

Restate the question in one line: which service, which environment, since
when, what "bad" looks like. Ask only if the answer changes where you look.

## 2. Look

Use what this deployment has turned on. The MCP tools appear as `grafana`,
`prometheus`, `elasticsearch`, `kibana` and `database`; the CLIs `aws`,
`gcloud` and `wrangler` are on the terminal when their credentials are set.

| Where | Useful reads |
|---|---|
| Grafana / Loki / alerts | search dashboards, list firing alerts, query Loki for errors around the start time |
| Prometheus | error rate, latency p95/p99, saturation (CPU, memory, connections) before and after the start |
| Elasticsearch / Kibana | `list_indices`, then ES\|QL on the log index: error counts by service and message |
| AWS | `aws cloudwatch get-metric-statistics`, `aws logs filter-log-events`, `aws ecs describe-services`, `aws elbv2 describe-target-health`, `aws rds describe-db-instances` |
| GCP | `gcloud logging read 'severity>=ERROR' --freshness=1h`, `gcloud run services describe`, `gcloud compute instances list`, `gcloud sql instances describe` |
| Cloudflare | `wrangler tail`, `wrangler deployments list`, `curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" https://api.cloudflare.com/client/v4/zones` (GraphQL analytics for traffic and error rates) |
| Database | read-only SQL: slow queries, locks, connection counts, row counts |

Correlate by time: what changed just before it started (deploys, config,
traffic, a dependency)?

## 3. Report

Give the user: what is wrong, the evidence (numbers, log lines, links), the
likely cause, and how sure you are.

## 4. Adjust (waits for approval)

Propose the smallest change that helps, how to undo it, and what you will
check afterwards. Then run it as one clear command, for example
`aws ecs update-service --cluster prod --service api --desired-count 6`,
`gcloud run services update api --min-instances 2`,
`wrangler rollback`, or a Grafana alert silence.

## 5. Verify

Re-run the reads from step 2 and show the before/after.
