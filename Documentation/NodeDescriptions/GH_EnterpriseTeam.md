# <img src="../Icons/gh_enterpriseteam.png" width="50"/> GH_EnterpriseTeam

Represents a GitHub enterprise-level team. Enterprise teams are assigned into organizations from the enterprise layer and can map to organization-scoped `ent:` teams that then carry repository permissions.

Created by: `Git-HoundEnterpriseTeam`

## Properties

| Property Name          | Data Type | Description |
| ---------------------- | --------- | ----------- |
| objectid               | string    | A synthetic enterprise-scoped identifier for the enterprise team. |
| name                   | string    | The display name of the enterprise team. |
| node_id                | string    | The enterprise team graph identifier. Redundant with objectid. |
| github_team_id         | string    | The raw enterprise team id returned by the GitHub enterprise team API. |
| environment_name       | string    | The enterprise slug. |
| environmentid          | string    | The enterprise node id. |
| enterpriseid           | string    | The enterprise node id, repeated explicitly for enterprise-scoped matching. |
| slug                   | string    | The enterprise team slug. |
| projected_slug         | string    | The projected organization team slug, typically using the `ent:` prefix. |
| description            | string    | The team description. |
| created_at             | string    | When the enterprise team was created. |
| updated_at             | string    | When the enterprise team was last updated. |

Enterprise team membership is represented through a synthetic `GH_TeamRole` node (`members`) linked with `GH_MemberOf`. Organization assignment is represented with `GH_AssignedTo`, and the enterprise team is linked to org-visible `ent:` teams with a property-matched `GH_MemberOf` edge once those organization teams exist in the graph.

## Diagram

```mermaid
flowchart TD
    GH_Enterprise[fa:fa-globe GH_Enterprise]
    GH_EnterpriseTeam[fa:fa-users-between-lines GH_EnterpriseTeam]
    GH_Organization[fa:fa-building GH_Organization]
    GH_Team[fa:fa-user-group GH_Team]
    GH_TeamRole[fa:fa-user-tie GH_TeamRole]
    GH_User[fa:fa-user GH_User]

    GH_Enterprise -.->|GH_Contains| GH_EnterpriseTeam
    GH_EnterpriseTeam -.->|GH_AssignedTo| GH_Organization
    GH_TeamRole -->|GH_MemberOf| GH_EnterpriseTeam
    GH_EnterpriseTeam -->|GH_MemberOf| GH_Team
    GH_User -->|GH_HasRole| GH_TeamRole
```
