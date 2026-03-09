# Computed Edges

This document describes the computed edge functions and what they produce. For the empirical testing that validates the underlying security model, see [MITIGATING_CONTROLS.md](./MITIGATING_CONTROLS.md). For the complete schema reference, see [SCHEMA.md](./SCHEMA.md).

---

# Computed Branch Access Edges

## Overview

`Compute-GitHoundBranchAccess` is a post-collection step that computes effective branch push access. It runs as **Step 6.5** in `Invoke-GitHound`, after branches and branch protection rules have been collected and before workflows are collected.

**Why it exists:** The raw permission edges in the graph (`GH_WriteRepoContents`, `GH_PushProtectedBranch`, `GH_BypassBranchProtection`) are each necessary but not sufficient for push access. A user with `GH_WriteRepoContents` may be blocked by branch protection rules, while a user with `GH_PushProtectedBranch` only bypasses push restrictions (not PR reviews). Determining whether someone can actually push requires cross-referencing role permissions, branch protection rule settings, per-rule allowances, and `enforce_admins` state. This function performs that analysis and emits computed edges that represent verified push capability.

**Key characteristics:**

- Pure in-memory computation — no API calls
- Operates over the full accumulated node and edge collections from prior steps
- Produces only edges (no new nodes)

## Input Data

The function takes two parameters:

| Parameter | Type        | Description                                       |
|-----------|-------------|---------------------------------------------------|
| `$Nodes`  | `ArrayList` | All accumulated nodes from prior collection steps |
| `$Edges`  | `ArrayList` | All accumulated edges from prior collection steps |

The following data must exist in the collections before the function runs:

| Required Nodes | Source Step |
|---------------|------------|
| `GH_Repository` | Step 3 (Repositories) |
| `GH_RepoRole` | Step 5 (Repository Roles) |
| `GH_Branch` | Step 6 (Branches) |
| `GH_BranchProtectionRule` | Step 6 (Branches) |
| `GH_User`, `GH_Team` | Steps 1-2 (Users, Teams) |

| Required Edges | Description |
|---------------|-------------|
| `GH_HasBranch` | Repository → Branch |
| `GH_ProtectedBy` | BranchProtectionRule → Branch |
| `GH_HasBaseRole` | Role → Role (inheritance chain) |
| `GH_HasRole` | User/Team → Role (role assignment) |
| `GH_WriteRepoContents`, `GH_AdminTo`, etc. | RepoRole → Repository (permission edges) |
| `GH_RestrictionsCanPush` | User/Team → BPR (push allowance) |
| `GH_BypassPullRequestAllowances` | User/Team → BPR (PR bypass allowance) |

## Output Structure

The function returns a `PSCustomObject`:

```
{
    Nodes = []              # Empty ArrayList (no new nodes created)
    Edges = [edge, ...]     # ArrayList of computed edge objects
}
```

The computed edges are merged into the main collection at the call site:

```powershell
$branchAccess = Compute-GitHoundBranchAccess -Nodes $nodes -Edges $edges
if($branchAccess.edges) { $edges.AddRange(@($branchAccess.edges)) }
```

They become part of the final consolidated `githound_<orgId>.json` output file alongside all other edges.

### Edge Object Shape

Each computed edge follows the standard GitHound edge format (created by `New-GitHoundEdge`):

```json
{
    "kind": "GH_CanWriteBranch",
    "start": { "value": "<sourceNodeId>" },
    "end": { "value": "<targetNodeId>" },
    "properties": {
        "traversable": true,
        "reason": "admin",
        "query_composition": "MATCH p1=(:GH_RepoRole {objectid:'<ROLEID>'})-[]->(:GH_Repository)-[:GH_HasBranch]->(b:GH_Branch {objectid:'<BRANCHID>'}) OPTIONAL MATCH p2=(b)<-[:GH_ProtectedBy]-(:GH_BranchProtectionRule) RETURN p1, p2"
    }
}
```

### Edge Kinds Produced

