# Mitigating Controls: Branch Protection & Attack Path Analysis

This document provides empirically verified analysis of how GitHub branch protection rules interact with two key attack paths in the GitHound model. All findings were validated through systematic testing against live GitHub repositories.

## Attack Paths

### 1. Secret Exfiltration via Workflow Creation

A user with write access (`GH_WriteRepoContents`) to a repository can:

1. Create a **new branch** in the repository
2. Push a **workflow file** (`.github/workflows/*.yml`) to that branch with `on: push` trigger
3. The workflow executes automatically on push
4. The workflow can access **all repo-level and org-level secrets** (`GH_HasSecret`) available to the repository
5. The workflow exfiltrates the secrets (e.g., via HTTP request to an attacker-controlled server)

**Graph path:** `(:GH_User)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_WriteRepoContents]->(repo:GH_Repository)-[:GH_HasSecret]->(:GH_RepoSecret|:GH_OrgSecret)`

PR reviews do **not** prevent this attack because they only gate merging, not pushing to new branches. The attacker never needs to merge anything.

### 2. Supply Chain Attack via Direct Push

A user with write access to a repository can push directly to the default branch (e.g., `main`, `master`), injecting a backdoor into released software.

**Graph path:** `(:GH_User)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_WriteRepoContents]->(repo:GH_Repository)`

## Branch Protection Settings

The following branch protection rule settings are relevant to these attack paths:

| Setting | GraphQL Field | BPR Property | Effect |
|---------|--------------|--------------|--------|
| Require PR reviews | `requiresApprovingReviews` | `required_pull_request_reviews` | Blocks direct pushes to **existing** protected branches (merge-gate control) |
| Restrict pushes | `restrictsPushes` | `push_restrictions` | Restricts who can push to matching branches (push-gate control) |
| Block creations | `blocksCreations` | `blocks_creations` | Restricts creation of new branches matching the pattern. **Requires `push_restrictions` to be enabled**; silently reverts to `false` otherwise |
| Lock branch | `lockBranch` | `lock_branch` | Makes the branch completely read-only (merge-gate control) |
| Enforce for admins | `isAdminEnforced` | `enforce_admins` | Enforces merge-gate controls for admins and users with `bypass_branch_protection` |
| Allow force pushes | `allowsForcePushes` | `allows_force_pushes` | Controls whether force pushes are allowed; does **not** grant push access |

### Merge-Gate vs. Push-Gate Controls

Branch protection settings fall into two distinct categories based on *what they control* and *how they can be bypassed*. This distinction is critical because each category has a completely different set of bypass mechanisms, and `enforce_admins` only affects one category.

**Merge-gate controls** govern whether changes can be merged or committed to a protected branch. They enforce code review and read-only policies:

| Setting | Property | What it blocks |
|---------|----------|---------------|
| Require PR reviews | `required_pull_request_reviews` | Direct pushes to existing protected branches — forces changes through pull requests |
| Lock branch | `lock_branch` | All changes to the branch — makes it completely read-only |

Merge-gate controls are bypassed by `bypass_branch_protection` and `bypassPullRequestAllowances`. They **are** enforced by `enforce_admins`.

**Push-gate controls** govern *who is authorized* to push to matching branches. They are an access control layer that restricts push operations to an explicit allowlist:

| Setting | Property | What it blocks |
|---------|----------|---------------|
| Restrict pushes | `push_restrictions` | Pushes from anyone not in the `pushAllowances` list |
| Block creations | `blocks_creations` | Creation of new branches matching the pattern (requires `push_restrictions`) |

Push-gate controls are bypassed by `push_protected_branch`, admin access, and `pushAllowances`. They are **NOT** enforced by `enforce_admins`.

**Why this matters:** A common misconfiguration is enabling `enforce_admins` and assuming all protections are enforced. In reality, `enforce_admins` only enforces merge-gate controls. Admin users and users with `push_protected_branch` can still bypass push restrictions regardless of the `enforce_admins` setting.

### Setting Dependencies

- `blocks_creations` requires `push_restrictions` to be `true`. If `push_restrictions` is `false`, the GitHub API accepts the mutation but silently reverts `blocks_creations` to `false`.
- `allows_force_pushes` only controls whether history rewrites are permitted. It does not bypass any access controls (`lock_branch`, `push_restrictions`, etc.).

