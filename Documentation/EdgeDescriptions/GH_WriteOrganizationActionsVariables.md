---
kind: GH_WriteOrganizationActionsVariables
is_traversable: false
---

# GH_WriteOrganizationActionsVariables

## Edge Schema

- Source: [GH_OrgRole](../NodeDescriptions/GH_OrgRole.md)
- Destination: [GH_Organization](../NodeDescriptions/GH_Organization.md)

## General Information

The non-traversable [GH_WriteOrganizationActionsVariables](GH_WriteOrganizationActionsVariables.md) edge represents that a role can write organization-level GitHub Actions variables. This edge is dynamically generated from custom organization role permissions discovered by the collector. Organization-level variables are available to workflows across multiple repositories and often contain configuration values such as environment URLs, feature flags, and service endpoints. An attacker with this permission could overwrite existing variables to redirect workflows to malicious endpoints or alter application behavior.

```mermaid
graph LR
    node1("GH_OrgRole SpecterOps\\Owners")
    node2("GH_Organization SpecterOps")
    node1 -- GH_WriteOrganizationActionsVariables --> node2
```
