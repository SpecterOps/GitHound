# <img src="../Icons/GH_Branch.png" width="50"/> GH_Branch

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

## Edges

### Outbound Edges

| Edge Kind                                                           | Target Node                                                                                                        | Traversable | Description                                                                                  |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ----------- | -------------------------------------------------------------------------------------------- |
| [GH_HasEnvironment](../EdgeDescriptions/GH_HasEnvironment.md)       | [GH_Environment](GH_Environment.md)                                                                                | No          | Branch has a deployment environment via custom branch policy (from Git-HoundEnvironment).    |
| [GH_CanAssumeIdentity](../EdgeDescriptions/GH_CanAssumeIdentity.md) | [AZFederatedIdentityCredential](https://bloodhound.specterops.io/resources/nodes/az-federated-identity-credential) | Yes         | Branch can assume an Azure federated identity via OIDC (subject: `ref:refs/heads/{branch}`). |

### Inbound Edges

| Edge Kind                                                           | Source Node                                           | Traversable | Description                                                                        |
| ------------------------------------------------------------------- | ----------------------------------------------------- | ----------- | ---------------------------------------------------------------------------------- |
| [GH_HasBranch](../EdgeDescriptions/GH_HasBranch.md)                 | [GH_Repository](GH_Repository.md)                     | No          | Repository has this branch.                                                        |
| [GH_ProtectedBy](../EdgeDescriptions/GH_ProtectedBy.md)             | [GH_BranchProtectionRule](GH_BranchProtectionRule.md) | No          | Branch protection rule protects this branch.                                       |
| [GH_CanEditProtection](../EdgeDescriptions/GH_CanEditProtection.md) | [GH_RepoRole](GH_RepoRole.md)                         | Yes         | Repo role can modify/remove the protection rules governing this branch (computed). |
| [GH_CanWriteBranch](../EdgeDescriptions/GH_CanWriteBranch.md)       | [GH_RepoRole](GH_RepoRole.md)                         | Yes         | Repo role can push to this branch (computed from permissions + BPR state).         |
| [GH_CanWriteBranch](../EdgeDescriptions/GH_CanWriteBranch.md)       | [GH_User](GH_User.md) or [GH_Team](GH_Team.md)        | Yes         | User or team can push to this branch (computed — per-actor allowance delta).       |

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

    style GH_Branch fill:#FF80D2
    style GH_Repository fill:#9EECFF
    style GH_RepoRole fill:#DEFEFA
    style GH_BranchProtectionRule fill:#FFB347
    style GH_Environment fill:#D5F2C2
    style GH_User fill:#FF8E40
    style GH_Team fill:#C06EFF
    style AZFederatedIdentityCredential fill:#FF80D2

    GH_Repository -.->|GH_HasBranch| GH_Branch
    GH_BranchProtectionRule -.->|GH_ProtectedBy| GH_Branch
    GH_Branch -.->|GH_HasEnvironment| GH_Environment
    GH_Branch -->|GH_CanAssumeIdentity| AZFederatedIdentityCredential
    GH_RepoRole -->|GH_CanWriteBranch| GH_Branch
    GH_RepoRole -->|GH_CanEditProtection| GH_Branch
    GH_User -->|GH_CanWriteBranch| GH_Branch
    GH_Team -->|GH_CanWriteBranch| GH_Branch
```
