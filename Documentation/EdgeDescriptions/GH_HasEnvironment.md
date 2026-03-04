---
kind: GH_HasEnvironment
is_traversable: false
---

# GH_HasEnvironment

## Edge Schema

- Source: [GH_Repository](../Nodes/GH_Repository.md), [GH_Branch](../Nodes/GH_Branch.md)
- Destination: [GH_Environment](../Nodes/GH_Environment.md)

## General Information

The non-traversable `GH_HasEnvironment` edge represents the relationship between a repository or branch and its deployment environments. Created by `Git-HoundEnvironment`, this edge links environments to the repositories that define them and to the branches that are allowed to deploy to them (via deployment branch policies). Environments are security-relevant because they can gate access to secrets and cloud credentials, and their deployment branch policies control which branches can trigger deployments.

```mermaid
graph LR
    node1("GH_Repository GitHound")
    node2("GH_Environment production")
    node3("GH_Environment staging")
    node4("GH_Branch main")
    node1 -- GH_HasEnvironment --> node2
    node1 -- GH_HasEnvironment --> node3
    node4 -- GH_HasEnvironment --> node2
```
