# GitHound Schema Reference

This document provides the complete schema reference for GitHound, including all node types, edges, and relationship patterns.

For individual node documentation with properties and diagrams, see the [Nodes](./Nodes/) directory.

## Nodes

| Node                    | Icon              | Color     | Description                                                                                        |
|-------------------------|-------------------|-----------|----------------------------------------------------------------------------------------------------|
| GH_AppInstallation      | plug              | #A8D8EA | A GitHub App installed on the organization with specific permissions and repository access.        |
| GH_Branch               | code-branch       | #FF80D2 | A named reference in a repository (e.g. `main`, `develop`) representing a line of development.     |
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
| `GH_Contains` | `GH_Organization` | `GH_OrgRole`           | No          | Organization contains this org role.     |
| `GH_Contains` | `GH_Organization` | `GH_RepoRole`          | No          | Organization contains this repo role.    |
| `GH_Contains` | `GH_Organization` | `GH_Repository`        | No          | Organization contains this repository.   |
| `GH_Contains` | `GH_Organization` | `GH_TeamRole`          | No          | Organization contains this team role.    |
| `GH_Contains` | `GH_Organization` | `GH_Team`              | No          | Organization contains this team.         |
| `GH_Contains` | `GH_Organization` | `GH_User`              | No          | Organization contains this user.         |
| `GH_Contains` | `GH_Organization` | `GH_OrgSecret`         | No          | Organization contains this secret.       |
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
| `GH_OrgBypassCodeScanningDismissalRequests` | `GH_OrgRole`| `GH_Organization` | No          | Can bypass code scanning dismissal.        |
| `GH_OrgBypassSecretScanningClosureRequests` | `GH_OrgRole`| `GH_Organization` | No          | Can bypass secret scanning closure.        |

### Repository Permission Edges

These edges represent permissions that repo roles grant on repositories.

| Edge Type                    | Source        | Target          | Traversable | Custom | Description                           |
|------------------------------|---------------|-----------------|-------------|--------|---------------------------------------|
| `GH_CanPull`                 | `GH_RepoRole` | `GH_Repository` | Yes         | No     | Can clone/pull the repository.        |
| `GH_ReadRepoContents`        | `GH_RepoRole` | `GH_Repository` | Yes         | No     | Can read repository contents.         |
| `GH_CanPush`                 | `GH_RepoRole` | `GH_Repository` | No          | No     | Can push to the repository.           |
| `GH_WriteRepoContents`       | `GH_RepoRole` | `GH_Repository` | No          | No     | Can write repository contents.        |
| `GH_AdminTo`                 | `GH_RepoRole` | `GH_Repository` | No          | No     | Has admin access to the repository.   |
| `GH_BypassProtections`       | `GH_RepoRole` | `GH_Repository` | No          | Yes    | Can bypass branch protections.        |
| `GH_EditProtections`         | `GH_RepoRole` | `GH_Repository` | No          | Yes    | Can edit branch protection rules.     |
| `GH_ViewSecretScanningAlerts`| `GH_RepoRole` | `GH_Repository` | No          | Yes    | Can view secret scanning alerts.      |

### Branch Protection Edges

These edges represent branch-level permissions and protections.

| Edge Type                        | Source    | Target      | Traversable | Description                                    |
|----------------------------------|-----------|-------------|-------------|------------------------------------------------|
| `GH_BypassPullRequestAllowances` | `GH_User` | `GH_Branch` | No          | User can bypass PR requirements on branch.     |
| `GH_BypassPullRequestAllowances` | `GH_Team` | `GH_Branch` | No          | Team can bypass PR requirements on branch.     |
| `GH_RestrictionsCanPush`         | `GH_User` | `GH_Branch` | No          | User is allowed to push to protected branch.   |
| `GH_RestrictionsCanPush`         | `GH_Team` | `GH_Branch` | No          | Team is allowed to push to protected branch.   |

### Resource Relationship Edges

These edges connect repositories to their resources.

