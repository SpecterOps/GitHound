# GH_EnterpriseTeam

Represents an enterprise-level team that can span multiple organizations. Enterprise teams differ from organization teams — their membership is typically managed via IdP group provisioning (SCIM) rather than direct assignment. When linked to an IdP group, the `group_id` property contains the SCIM group GUID.

Enterprise teams do not have team roles (no member/maintainer distinction). The `organization_selection_type` indicates whether the team applies to "all" orgs or "selected" orgs, but the API does not expose which specific orgs are selected.

Created by: `Git-HoundEnterpriseTeam`

## Properties

| Property Name                | Data Type | Description                                                                |
| ---------------------------- | --------- | -------------------------------------------------------------------------- |
| objectid                     | string    | Synthetic ID in the format `GH_EntTeam_{id}`.                             |
| name                         | string    | The team's display name.                                                   |
| id                           | integer   | The numeric REST API ID of the team.                                       |
| slug                         | string    | The team's URL-safe slug (prefixed with `ent:`).                           |
| description                  | string    | The team's description.                                                    |
| group_id                     | string    | The SCIM group GUID linked to this team (null if not IdP-managed).         |
| organization_selection_type  | string    | Whether the team applies to "all" or "selected" organizations.             |
| environment_name             | string    | The enterprise slug.                                                       |
| environmentid                | string    | The enterprise's GraphQL node ID.                                          |
| created_at                   | datetime  | When the team was created.                                                 |
| updated_at                   | datetime  | When the team was last updated.                                            |

## Diagram

```mermaid
flowchart TD
    GH_Enterprise[fa:fa-city GH_Enterprise]
    GH_EnterpriseTeam[fa:fa-users-between-lines GH_EnterpriseTeam]
    GH_User[fa:fa-user GH_User]
    SCIM_Group[fa:fa-users-gear SCIM_Group]

    GH_Enterprise -.->|GH_Contains| GH_EnterpriseTeam
    GH_EnterpriseTeam -.->|GH_HasMember| GH_User
    SCIM_Group -->|SCIM_Provisioned| GH_EnterpriseTeam
```
