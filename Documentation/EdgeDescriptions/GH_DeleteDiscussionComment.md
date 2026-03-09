---
kind: GH_DeleteDiscussionComment
is_traversable: false
---

# GH_DeleteDiscussionComment

## Edge Schema

- Source: [GH_RepoRole](../Nodes/GH_RepoRole.md)
- Destination: [GH_Repository](../Nodes/GH_Repository.md)

## General Information

The non-traversable `GH_DeleteDiscussionComment` edge represents a role's ability to delete discussion comments authored by any user. This permission is available to Triage, Write, Maintain, and Admin roles and custom roles that have been granted this specific permission.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\triage")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_DeleteDiscussionComment --> repo
```
