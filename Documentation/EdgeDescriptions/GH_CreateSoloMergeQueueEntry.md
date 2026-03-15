---
kind: GH_CreateSoloMergeQueueEntry
is_traversable: false
---

# GH_CreateSoloMergeQueueEntry

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_CreateSoloMergeQueueEntry](GH_CreateSoloMergeQueueEntry.md) edge represents a role's ability to create solo merge queue entries, effectively bypassing the merge queue by merging independently of other queued changes. This permission is available to Admin roles and custom roles that have been granted this specific permission. Solo merge queue entries skip the batching and ordering guarantees of the merge queue, allowing changes to land without waiting for or being tested alongside other pending merges. This can circumvent the integration testing benefits that merge queues provide.

```mermaid
graph LR
    user1("GH_User carol")
    adminRole("GH_RepoRole GitHound\admin")
    customRole("GH_RepoRole GitHound\release_manager")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> customRole
    adminRole -- GH_CreateSoloMergeQueueEntry --> repo
    customRole -- GH_CreateSoloMergeQueueEntry --> repo
```
