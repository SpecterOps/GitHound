# GitHound Schema Reference

This document provides the complete schema reference for GitHound, including all node types, edges, and relationship patterns.

For individual node documentation with properties and diagrams, see the [Nodes](./Nodes/) directory.

## Nodes

| Node                    | Icon              | Color     | Description                                                                                        |
|-------------------------|-------------------|-----------|----------------------------------------------------------------------------------------------------|
| GH_App                  | cube              | #7EC8E3 | A GitHub App definition. The app owner controls the private key used to generate installation tokens. |
| GH_AppInstallation      | plug              | #A8D8EA | A GitHub App installed on the organization with specific permissions and repository access.        |
| GH_Branch               | code-branch       | #FF80D2 | A named reference in a repository (e.g. `main`, `develop`) representing a line of development.     |
| GH_BranchProtectionRule | shield            | #FFB347 | A branch protection rule that applies to one or more branches via pattern matching.                |
| GH_Environment          | leaf              | #D5F2C2 | A GitHub Actions deployment environment with protection rules and deployment branch policies.      |
| GH_EnvironmentSecret    | lock              | #6FB94A | An environment-level GitHub Actions secret scoped to a specific deployment environment.            |
| GH_ExternalIdentity     | arrows-left-right | #8A8F98 | An external identity from a SAML/SCIM provider linked to a GitHub user for SSO authentication.     |
| GH_Organization         | building          | #5FED83 | A GitHub Organization—top‑level container for repositories, teams, & settings.                     |
| GH_OrgRole              | user-tie          | #BFFFD1 | The role a user has at the organization level (e.g. `admin`, `member`).                            |
| GH_OrgSecret            | lock              | #1FB65A | An organization-level GitHub Actions secret that can be scoped to all, private, or selected repos. |
| GH_Repository           | box-archive       | #9EECFF | A code repository in an organization, containing files, issues, etc.                               |
| GH_RepoRole             | user-tie          | #DEFEFA | The permission granted to a user or team on a repository (e.g. `admin`, `write`, `read`).          |
| GH_RepoSecret           | lock              | #32BEE6 | A repository-level GitHub Actions secret accessible only to workflows in that repository.          |
| GH_SamlIdentityProvider | id-badge          | #5A6C8F | A SAML identity provider configured for the organization, enabling SSO.                            |
| GH_SecretScanningAlert  | key               | #3C7A6E | A GitHub Advanced Security alert indicating a secret was accidentally committed.                   |
| GH_Team                 | user-group        | #C06EFF | A team within an organization, grouping users for shared access and collaboration.                 |
| GH_TeamRole             | user-tie          | #D0B0FF | The role a user has within a team (e.g. `maintainer`, `member`).                                   |
| GH_User                 | user              | #FF8E40 | An individual GitHub user account.                                                                 |
| GH_Workflow             | cogs              | #FFE4A1 | A GitHub Actions workflow defined in a repository.                                                 |

## Edges

### Containment Edges

These edges represent organizational hierarchy and ownership.

| Edge Type     | Source            | Target                 | Traversable | Description                              |
|---------------|-------------------|------------------------|-------------|------------------------------------------|
| `GH_Contains` | `GH_Organization` | `GH_OrgSecret`         | No          | Organization contains this secret.       |
| `GH_Contains` | `GH_Organization` | `GH_AppInstallation`   | No          | Organization contains this app installation. |
| `GH_Contains` | `GH_Repository`   | `GH_RepoSecret`        | No          | Repository contains this secret.         |
| `GH_Contains` | `GH_Environment`  | `GH_EnvironmentSecret` | No          | Environment contains this secret.        |
| `GH_Owns`     | `GH_Organization` | `GH_Repository`        | Yes         | Organization owns this repository.       |

### Role & Membership Edges

These edges connect principals to roles and define membership relationships.

