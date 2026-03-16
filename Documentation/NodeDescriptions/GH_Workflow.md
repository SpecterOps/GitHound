# <img src="../Icons/gh_workflow.png" width="50"/> GH_Workflow

Represents a GitHub Actions workflow defined in a repository. Workflow nodes capture the workflow definition metadata including its file path, state, containing repository, and the full YAML contents of the workflow file. Only repositories with GitHub Actions enabled are queried for workflows.

Created by: `Git-HoundWorkflow`

## Properties

| Property Name    | Data Type | Description                                                                  |
| ---------------- | --------- | ---------------------------------------------------------------------------- |
| objectid         | string    | The GitHub `node_id` of the workflow, used as the unique graph identifier.   |
| name             | string    | The fully qualified workflow name (e.g., `repoName\CI Build`).               |
| short_name       | string    | The workflow's display name.                                                 |
| node_id          | string    | The GitHub GraphQL node ID. Redundant with objectid.                         |
| environment_name | string    | The name of the environment (GitHub organization).                           |
| environmentid    | string    | The node_id of the environment (GitHub organization).                        |
| repository_name  | string    | The full name of the containing repository.                                  |
| repository_id    | string    | The node_id of the containing repository.                                    |
| path             | string    | The file path of the workflow definition (e.g., `.github/workflows/ci.yml`). |
| state            | string    | The workflow state (e.g., `active`, `disabled_manually`).                    |
| url              | string    | The API URL for the workflow.                                                |
| html_url         | string    | The GitHub web URL for the workflow file.                                    |
| branch           | string    | The branch where the workflow file was found.                                |
| contents         | string    | The full YAML contents of the workflow file, downloaded from the repository. |

## Edges

### Outbound Edges

None

### Inbound Edges

| Edge Kind                                               | Source Node                       | Traversable | Description                   |
| ------------------------------------------------------- | --------------------------------- | ----------- | ----------------------------- |
| [GH_HasWorkflow](../EdgeDescriptions/GH_HasWorkflow.md) | [GH_Repository](GH_Repository.md) | No          | Repository has this workflow. |

## Diagram

```mermaid
flowchart TD
    GH_Workflow[fa:fa-cogs GH_Workflow]
    GH_Repository[fa:fa-box-archive GH_Repository]

    style GH_Workflow fill:#FFE4A1
    style GH_Repository fill:#9EECFF

    GH_Repository -.->|GH_HasWorkflow| GH_Workflow
```
