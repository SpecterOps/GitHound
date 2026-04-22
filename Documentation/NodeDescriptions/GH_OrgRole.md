# <img src="../Icons/gh_orgrole.png" width="50"/> GH_OrgRole

Represents an organization-level role such as Owner, Member, or a custom organization role. Org roles define what permissions a user or team has at the organization level. The Owner and Member roles are default (built-in), while custom roles inherit from a base role and can have additional permissions.

Created by: `Git-HoundOrganization`

## Properties

| Property Name    | Data Type | Description                                                                              |
| ---------------- | --------- | ---------------------------------------------------------------------------------------- |
| objectid         | string    | A deterministic synthetic ID in the form `{orgNodeId}_{roleName}` for custom roles, `{orgNodeId}_owners`, `{orgNodeId}_members`, or `{orgNodeId}_all_repo_{baseRole}` for default and inherited org role nodes. |
| name             | string    | The fully qualified role name (e.g., `OrgName\Owners`).                                  |
| id               | string    | Same as objectid.                                                                        |
| short_name       | string    | The short display name of the role (e.g., `Owners`, `Members`, or the custom role name). |
| type             | string    | `default` for built-in roles (Owner, Member) or `custom` for custom organization roles.  |
| environment_name | string    | The name of the environment (GitHub organization).                                       |
| environmentid    | string    | The node_id of the environment (GitHub organization).                                    |

## Diagram

```mermaid
flowchart TD
    GH_OrgRole[fa:fa-user-tie GH_OrgRole]
    GH_User[fa:fa-user GH_User]
    GH_Team[fa:fa-user-group GH_Team]
    GH_Organization[fa:fa-building GH_Organization]
    GH_RepoRole[fa:fa-user-tie GH_RepoRole]
    GH_SecretScanningAlert[fa:fa-key GH_SecretScanningAlert]


    GH_User -->|GH_HasRole| GH_OrgRole
    GH_Team -->|GH_HasRole| GH_OrgRole
    GH_OrgRole -->|GH_HasBaseRole| GH_OrgRole
    GH_OrgRole -.->|GH_ManageOrganizationWebhooks| GH_Organization
    GH_OrgRole -.->|GH_OrgBypassCodeScanningDismissalRequests| GH_Organization
    GH_OrgRole -.->|GH_OrgBypassSecretScanningClosureRequests| GH_Organization
    GH_OrgRole -.->|GH_CreateRepository| GH_Organization
    GH_OrgRole -.->|GH_InviteMember| GH_Organization
    GH_OrgRole -.->|GH_AddCollaborator| GH_Organization
    GH_OrgRole -.->|GH_CreateTeam| GH_Organization
    GH_OrgRole -.->|GH_TransferRepository| GH_Organization
    GH_OrgRole -->|GH_HasBaseRole| GH_RepoRole
    GH_OrgRole -->|GH_CanReadSecretScanningAlert| GH_SecretScanningAlert
```