| Edge Type       | Source        | Target        | Traversable | Description                                       |
|-----------------|---------------|---------------|-------------|---------------------------------------------------|
| `GH_HasRole`    | `GH_User`     | `GH_OrgRole`  | Yes         | User has this organization role.                  |
| `GH_HasRole`    | `GH_User`     | `GH_RepoRole` | Yes         | User has this repository role.                    |
| `GH_HasRole`    | `GH_User`     | `GH_TeamRole` | Yes         | User has this team role.                          |
| `GH_HasRole`    | `GH_Team`     | `GH_OrgRole`  | Yes         | Team has this organization role.                  |
| `GH_HasRole`    | `GH_Team`     | `GH_RepoRole` | Yes         | Team has this repository role.                    |
| `GH_MemberOf`   | `GH_TeamRole` | `GH_Team`     | Yes         | Team role is a member of this team.               |
| `GH_MemberOf`   | `GH_Team`     | `GH_Team`     | Yes         | Team is a nested member of parent team.           |
| `GH_AddMember`  | `GH_TeamRole` | `GH_Team`     | Yes         | Team role can add members (maintainer privilege). |
| `GH_HasBaseRole`| `GH_OrgRole`  | `GH_OrgRole`  | Yes         | Org role inherits from another org role.          |
| `GH_HasBaseRole`| `GH_OrgRole`  | `GH_RepoRole` | Yes         | Org role inherits from a repo role.               |
| `GH_HasBaseRole`| `GH_RepoRole` | `GH_RepoRole` | Yes         | Repo role inherits from another repo role.        |

### Organization Permission Edges

These edges represent permissions that org roles grant on the organization.

| Edge Type                                   | Source      | Target            | Traversable | Description                                |
|---------------------------------------------|-------------|----------------- -|-------------|--------------------------------------------|
| `GH_CreateRepository`                       | `GH_OrgRole`| `GH_Organization` | No          | Can create repositories in the org.        |
| `GH_InviteMember`                           | `GH_OrgRole`| `GH_Organization` | No          | Can invite members to the org.             |
| `GH_AddCollaborator`                        | `GH_OrgRole`| `GH_Organization` | No          | Can add outside collaborators.             |
| `GH_CreateTeam`                             | `GH_OrgRole`| `GH_Organization` | No          | Can create teams in the org.               |
| `GH_TransferRepository`                     | `GH_OrgRole`| `GH_Organization` | No          | Can transfer repositories.                 |
| `GH_ManageOrganizationWebhooks`             | `GH_OrgRole`| `GH_Organization` | No          | Can manage org webhooks.                   |
| `GH_OrgBypassCodeScanningDismissalRequests`                | `GH_OrgRole`| `GH_Organization` | No          | Can bypass code scanning dismissal.                        |
| `GH_OrgBypassSecretScanningClosureRequests`                | `GH_OrgRole`| `GH_Organization` | No          | Can bypass secret scanning closure.                        |
| `GH_OrgReviewAndManageSecretScanningBypassRequests`        | `GH_OrgRole`| `GH_Organization` | No          | Can review/manage secret scanning bypass requests.         |
| `GH_OrgReviewAndManageSecretScanningClosureRequests`       | `GH_OrgRole`| `GH_Organization` | No          | Can review/manage secret scanning closure requests.        |
| `GH_ReadOrganizationActionsUsageMetrics`                   | `GH_OrgRole`| `GH_Organization` | No          | Can read Actions usage metrics.                            |
| `GH_ReadOrganizationCustomOrgRole`                         | `GH_OrgRole`| `GH_Organization` | No          | Can read custom org role definitions.                      |
| `GH_ReadOrganizationCustomRepoRole`                        | `GH_OrgRole`| `GH_Organization` | No          | Can read custom repo role definitions.                     |
| `GH_ResolveSecretScanningAlerts`                           | `GH_OrgRole`| `GH_Organization` | No          | Can resolve secret scanning alerts.                        |
| `GH_ViewSecretScanningAlerts`                              | `GH_OrgRole`| `GH_Organization` | No          | Can view secret scanning alerts.                           |
| `GH_WriteOrganizationActionsSecrets`                       | `GH_OrgRole`| `GH_Organization` | No          | Can write Actions secrets.                                 |
| `GH_WriteOrganizationActionsSettings`                      | `GH_OrgRole`| `GH_Organization` | No          | Can write Actions settings.                                |
| `GH_WriteOrganizationCustomOrgRole`                        | `GH_OrgRole`| `GH_Organization` | No          | Can write custom org role definitions.                     |
| `GH_WriteOrganizationCustomRepoRole`                       | `GH_OrgRole`| `GH_Organization` | No          | Can write custom repo role definitions.                    |
| `GH_WriteOrganizationNetworkConfigurations`                | `GH_OrgRole`| `GH_Organization` | No          | Can write network configurations.                          |

