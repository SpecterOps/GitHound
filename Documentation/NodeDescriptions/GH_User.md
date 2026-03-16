# <img src="../Icons/gh_user.png" width="50"/> GH_User

Represents a GitHub user who is a member of the organization. Users are associated with organization roles (Owner or Member) and can be assigned to repository roles and team roles.

Created by: `Git-HoundUser`

## Properties

| Property Name    | Data Type | Description                                                            |
| ---------------- | --------- | ---------------------------------------------------------------------- |
| objectid         | string    | The GitHub `node_id` of the user, used as the unique graph identifier. |
| name             | string    | The user's display name, derived from the login property.              |
| login            | string    | The user's GitHub login handle.                                        |
| company          | string    | The company listed on the user's profile.                              |
| email            | string    | The user's public email address.                                       |
| full_name        | string    | The user's full name from their profile.                               |
| id               | integer   | The numeric GitHub ID of the user.                                     |
| node_id          | string    | The GitHub GraphQL node ID. Redundant with objectid.                   |
| environment_name | string    | The name of the environment (GitHub organization) the user belongs to. |
| environmentid    | string    | The node_id of the environment (GitHub organization).                  |

## Diagram

```mermaid
flowchart TD
    GH_User[fa:fa-user GH_User]
    GH_OrgRole[fa:fa-user-tie GH_OrgRole]
    GH_RepoRole[fa:fa-user-tie GH_RepoRole]
    GH_TeamRole[fa:fa-user-tie GH_TeamRole]
    GH_Branch[fa:fa-code-branch GH_Branch]
    GH_ExternalIdentity[fa:fa-arrows-left-right GH_ExternalIdentity]
    AZUser[fa:fa-user AZUser]
    Okta_User[fa:fa-user Okta_User]
    PingOneUser[fa:fa-user PingOneUser]


    GH_PersonalAccessToken[fa:fa-key GH_PersonalAccessToken]
    GH_PersonalAccessTokenRequest[fa:fa-key GH_PersonalAccessTokenRequest]


    GH_BranchProtectionRule[fa:fa-shield GH_BranchProtectionRule]
    GH_Repository[fa:fa-box-archive GH_Repository]


    GH_User -->|GH_HasRole| GH_OrgRole
    GH_User -->|GH_HasRole| GH_TeamRole
    GH_User -->|GH_HasRole| GH_RepoRole
    GH_User -.->|GH_BypassPullRequestAllowances| GH_BranchProtectionRule
    GH_User -.->|GH_RestrictionsCanPush| GH_BranchProtectionRule
    GH_User -->|GH_CanWriteBranch| GH_Branch
    GH_User -->|GH_CanCreateBranch| GH_Repository
    GH_ExternalIdentity -.->|GH_MapsToUser| GH_User
    AZUser -->|GH_SyncedTo| GH_User
    Okta_User -->|GH_SyncedTo| GH_User
    PingOneUser -->|GH_SyncedTo| GH_User
```