| Edge Kind | Source | Target | Traversable | Description |
|-----------|--------|--------|-------------|-------------|
| `GH_CanCreateBranch` | `GH_RepoRole` | `GH_Repository` | Yes | Role can create new branches |
| `GH_CanCreateBranch` | `GH_User` or `GH_Team` | `GH_Repository` | Yes | Per-rule allowance delta — actor can create branches when role alone doesn't grant access |
| `GH_CanWriteBranch` | `GH_RepoRole` | `GH_Branch` | Yes | Role can push to this specific branch |
| `GH_CanWriteBranch` | `GH_User` or `GH_Team` | `GH_Branch` | Yes | Per-rule allowance delta — actor can push when role alone doesn't grant access |
| `GH_CanEditProtection` | `GH_RepoRole` | `GH_Branch` | Yes | Role can modify/remove the BPR(s) governing this branch |

Most edges emit from `GH_RepoRole`. Per-actor edges from `GH_User`/`GH_Team` are only emitted when per-rule allowances (`pushAllowances`, `bypassPullRequestAllowances`) grant access beyond what the role provides. `GH_CanEditProtection` is always role-level (it has no per-actor component).

### Reason Values

Each computed edge includes a `reason` property explaining why access was granted:

| Reason | Meaning |
|--------|---------|
| `no_protection` | No branch protection rule applies to this branch |
| `admin` | Admin access bypasses the gate |
| `push_protected_branch` | Role has `push_protected_branch` permission (bypasses push gate) |
| `bypass_branch_protection` | Role has `bypass_branch_protection` permission (bypasses merge gate) |
| `push_allowance` | Actor is in `pushAllowances` for the matching BPR |
| `bypass_pr_allowance` | Actor is in `bypassPullRequestAllowances` (bypasses PR reviews only) |
| `edit_repo_protections` | Role can modify/remove this BPR (used on `GH_CanEditProtection` edges) |

### Composition Queries

Each computed edge includes a `query_composition` property containing a Cypher query that reveals the underlying graph elements that caused the edge to be created. Running this query shows the full composition: the role's permission edges to the repository, the BPR(s) protecting the target, and any per-rule allowance edges involved.

The query varies by edge type:

| Edge Type | Source | What the query shows |
|-----------|--------|---------------------|
| `GH_CanWriteBranch` | RepoRole → Branch | Role's permission edges + BPR protecting the branch |
| `GH_CanCreateBranch` | RepoRole → Repository | Role's permission edges + wildcard BPR (if any) |
| `GH_CanEditProtection` | RepoRole → Branch | Role's edit/admin permission edge + repo's branches + protecting BPR(s) |
| `GH_CanWriteBranch` | User/Team → Branch | Actor's allowance edges to the BPR + actor's role path with permissions |
| `GH_CanCreateBranch` | User/Team → Repository | Actor's push allowance to the wildcard BPR + actor's role path |

## The Two-Gate Model

The computation evaluates two independent gates per branch. An actor must pass **both** gates to push.

### Merge Gate

Active when `required_pull_request_reviews` or `lock_branch` is true on the protecting BPR.

| Bypass Mechanism | Scope | Suppressed by `enforce_admins`? |
|-----------------|-------|-------------------------------|
| `GH_AdminTo` (admin access) | Role-level | Yes |
| `GH_BypassBranchProtection` | Role-level | Yes |
| `bypassPullRequestAllowances` | Per-actor | Yes (PR reviews only, does not bypass `lock_branch`) |

### Push Gate

Active when `push_restrictions` is true on the protecting BPR.

| Bypass Mechanism | Scope | Suppressed by `enforce_admins`? |
|-----------------|-------|-------------------------------|
| `GH_AdminTo` (admin access) | Role-level | **No** |
| `GH_PushProtectedBranch` | Role-level | **No** |
| `pushAllowances` | Per-actor | **No** |

The asymmetry is critical: `enforce_admins` only suppresses merge-gate bypasses. Admin users and users with `push_protected_branch` can always bypass push restrictions regardless of `enforce_admins`.

## Algorithm Walkthrough

### Phase 1: Index Building

Constructs lookup structures from the raw node and edge collections for O(1) access during evaluation.

**Node and edge indexes:**

| Index | Key | Value | Purpose |
|-------|-----|-------|---------|
| `$nodeById` | node ID | node object | Look up any node by ID |
| `$outbound` | `"edgeKind\|startId"` | list of end IDs | Follow edges forward |
| `$inbound` | `"edgeKind\|endId"` | list of start IDs | Follow edges backward |

