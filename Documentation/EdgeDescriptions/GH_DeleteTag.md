---
kind: GH_DeleteTag
is_traversable: false
---

# GH_DeleteTag

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_DeleteTag](GH_DeleteTag.md) edge represents a role's ability to delete tags and releases. This permission is available to Admin roles and custom roles that have been granted this specific permission. Deleting tags can break downstream dependency references and remove published artifacts.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_DeleteTag --> repo
```
