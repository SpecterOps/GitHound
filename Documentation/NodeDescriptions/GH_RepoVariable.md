# <img src="../Icons/gh_repovariable.png" width="50"/> GH_RepoVariable

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

## Diagram

```mermaid
flowchart TD
    GH_RepoVariable[fa:fa-lock-open GH_RepoVariable]
    GH_Repository[fa:fa-book GH_Repository]


    GH_Repository -.->|GH_Contains| GH_RepoVariable
    GH_Repository -->|GH_HasVariable| GH_RepoVariable
```
