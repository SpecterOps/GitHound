# <img src="../images/GH_Environment.png" width="50"/> GH_Environment

Represents a GitHub Actions deployment environment configured on a repository. Environments can have protection rules including required reviewers, wait timers, and deployment branch policies. When custom branch policies are configured, the environment is connected to specific branches; otherwise, it is connected directly to the repository.

Created by: `Git-HoundEnvironment`

## Properties

| Property Name     | Data Type | Description                                                                   |
| ----------------- | --------- | ----------------------------------------------------------------------------- |
| objectid          | string    | The GitHub `node_id` of the environment, used as the unique graph identifier. |
| id                | integer   | The numeric GitHub ID of the environment.                                     |
| node_id           | string    | The GitHub node ID. Redundant with objectid.                                  |
| name              | string    | The fully qualified environment name (e.g., `repoName\production`).           |
| short_name        | string    | The environment's display name (e.g., `production`, `staging`).               |
| can_admins_bypass | boolean   | Whether repository administrators can bypass environment protection rules.    |
| environment_name  | string    | The name of the environment (GitHub organization)                             |
| environment_id    | string    | The node_id of the environment (GitHub organization)                          |
| repository_name   | string    | The full name of the containing repository.                                   |
| repository_id     | string    | The ID of the containing repository.                                          |

## Edges

### Outbound Edges

| Edge Kind         | Target Node                   | Traversable | Description                                                                          |
| ----------------- | ----------------------------- | ----------- | ------------------------------------------------------------------------------------ |
| GH_Contains        | GH_EnvironmentSecret           | No          | Environment contains an environment-level secret.                                    |
| GH_HasSecret       | GH_EnvironmentSecret           | No          | Environment has an environment-level secret.                                         |
| CanAssumeIdentity | AZFederatedIdentityCredential | Yes         | Environment can assume an Azure federated identity via OIDC (subject: environment:{envName}). |

### Inbound Edges

| Edge Kind        | Source Node  | Traversable | Description                                                                 |
| ---------------- | ------------ | ----------- | --------------------------------------------------------------------------- |
| GH_HasEnvironment | GH_Repository | Yes         | Repository has this environment (when no custom branch policies).           |
| GH_HasEnvironment | GH_Branch     | No          | Branch is allowed to deploy to this environment (via custom branch policy). |

## Diagram

```mermaid
flowchart TD
    GH_Environment[fa:fa-leaf GH_Environment]
    GH_Repository[fa:fa-box-archive GH_Repository]
    GH_Branch[fa:fa-code-branch GH_Branch]
    GH_EnvironmentSecret[fa:fa-lock GH_EnvironmentSecret]
    AWSRole[fa:fa-user-tag AWSRole]
    AZFederatedIdentityCredential[fa:fa-id-card AZFederatedIdentityCredential]

    style GH_Environment fill:#D5F2C2
    style GH_Repository fill:#9EECFF
    style GH_Branch fill:#FF80D2
    style GH_EnvironmentSecret fill:#6FB94A
    style AWSRole fill:#FF8E40
    style AZFederatedIdentityCredential fill:#FF80D2

    GH_Repository -.->|GH_HasEnvironment| GH_Environment
    GH_Branch -.->|GH_HasEnvironment| GH_Environment
    GH_Environment -.->|GH_Contains| GH_EnvironmentSecret
    GH_Environment -.->|GH_HasSecret| GH_EnvironmentSecret
    GH_Environment -.->|GH_CanAssumeAWSRole| AWSRole
    GH_Environment -->|CanAssumeIdentity| AZFederatedIdentityCredential
```
