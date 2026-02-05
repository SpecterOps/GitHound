# <img src="../../images/black_GHUser.png" width="50"/> GH_User

Represents a GitHub user who is a member of the organization. Users are associated with organization roles (Owner or Member) and can be assigned to repository roles and team roles.

Created by: `Git-HoundUser`

## Properties

| Property Name     | Data Type | Description                                                            |
| ----------------- | --------- | ---------------------------------------------------------------------- |
| objectid          | string    | The GitHub `node_id` of the user, used as the unique graph identifier. |
| name              | string    | The user's display name, derived from the login property.              |
| login             | string    | The user's GitHub login handle.                                        |
| company           | string    | The company listed on the user's profile.                              |
| email             | string    | The user's public email address.                                       |
| full_name         | string    | The user's full name from their profile.                               |
| type              | string    | The account type (e.g., `User`).                                       |
| twitter_username  | string    | The user's Twitter username.                                           |
| site_admin        | boolean   | Whether the user is a GitHub site administrator.                       |
| id                | integer   | The numeric GitHub ID of the user.                                     |
| node_id           | string    | The GitHub GraphQL node ID. Redundant with objectid.                   |
| environment_name  | string    | The name of the environment (GitHub organization) the user belongs to. |
| environment_id    | string    | The node_id of the environment (GitHub organization).                  |

## Edges

### Outbound Edges

| Edge Kind | Target Node | Traversable | Description                                                                    |
| --------- | ----------- | ----------- | ------------------------------------------------------------------------------ |
| GH_HasRole | GH_OrgRole   | Yes         | User is assigned to an organization role (Owner or Member).                    |
| GH_HasRole | GH_RepoRole  | Yes         | User is directly assigned to a repository role (from Git-HoundRepositoryRole). |
| GH_HasRole | GH_TeamRole  | Yes         | User has a team role (Member or Maintainer).                                   |

### Inbound Edges

| Edge Kind    | Source Node        | Traversable | Description                                              |
| ------------ | ------------------ | ----------- | -------------------------------------------------------- |
| GH_MapsToUser | GH_ExternalIdentity | No          | An external SAML/SCIM identity maps to this GitHub user. |

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
    OktaUser[fa:fa-user OktaUser]
    PingOneUser[fa:fa-user PingOneUser]

    style GH_User fill:#FF8E40
    style GH_OrgRole fill:#BFFFD1
    style GH_RepoRole fill:#DEFEFA
    style GH_TeamRole fill:#D0B0FF
    style GH_Branch fill:#FF80D2
    style GH_ExternalIdentity fill:#8A8F98
    style AZUser fill:#FF80D2
    style OktaUser fill:#FFE4A1
    style PingOneUser fill:#FFE4A1

    GH_User -->|GH_HasRole| GH_OrgRole
    GH_User -->|GH_HasRole| GH_TeamRole
    GH_User -->|GH_HasRole| GH_RepoRole
    GH_User -.->|GH_BypassPullRequestAllowances| GH_Branch
    GH_User -.->|GH_RestrictionsCanPush| GH_Branch
    GH_ExternalIdentity -.->|GH_MapsToUser| GH_User
    AZUser -->|SyncedToGH_User| GH_User
    OktaUser -->|SyncedToGH_User| GH_User
    PingOneUser -->|SyncedToGH_User| GH_User
```