## Bypass Mechanisms

There are seven mechanisms that can bypass branch protection rules. They fall into two categories based on which type of control they bypass.

### Merge-Gate Bypasses

These bypass controls that gate merging and read-only status (PR reviews, lock branch):

| Mechanism | Scope | Edge/Property | Blocked by `enforce_admins`? |
|-----------|-------|---------------|------------------------------|
| `bypass_branch_protection` permission | Repo-wide (via custom role) | `GH_BypassBranchProtection` (RepoRole -> Repository) | **Yes** |
| `bypassPullRequestAllowances` | Per-rule (specific users/teams) | `GH_BypassPullRequestAllowances` (User/Team -> BPR) | Not tested (likely yes) |

**Important:** `bypassPullRequestAllowances` is **narrower** than `bypass_branch_protection`. It only bypasses PR review requirements, not lock branch. The repo-wide permission bypasses both.

### Push-Gate Bypasses

These bypass controls that restrict who can push (`push_restrictions`, `blocks_creations`):

| Mechanism | Scope | Edge/Property | Blocked by `enforce_admins`? |
|-----------|-------|---------------|------------------------------|
| `push_protected_branch` permission | Repo-wide (via custom role) | `GH_PushProtectedBranch` (RepoRole -> Repository) | **No** |
| Admin access | Repo-wide (built-in role) | `GH_AdminTo` (RepoRole -> Repository) | **No** |
| `pushAllowances` | Per-rule (specific users/teams) | `GH_RestrictionsCanPush` (User/Team -> BPR) | Not tested (likely no) |

### Other Bypasses

| Mechanism | Effect | Edge |
|-----------|--------|------|
| `edit_repo_protections` permission | Can remove/modify protection rules entirely, then push | `GH_EditRepoProtections` (RepoRole -> Repository) |

## Complete Test Results

### Test Series 1: New Branch Creation (Secret Exfiltration Path)

Can a user with write access create a new branch and push a workflow?

| Test | PR Reviews | Push Restrictions | Blocks Creations (`*`) | Result |
|------|:---:|:---:|:---:|--------|
| 1 | On | Off | Off | **Succeeded** - new branch created |
| 2 | On | On | Off | **Succeeded** - new branch created |
| 3 | On | On | On | **Blocked** |
| 4 | Off | On | On | **Blocked** |
| 5 | Off | Off | On (silently ignored) | **Succeeded** - `blocks_creations` reverted to `false` |

**Conclusion:** The **only** branch protection configuration that blocks the secret exfiltration attack is `push_restrictions` + `blocks_creations` on a `*` pattern rule.

### Test Series 2: Push to Existing Protected Branch (Supply Chain Path)

Can a user with write access push directly to `master`?

| Test | Protection Config | Result | Error Message |
|------|-------------------|--------|---------------|
| 1 | PR reviews only | **Blocked** | "Changes must be made through a pull request" |
| 2 | Push restrictions (user NOT in allowances) | **Blocked** | "You're not authorized to push" |
| 3 | Push restrictions (user IN allowances) | **Succeeded** | - |
| 4 | Lock branch | **Blocked** | "Cannot change this locked branch" |

**Conclusion:** Any one of PR reviews, push restrictions (without allowance), or lock branch is sufficient to block direct pushes to an existing protected branch.

### Test Series 3: `bypass_branch_protection` Permission

| Test | Protection Config | Result |
|------|-------------------|--------|
| 3.1 | PR reviews | **Bypassed** ("Bypassed rule violations") |
| 3.2 | Push restrictions (not in allowances) | **Blocked** ("You're not authorized to push") |
| 3.3 | Lock branch | **Bypassed** ("Bypassed rule violations") |
| 3.4 | Push restrictions + blocks creations (`*`) | **Blocked** ("You're not authorized to push") |

**Conclusion:** `bypass_branch_protection` bypasses merge-gate controls (PR reviews, lock branch) but NOT push-gate controls (`push_restrictions`).

### Test Series 4: `push_protected_branch` Permission

