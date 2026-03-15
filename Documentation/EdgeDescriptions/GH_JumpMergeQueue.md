---
kind: GH_JumpMergeQueue
is_traversable: false
---

# GH_JumpMergeQueue

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_JumpMergeQueue](GH_JumpMergeQueue.md) edge represents a role's ability to jump ahead of other entries in the merge queue. This permission is available to Admin roles and custom roles that have been granted this specific permission. Merge queues enforce an ordered sequence of CI checks and merges; jumping the queue allows a principal to prioritize their changes ahead of others. While less severe than bypassing protections entirely, this permission can be used to accelerate the landing of malicious changes before other queued entries are reviewed or tested.

```mermaid
graph LR
    user1("GH_User bob")
    adminRole("GH_RepoRole GitHound\admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> adminRole
    adminRole -- GH_JumpMergeQueue --> repo
    adminRole -- GH_AdminTo --> repo
```
