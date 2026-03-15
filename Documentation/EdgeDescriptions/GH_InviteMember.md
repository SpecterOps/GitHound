---
kind: GH_InviteMember
is_traversable: false
---

# GH_InviteMember

## Edge Schema

- Source: [GH_OrgRole](../NodeDescriptions/GH_OrgRole.md)
- Destination: [GH_Organization](../NodeDescriptions/GH_Organization.md)

## General Information

The non-traversable [GH_InviteMember](GH_InviteMember.md) edge represents that a role has the ability to invite new members to the organization. This permission is typically restricted to Owners, as inviting members expands the organization's trust boundary by granting new users access to internal resources. An attacker with this permission could invite a controlled account to gain persistent access to the organization's repositories, teams, and secrets.

```mermaid
graph LR
    node1("GH_OrgRole SpecterOps\\Owners")
    node2("GH_Organization SpecterOps")
    node1 -- GH_InviteMember --> node2
```
