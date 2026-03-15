# <img src="../Icons/GH_SecretScanningAlert.png" width="50"/> GH_SecretScanningAlert

Represents a GitHub secret scanning alert detected in a repository. Secret scanning alerts are raised when GitHub detects a known secret pattern (such as an API key, token, or credential) committed to a repository. The alert captures the secret type, validity status, and current resolution state.

Created by: `Git-HoundSecretScanningAlert`

## Properties

| Property Name            | Data Type | Description                                                                                    |
| ------------------------ | --------- | ---------------------------------------------------------------------------------------------- |
| objectid                 | string    | A deterministic Base64-encoded ID derived from the organization, repository, and alert number. |
| id                       | string    | Same as objectid.                                                                              |
| name                     | string    | The alert number.                                                                              |
| repository_name          | string    | The name of the repository where the secret was detected.                                      |
| repository_id            | string    | The node_id of the repository.                                                                 |
| repository_url           | string    | The HTML URL of the repository.                                                                |
| secret_type              | string    | The type of secret detected (e.g., `github_personal_access_token`, `aws_access_key_id`).       |
| secret_type_display_name | string    | A human-readable name for the secret type.                                                     |
| validity                 | string    | The validity status of the detected secret (e.g., `active`, `inactive`, `unknown`).            |
| state                    | string    | The alert state (e.g., `open`, `resolved`).                                                    |
| created_at               | datetime  | When the alert was created.                                                                    |
| updated_at               | datetime  | When the alert was last updated.                                                               |
| url                      | string    | The HTML URL to view the alert on GitHub.                                                      |

## Edges

### Outbound Edges

| Edge Kind      | Target Node | Traversable | Description                                                                                                                      |
| -------------- | ----------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------- |
| [GH_ValidToken](../EdgeDescriptions/GH_ValidToken.md)  | [GH_User](GH_User.md)     | Yes         | Alert contains a valid, active PAT belonging to this user. Only emitted when the alert is open and the token is confirmed valid. |

### Inbound Edges

| Edge Kind                        | Source Node              | Traversable | Description                                                                      |
| -------------------------------- | ------------------------ | ----------- | -------------------------------------------------------------------------------- |
| [GH_Contains](../EdgeDescriptions/GH_Contains.md)                      | [GH_Repository](GH_Repository.md)            | No          | Repository contains this secret scanning alert.                                  |
| [GH_CanReadSecretScanningAlert](../EdgeDescriptions/GH_CanReadSecretScanningAlert.md)    | [GH_OrgRole](GH_OrgRole.md), [GH_RepoRole](GH_RepoRole.md)  | Yes         | Role can read this alert (computed from [GH_ViewSecretScanningAlerts](../EdgeDescriptions/GH_ViewSecretScanningAlerts.md) permission). |

## Diagram

```mermaid
flowchart TD
    GH_Repository[fa:fa-box-archive GH_Repository]
    GH_SecretScanningAlert[fa:fa-key GH_SecretScanningAlert]
    GH_User[fa:fa-user GH_User]
    GH_OrgRole[fa:fa-user-tie GH_OrgRole]
    GH_RepoRole[fa:fa-user-tie GH_RepoRole]

    style GH_Repository fill:#9EECFF
    style GH_SecretScanningAlert fill:#3C7A6E
    style GH_User fill:#FF8E40
    style GH_OrgRole fill:#BFFFD1
    style GH_RepoRole fill:#DEFEFA

    GH_Repository -.->|GH_Contains| GH_SecretScanningAlert
    GH_SecretScanningAlert -->|GH_ValidToken| GH_User
    GH_OrgRole -->|GH_CanReadSecretScanningAlert| GH_SecretScanningAlert
    GH_RepoRole -->|GH_CanReadSecretScanningAlert| GH_SecretScanningAlert
```