| Test | Protection Config | Result |
|------|-------------------|--------|
| 4.1 | PR reviews | **Blocked** ("Changes must be made through a pull request") |
| 4.2 | Push restrictions (not in allowances) | **Bypassed** |
| 4.3 | Lock branch | **Blocked** ("Cannot change this locked branch") |
| 4.4 | Push restrictions + blocks creations (`*`) | **Bypassed** (new branch created) |

**Conclusion:** `push_protected_branch` bypasses push-gate controls (`push_restrictions`, `blocks_creations`) but NOT merge-gate controls (PR reviews, lock branch). It is the **exact complement** of `bypass_branch_protection`.

### Test Series 5: `enforce_admins` Interaction

| Test | Protection | Actor | Result |
|------|-----------|-------|--------|
| 5.1 | PR reviews | `bypass_branch_protection` | **Blocked** (enforce_admins suppresses bypass) |
| 5.2 | Lock branch | `bypass_branch_protection` | **Blocked** (enforce_admins suppresses bypass) |
| 5.3 | Push restrictions | `push_protected_branch` | **Bypassed** (enforce_admins has no effect) |
| 5.4 | Push restrictions + blocks creations (`*`) | Admin (enforce_admins OFF) | **Bypassed** |
| 5.5 | Push restrictions + blocks creations (`*`) | Admin (enforce_admins ON) | **Bypassed** (enforce_admins has no effect) |

**Conclusion:** `enforce_admins` only enforces merge-gate controls. It suppresses `bypass_branch_protection` but has **no effect** on `push_protected_branch` or admin push access. Push restrictions are a separate access control layer.

### Test Series 6: `allows_force_pushes`

| Test | Protection Config | Result |
|------|-------------------|--------|
| 6.1 | Lock branch + force push allowed | **Blocked** ("Cannot change this locked branch") |
| 6.2 | Push restrictions + force push allowed | **Blocked** ("You're not authorized to push") |

**Conclusion:** `allows_force_pushes` is not a bypass mechanism. It only controls whether force pushes (history rewrites) are permitted for users who already have push access.

### Test Series 7: Both Permissions Combined

User with both `bypass_branch_protection` and `push_protected_branch`:

| Test | Protection Config | Result |
|------|-------------------|--------|
| 7.1 | PR reviews | **Bypassed** |
| 7.2 | Push restrictions | **Bypassed** |
| 7.3 | Lock branch | **Bypassed** |
| 7.4 | Push restrictions + blocks creations (`*`) | **Bypassed** (new branch created) |

**Conclusion:** Both permissions combined provide full bypass capability, equivalent to admin access.

### Test Series 8: `bypassPullRequestAllowances` (Per-Rule Edge)

User in `bypassPullRequestAllowances` list (regular write access, no custom role):

| Test | Protection Config | Result |
|------|-------------------|--------|
| 8.1 | PR reviews | **Bypassed** ("Bypassed rule violations") |
| 8.2 | Lock branch | **Blocked** ("Cannot change this locked branch") |

**Conclusion:** `bypassPullRequestAllowances` is narrower than the `bypass_branch_protection` permission. It only bypasses PR review requirements, not lock branch.

## Summary Matrix

| Protection | Regular Write | `bypass_branch_protection` | `push_protected_branch` | Both | Admin | `bypassPRAllowances` | `pushAllowances` |
|-----------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| PR reviews | Blocked | **Bypassed** | Blocked | **Bypassed** | N/T | **Bypassed** | N/T |
| Push restrictions | Blocked | Blocked | **Bypassed** | **Bypassed** | **Bypassed** | N/T | **Bypassed** |
| Lock branch | Blocked | **Bypassed** | Blocked | **Bypassed** | N/T | Blocked | N/T |
| Blocks creations (`*`) | Blocked | Blocked | **Bypassed** | **Bypassed** | **Bypassed** | N/T | N/T |
| **enforce_admins effect** | - | **Suppressed** | **No effect** | - | **No effect** | N/T | N/T |

N/T = Not tested (not applicable to that control type)

## Effective Mitigating Controls

### For Secret Exfiltration (Write -> New Branch -> Workflow -> Secrets)

The attack requires creating a new branch. This is only blocked when **all** of the following are true:

