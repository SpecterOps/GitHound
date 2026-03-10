---
kind: GH_CanReadSecretScanningAlert
is_traversable: true
---

# GH_CanReadSecretScanningAlert

## Edge Schema

- Source: [GH_OrgRole](../Nodes/GH_OrgRole.md), [GH_RepoRole](../Nodes/GH_RepoRole.md)
- Destination: [GH_SecretScanningAlert](../Nodes/GH_SecretScanningAlert.md)

## General Information

The traversable `GH_CanReadSecretScanningAlert` edge is a computed edge indicating that a role can read a specific secret scanning alert, including the leaked secret value. Created by `Compute-GitHoundSecretScanningAccess` with no additional API calls, the computation cross-references `GH_ViewSecretScanningAlerts` permission edges with `GH_Contains` structural edges (org-level and repo-level) to determine which alerts each role can access. This edge is traversable because reading an alert reveals the leaked secret — if the secret is a valid GitHub Personal Access Token, the `GH_ValidToken` edge enables identity compromise of the token's owner.

Each edge includes a `reason` property (`org_role_permission` or `repo_role_permission`) and a `query_composition` Cypher query showing the underlying graph evidence.

## Scenarios

### `org_role_permission` — Org role views alerts via organization

An org role with `GH_ViewSecretScanningAlerts` to the organization can read all secret scanning alerts across the entire org. The computation follows `GH_Contains` edges from the organization to each alert.

```mermaid
graph LR
    role("GH_OrgRole security_manager") -->|GH_ViewSecretScanningAlerts| org("GH_Organization")
    org -->|GH_Contains| alert("GH_SecretScanningAlert #42")
    role ==>|GH_CanReadSecretScanningAlert| alert
    alert -.->|GH_ValidToken| user("GH_User jdoe")
```

### `repo_role_permission` — Repo role views alerts via repository

A repo role with `GH_ViewSecretScanningAlerts` to the repository can read secret scanning alerts in that specific repo. The computation follows `GH_Contains` edges from the repository to each alert.

```mermaid
graph LR
    role("GH_RepoRole admin") -->|GH_ViewSecretScanningAlerts| repo("GH_Repository")
    repo -->|GH_Contains| alert("GH_SecretScanningAlert #17")
    role ==>|GH_CanReadSecretScanningAlert| alert
    alert -.->|GH_ValidToken| user("GH_User jdoe")
```