**Domain-specific indexes:**

| Index | Key | Value | Purpose |
|-------|-----|-------|---------|
| `$repoBranches` | repo ID | list of branch IDs | Enumerate branches per repo |
| `$branchToBPR` | branch ID | BPR ID | Find protecting rule for a branch |
| `$bprToRepo` | BPR ID | repo ID | Find which repo a BPR belongs to |
| `$rolePermissions` | role ID | HashSet of permission edge kinds | Direct permissions per role |
| `$pushAllowanceActors` | BPR ID | HashSet of actor IDs | Actors with push allowance per rule |
| `$bypassPRActors` | BPR ID | HashSet of actor IDs | Actors with PR bypass per rule |
| `$repoBPRs` | repo ID | list of BPR IDs | All BPRs per repo |
| `$repoIds` | — | list of repo IDs | All repositories |

### Phase 2: Role Permission Resolution

Builds full permission sets for all roles by traversing the `GH_HasBaseRole` inheritance chain.

**`Get-BaseRolePerms`** performs a forward-transitive closure: given a role, follows outbound `GH_HasBaseRole` edges to collect all inherited permissions. For example:

| Role | Direct Permissions | Inherited Permissions | Full Permission Set |
|------|-------------------|----------------------|-------------------|
| `repoAdmin` | `{GH_AdminTo, GH_PushProtectedBranch, GH_BypassBranchProtection}` | (none — no HasBaseRole to other leaf roles) | `{GH_AdminTo, GH_PushProtectedBranch, GH_BypassBranchProtection}` |
| `repoMaintain` | `{GH_PushProtectedBranch}` | `{GH_WriteRepoContents}` (from write via HasBaseRole) | `{GH_PushProtectedBranch, GH_WriteRepoContents}` |
| `repoWrite` | `{GH_WriteRepoContents}` | (none) | `{GH_WriteRepoContents}` |
| Custom role (base=write) | `{GH_BypassBranchProtection}` | `{GH_WriteRepoContents}` (from write via HasBaseRole) | `{GH_BypassBranchProtection, GH_WriteRepoContents}` |

**Data structures built:**

| Structure | Key | Value | Purpose |
|-----------|-----|-------|---------|
| `$roleFullPerms` | role ID | HashSet of all permission edge kinds | Complete permission set for gate evaluation |
| `$repoWriteRoles` | repo ID | list of role IDs | Roles with write access (have `GH_WriteRepoContents` or `GH_AdminTo`) |
| `$actorRepoRoles` | `[repoId][actorId]` | HashSet of leaf role IDs | Maps each actor to the leaf RepoRole(s) they reach |

**Building `$actorRepoRoles`:** For each leaf role with direct permission edges, `Get-InheritingRoles` (reverse-transitive closure of `GH_HasBaseRole`) finds all parent roles that eventually inherit from it. For each role in that closure, actors with `GH_HasRole` edges are mapped to the leaf role. This tells us which leaf RepoRole(s) each actor effectively reaches on a given repo.

### Phase 3a: Role-Level Edge Emission

For each repository and each write-capable role on that repo, evaluates whether the role's permissions alone are sufficient to bypass branch protection.

#### GH_CanEditProtection

If the role has `GH_EditRepoProtections` or `GH_AdminTo`, emit an edge from the role to each protected branch on the repo. These edges are traversable — they represent the ability to weaken or remove the branch protection rules governing a specific branch, enabling subsequent code push.

#### GH_CanCreateBranch

Evaluates whether the role can create new branches. This requires checking for a wildcard (`*`) BPR with both `push_restrictions` and `blocks_creations` enabled:

- **No wildcard blocking BPR** → emit `role → repo` (reason: `no_protection`)
- **Wildcard BPR exists + role has admin** → emit `role → repo` (reason: `admin`)
- **Wildcard BPR exists + role has `push_protected_branch`** → emit `role → repo` (reason: `push_protected_branch`)
- **Otherwise** → no edge (role cannot create branches)

#### GH_CanWriteBranch

