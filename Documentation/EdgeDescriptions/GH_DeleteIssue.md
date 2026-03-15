---
kind: GH_DeleteIssue
is_traversable: false
---

# GH_DeleteIssue

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_DeleteIssue](GH_DeleteIssue.md) edge represents a role's ability to delete issues permanently. Deleted issues cannot be recovered. This permission is available to Admin roles and custom roles that have been granted this specific permission. Deleting issues can destroy audit trails and remove evidence of security discussions or vulnerability reports.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_DeleteIssue --> repo
```
