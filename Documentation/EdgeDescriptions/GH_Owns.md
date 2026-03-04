---
kind: GH_Owns
is_traversable: true
---

# GH_Owns

## Edge Schema

- Source: [GH_Organization](../Nodes/GH_Organization.md)
- Destination: [GH_Repository](../Nodes/GH_Repository.md)

## General Information

The traversable `GH_Owns` edge represents that an organization owns a repository. Created by `Git-HoundRepository`, this edge establishes the foundation of the access control model by linking repositories to their owning organization. It is traversable because repository ownership is a critical relationship for understanding how organizational permissions cascade down to repository-level access, making it essential for attack path analysis.

```mermaid
graph LR
    node1("GH_Organization SpecterOps")
    node2("GH_Repository GitHound")
    node3("GH_Repository BloodHound")
    node4("GH_Repository Nemesis")
    node1 -- GH_Owns --> node2
    node1 -- GH_Owns --> node3
    node1 -- GH_Owns --> node4
```
