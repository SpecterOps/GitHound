# GH_RepoRunner

Represents a GitHub Actions self-hosted runner registered directly to a repository.

Created by: `Git-HoundRunner`

## Properties

| Property Name         | Data Type | Description |
| --------------------- | --------- | ----------- |
| objectid              | string    | Synthetic graph identifier for the runner node in the form `{repoNodeId}_repo_runner_{runnerId}`. |
| name                  | string    | The runner name shown in GitHub Actions settings. |
| node_id               | string    | Same as objectid. |
| environment_name      | string    | The organization login that owns the repository. |
| environmentid         | string    | The organization node_id. |
| runner_id             | integer   | The numeric GitHub runner ID. |
| repository_name       | string    | The repository name that owns the runner. |
| repository_id         | string    | The repository node_id that owns the runner. |
| repository_full_name  | string    | The fully-qualified repository name. |
| os                    | string    | The operating system reported by the runner, such as `linux` or `macos`. |
| status                | string    | The runner status, such as `online` or `offline`. |
| busy                  | boolean   | Whether the runner is currently processing a job. |
| ephemeral             | boolean   | Whether the runner is ephemeral and intended for single-job use. |
| labels                | string    | JSON-serialized runner labels, including default and custom labels. |

## Diagram

```mermaid
flowchart TD
    GH_Repository[fa:fa-box-archive GH_Repository]
    GH_RepoRunner[fa:fa-server GH_RepoRunner]

    GH_Repository -.->|GH_Contains| GH_RepoRunner
    GH_Repository -->|GH_CanUseRunner| GH_RepoRunner
```
