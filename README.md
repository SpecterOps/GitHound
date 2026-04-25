# GitHound

![GitHound](./Documentation/images/github_bloodhound.png)

## Overview

**GitHound** is a BloodHound OpenGraph collector for GitHub, designed to map your organization’s structure and permissions into a navigable attack‑path graph. It:

- **Models Key GitHub Entities**  
  - **GH_Organization**: Your GitHub org metadata  
  - **GH_User**: Individual user accounts in the org  
  - **GH_Team**: Teams that group users for shared access  
  - **GH_Repository**: Repositories within the org  
  - **GH_Branch**: Named branches in each repo  
  - **GH_OrgRole**, **GH_TeamRole**, **GH_RepoRole**: Org‑, team‑, and repo‑level roles/permissions  

- **Visualize & Analyze in BloodHound**  
  - **Access Audits**: See at a glance who has admin/write/read on repos and branches  
  - **Compliance Checks**: Validate least‑privilege across teams and repos  
  - **Incident Response**: Trace privilege escalations and group memberships  

With GitHound, you get a clear, interactive graph of your GitHub permissions landscape—perfect for security reviews, compliance audits, and rapid incident investigations.

## Documentation

For detailed documentation, see [BloodHound Docs - GitHound](https://bloodhound.specterops.io/opengraph/extensions/githound).

## Quick Start

```powershell
# 1. Load the collector
. ./githound.ps1

# 2. Create a session with your Personal Access Token
$session = New-GitHubSession -OrganizationName "YourOrgName" -Token (Get-Clipboard)

# 3. Run the collection
Invoke-GitHound -Session $session

# 4. Upload the resulting githound_<orgId>.json file to BloodHound
```

If collection is interrupted, resume from where you left off:

```powershell
Invoke-GitHound -Session $session -Resume
```

## GitHub App Sessions

GitHound supports both Personal Access Token sessions and GitHub App installation sessions.
The existing organization-scoped GitHub App workflow is unchanged:

```powershell
. ./githound.ps1

$session = New-GitHubJwtSession `
  -OrganizationName "YourOrgName" `
  -ClientId $clientId `
  -PrivateKeyPath $privateKeyPath `
  -InstallationId $installationId

Invoke-GitHound -Session $session -CollectAll
```

The same function can also create enterprise-capable sessions:

```powershell
. ./githound.ps1

$session = New-GitHubJwtSession `
  -EnterpriseName "YourEnterpriseSlug" `
  -ClientId $clientId `
  -PrivateKeyPath $privateKeyPath `
  -InstallationId $installationId `
  -PersonalAccessToken $pat
```

Enterprise-capable sessions retain multiple auth contexts on the returned `GitHound.Session`:

- `Headers`: the GitHub App installation token headers used for normal collection
- `JwtHeaders`: GitHub App JWT headers used for app-level endpoints such as installation enumeration
- `PatHeaders`: optional Personal Access Token headers for collection paths that require user-token auth

To enumerate the installations that belong to the authenticated GitHub App:

```powershell
Get-GitHubAppInstallation -Session $session |
  Select-Object TargetType, InstallationId, Login, Name, SuspendedAt
```

## Workflow Analysis

Workflow parsing is now built into `Invoke-GitHound` when you use `-CollectAll`. The collector
will:

- collect raw `GH_Workflow` nodes and workflow contents
- analyze those workflows into `GH_WorkflowJob` and `GH_WorkflowStep`
- compute `GH_CanPwnRequest` and `GH_CanDispatchTo`
- merge the results into the normal consolidated `githound_<orgId>.json` output

For resume/debugging purposes, the intermediate workflow-analysis checkpoint is written as
`githound_WorkflowAnalysis_<orgId>.json`.

## Enterprise Collection Foundation

GitHound now includes a minimal enterprise collection foundation through `Git-HoundEnterprise`.
That collector currently creates:

- `GH_Enterprise`
- lightweight `GH_Organization` stub nodes for member organizations
- `GH_Contains` edges from the enterprise to its organizations

Enterprise user collection through `Git-HoundEnterpriseUser` adds:

- `GH_User`
- `GH_HasMember` edges from the enterprise to those users

Enterprise SAML collection through `Git-HoundEnterpriseSamlProvider` adds:

- `GH_SamlIdentityProvider`
- `GH_ExternalIdentity`
- `GH_HasSamlIdentityProvider` from the enterprise to the provider
- the same identity-correlation edges used by the organization SAML collector

This path requires a PAT-backed session because GitHub exposes enterprise SAML through
`enterprise.ownerInfo`.

Enterprise team collection through `Git-HoundEnterpriseTeam` adds:

- `GH_EnterpriseTeam`
- `GH_AssignedTo` edges from enterprise teams to assigned organizations
- `GH_MemberOf` edges from enterprise teams to org-visible `ent:` `GH_Team` nodes using property matching
- enterprise-team `members` roles and `GH_HasRole` edges from users to those roles

Enterprise SCIM collection currently adds:

- `SCIM_User`
- `SCIM_Group`
- `SCIM_Provisioned` from `SCIM_User` to `GH_ExternalIdentity`
- `SCIM_Provisioned` from `SCIM_Group` to `GH_EnterpriseTeam` when GitHub exposes the enterprise team `group_id`
- `SCIM_MemberOf` from `SCIM_User` to `SCIM_Group`

This gives GitHound a provider-agnostic bridge from the shared SCIM schema into GitHub's native enterprise identity and team model.

The `GH_Organization` stubs emitted by enterprise collection are intentionally marked
`collected = false`. They represent structural discovery from the enterprise context and are
meant to be enriched later by normal organization collection.

For enterprise-first orchestration, `Invoke-GitHoundEnterprise` will collect the supported
enterprise-scoped data, enumerate related organization installations, and then run the
existing `Invoke-GitHound` workflow for each organization in its own subdirectory under the
chosen checkpoint path.

Example:

```powershell
$session = New-GitHubJwtSession `
  -EnterpriseName "your-enterprise-slug" `
  -ClientId $clientId `
  -PrivateKeyPath $privateKeyPath `
  -InstallationId $enterpriseInstallationId `
  -PersonalAccessToken $pat

Invoke-GitHoundEnterprise -Session $session -CheckpointPath "./output/your-enterprise" -CollectAll
```

For enterprise-only testing without enumerating the related organizations:

```powershell
Invoke-GitHoundEnterprise -Session $session -CheckpointPath "./output/your-enterprise" -EnterpriseOnly
```

## Schema

![Mermaid Schema](./Documentation/images/GitHound-Mermaid.png)

For detailed documentation, see [BloodHound Docs - GitHound Schema](https://bloodhound.specterops.io/opengraph/extensions/githound/reference/schema).

**Key edge categories:**

| Category                   | Key Edges                                                  | Description               |
|----------------------------|------------------------------------------------------------|---------------------------|
| **Containment**            | `GH_Contains`, `GH_Owns`                                   | Organizational hierarchy  |
| **Role Assignment**        | `GH_HasRole`, `GH_MemberOf`, `GH_HasBaseRole`              | Who has which roles       |
| **Repository Permissions** | `GH_AdminTo`, `GH_CanPush`, `GH_CanPull`                   | What roles can do         |
| **Branch Protections**     | `GH_BypassPullRequestAllowances`, `GH_RestrictionsCanPush` | Branch-level access       |
| **Secrets**                | `GH_HasSecret`                                             | Secret access mapping     |
| **Cross-Cloud**            | `GH_CanAssumeIdentity`, `GH_SyncedTo`                   | Attack paths to Azure/AWS |

**Primary attack path pattern:**

```cypher
(:GH_User)-[:GH_HasRole|GH_MemberOf|GH_AddMember*1..]->(:GH_RepoRole)-[:GH_AdminTo|GH_CanPush]->(:GH_Repository)
```

## Usage Examples

### What Repos does a User have Write Access to?

Find the object identifier for your target user:

```cypher
MATCH (n:GH_User)
RETURN n
```

HINT: Select Table Layout

<https://github.com/user-attachments/assets/1ddfd075-2a15-4aa9-bad7-74c43e6c82d6>

Replace the `<object_id>` value in the subsequent query with the user's object identifier:

```cypher
MATCH p = (:GH_User {objectid:"<object_id>"})-[:GH_MemberOf|GH_AddMember|GH_HasRole|GH_HasBaseRole|GH_Owns*1..]->(:GH_RepoRole)-[:GH_WriteRepoContents]->(:GH_Repository)
RETURN p
```

![User to Repos](./Documentation/images/user-repo.png)

### Who has Write Access to a Repo?

Obtain the object identifier for your target repository:

```cypher
MATCH (n:GH_Repository)
RETURN n
```

Take the object identifier for your target repository and replace the `<object_id>` value in the subsequent query with it:

```cypher
MATCH p = (:GH_User)-[:GH_MemberOf|GH_HasRole|GH_HasBaseRole|GH_Owns|GH_AddMember*1..]->(:GH_RepoRole)-[:GH_WriteRepoContents]->(:GH_Repository {objectid:"<object_id>"})
RETURN p
```

![Repo to Users](./Documentation/images/who-repo.png)

### Members of the Organization Admins (Domain Admin equivalent)?

```cypher
MATCH p = (:GH_User)-[:GH_HasRole|GH_HasBaseRole]->(:GH_OrgRole {short_name: "owners"})
RETURN p
```

![Org Admins](./Documentation/images/org-admins.png)

### Users that are managed via SSO (Entra-only)

```cypher
MATCH p = (:AZUser)-[:GH_SyncedTo]->(:GH_User)
RETURN p
```

![SSO Users](./Documentation/images/sso-users.png)

### Cross-Cloud Attack Paths: GitHub to Azure

Find GitHub entities that can assume Azure federated identities (OIDC trust relationships):

```cypher
// All GitHub → Azure OIDC attack paths
MATCH p = (:GH_Repository|GH_Branch|GH_Environment)-[:GH_CanAssumeIdentity]->(:AZFederatedIdentityCredential)
RETURN p

// Users with paths to Azure via GitHub Actions
MATCH p = (:GH_User)-[:GH_HasRole|GH_MemberOf|GH_AddMember*1..]->(:GH_RepoRole)-[:GH_CanPush]->(:GH_Repository)-[:GH_CanAssumeIdentity]->(:AZFederatedIdentityCredential)
RETURN p
```

### Which Repositories Have Access to Organization Secrets?

```cypher
MATCH p = (:GH_Repository)-[:GH_HasSecret]->(:GH_OrgSecret)
RETURN p
```

### Repositories with Secret Scanning Alerts

```cypher
MATCH p = (:GH_Repository)-[:GH_Contains]->(:GH_SecretScanningAlert)
RETURN p
```

## Contributing

We welcome and appreciate your contributions! To make the process smooth and efficient, please follow these steps:

1. **Discuss Your Idea**  
   - If you’ve found a bug or want to propose a new feature, please start by opening an issue in this repo. Describe the problem or enhancement clearly so we can discuss the best approach.

2. **Fork & Create a Branch**  
   - Fork this repository to your own account.  
   - Create a topic branch for your work:

     ```bash
     git checkout -b feat/my-new-feature
     ```

3. **Implement & Test**  
   - Follow the existing style and patterns in the repo.  
   - Add or update any tests/examples to cover your changes.  
   - Verify your code runs as expected:

     ```bash
     # e.g. dot-source the collector and run it, or load the model.json in BloodHound
     ```

4. **Submit a Pull Request**  
   - Push your branch to your fork:

     ```bash
     git push origin feat/my-new-feature
     ```  

   - Open a Pull Request against the `main` branch of this repository.  
   - In your PR description, please include:
     - **What** you’ve changed and **why**.  
     - **How** to reproduce/test your changes.

5. **Review & Merge**  
   - I’ll review your PR, give feedback if needed, and merge once everything checks out.  
   - For larger or more complex changes, review may take a little longer—thanks in advance for your patience!

Thank you for helping improve this extension! 🎉  

## Licensing

```text
Copyright 2025 Jared Atkinson

Licensed under the Apache License, Version 2.0
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

Unless otherwise annotated by a lower-level LICENSE file or license header, all files in this repository are released
under the `Apache-2.0` license. A full copy of the license may be found in the top-level [LICENSE](LICENSE) file.
