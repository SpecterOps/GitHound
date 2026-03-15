---
kind: GH_CanEditProtection
is_traversable: true
---

# GH_CanEditProtection

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Branch](../NodeDescriptions/GH_Branch.md)

## General Information

The traversable [GH_CanEditProtection](GH_CanEditProtection.md) edge is a computed edge indicating that a role can modify or remove the branch protection rules governing a specific branch. Created by `Compute-GitHoundBranchAccess` with no additional API calls, this edge is emitted when the role has [GH_EditRepoProtections](GH_EditRepoProtections.md) or [GH_AdminTo](GH_AdminTo.md) permissions and the branch is covered by at least one branch protection rule. The edge targets the protected branch (not the BPR itself) because the security impact is evaluated per-branch — a role that can weaken or remove protections on a branch can subsequently push code to it, representing a privilege escalation path.

## Scenarios

### `admin` — Admin can edit protections

The admin role has [GH_AdminTo](GH_AdminTo.md) which implicitly grants the ability to modify or remove any branch protection rule.

```mermaid
graph LR
    role("GH_RepoRole admin") -->|GH_AdminTo| repo("GH_Repository")
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule") -->|GH_ProtectedBy| branch
    role ==>|GH_CanEditProtection| branch
```

### `edit_repo_protections` — Explicit edit permission

A custom or standard role with the [GH_EditRepoProtections](GH_EditRepoProtections.md) permission can modify or remove branch protection rules.

```mermaid
graph LR
    role("GH_RepoRole custom") -->|GH_EditRepoProtections| repo("GH_Repository")
    repo -->|GH_HasBranch| branch("GH_Branch main")
    bpr("GH_BranchProtectionRule") -->|GH_ProtectedBy| branch
    role ==>|GH_CanEditProtection| branch
```
