# GH_HasWorkflow

## Edge Schema

- Source: [GH_Repository](../NodeDescriptions/GH_Repository.md)
- Destination: [GH_Workflow](../NodeDescriptions/GH_Workflow.md)

## General Information

The non-traversable [GH_HasWorkflow](GH_HasWorkflow.md) edge represents the relationship between a repository and its GitHub Actions workflows. Created by `Git-HoundWorkflow`, this edge links each discovered workflow definition to its parent repository. Workflows are significant from a security perspective because they can execute arbitrary code with repository permissions, access secrets, and assume cloud identities. This structural edge enables analysts to enumerate which workflows exist in a given repository.

```mermaid
graph LR
    node1("GH_Repository GitHound")
    node2("GH_Workflow ci.yml")
    node3("GH_Workflow deploy.yml")
    node4("GH_Repository BloodHound")
    node5("GH_Workflow release.yml")
    node1 -- GH_HasWorkflow --> node2
    node1 -- GH_HasWorkflow --> node3
    node4 -- GH_HasWorkflow --> node5
```
