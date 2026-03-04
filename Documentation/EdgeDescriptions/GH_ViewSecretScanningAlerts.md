---
kind: GH_ViewSecretScanningAlerts
is_traversable: false
---

# GH_ViewSecretScanningAlerts

## Edge Schema

- Source: [GH_OrgRole](../Nodes/GH_OrgRole.md), [GH_RepoRole](../Nodes/GH_RepoRole.md)
- Destination: [GH_Organization](../Nodes/GH_Organization.md), [GH_Repository](../Nodes/GH_Repository.md)

## General Information

The non-traversable `GH_ViewSecretScanningAlerts` edge represents that a role can view secret scanning alerts at the organization or repository level. This edge is dynamically generated from custom role permissions discovered by the collector. Secret scanning alerts may reveal details about leaked credentials, including partial or full secret values and the locations where they were detected. This makes the permission significant for security because an attacker with access to view these alerts could harvest exposed credentials for use in lateral movement or privilege escalation.

```mermaid
graph LR
    node1("GH_OrgRole SpecterOps\\Owners")
    node2("GH_Organization SpecterOps")
    node3("GH_RepoRole GitHound\\write")
    node4("GH_Repository GitHound")
    node1 -- GH_ViewSecretScanningAlerts --> node2
    node3 -- GH_ViewSecretScanningAlerts --> node4
```
