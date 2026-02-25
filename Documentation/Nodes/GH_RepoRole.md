# <img src="../images/GH_RepoRole.png" width="50"/> GH_RepoRole

Represents a repository-level permission role. Each repository has five default roles (Read, Write, Admin, Triage, Maintain) plus any custom repository roles defined at the organization level. Repo roles define what actions a user or team can perform on a specific repository. Default roles form an inheritance hierarchy (Triage → Read, Maintain → Write, Admin includes all), and custom roles inherit from one of the base roles.

Created by: `Git-HoundRepository`

## Properties

| Property Name     | Data Type | Description                                                                                      |
| ----------------- | --------- | ------------------------------------------------------------------------------------------------ |
| objectid          | string    | A deterministic ID derived from the repo node_id and role name.                                  |
| name              | string    | The fully qualified role name (e.g., `repoName\read`).                                           |
| id                | string    | Same as objectid.                                                                                |
| short_name        | string    | The short role name (e.g., `read`, `write`, `admin`, `triage`, `maintain`, or custom role name). |
| type              | string    | `default` for built-in roles or `custom` for custom repository roles.                            |
| environment_name  | string    | The name of the environment (GitHub organization).                                               |
| environment_id    | string    | The node_id of the environment (GitHub organization).                                            |
| repository_name   | string    | The name of the repository this role belongs to.                                                 |
| repository_id     | string    | The node_id of the repository this role belongs to.                                              |

## Edges

### Outbound Edges

| Edge Kind                       | Target Node  | Traversable | Description                                                             |
| ------------------------------- | ------------ | ----------- | ----------------------------------------------------------------------- |
| GH_ReadRepoContents              | GH_Repository | No          | Read role can read repository contents.                                 |
| GH_WriteRepoContents             | GH_Repository | No          | Write/Admin role can push to the repository.                            |
| GH_WriteRepoPullRequests         | GH_Repository | No          | Write/Admin role can create and merge pull requests.                    |
| GH_AdminTo                       | GH_Repository | No          | Admin role has full administrative access.                              |
| GH_ManageWebhooks                | GH_Repository | No          | Admin role can manage webhooks.                                         |
| GH_ManageDeployKeys              | GH_Repository | No          | Admin role can manage deploy keys.                                      |
| GH_PushProtectedBranch           | GH_Repository | No          | Admin/Maintain role can push to protected branches.                     |
| GH_DeleteAlertsCodeScanning      | GH_Repository | No          | Admin role can delete code scanning alerts.                             |
| GH_ViewSecretScanningAlerts      | GH_Repository | No          | Admin role can view secret scanning alerts.                             |
| GH_RunOrgMigration               | GH_Repository | No          | Admin role can run organization migrations.                             |
| GH_BypassBranchProtection        | GH_Repository | No          | Admin role can bypass branch protection rules.                          |
| GH_ManageSecurityProducts        | GH_Repository | No          | Admin role can manage security products.                                |
| GH_ManageRepoSecurityProducts    | GH_Repository | No          | Admin role can manage repo security products.                           |
| GH_EditRepoProtections           | GH_Repository | No          | Admin role can edit branch protection rules.                            |
| GH_JumpMergeQueue                | GH_Repository | No          | Admin role can jump the merge queue.                                    |
| GH_CreateSoloMergeQueueEntry     | GH_Repository | No          | Admin role can create solo merge queue entries.                         |
| GH_EditRepoCustomPropertiesValue | GH_Repository | No          | Admin role can edit custom property values.                             |
| GH_HasBaseRole                   | GH_RepoRole   | Yes         | Role inherits from a base role (e.g., Triage → Read, Maintain → Write). |
| GH_CanCreateBranch               | GH_Repository | Yes         | Role can create new branches (computed from permissions + BPR state).    |
| GH_CanWriteBranch                | GH_Branch              | Yes | Role can push to this branch (computed from permissions + BPR state). |
| GH_CanEditProtection             | GH_BranchProtectionRule | No  | Role can modify/remove this branch protection rule (computed from edit_repo_protections or admin). |

### Inbound Edges

| Edge Kind     | Source Node | Traversable | Description                                                                       |
| ------------- | ----------- | ----------- | --------------------------------------------------------------------------------- |
| GH_HasRole     | GH_User      | Yes         | A user is directly assigned to this repository role.                              |
| GH_HasRole     | GH_Team      | Yes         | A team is assigned to this repository role.                                       |
| GH_HasBaseRole | GH_OrgRole   | Yes         | An org-level `all_repo_*` role inherits to this repo role.                        |
| GH_HasBaseRole | GH_RepoRole  | Yes         | A higher-level repo role inherits from this role (e.g., custom role → base role). |

## Diagram

```mermaid
flowchart TD
    GH_RepoRole[fa:fa-user-tie GH_RepoRole]
    GH_Repository[fa:fa-box-archive GH_Repository]
    GH_Branch[fa:fa-code-branch GH_Branch]
    GH_BranchProtectionRule[fa:fa-shield GH_BranchProtectionRule]
    GH_User[fa:fa-user GH_User]
    GH_Team[fa:fa-user-group GH_Team]
    GH_OrgRole[fa:fa-user-tie GH_OrgRole]

    style GH_RepoRole fill:#DEFEFA
    style GH_Repository fill:#9EECFF
    style GH_Branch fill:#FF80D2
    style GH_BranchProtectionRule fill:#FFB347
    style GH_User fill:#FF8E40
    style GH_Team fill:#C06EFF
    style GH_OrgRole fill:#BFFFD1

    GH_RepoRole -.->|GH_ReadRepoContents| GH_Repository
    GH_RepoRole -.->|GH_WriteRepoContents| GH_Repository
    GH_RepoRole -.->|GH_AdminTo| GH_Repository
    GH_RepoRole -.->|GH_ViewSecretScanningAlerts| GH_Repository
    GH_RepoRole -.->|GH_BypassProtections| GH_Repository
    GH_RepoRole -.->|GH_EditProtections| GH_Repository
    GH_RepoRole -->|GH_HasBaseRole| GH_RepoRole
    GH_User -->|GH_HasRole| GH_RepoRole
    GH_Team -->|GH_HasRole| GH_RepoRole
    GH_OrgRole -->|GH_HasBaseRole| GH_RepoRole
```
