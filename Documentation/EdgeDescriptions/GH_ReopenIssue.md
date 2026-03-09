---
kind: GH_ReopenIssue
is_traversable: false
---

# GH_ReopenIssue

## Edge Schema

- Source: [GH_RepoRole](../Nodes/GH_RepoRole.md)
- Destination: [GH_Repository](../Nodes/GH_Repository.md)

## General Information

The non-traversable `GH_ReopenIssue` edge represents a role's ability to reopen closed issues. This permission is available to Triage, Write, Maintain, and Admin roles and custom roles that have been granted this specific permission.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\triage")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_ReopenIssue --> repo
```
