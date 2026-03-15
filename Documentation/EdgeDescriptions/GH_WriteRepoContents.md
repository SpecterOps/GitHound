---
kind: GH_WriteRepoContents
is_traversable: false
---

# GH_WriteRepoContents

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_WriteRepoContents](GH_WriteRepoContents.md) edge represents a role's ability to push commits to the repository. This permission is available to Write, Maintain, and Admin roles. Pushing code can modify application behavior and introduce vulnerabilities, making this a security-significant edge. However, this edge represents only the raw permission; actual branch push capability is determined by the computed [GH_CanWriteBranch](GH_CanWriteBranch.md) edge, which factors in branch protection rules and push restrictions.

```mermaid
graph LR
    user1("GH_User bob")
    writeRole("GH_RepoRole GitHound\write")
    maintainRole("GH_RepoRole GitHound\maintain")
    adminRole("GH_RepoRole GitHound\admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> writeRole
    writeRole -- GH_WriteRepoContents --> repo
    maintainRole -- GH_WriteRepoContents --> repo
    adminRole -- GH_WriteRepoContents --> repo
```
