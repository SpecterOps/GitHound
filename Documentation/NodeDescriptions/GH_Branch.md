# <img src="../Icons/gh_branch.png" width="50"/> GH_Branch

Represents a Git branch within a repository. Branch nodes capture basic branch information and whether the branch is protected. Protection rule details are stored in separate [GH_BranchProtectionRule](GH_BranchProtectionRule.md) nodes, linked via [GH_ProtectedBy](../EdgeDescriptions/GH_ProtectedBy.md) edges.

Created by: `Git-HoundBranch`

## Properties

| Property Name    | Data Type | Description                                                                    |
| ---------------- | --------- | ------------------------------------------------------------------------------ |
| objectid         | string    | A unique identifier for the branch: `REF_kwDOMuFnXLNyZWZzL2hlYWRzL0NhblB1c2gz` |
| name             | string    | The fully qualified branch name (e.g., `repo\main`).                           |
| short_name       | string    | The branch reference name (e.g., `main`).                                      |
| node_id          | string    | Same as objectid.                                                              |
| environment_name | string    | The name of the environment (GitHub organization).                             |
| environmentid    | string    | The node_id of the environment (GitHub organization).                          |
| protected        | boolean   | Whether the branch has a protection rule.                                      |

## Diagram

```mermaid
flowchart TD
    GH_Branch[fa:fa-code-branch GH_Branch]
    GH_Repository[fa:fa-box-archive GH_Repository]
    GH_RepoRole[fa:fa-user-tie GH_RepoRole]
    GH_BranchProtectionRule[fa:fa-shield GH_BranchProtectionRule]
    GH_Environment[fa:fa-leaf GH_Environment]
    GH_User[fa:fa-user GH_User]
    GH_Team[fa:fa-user-group GH_Team]
    AZFederatedIdentityCredential[fa:fa-id-card AZFederatedIdentityCredential]


    GH_Repository -.->|GH_HasBranch| GH_Branch
    GH_BranchProtectionRule -.->|GH_ProtectedBy| GH_Branch
    GH_Branch -.->|GH_HasEnvironment| GH_Environment
    GH_Branch -->|GH_CanAssumeIdentity| AZFederatedIdentityCredential
    GH_RepoRole -->|GH_CanWriteBranch| GH_Branch
    GH_RepoRole -->|GH_CanEditProtection| GH_Branch
    GH_User -->|GH_CanWriteBranch| GH_Branch
    GH_Team -->|GH_CanWriteBranch| GH_Branch
```
