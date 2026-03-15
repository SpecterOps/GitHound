# <img src="../Icons/GH_RepoVariable.png" width="50"/> GH_RepoVariable

Represents a repository-level GitHub Actions variable. These are variables defined directly on a specific repository and are only accessible to workflows running in that repository. Unlike secrets, variable values are readable via the API.

Created by: `Git-HoundVariable`

## Properties

| Property Name    | Data Type | Description                                                                 |
| ---------------- | --------- | --------------------------------------------------------------------------- |
| objectid         | string    | A deterministic ID in the format `GH_Variable_{repoNodeId}_{variableName}`. |
| id               | string    | Same as objectid.                                                           |
| name             | string    | The name of the variable.                                                   |
| environment_name | string    | The name of the environment (GitHub organization).                          |
| environmentid    | string    | The node_id of the environment (GitHub organization).                       |
| repository_name  | string    | The name of the containing repository.                                      |
| repository_id    | string    | The node_id of the containing repository.                                   |
| value            | string    | The plaintext value of the variable.                                        |
| created_at       | datetime  | When the variable was created.                                              |
| updated_at       | datetime  | When the variable was last updated.                                         |

## Edges

### Outbound Edges

None

### Inbound Edges

| Edge Kind                                               | Source Node                       | Traversable | Description                                                                                                               |
| ------------------------------------------------------- | --------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------- |
| [GH_Contains](../EdgeDescriptions/GH_Contains.md)       | [GH_Repository](GH_Repository.md) | No          | Repository contains this variable.                                                                                        |
| [GH_HasVariable](../EdgeDescriptions/GH_HasVariable.md) | [GH_Repository](GH_Repository.md) | Yes         | Repository has this variable. Traversable because write access to the repo enables variable access via workflow creation. |

## Diagram

```mermaid
flowchart TD
    GH_RepoVariable[fa:fa-lock-open GH_RepoVariable]
    GH_Repository[fa:fa-box-archive GH_Repository]

    style GH_RepoVariable fill:#E89B5C
    style GH_Repository fill:#9EECFF

    GH_Repository -.->|GH_Contains| GH_RepoVariable
    GH_Repository -->|GH_HasVariable| GH_RepoVariable
```
