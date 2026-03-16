# <img src="../Icons/gh_orgvariable.png" width="50"/> GH_OrgVariable

Represents an organization-level GitHub Actions variable. Organization variables can be scoped to all repositories, only private/internal repositories, or a specific set of selected repositories. The visibility property determines how GH_HasVariable edges are resolved to repository nodes. Unlike secrets, variable values are readable via the API.

Created by: `Git-HoundOrganizationSecret`

## Properties

| Property Name    | Data Type | Description                                                                                                                 |
| ---------------- | --------- | --------------------------------------------------------------------------------------------------------------------------- |
| objectid         | string    | A deterministic ID in the format `GH_OrgVariable_{orgNodeId}_{variableName}`.                                               |
| id               | string    | Same as objectid.                                                                                                           |
| name             | string    | The name of the variable.                                                                                                   |
| environment_name | string    | The name of the environment (GitHub organization).                                                                          |
| environmentid    | string    | The node_id of the environment (GitHub organization).                                                                       |
| value            | string    | The plaintext value of the variable.                                                                                        |
| created_at       | datetime  | When the variable was created.                                                                                              |
| updated_at       | datetime  | When the variable was last updated.                                                                                         |
| visibility       | string    | The variable's visibility scope: `all` (all repos), `private` (private and internal repos), or `selected` (specific repos). |

## Diagram

```mermaid
flowchart TD
    GH_OrgVariable[fa:fa-lock-open GH_OrgVariable]
    GH_Organization[fa:fa-building GH_Organization]
    GH_Repository[fa:fa-box-archive GH_Repository]


    GH_Organization -.->|GH_Contains| GH_OrgVariable
    GH_Repository -->|GH_HasVariable| GH_OrgVariable
```