Calls `Invoke-RoleGateEvaluation` to evaluate the merge gate and push gate for each branch using only the role's permissions (no per-actor allowances). This helper iterates every branch in the repo:

1. Look up the protecting BPR (if any)
2. Evaluate the merge gate — blocked unless bypassed by admin or `bypass_branch_protection` (both suppressed by `enforce_admins`)
3. Evaluate the push gate — blocked unless bypassed by admin or `push_protected_branch` (neither affected by `enforce_admins`)
4. Branch is accessible only if both gates pass

**Edge emission logic:**
- **One or more branches accessible** → per-branch edges `role → branch`
- **No branches accessible** → no edges

The function tracks `$roleAccessibleBranches[roleId]` and `$roleCanCreate[roleId]` for use in Phase 3b.

### Phase 3b: Per-Actor Allowance Delta

Per-rule allowances (`pushAllowances`, `bypassPullRequestAllowances`) are actor-specific — they grant access to individual users or teams, not to roles. This phase computes the **delta**: branches an actor can access via allowances that their role alone doesn't cover.

For each repository, the function collects all actors who appear in any per-rule allowance on any BPR for that repo. For each such actor:

1. **Compute covered branches:** Union of `$roleAccessibleBranches` across all leaf roles the actor reaches. These branches are already covered by role-level edges — no per-actor edges needed.

2. **Prerequisite check:** The actor must have write access (via their role) to the repo. Allowances don't grant write access — they only modify which branches a writer can push to.

3. **GH_CanCreateBranch delta:** If a wildcard blocking BPR exists and the actor's role doesn't grant `GH_CanCreateBranch`, check if the actor is in `pushAllowances` for the wildcard BPR. If so, emit `actor → repo` (reason: `push_allowance`).

4. **GH_CanWriteBranch delta:** For each branch not covered by the actor's role:
   - Re-evaluate the merge gate considering the actor's `bypassPullRequestAllowances` membership (only bypasses PR reviews, not `lock_branch`; suppressed by `enforce_admins`)
   - Re-evaluate the push gate considering the actor's `pushAllowances` membership
   - If both gates pass, emit `actor → branch`

Only unprotected branches are skipped during delta evaluation (they are always covered at the role level since any write role passes both gates when no BPR exists).

## Edge Deduplication

The `Add-ComputedEdge` helper maintains an `$emittedEdges` hashtable keyed by `"startId|endId|kind"`. If an edge with the same key already exists, the duplicate is silently skipped. This prevents redundant edges when multiple code paths could emit the same edge.

## Graph Traversal Paths

Because edges primarily emit from `GH_RepoRole`, queries must traverse through the role chain. The following paths are all valid:

**Role-level (common case):**
```
User → GH_HasRole → RepoRole → GH_CanWriteBranch → Branch
User → GH_HasRole → OrgRole → GH_HasBaseRole → ... → RepoRole → GH_CanWriteBranch → Branch
User → GH_HasRole → TeamRole → GH_MemberOf → Team → GH_HasRole → RepoRole → GH_CanWriteBranch → Branch
```

**Per-actor allowance delta:**
```
User → GH_CanWriteBranch → Branch
User → GH_HasRole → TeamRole → GH_MemberOf → Team → GH_CanWriteBranch → Branch
```

Cypher queries use OPTIONAL MATCH to cover both cases:

```cypher
MATCH p1=(:GH_User)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_CanWriteBranch]->(:GH_Branch)
OPTIONAL MATCH p2=(:GH_User)-[:GH_CanWriteBranch]->(:GH_Branch)
OPTIONAL MATCH p3=(:GH_User)-[:GH_HasRole|GH_MemberOf|GH_AddMember*1..]->(:GH_Team)-[:GH_CanWriteBranch]->(:GH_Branch)
RETURN p1, p2, p3
```

## Helper Functions