1. A `GH_BranchProtectionRule` exists with `pattern` = `*`
2. `push_restrictions` = `true`
3. `blocks_creations` = `true`

**However**, even with this control in place, the following actors can still exfiltrate secrets:

- Users with `push_protected_branch` permission (`GH_PushProtectedBranch`)
- Users with admin access (`GH_AdminTo`) -- **cannot** be mitigated by `enforce_admins`
- Users in `pushAllowances` for the `*` rule (`GH_RestrictionsCanPush`)
- Users with `edit_repo_protections` permission (`GH_EditRepoProtections`) -- can remove the rule
- Users with both `bypass_branch_protection` and `push_protected_branch`

### For Supply Chain Attack (Write -> Push to Default Branch)

Any **one** of the following protections is sufficient to block direct pushes to an existing branch:

- `required_pull_request_reviews` = `true`
- `push_restrictions` = `true` (and attacker not in `pushAllowances`)
- `lock_branch` = `true`

**Bypass vectors per protection type:**

| Protection | Bypassed by |
|-----------|-------------|
| PR reviews | `bypass_branch_protection`, `bypassPullRequestAllowances` (both blocked by `enforce_admins`) |
| Push restrictions | `push_protected_branch`, admin, `pushAllowances` (none blocked by `enforce_admins`) |
| Lock branch | `bypass_branch_protection` (blocked by `enforce_admins`) |

## Computed Branch Access Edges

The analysis above is complex — determining whether a user can actually push to a branch requires cross-referencing role permissions, branch protection rule settings, per-rule allowances, and `enforce_admins` state. GitHound encodes this analysis into computed edges that represent effective access, emitted by the `Compute-GitHoundBranchAccess` post-collection step.

### Edge Kinds

| Edge | Source | Target | Traversable | What it represents |
|------|--------|--------|-------------|-------------------|
| `GH_CanCreateBranch` | RepoRole | Repository | Yes | Role can create new branches (enables secret exfiltration via workflow creation) |
| `GH_CanCreateBranch` | User/Team | Repository | Yes | Per-rule allowance delta — user/team can create branches when role alone doesn't grant access |
| `GH_CanWriteBranch` | RepoRole | Branch | Yes | Role can push to this specific branch |
| `GH_CanWriteBranch` | User/Team | Branch | Yes | Per-rule allowance delta — user/team can push when role alone doesn't grant access |
| `GH_CanEditProtection` | RepoRole | BPR | No | Role can modify/remove this branch protection rule (indirect bypass) |

**Separation of concerns:** `GH_CanWriteBranch` and `GH_CanCreateBranch` represent **direct** push capability only — they evaluate the merge-gate and push-gate for each branch. `GH_CanEditProtection` represents the ability to weaken or remove protections — a separate indirect bypass path. An analyst combines these visually: "this user can edit this BPR, which protects these branches, and the user also has write access."

### How the Computation Works

The computation operates in two phases: **role-level evaluation** and **per-actor allowance delta**.

**Phase 1: Role-level evaluation.** For each repo role with write access, the computation builds a full permission set (direct permissions plus inherited via `GH_HasBaseRole`), then evaluates two independent gates per branch:

**Merge gate** (active when `required_pull_request_reviews` or `lock_branch` is true):
- Bypassed by admin access (unless `enforce_admins`)
- Bypassed by `bypass_branch_protection` permission (unless `enforce_admins`)

**Push gate** (active when `push_restrictions` is true):
- Bypassed by admin access (NOT affected by `enforce_admins`)
- Bypassed by `push_protected_branch` permission (NOT affected by `enforce_admins`)

A role can push to a branch only if it passes **both** gates. For each accessible branch, a `GH_CanWriteBranch` edge is emitted from the role to the branch. Since users reach roles via traversable `GH_HasRole` and `GH_HasBaseRole` edges, paths flow through the role chain to each individual branch.

**Phase 2: Per-actor allowance delta.** Per-rule allowances (`pushAllowances`, `bypassPullRequestAllowances`) are actor-specific — they grant access to individual users or teams, not to roles. For actors listed in these allowances, the computation identifies branches the actor's role(s) already cover, then evaluates only the uncovered branches considering the actor's allowance memberships. Edges are emitted from the user/team directly to the branch only for the delta — branches the role alone doesn't grant access to.