### Repository Permission Edges

These edges represent permissions that repo roles grant on repositories.

| Edge Type                          | Source        | Target          | Traversable | Description                                          |
|------------------------------------|---------------|-----------------|-------------|------------------------------------------------------|
| `GH_ReadRepoContents`              | `GH_RepoRole` | `GH_Repository` | No          | Can read repository contents.                        |
| `GH_WriteRepoContents`             | `GH_RepoRole` | `GH_Repository` | No          | Can write repository contents.                       |
| `GH_WriteRepoPullRequests`         | `GH_RepoRole` | `GH_Repository` | No          | Can create and merge pull requests.                  |
| `GH_AdminTo`                       | `GH_RepoRole` | `GH_Repository` | No          | Has admin access to the repository.                  |
| `GH_ManageWebhooks`               | `GH_RepoRole` | `GH_Repository` | No          | Can manage repository webhooks.                      |
| `GH_ManageDeployKeys`             | `GH_RepoRole` | `GH_Repository` | No          | Can manage deploy keys.                              |
| `GH_PushProtectedBranch`          | `GH_RepoRole` | `GH_Repository` | No          | Can push to protected branches.                      |
| `GH_DeleteAlertsCodeScanning`     | `GH_RepoRole` | `GH_Repository` | No          | Can delete code scanning alerts.                     |
| `GH_ViewSecretScanningAlerts`      | `GH_RepoRole` | `GH_Repository` | No          | Can view secret scanning alerts.                     |
| `GH_RunOrgMigration`              | `GH_RepoRole` | `GH_Repository` | No          | Can run organization migrations.                     |
| `GH_BypassBranchProtection`       | `GH_RepoRole` | `GH_Repository` | No          | Can bypass branch protection rules.                  |
| `GH_ManageSecurityProducts`       | `GH_RepoRole` | `GH_Repository` | No          | Can manage security products.                        |
| `GH_ManageRepoSecurityProducts`   | `GH_RepoRole` | `GH_Repository` | No          | Can manage repo-level security products.             |
| `GH_EditRepoProtections`          | `GH_RepoRole` | `GH_Repository` | No          | Can edit branch protection rules.                    |
| `GH_JumpMergeQueue`               | `GH_RepoRole` | `GH_Repository` | No          | Can jump the merge queue.                            |
| `GH_CreateSoloMergeQueueEntry`    | `GH_RepoRole` | `GH_Repository` | No          | Can create solo merge queue entries.                 |
| `GH_EditRepoCustomPropertiesValue`| `GH_RepoRole` | `GH_Repository` | No          | Can edit custom property values.                     |

### Branch Protection Edges

These edges represent branch-level permissions and protections.

