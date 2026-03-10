---
kind: GH_CanWriteBranch
is_traversable: true
---

# GH_CanWriteBranch

## Edge Schema

- Source: [GH_RepoRole](../Nodes/GH_RepoRole.md), [GH_User](../Nodes/GH_User.md), [GH_Team](../Nodes/GH_Team.md)
- Destination: [GH_Branch](../Nodes/GH_Branch.md)

## General Information

The traversable `GH_CanWriteBranch` edge is a computed edge indicating that a role or actor can push to a specific branch. Created by `Compute-GitHoundBranchAccess` with no additional API calls, the computation evaluates both the merge gate (PR review requirements) and push gate (push restrictions) of any branch protection rule protecting the branch. Role-level edges are the common case; per-actor edges from `GH_User` or `GH_Team` are only emitted when BPR allowances grant access beyond what the role provides. Each edge includes a `reason` property (`no_protection`, `admin`, `push_protected_branch`, `bypass_branch_protection`, `push_allowance`, `bypass_pr_allowance`) and a `query_composition` Cypher query showing the underlying graph evidence.

## Scenarios

### `no_protection` — Unprotected branch

Branch has no BPR. Any write-capable role can push directly.

```mermaid
graph LR
    role("GH_RepoRole write") -->|GH_WriteRepoContents| repo("GH_Repository")
    repo -->|GH_HasBranch| branch("GH_Branch develop")
    role ==>|GH_CanWriteBranch| branch
```

### `admin` — Admin bypasses both gates

BPR blocks both the merge gate (PR reviews) and push gate (push_restrictions). The admin role bypasses both gates. Requires `enforce_admins=false`; when `enforce_admins=true`, admin cannot bypass the merge gate.

```mermaid
graph LR
    role("GH_RepoRole admin") -->|GH_AdminTo| repo("GH_Repository")
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule\nrequired_pull_request_reviews\npush_restrictions\nenforce_admins=false") -->|GH_ProtectedBy| branch
    role ==>|GH_CanWriteBranch| branch
```

### `push_protected_branch` — Push gate bypass

Push gate blocked by `push_restrictions` (no merge gate block). The `GH_PushProtectedBranch` permission bypasses the push gate regardless of `enforce_admins`.

```mermaid
graph LR
    role("GH_RepoRole maintain") -->|GH_WriteRepoContents| repo("GH_Repository")
    role -->|GH_PushProtectedBranch| repo
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule\npush_restrictions") -->|GH_ProtectedBy| branch
    role ==>|GH_CanWriteBranch| branch
```

### `bypass_branch_protection` — Merge gate bypass

Merge gate blocked by PR reviews. The `GH_BypassBranchProtection` permission bypasses the merge gate. Requires `enforce_admins=false`; suppressed when `enforce_admins=true`.

```mermaid
graph LR
    role("GH_RepoRole custom") -->|GH_WriteRepoContents| repo("GH_Repository")
    role -->|GH_BypassBranchProtection| repo
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule\nrequired_pull_request_reviews\nenforce_admins=false") -->|GH_ProtectedBy| branch
    role ==>|GH_CanWriteBranch| branch
```

### `push_allowance` — Per-actor push restriction bypass

User or Team listed in the BPR's `pushAllowances` bypasses the push gate. This is a per-actor delta edge — only emitted when the actor's role-level access doesn't already cover the branch.

```mermaid
graph LR
    user("GH_User alice") -->|GH_HasRole| role("GH_RepoRole write")
    role -->|GH_WriteRepoContents| repo("GH_Repository")
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule\npush_restrictions") -->|GH_ProtectedBy| branch
    user -->|GH_RestrictionsCanPush| bpr
    user ==>|GH_CanWriteBranch| branch
```

### `bypass_pr_allowance` — Per-actor PR review bypass

User or Team listed in the BPR's `bypassPullRequestAllowances` bypasses the merge gate (PR reviews only, not `lock_branch`). Requires `enforce_admins=false`. This is a per-actor delta edge — only emitted when the actor's role-level access doesn't already cover the branch.

```mermaid
graph LR
    user("GH_User alice") -->|GH_HasRole| role("GH_RepoRole write")
    role -->|GH_WriteRepoContents| repo("GH_Repository")
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule\nrequired_pull_request_reviews\nenforce_admins=false") -->|GH_ProtectedBy| branch
    user -->|GH_BypassPullRequestAllowances| bpr
    user ==>|GH_CanWriteBranch| branch
```