| Function | Purpose | Input | Output |
|----------|---------|-------|--------|
| `Get-InheritingRoles` | Reverse-transitive closure of `GH_HasBaseRole` — finds all roles that inherit from a given role | Role ID, visited set | Array of role IDs (including the root) |
| `Get-BaseRolePerms` | Forward-transitive closure of `GH_HasBaseRole` — collects all permissions a role has (direct + inherited) | Role ID, visited set | Array of permission edge kinds |
| `Invoke-RoleGateEvaluation` | Evaluates merge gate + push gate for all branches given a permission set (role-level only, no per-actor allowances) | Permission HashSet, branch list, branch-to-BPR map | `@{ accessible = [branchIds]; reasons = @{ branchId = reason } }` |
| `Test-BPRProperty` | Converts BPR boolean properties to PowerShell booleans (handles both `[bool]` and `[string]` after `Normalize-Null`) | Property value | Boolean |
| `Add-ComputedEdge` | Creates a computed edge with deduplication via `$emittedEdges` hashtable | Kind, StartId, EndId, Properties | (void — appends to `$computedEdges`) |

## Separation of Concerns

`GH_CanWriteBranch` and `GH_CanCreateBranch` represent **direct** push capability — they confirm the actor can push by evaluating both gates for each branch. These edges are traversable.

`GH_CanEditProtection` represents the ability to weaken or remove the branch protection rules governing a specific branch. It is traversable because a role that can modify protections on a branch can subsequently push code to it — representing a privilege escalation path. The edge targets the protected branch (not the BPR itself) because the security impact is evaluated per-branch.

---

# Computed Secret Scanning Access Edges

This section describes how the `Compute-GitHoundSecretScanningAccess` function works and what it produces.

## Overview

`Compute-GitHoundSecretScanningAccess` is a post-collection step that computes effective secret scanning alert read access. It runs as **Step 11.5** in `Invoke-GitHound`, after secret scanning alerts have been collected and before app installations are collected.

**Why it exists:** The raw `GH_ViewSecretScanningAlerts` permission edges connect roles to organizations or repositories, but do not connect roles directly to the individual alert nodes. Without computed edges, BloodHound pathfinding cannot traverse from a role to the alert (and onward via `GH_ValidToken` to the compromised user identity). This function bridges that gap by resolving which specific alerts each role can read.

**Key characteristics:**

- Pure in-memory computation — no API calls
- Operates over the full accumulated node and edge collections from prior steps
- Produces only edges (no new nodes)
- Simpler than branch access computation — no gate evaluation needed

## Input Data

The function takes two parameters:

| Parameter | Type        | Description                                       |
|-----------|-------------|---------------------------------------------------|
| `$Nodes`  | `ArrayList` | All accumulated nodes from prior collection steps |
| `$Edges`  | `ArrayList` | All accumulated edges from prior collection steps |

The following data must exist in the collections before the function runs:

| Required Nodes | Source Step |
|---------------|------------|
| `GH_SecretScanningAlert` | Step 11 (Secret Scanning Alerts) |
| `GH_Organization` | Step 0 (Organization) |
| `GH_Repository` | Step 3 (Repositories) |
| `GH_OrgRole` | Step 0 (Organization) |
| `GH_RepoRole` | Step 5 (Repository Roles) |

| Required Edges | Description |
|---------------|-------------|
| `GH_ViewSecretScanningAlerts` | OrgRole → Organization or RepoRole → Repository |
| `GH_Contains` | Organization → SecretScanningAlert |
| `GH_HasSecretScanningAlert` | Repository → SecretScanningAlert |

## Output Structure

The function returns a `PSCustomObject`:

```
{
    Nodes = []              # Empty ArrayList (no new nodes created)
    Edges = [edge, ...]     # ArrayList of computed edge objects
}
```

The computed edges are merged into the main collection at the call site:

```powershell
$secretScanningAccess = Compute-GitHoundSecretScanningAccess -Nodes $nodes -Edges $edges
if($secretScanningAccess.edges) { $edges.AddRange(@($secretScanningAccess.edges)) }
```

### Edge Kind Produced

| Edge Kind | Source | Target | Traversable | Description |
|-----------|--------|--------|-------------|-------------|
| `GH_CanReadSecretScanningAlert` | `GH_OrgRole` | `GH_SecretScanningAlert` | Yes | Org role can read all alerts in the organization |
| `GH_CanReadSecretScanningAlert` | `GH_RepoRole` | `GH_SecretScanningAlert` | Yes | Repo role can read alerts in the repository |

### Reason Values