| Edge Type                        | Source                    | Target                    | Traversable | Description                                                |
|----------------------------------|---------------------------|---------------------------|-------------|------------------------------------------------------------|
| `GH_ProtectedBy`                 | `GH_BranchProtectionRule` | `GH_Branch`               | Yes         | Branch protection rule protects this branch.               |
| `GH_BypassPullRequestAllowances` | `GH_User`                 | `GH_BranchProtectionRule` | No          | User can bypass PR requirements on this protection rule.   |
| `GH_BypassPullRequestAllowances` | `GH_Team`                 | `GH_BranchProtectionRule` | No          | Team can bypass PR requirements on this protection rule.   |
| `GH_RestrictionsCanPush`         | `GH_User`                 | `GH_BranchProtectionRule` | No          | User is allowed to push to branches protected by this rule.|
| `GH_RestrictionsCanPush`         | `GH_Team`                 | `GH_BranchProtectionRule` | No          | Team is allowed to push to branches protected by this rule.|

### Computed Branch Access Edges

These edges are computed post-collection by `Compute-GitHoundBranchAccess`. They cross-reference role permissions with branch protection rule settings and per-rule allowances to determine effective access. Unlike raw permission edges (which are necessary but not sufficient), computed edges represent actual push capability.

| Edge Type              | Source                  | Target                    | Traversable | Description                                                                                      |
|------------------------|-------------------------|---------------------------|-------------|--------------------------------------------------------------------------------------------------|
| `GH_CanCreateBranch`   | `GH_RepoRole`           | `GH_Repository`           | Yes         | Role can create new branches (enables secret exfiltration via workflow creation).                |
| `GH_CanCreateBranch`   | `GH_User`               | `GH_Repository`           | Yes         | User can create new branches via per-rule allowance (delta only — when role alone doesn't grant access). |
| `GH_CanCreateBranch`   | `GH_Team`               | `GH_Repository`           | Yes         | Team can create new branches via per-rule allowance (delta only — when role alone doesn't grant access). |
| `GH_CanWriteBranch`    | `GH_RepoRole`           | `GH_Branch`               | Yes         | Role can push to this specific branch.                                                          |
| `GH_CanWriteBranch`    | `GH_RepoRole`           | `GH_Repository`           | Yes         | Role can push to ALL branches in this repository.                                               |
| `GH_CanWriteBranch`    | `GH_User`               | `GH_Branch`               | Yes         | User can push to this branch via per-rule allowance (delta only — when role alone doesn't grant access). |
| `GH_CanWriteBranch`    | `GH_User`               | `GH_Repository`           | Yes         | User can push to ALL branches via per-rule allowance (delta only).                              |
| `GH_CanWriteBranch`    | `GH_Team`               | `GH_Branch`               | Yes         | Team can push to this branch via per-rule allowance (delta only — when role alone doesn't grant access). |
| `GH_CanWriteBranch`    | `GH_Team`               | `GH_Repository`           | Yes         | Team can push to ALL branches via per-rule allowance (delta only).                              |
| `GH_CanEditProtection` | `GH_RepoRole`           | `GH_BranchProtectionRule` | No          | Role can modify/remove this branch protection rule (indirect bypass — separate from push access).|

Each computed edge includes a `reason` property indicating why access was granted, and a `query_composition` property containing a Cypher query that reveals the underlying graph elements (permission edges, BPRs, allowances) that caused the edge to be created:

| Reason | Meaning |
|--------|---------|
| `no_protection` | No branch protection rule applies to this branch/repo |
| `admin` | Has admin access (bypasses push-gate; bypasses merge-gate unless `enforce_admins`) |
| `push_protected_branch` | Role has `push_protected_branch` permission (bypasses push-gate) |
| `push_allowance` | Actor is in `pushAllowances` for the matching BPR |
| `bypass_branch_protection` | Role has `bypass_branch_protection` permission (bypasses merge-gate unless `enforce_admins`) |
| `bypass_pr_allowance` | Actor is in `bypassPullRequestAllowances` (bypasses PR reviews only, not lock branch) |
| `edit_repo_protections` | Can modify/remove this BPR (used on `GH_CanEditProtection` edges) |

**Separation of concerns:** `GH_CanWriteBranch` and `GH_CanCreateBranch` represent **direct** push capability. `GH_CanEditProtection` represents the ability to weaken/remove protections — a separate indirect bypass path. The analyst combines these visually: a user can edit a BPR, which protects certain branches, and the user may also have write access.

### Resource Relationship Edges

These edges connect repositories to their resources.

| Edge Type                  | Source          | Target                   | Traversable | Description                                    |
|----------------------------|-----------------|--------------------------|-------------|------------------------------------------------|
| `GH_HasBranch`             | `GH_Repository` | `GH_Branch`              | Yes         | Repository has this branch.                    |
| `GH_HasWorkflow`           | `GH_Repository` | `GH_Workflow`            | No          | Repository has this workflow.                  |
| `GH_HasEnvironment`        | `GH_Repository` | `GH_Environment`         | Yes         | Repository has this environment.               |
| `GH_HasEnvironment`        | `GH_Branch`     | `GH_Environment`         | No          | Branch can deploy to this environment.         |
| `GH_HasSecret`             | `GH_Repository` | `GH_OrgSecret`           | Yes         | Repository has access to this org secret. Traversable because write access enables secret access via workflow creation. |
| `GH_HasSecret`             | `GH_Repository` | `GH_RepoSecret`          | Yes         | Repository has this repo secret. Traversable because write access enables secret access via workflow creation. |
| `GH_HasSecretScanningAlert`| `GH_Repository` | `GH_SecretScanningAlert` | No          | Repository has this secret scanning alert.     |

### App Installation Edges

These edges connect GitHub Apps to their installations and installations to accessible repositories.

| Edge Type                  | Source               | Target                | Traversable | Description                                                |
|----------------------------|----------------------|-----------------------|-------------|------------------------------------------------------------|
| `GH_InstalledAs`           | `GH_App`             | `GH_AppInstallation`  | Yes         | App is installed as this installation on an organization.  |
| `GH_CanAccess`             | `GH_AppInstallation` | `GH_Repository`       | No          | App installation can access this repository.               |

### Identity Provider Edges

These edges connect SAML/SCIM identity providers to external identities.

| Edge Type                   | Source                   | Target                   | Traversable | Description                                    |
|-----------------------------|--------------------------|--------------------------|-------------|------------------------------------------------|
| `GH_HasSamlIdentityProvider`| `GH_Organization`        | `GH_SamlIdentityProvider`| No          | Organization has this SAML provider configured.|
| `GH_HasExternalIdentity`    | `GH_SamlIdentityProvider`| `GH_ExternalIdentity`    | No          | Provider has this external identity.           |
| `GH_MapsToUser`             | `GH_ExternalIdentity`    | `GH_User`                | No          | External identity maps to this GitHub user.    |

## Hybrid/Cross-Cloud Edges

These edges connect GitHub nodes to nodes in other platforms (Azure, AWS, Okta, PingOne), enabling cross-cloud attack path analysis.

| Edge Type            | Source                | Target                           | Traversable | Description                                                                      |
|----------------------|-----------------------|----------------------------------|-------------|----------------------------------------------------------------------------------|
| `SyncedToGHUser`     | `AZUser`              | `GH_User`                        | Yes         | Azure AD user is synced to GitHub user via SAML/SCIM.                            |
| `SyncedToGHUser`     | `OktaUser`            | `GH_User`                        | Yes         | Okta user is synced to GitHub user via SAML/SCIM.                                |
| `SyncedToGHUser`     | `PingOneUser`         | `GH_User`                        | Yes         | PingOne user is synced to GitHub user via SAML/SCIM.                             |
| `GH_MapsToUser`      | `GH_ExternalIdentity` | `AZUser`/`OktaUser`/`PingOneUser`| No          | External identity maps to identity provider user.                                |
| `SCIMProvisioned`    | `SCIMUser`            | `GH_User`                        | Yes         | SCIM user is provisioned and mapped to a GitHub user.                            |
| `CanAssumeIdentity`  | `GH_Repository`       | `AZFederatedIdentityCredential`  | Yes         | Repository can assume Azure federated identity (subject: `*`).                   |
| `CanAssumeIdentity`  | `GH_Branch`           | `AZFederatedIdentityCredential`  | Yes         | Branch can assume Azure federated identity (subject: `ref:refs/heads/{branch}`). |
| `CanAssumeIdentity`  | `GH_Environment`      | `AZFederatedIdentityCredential`  | Yes         | Environment can assume Azure federated identity (subject: `environment:{name}`). |

## Structural Edge Patterns

These patterns show how to traverse the graph to answer common security questions.

### User → Repository Permission Path

Find all repositories a user can access through any role assignment:

```cypher
(:GH_User)-[:GH_HasRole|GH_MemberOf|GH_AddMember*1..]->(:GH_RepoRole)-[:GH_AdminTo|GH_WriteRepoContents|GH_ReadRepoContents]->(:GH_Repository)
```

### Team → Repository Permission Path

Find all repositories a team can access:

```cypher
(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole)-[:GH_AdminTo|GH_WriteRepoContents|GH_ReadRepoContents]->(:GH_Repository)
```

### User → Organization Admin Path

Find users with organization admin privileges:

```cypher
(:GH_User)-[:GH_HasRole|GH_HasBaseRole*1..]->(:GH_OrgRole {short_name: "owners"})
```

### Role Inheritance Chain

Trace role inheritance:

```cypher
(:GH_OrgRole)-[:GH_HasBaseRole*1..]->(:GH_RepoRole)
```

### Cross-Cloud Attack Path (GitHub → Azure)

Find GitHub users who can push to a branch and assume Azure identities:

```cypher
(:GH_User)-[:GH_HasRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_WriteRepoContents]->(:GH_Repository)-[:CanAssumeIdentity]->(:AZFederatedIdentityCredential)
```

## Key Traversable Edges

The following edges are marked as "traversable" and form the primary attack paths in the graph:

| Edge Type             | Description                                        |
|-----------------------|----------------------------------------------------|
| `GH_HasRole`          | User/Team has a role assignment                    |
| `GH_InstalledAs`      | App is installed as this installation              |
| `GH_MemberOf`         | Team role membership or nested team membership     |
| `GH_AddMember`        | Team role can add members (maintainer privilege)   |
| `GH_HasBaseRole`      | Role inherits from another role                    |
| `GH_Owns`             | Organization owns repository                       |
| `GH_HasBranch`        | Repository has this branch                         |
| `GH_ProtectedBy`      | Branch protection rule protects this branch        |
| `SyncedToGHUser`      | Identity provider user synced to GitHub user       |
| `SCIMProvisioned`     | SCIM user provisioned and mapped to GitHub user    |
| `CanAssumeIdentity`   | GitHub entity can assume Azure identity            |

## Mitigating Controls & Computed Edges

Branch protection rules can mitigate the `GH_WriteRepoContents` → `GH_HasSecret` secret exfiltration attack path and the direct-push supply chain attack path. However, multiple bypass mechanisms exist (`GH_PushProtectedBranch`, `GH_AdminTo`, `GH_BypassBranchProtection`, `GH_RestrictionsCanPush`, `GH_BypassPullRequestAllowances`, `GH_EditRepoProtections`), each with different scope and interaction with `enforce_admins`.

The raw permission edges (`GH_WriteRepoContents`, `GH_PushProtectedBranch`, `GH_BypassBranchProtection`) are **not traversable** because each is necessary but not sufficient for push access. The computed edges (`GH_CanCreateBranch`, `GH_CanWriteBranch`) cross-reference these permissions with branch protection rule settings and per-rule allowances to determine effective access, and **are traversable** because they represent actual push capability.

For complete empirically verified analysis including test results, bypass matrices, and effective mitigating control requirements, see [MITIGATING_CONTROLS.md](./MITIGATING_CONTROLS.md).