| Edge Type                 | Source          | Target                   | Traversable | Description                                    |
|---------------------------|-----------------|--------------------------|-------------|------------------------------------------------|
| `GH_HasBranch`            | `GH_Repository` | `GH_Branch`              | No          | Repository has this branch.                    |
| `GH_HasWorkflow`          | `GH_Repository` | `GH_Workflow`            | No          | Repository has this workflow.                  |
| `GH_HasEnvironment`       | `GH_Repository` | `GH_Environment`         | No          | Repository has this environment.               |
| `GH_HasEnvironment`       | `GH_Branch`     | `GH_Environment`         | No          | Branch can deploy to this environment.         |
| `GH_HasSecret`            | `GH_Repository` | `GH_OrgSecret`           | No          | Repository has access to this org secret.      |
| `GH_HasSecret`            | `GH_Repository` | `GH_RepoSecret`          | No          | Repository has this repo secret.               |
| `GH_HasSecret`            | `GH_Environment`| `GH_EnvironmentSecret`   | No          | Environment has this secret.                   |
| `GH_HasSecretScanningAlert`| `GH_Repository`| `GH_SecretScanningAlert` | No          | Repository has this secret scanning alert.     |

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
| `GH_CanAssumeAWSRole`| `GH_Repository`       | `AWSRole`                        | Yes         | Repository can assume AWS IAM role via OIDC.                                     |
| `GH_CanAssumeAWSRole`| `GH_Branch`           | `AWSRole`                        | Yes         | Branch can assume AWS IAM role via OIDC.                                         |
| `GH_CanAssumeAWSRole`| `GH_Environment`      | `AWSRole`                        | Yes         | Environment can assume AWS IAM role via OIDC.                                    |
| `CanAssumeIdentity`  | `GH_Repository`       | `AZFederatedIdentityCredential`  | Yes         | Repository can assume Azure federated identity (subject: `*`).                   |
| `CanAssumeIdentity`  | `GH_Branch`           | `AZFederatedIdentityCredential`  | Yes         | Branch can assume Azure federated identity (subject: `ref:refs/heads/{branch}`). |
| `CanAssumeIdentity`  | `GH_Environment`      | `AZFederatedIdentityCredential`  | Yes         | Environment can assume Azure federated identity (subject: `environment:{name}`). |

## Structural Edge Patterns

These patterns show how to traverse the graph to answer common security questions.

### User → Repository Permission Path

Find all repositories a user can access through any role assignment:

```cypher
(:GH_User)-[:GH_HasRole|GH_MemberOf|GH_AddMember*1..]->(:GH_RepoRole)-[:GH_AdminTo|GH_CanPush|GH_CanPull]->(:GH_Repository)
```

### Team → Repository Permission Path

Find all repositories a team can access:

```cypher
(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole)-[:GH_AdminTo|GH_CanPush|GH_CanPull]->(:GH_Repository)
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

Find GitHub entities that can assume Azure identities:

```cypher
(:GH_User)-[:GH_HasRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_CanPush]->(:GH_Repository)-[:CanAssumeIdentity]->(:AZFederatedIdentityCredential)
```

## Key Traversable Edges

The following edges are marked as "traversable" and form the primary attack paths in the graph:

| Edge Type             | Description                                        |
|-----------------------|----------------------------------------------------|
| `GH_HasRole`          | User/Team has a role assignment                    |
| `GH_MemberOf`         | Team role membership or nested team membership     |
| `GH_AddMember`        | Team role can add members (maintainer privilege)   |
| `GH_HasBaseRole`      | Role inherits from another role                    |
| `GH_Owns`             | Organization owns repository                       |
| `GH_CanPull`          | Role grants read access to repository              |
| `GH_ReadRepoContents` | Role grants content read access                    |
| `GH_AdminTo`          | Role grants admin access to repository             |
| `SyncedToGHUser`      | Identity provider user synced to GitHub user       |
| `GH_CanAssumeAWSRole` | GitHub entity can assume AWS role                  |
| `CanAssumeIdentity`   | GitHub entity can assume Azure identity            |
