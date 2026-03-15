---
kind: GH_OrgReviewAndManageSecretScanningClosureRequests
is_traversable: false
---

# GH_OrgReviewAndManageSecretScanningClosureRequests

## Edge Schema

- Source: [GH_OrgRole](../NodeDescriptions/GH_OrgRole.md)
- Destination: [GH_Organization](../NodeDescriptions/GH_Organization.md)

## General Information

The non-traversable [GH_OrgReviewAndManageSecretScanningClosureRequests](GH_OrgReviewAndManageSecretScanningClosureRequests.md) edge represents that a role can review and manage secret scanning alert closure requests at the organization level. This edge is dynamically generated from custom organization role permissions discovered by the collector. Alert closure requests are part of the workflow for closing secret scanning alerts, and this permission controls who can approve or deny those requests. An attacker with this permission could approve closure requests to suppress alerts about actively leaked credentials, undermining the organization's secret scanning remediation process.

```mermaid
graph LR
    node1("GH_OrgRole SpecterOps\\Owners")
    node2("GH_Organization SpecterOps")
    node1 -- GH_OrgReviewAndManageSecretScanningClosureRequests --> node2
```
