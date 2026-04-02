# GH_DeploysTo

## Edge Schema

- Source: [GH_WorkflowJob](../NodeDescriptions/GH_WorkflowJob.md)
- Destination: [GH_Environment](../NodeDescriptions/GH_Environment.md)

## General Information

The non-traversable [GH_DeploysTo](GH_DeploysTo.md) edge links a workflow job to the GitHub Environment it targets via the `environment:` key. Created by `Parse-GitHoundWorkflow`, this edge records which jobs deploy to which environments. Environments can gate deployments with protection rules (required reviewers, wait timers, deployment branch policies) and can expose environment-scoped secrets.

```mermaid
graph LR
    node1("GH_WorkflowJob deploy")
    node2("GH_Environment production")
    node1 -- GH_DeploysTo --> node2
```
