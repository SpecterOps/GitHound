---
kind: GH_AddCollaborator
is_traversable: false
---

# GH_AddCollaborator

## Edge Schema

- Source: [GH_OrgRole](../Nodes/GH_OrgRole.md)
- Destination: [GH_Organization](../Nodes/GH_Organization.md)

## General Information

The non-traversable `GH_AddCollaborator` edge represents that a role has the ability to add outside collaborators to organization repositories. This permission is typically restricted to Owners, as it grants repository access to external users who are not members of the organization. Outside collaborators bypass organizational membership controls, making this permission significant for security because it can be used to grant access to untrusted external identities without the visibility that full membership provides.

```mermaid
graph LR
    node1("GH_OrgRole SpecterOps\\Owners")
    node2("GH_Organization SpecterOps")
    node1 -- GH_AddCollaborator --> node2
```
