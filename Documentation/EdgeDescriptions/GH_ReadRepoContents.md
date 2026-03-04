---
kind: GH_ReadRepoContents
is_traversable: true
---

# GH_ReadRepoContents

## Edge Schema

- Source: [GH_RepoRole](../Nodes/GH_RepoRole.md)
- Destination: [GH_Repository](../Nodes/GH_Repository.md)

## General Information

The traversable `GH_ReadRepoContents` edge represents a role's ability to read repository contents including source code, issues, and pull requests. This is the base level of repository access, available to all roles at the Read permission level and above (Read, Triage, Write, Maintain, Admin). It is traversable because read access is the entry point to the repository and the foundation from which all other repository interactions are built. Without this edge, a principal has no visibility into the repository's contents.

```mermaid
graph LR
    user1("GH_User alice")
    readRole("GH_RepoRole GitHound\read")
    writeRole("GH_RepoRole GitHound\write")
    adminRole("GH_RepoRole GitHound\admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> readRole
    readRole -- GH_ReadRepoContents --> repo
    writeRole -- GH_ReadRepoContents --> repo
    adminRole -- GH_ReadRepoContents --> repo
```
