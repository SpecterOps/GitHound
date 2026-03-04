---
kind: GH_EditRepoProtections
is_traversable: false
---

# GH_EditRepoProtections

## Edge Schema

- Source: [GH_RepoRole](../Nodes/GH_RepoRole.md)
- Destination: [GH_Repository](../Nodes/GH_Repository.md)

## General Information

The non-traversable `GH_EditRepoProtections` edge represents a role's ability to edit or remove branch protection rules on the repository. This permission is available to Admin roles and custom roles that have been granted this specific permission. Modifying a branch protection rule is an indirect bypass -- removing or weakening protections opens the branch to direct push or unreviewed merges, making this a high-severity permission from a security perspective. Attack paths that include this edge can escalate to full branch write access by first disabling protections.

```mermaid
graph LR
    user1("GH_User bob")
    adminRole("GH_RepoRole GitHound\admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> adminRole
    adminRole -- GH_EditRepoProtections --> repo
    adminRole -- GH_AdminTo --> repo
```
