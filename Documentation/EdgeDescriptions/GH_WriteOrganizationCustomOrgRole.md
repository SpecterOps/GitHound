---
kind: GH_WriteOrganizationCustomOrgRole
is_traversable: true
---

# GH_WriteOrganizationCustomOrgRole

## Edge Schema

- Source: [GH_OrgRole](../Nodes/GH_OrgRole.md)
- Destination: [GH_Organization](../Nodes/GH_Organization.md)

## General Information

The traversable `GH_WriteOrganizationCustomOrgRole` edge represents that a role can create or modify custom organization role definitions. This edge is dynamically generated from custom organization role permissions discovered by the collector. Modifying organization role definitions can escalate privileges because an attacker could add permissions to an existing custom role that is already assigned to their account, including setting the base_role to inherit all_repo_admin. Since this permission can only belong to custom organization roles, the user necessarily holds the role they can modify — guaranteeing a self-escalation path. This makes it a Tier Zero privilege escalation vector.

```mermaid
graph LR
    node1("GH_OrgRole SpecterOps\\Owners")
    node2("GH_Organization SpecterOps")
    node1 -- GH_WriteOrganizationCustomOrgRole --> node2
```
