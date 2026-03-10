---
kind: GH_CanCreateBranch
is_traversable: true
---

# GH_CanCreateBranch

## Edge Schema

- Source: [GH_RepoRole](../Nodes/GH_RepoRole.md), [GH_User](../Nodes/GH_User.md), [GH_Team](../Nodes/GH_Team.md)
- Destination: [GH_Repository](../Nodes/GH_Repository.md)

## General Information

The traversable `GH_CanCreateBranch` edge is a computed edge indicating that a role or actor can create new branches in a repository. Created by `Compute-GitHoundBranchAccess` with no additional API calls, the computation evaluates whether a wildcard (`*`) BPR with push restrictions and `blocks_creations` exists. If no such BPR exists, any write-capable role can create branches. If one exists, admin or `push_protected_branch` permission is required, or the actor must be listed in pushAllowances. Per-actor edges from `GH_User` or `GH_Team` are only emitted when BPR allowances grant branch creation access beyond what the role provides. Each edge includes a `reason` property and a `query_composition` Cypher query showing the underlying graph evidence.

## Scenarios

### `no_protection` — No wildcard BPR blocking creations

No wildcard (`*`) BPR with `blocks_creations` exists. Any write-capable role can create new branches.

```mermaid
graph LR
    role("GH_RepoRole write") -->|GH_WriteRepoContents| repo("GH_Repository")
    role ==>|GH_CanCreateBranch| repo
```

### `admin` — Admin bypasses wildcard BPR

A wildcard BPR with `push_restrictions` and `blocks_creations` prevents branch creation. The admin role bypasses this restriction.

```mermaid
graph LR
    role("GH_RepoRole admin") -->|GH_AdminTo| repo("GH_Repository")
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule\npattern=*\npush_restrictions\nblocks_creations") -->|GH_ProtectedBy| branch
    role ==>|GH_CanCreateBranch| repo
```

### `push_protected_branch` — Push-protected role bypasses wildcard BPR

A wildcard BPR blocks creations. The `GH_PushProtectedBranch` permission bypasses the push gate regardless of `enforce_admins`.

```mermaid
graph LR
    role("GH_RepoRole maintain") -->|GH_WriteRepoContents| repo("GH_Repository")
    role -->|GH_PushProtectedBranch| repo
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule\npattern=*\npush_restrictions\nblocks_creations") -->|GH_ProtectedBy| branch
    role ==>|GH_CanCreateBranch| repo
```

### `push_allowance` — Per-actor push restriction bypass

User or Team listed in the wildcard BPR's `pushAllowances` can create branches. This is a per-actor delta edge — only emitted when the actor's role doesn't already grant `GH_CanCreateBranch`.

```mermaid
graph LR
    user("GH_User alice") -->|GH_HasRole| role("GH_RepoRole write")
    role -->|GH_WriteRepoContents| repo("GH_Repository")
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule\npattern=*\npush_restrictions\nblocks_creations") -->|GH_ProtectedBy| branch
    user -->|GH_RestrictionsCanPush| bpr
    user ==>|GH_CanCreateBranch| repo
```