| Reason | Meaning |
|--------|---------|
| `org_role_permission` | Org role has `GH_ViewSecretScanningAlerts` on the organization containing the alert |
| `repo_role_permission` | Repo role has `GH_ViewSecretScanningAlerts` on the repository containing the alert |

### Composition Queries

Each computed edge includes a `query_composition` property containing a Cypher query that reveals the underlying graph elements:

| Source Type | What the query shows |
|-------------|---------------------|
| `GH_OrgRole` → Alert | Role's `GH_ViewSecretScanningAlerts` edge to organization + organization's `GH_Contains` edge to alert |
| `GH_RepoRole` → Alert | Role's `GH_ViewSecretScanningAlerts` edge to repository + repository's `GH_HasSecretScanningAlert` edge to alert |

## Algorithm Walkthrough

### Phase 1: Index Building

Constructs lookup structures from the raw node and edge collections.

**Node index:**

| Index | Key | Value | Purpose |
|-------|-----|-------|---------|
| `$nodeById` | node ID | node object | Look up any node by ID (used to determine target kind of `GH_ViewSecretScanningAlerts` edges) |

**Alert indexes:**

| Index | Key | Value | Purpose |
|-------|-----|-------|---------|
| `$alertNodeIds` | — | HashSet of alert IDs | Validate that a `GH_Contains` target is actually a `GH_SecretScanningAlert` |
| `$orgAlerts` | org ID | list of alert IDs | All alerts contained in each organization |
| `$repoAlerts` | repo ID | list of alert IDs | All alerts associated with each repository |

**Permission edge partitioning:**

`GH_ViewSecretScanningAlerts` edges are split into two lists based on the target node's kind:
- `$orgViewEdges`: target is `GH_Organization` (source is `GH_OrgRole`)
- `$repoViewEdges`: target is `GH_Repository` (source is `GH_RepoRole`)

### Phase 2: Org-Level Emission

For each `GH_ViewSecretScanningAlerts` edge targeting a `GH_Organization`:

1. Get the source role ID and target org ID
2. Look up all alerts in that org via `$orgAlerts[orgId]`
3. For each alert: emit `GH_CanReadSecretScanningAlert` from the org role to the alert
4. Reason: `org_role_permission`

### Phase 3: Repo-Level Emission

For each `GH_ViewSecretScanningAlerts` edge targeting a `GH_Repository`:

1. Get the source role ID and target repo ID
2. Look up all alerts in that repo via `$repoAlerts[repoId]`
3. For each alert: emit `GH_CanReadSecretScanningAlert` from the repo role to the alert
4. Reason: `repo_role_permission`

## Edge Deduplication

Uses the same `Add-ComputedEdge` helper pattern as `Compute-GitHoundBranchAccess`. An `$emittedEdges` hashtable keyed by `"startId|endId|kind"` prevents duplicate edges when multiple code paths could emit the same edge.

## Graph Traversal Paths

The complete attack path from user to compromised identity:

**Via org role:**
```
User → GH_HasRole → OrgRole → GH_CanReadSecretScanningAlert → SecretScanningAlert → GH_ValidToken → CompromisedUser
```

**Via repo role (through org):**
```
User → GH_HasRole → OrgRole → GH_HasBaseRole → RepoRole → GH_CanReadSecretScanningAlert → SecretScanningAlert → GH_ValidToken → CompromisedUser
```

**Via repo role (direct):**
```
User → GH_HasRole → RepoRole → GH_CanReadSecretScanningAlert → SecretScanningAlert → GH_ValidToken → CompromisedUser
```

**Via team:**
```
User → GH_HasRole → TeamRole → GH_MemberOf → Team → GH_HasRole → RepoRole → GH_CanReadSecretScanningAlert → SecretScanningAlert → GH_ValidToken → CompromisedUser
```

## Security Significance

This edge completes a critical attack path: an actor who can view secret scanning alerts gains access to the raw leaked secret values. When the leaked secret is a valid GitHub Personal Access Token (detected by the `GH_ValidToken` edge), the actor can impersonate the token owner and exercise all permissions granted to that token. This makes `GH_CanReadSecretScanningAlert` a traversable edge — it represents a real privilege escalation path from "can view alerts" to "can act as the token owner."
