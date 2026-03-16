# GH_WriteOrganizationActionsSecrets

## Edge Schema

- Source: [GH_OrgRole](../NodeDescriptions/GH_OrgRole.md)
- Destination: [GH_Organization](../NodeDescriptions/GH_Organization.md)

## General Information

The non-traversable [GH_WriteOrganizationActionsSecrets](GH_WriteOrganizationActionsSecrets.md) edge represents that a role can write organization-level GitHub Actions secrets. This edge is dynamically generated from custom organization role permissions discovered by the collector. Organization-level secrets are available to workflows across multiple repositories and often contain credentials for external systems such as cloud providers, package registries, and deployment targets. An attacker with this permission could overwrite existing secrets to inject malicious credentials or create new secrets to facilitate lateral movement.

```mermaid
graph LR
    node1("GH_OrgRole SpecterOps\\Owners")
    node2("GH_Organization SpecterOps")
    node1 -- GH_WriteOrganizationActionsSecrets --> node2
```
