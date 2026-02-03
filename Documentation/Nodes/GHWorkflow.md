# <img src="../../images/black_GHWorkflow.png" width="30"/> GHWorkflow

## Naming Convention

This section should include how the Object Identifier is derived and/or formatted. It should also include information regarding fully qualified, normal, or short names.

## Properties

For this, we found that it was useful to include the name of the repository in the "name" property because it is possible to have several workflows with the same name because they are in different repositories.
I wonder if it may be worth considering whether we should include the containing repository name and id in the property list?

| Property Name     | Display Name      | Data Type | Sample Value              | Description |
|-------------------|-------------------|-----------|---------------------------|-------------|
| objectid          | Object Id         | string    | | This is derived from the node_id property to uniquely identify the Workflow. |
| name              | Name              | string    | | |
| short_name        | Short Name        | string    | | |
| id                | Id                | integer   | | |
| node_id           | Node Id           | string    | | * We can delete this field because it is being used as the objectId. |
| path              | Path              | string    | | |
| state             | State             | string    | | |
| url               | Url               | string    | | |
| organization_name | Organization Name | string    | | |
| organization_id   | Organization Id   | string    | | |