### Relationship to Raw Permission Edges

The raw permission edges remain in the graph for detailed analysis:

| Raw Edge | Traversable | Why not traversable |
|----------|-------------|-------------------|
| `GH_WriteRepoContents` | No | Necessary but not sufficient — BPR may block push |
| `GH_PushProtectedBranch` | No | Bypasses push-gate only — merge-gate may still block |
| `GH_BypassBranchProtection` | No | Bypasses merge-gate only — push-gate may still block |

The computed edges (`GH_CanCreateBranch`, `GH_CanWriteBranch`) are **traversable** because they represent verified push capability after evaluating all gates and bypass mechanisms.

## Saved Queries

### Repos Vulnerable to Workflow Secret Exfiltration

File: `saved-queries/repos-vulnerable-to-workflow-secret-exfil.json`

Uses the computed `GH_CanCreateBranch` edge to find users who can create branches and reach secrets. This is more precise than the raw permission query because it accounts for branch protection rules and bypass mechanisms.

### Secrets Reachable by User

File: `saved-queries/secrets-reachable-by-user.json`

Shows all write -> secret paths regardless of mitigating controls. Useful for understanding total exposure.

## Testing Methodology

All findings in this document were empirically validated against a live GitHub repository. This section describes the test environment and process so that results can be independently reproduced.

### Test Environment

- **Organization:** A GitHub Enterprise Cloud organization with custom repository roles enabled
- **Repository:** A test repository with a single default branch (`master`) and GitHub Actions enabled
- **Machine user:** A separate GitHub account added as a collaborator, used to simulate an attacker with various permission levels
- **Admin user:** The repository owner's account, used to configure branch protection rules and assign roles via the GitHub API

### Setting Up the Machine User

The machine user is a separate GitHub account that represents the "attacker" in each test. All push operations must authenticate as this user so that GitHub evaluates permissions against their role, not the admin's.

**1. Create a Personal Access Token (PAT) for the machine user:**

Log into GitHub as the machine user and create a fine-grained PAT with the following repository permissions:
- **Actions**: Read and write (required for workflow execution)
- **Contents**: Read and write (required for pushing code)
- **Workflows**: Read and write (required for creating/modifying workflow files in `.github/workflows/`)

**2. Clone the test repository using the machine user's credentials:**

```bash
mkdir /tmp/bp-test && cd /tmp/bp-test
git clone https://<MACHINE_USERNAME>:<PAT>@github.com/<ORG>/<REPO>.git .
```

Embedding the PAT in the clone URL ensures all subsequent `git push` operations authenticate as the machine user. Alternatively, you can configure the credential for just this repo:

```bash
git clone https://github.com/<ORG>/<REPO>.git /tmp/bp-test
cd /tmp/bp-test
git remote set-url origin https://<MACHINE_USERNAME>:<PAT>@github.com/<ORG>/<REPO>.git
```

**3. Add the machine user as a collaborator:**

From the admin user's terminal (authenticated via `gh`):

```bash
gh api -X PUT /repos/<ORG>/<REPO>/collaborators/<MACHINE_USERNAME> \
  -f permission=push
```

The machine user must accept the invitation (via GitHub UI or API) before they can push.

**4. Verify authentication:**

From the machine user's clone, confirm which account is pushing:

```bash
cd /tmp/bp-test
echo "auth-test" >> test.txt
git add test.txt && git commit -m "verify auth"
git push origin master
```

Check the commit on GitHub — the author should show the machine user's account. If the push succeeds when you expect it to (with only `push`/write permission and no branch protection), the setup is correct.

**Important:** All `gh api` commands (for configuring branch protection rules and assigning roles) run as the **admin user** via the `gh` CLI. Only `git push` operations run as the **machine user** via the PAT-authenticated clone. This separation ensures the admin configures the test and the machine user exercises the permission being tested.

### Test Process

Each test follows a three-step pattern: **configure**, **attempt**, **observe**.

#### Step 1: Configure the Branch Protection Rule

Use the GitHub GraphQL API to set the desired branch protection state. For example, to enable PR reviews only on `master`:

```bash
gh api graphql -f query='
mutation {
  updateBranchProtectionRule(input: {
    branchProtectionRuleId: "<BPR_ID>"
    requiresApprovingReviews: true
    restrictsPushes: false
    lockBranch: false
    isAdminEnforced: false
    pushActorIds: []
  }) {
    branchProtectionRule {
      id pattern requiresApprovingReviews restrictsPushes lockBranch isAdminEnforced
    }
  }
}'
```

To create a `*` pattern rule for testing new branch creation controls:

```bash
gh api graphql -f query='
mutation {
  createBranchProtectionRule(input: {
    repositoryId: "<REPO_ID>"
    pattern: "*"
    restrictsPushes: true
    blocksCreations: true
    requiresApprovingReviews: false
    pushActorIds: []
  }) {
    branchProtectionRule { id pattern restrictsPushes blocksCreations }
  }
}'
```

Always verify the returned fields to confirm settings took effect — especially `blocksCreations`, which silently reverts to `false` if `restrictsPushes` is not also `true`.

#### Step 2: Assign the Appropriate Role to the Machine User

For testing custom role permissions, assign a custom repository role via the REST API:

```bash
gh api -X PUT /repos/<ORG>/<REPO>/collaborators/<USERNAME> \
  -f permission=<ROLE_NAME>
```

For testing built-in roles, use standard permission names (`push` for write, `admin` for admin):

```bash
gh api -X PUT /repos/<ORG>/<REPO>/collaborators/<USERNAME> \
  -f permission=push
```

Custom roles used in testing were created with isolated permissions to test each capability independently:

| Role Name | Base Role | Permissions | Purpose |
|-----------|-----------|-------------|---------|
| CanBypassProtections | write | `bypass_branch_protection` | Test merge-gate bypass in isolation |
| CanPushProtected | write | `push_protected_branch` | Test push-gate bypass in isolation |
| CanBypassAndPush | write | `bypass_branch_protection`, `push_protected_branch` | Test both permissions combined |

#### Step 3: Attempt the Push as the Machine User

For testing pushes to an existing branch, authenticate as the machine user and push to `master`:

```bash
cd /tmp/bp-test
git checkout master && git reset --hard origin/master && git pull
echo "test-description" >> test.txt
git add test.txt && git commit -m "test description"
git push origin master
```

For testing new branch creation (secret exfiltration path), create and push a new branch:

```bash
cd /tmp/bp-test
git checkout master && git reset --hard origin/master && git pull
git checkout -b test-new-branch
echo "test-description" >> test.txt
git add test.txt && git commit -m "test description"
git push origin test-new-branch
```

#### Interpreting Results

- **Push succeeds**: The protection was bypassed. If GitHub acknowledges a bypass, the remote output includes `"Bypassed rule violations"` followed by the specific rule that was bypassed.
- **Push blocked**: The remote returns `error: GH006: Protected branch update failed` with a message indicating which protection blocked the push:
  - `"Changes must be made through a pull request"` — PR review requirement blocked the push
  - `"You're not authorized to push to this branch"` — push restrictions blocked the push
  - `"Cannot change this locked branch"` — lock branch blocked the push

#### Adding Users to Per-Rule Allowances

To test `pushAllowances` (adds the user to the push restrictions allowlist for a specific rule):

```bash
# First get the user's node ID
gh api graphql -f query='{ user(login: "<USERNAME>") { id } }'

# Then update the rule with the user in pushActorIds
gh api graphql -f query='
mutation {
  updateBranchProtectionRule(input: {
    branchProtectionRuleId: "<BPR_ID>"
    restrictsPushes: true
    pushActorIds: ["<USER_NODE_ID>"]
  }) {
    branchProtectionRule {
      pushAllowances(first: 10) { nodes { actor { ... on User { login } } } }
    }
  }
}'
```

To test `bypassPullRequestAllowances`:

```bash
gh api graphql -f query='
mutation {
  updateBranchProtectionRule(input: {
    branchProtectionRuleId: "<BPR_ID>"
    requiresApprovingReviews: true
    bypassPullRequestActorIds: ["<USER_NODE_ID>"]
  }) {
    branchProtectionRule {
      bypassPullRequestAllowances(first: 10) { nodes { actor { ... on User { login } } } }
    }
  }
}'
```
