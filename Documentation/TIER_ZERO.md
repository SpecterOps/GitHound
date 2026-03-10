# Tier Zero Classification for GitHub

## Overview

Tier Zero (T0) identifies assets whose compromise grants control over the entire GitHub organization or the ability to compromise everything else. This is analogous to Active Directory Tier Zero, where Domain Controllers and Domain Admins are T0 because their compromise means full domain compromise.

In GitHub, T0 classification serves two purposes:

1. **Defensive prioritization** — T0 assets should receive the highest level of protection, monitoring, and access review.
2. **Attack path analysis** — any attack path that reaches a T0 asset represents a critical finding, regardless of the number of hops.

## The Two Dimensions of GitHub Tier Zero

### Control Plane — Organizational Authority

Control plane T0 assets can reshape the access model itself. They don't just have access to resources — they control *who* has access and *how* access is granted. This includes:

- **Organization administration** — managing members, teams, billing, security settings
- **SSO/SCIM configuration** — controlling authentication for all org members
- **Role definition** — creating or modifying custom organization and repository roles
- **App management** — installing or configuring GitHub Apps with arbitrary permissions

An actor with control plane authority can grant themselves (or anyone else) any level of access, making them effectively omnipotent within the organization.

### Data Plane — Universal Repository Access

Data plane T0 assets have or cascade to admin access on every repository in the organization. Through the graph, this means they can reach:

- Every secret (via `GH_HasSecret`)
- Every branch (via `GH_HasBranch` → `GH_CanWriteBranch`)
- Every environment (via `GH_HasEnvironment`)
- Every cloud identity (via `GH_CanAssumeIdentity`)

The `all_repo_admin` synthetic role is the primary mechanism: the owners org role inherits it via `GH_HasBaseRole`, and it fans out via `GH_AdminTo`, `GH_WriteRepoContents`, `GH_BypassBranchProtection`, etc. to every repository.

## T0 Asset Categories

### Always T0

| Asset | Node Kind | Identifying Property | Dimension | Rationale |
|-------|-----------|---------------------|-----------|-----------|
| Organization | `GH_Organization` | All instances | Control | Root trust boundary for all contained assets |
| Owners role | `GH_OrgRole` | `short_name:'owners'` | Both | Full administrative control + inherits `all_repo_admin` |
| All-repo admin role | `GH_OrgRole` | `name` ends with `/all_repo_admin` | Data | Admin access to every repository in the org |
| SAML identity provider | `GH_SamlIdentityProvider` | All instances | Control | Controls SSO authentication; can impersonate any user |

### T0 by Relationship

| Asset | Condition | Dimension | Rationale |
|-------|-----------|-----------|-----------|
| Owner users | `GH_User` → `GH_HasRole` → `GH_OrgRole {owners}` | Both | Identity with full org control |
| Privilege escalation roles | `GH_OrgRole` → `GH_WriteOrganizationCustomOrgRole` → `GH_Organization` | Control | Can modify org role definitions to set base_role to all_repo_admin — guaranteed self-escalation |
| Privilege escalation users | `GH_User` → role chain → above roles | Control | Can escalate the org role they hold to gain full organizational control |
| External identities (owner-mapped) | `GH_ExternalIdentity` → `GH_MapsToUser` → owner `GH_User` | Control | IdP identity of an org owner; compromising it grants owner access via SSO |
| App installations (all repos, write) | `GH_AppInstallation {repository_selection:'all'}` + write permissions | Data | App credential with write access to every repository |
| Apps (all-repo installations, write) | `GH_App` → `GH_InstalledAs` → all-repo `GH_AppInstallation` with write permissions | Data | App private key can generate write tokens for every repository |
| PATs (all repos, write) | `GH_PersonalAccessToken {repository_selection:'all'}` + write permissions | Data | Single token with write access to every repository |

### Explicitly Not T0

| Asset | Rationale |
|-------|-----------|
| Individual repositories | Even critical ones — T0 is about universal control, not single-resource importance |
| `GH_OrgRole` (members) | Default role with limited, non-administrative permissions |
| Team maintainer roles | Scoped to one team's repositories, not org-wide |
| `GH_RepoRole` (admin on single repo) | Single-repository scope, not universal |
| Secret scanning alerts | Attack paths *to* T0, not T0 themselves |
| Individual secrets or variables | Resources protected by T0, not T0 themselves |
| Read-only all-repo apps/PATs | Data exfiltration risk but no write control — visibility without the ability to modify |
| `write_organization_custom_repo_role` roles | Manages custom repo roles, but the holder may not hold those repo roles — no guaranteed self-escalation |

## Classification Rules

The classification rules are located in the [`pz-rules/`](../pz-rules/) directory. Each rule is a Cypher query that returns nodes to be tagged as Tier Zero.

| Rule | File | Category |
|------|------|----------|
| Organizations | [`t0-organizations.json`](../pz-rules/t0-organizations.json) | Control |
| Owners Role | [`t0-owners-role.json`](../pz-rules/t0-owners-role.json) | Control |
| Owner Users | [`t0-owner-users.json`](../pz-rules/t0-owner-users.json) | Control |
| All-Repo Admin Role | [`t0-all-repo-admin-role.json`](../pz-rules/t0-all-repo-admin-role.json) | Data |
| SAML Identity Providers | [`t0-saml-identity-providers.json`](../pz-rules/t0-saml-identity-providers.json) | Control |
| Privilege Escalation Roles | [`t0-privilege-escalation-roles.json`](../pz-rules/t0-privilege-escalation-roles.json) | Control |
| Privilege Escalation Users | [`t0-privilege-escalation-users.json`](../pz-rules/t0-privilege-escalation-users.json) | Control |
| External Identities (Owner-Mapped) | [`t0-external-identities-owners.json`](../pz-rules/t0-external-identities-owners.json) | Control |
| App Installations (All Repos) | [`t0-app-installations-all-repos.json`](../pz-rules/t0-app-installations-all-repos.json) | Data |
| Apps (All-Repo Installations) | [`t0-apps-all-repos.json`](../pz-rules/t0-apps-all-repos.json) | Data |
| PATs (All Repos) | [`t0-pats-all-repos.json`](../pz-rules/t0-pats-all-repos.json) | Data |
