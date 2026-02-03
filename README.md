# GitHound

![GitHound](./images/github_bloodhound.png)

## Overview

**GitHound** is a BloodHound OpenGraph collector for GitHub, designed to map your organization’s structure and permissions into a navigable attack‑path graph. It:

- **Models Key GitHub Entities**  
  - **GHOrganization**: Your GitHub org metadata  
  - **GHUser**: Individual user accounts in the org  
  - **GHTeam**: Teams that group users for shared access  
  - **GHRepository**: Repositories within the org  
  - **GHBranch**: Named branches in each repo  
  - **GHOrgRole**, **GHTeamRole**, **GHRepoRole**: Org‑, team‑, and repo‑level roles/permissions  

- **Visualize & Analyze in BloodHound**  
  - **Access Audits**: See at a glance who has admin/write/read on repos and branches  
  - **Compliance Checks**: Validate least‑privilege across teams and repos  
  - **Incident Response**: Trace privilege escalations and group memberships  

With GitHound, you get a clear, interactive graph of your GitHub permissions landscape—perfect for security reviews, compliance audits, and rapid incident investigations.  

## Schema

![Mermaid Schema](./images/GitHound-Mermaid.png)

### Nodes

Nodes correspond to each object type.

| Node                                                                                      | Icon              | Color     | Description                                                                                    |
|-------------------------------------------------------------------------------------------|-------------------|-----------|------------------------------------------------------------------------------------------------|
| <img src="./images/black_GHBranch.png" width="30"/> GHBranch                              | code-branch       | #FF80D2 | A named reference in a repository (e.g. `main`, `develop`) representing a line of development. |
| <img src="./images/black_GHEnvironment.png" width="30"/> GHEnvironment                    | leaf              | #D5F2C2 |                                                                                                |
| <img src="./images/black_GHEnvironmentSecret.png" width="30"/> GHEnvironmentSecret        | lock              | #6FB94A |                                                                                                |
| <img src="./images/black_GHExternalIdentity.png" width="30"/> GHExternalIdentity          | arrows-left-right | #8A8F98 |                                                                                                |
| <img src="./images/black_GHOrganization.png" width="30"/> GHOrganization                  | building          | #5FED83 | A GitHub Organization—top‑level container for repositories, teams, & settings.                 |
| <img src="./images/black_GHOrgRole.png" width="30"/> GHOrgRole                            | user-tie          | #BFFFD1 | The role a user has at the organization level (e.g. `admin`, `member`).                        |
| <img src="./images/black_GHOrgSecret.png" width="30"/> GHOrgSecret                        | lock              | #1FB65A |                                                                                                |
| <img src="./images/black_GHRepository.png" width="30"/> GHRepository                      | box-archive       | #9EECFF | A code repository in an organization (or user account), containing files, issues, etc.         |
| <img src="./images/black_GHRepoRole.png" width="30"/> GHRepoRole                          | user-tie          | #DEFEFA | The permission granted to a user or team on a repository (e.g. `admin`, `write`, `read`).      |
| <img src="./images/black_GHRepoSecret.png" width="30"/> GHRepoSecret                      | lock              | #32BEE6 |                                                                                                |
|  <img src="./images/black_GHSamlIdentityProvider.png" width="30"/> GHSamlIdentityProvider | id-badge          | #5A6C8F |                                                                                                |
| <img src="./images/black_GHSecretScanningAlert.png" width="30"/> GHSecretScanningAlert    | key               | #3C7A6E | A component of GitHub Advanced Security to notify organizations when a secret is accidentally included in a repo's contents |
| <img src="./images/black_GHTeam.png" width="30"/> GHTeam                                  | user-group        | #C06EFF | A team within an organization, grouping users for shared access and collaboration.             |
| <img src="./images/black_GHTeamRole.png" width="30"/> GHTeamRole                          | user-tie          | #D0B0FF | The role a user has within a team (e.g. `maintainer`, `member`).                               |
| <img src="./images/black_GHUser.png" width="30"/> GHUser                                  | user              | #FF8E40 | An individual GitHub user account.                                                             |
| <img src="./images/black_GHWorkflow.png" width="30"/> GHWorkflow                          | cogs              | #FFE4A1 |                                                                                                |

### Edges

| Edge Type                                           | Source           | Target                  | Travesable | Custom |
|-----------------------------------------------------|------------------|-------------------------|------------|--------|
| `GHContains`                                        | `GHOrganization` | `GHOrgRole`             | n          | n/a    |
| `GHContains`                                        | `GHOrganization` | `GHRepoRole`            | n          | n/a    |
| `GHContains`                                        | `GHOrganization` | `GHRepository`          | n          | n/a    |
| `GHContains`                                        | `GHOrganization` | `GHTeamRole`            | n          | n/a    |
| `GHContains`                                        | `GHOrganization` | `GHTeam`                | n          | n/a    |
| `GHContains`                                        | `GHOrganization` | `GHUser`                | n          | n/a    |
| `OPContains`                                        | `GHRepository`   | `GHBranch`              | n          | n/a    |
| `GHHasRole`                                         | `GHUser`         | `GHOrgRole`             | y          | n/a    |
| `GHHasRole`                                         | `GHUser`         | `GHRepoRole`            | y          | n/a    |
| `GHHasRole`                                         | `GHUser`         | `GHTeamRole`            | y          | n/a    |
| `GHMemberOf`                                        | `GHTeamRole`     | `GHTeam`                | y          | n/a    |
| `GHMemberOf`                                        | `GHTeam`         | `GHTeam`                | y          | n/a    |
| `GHAddMember`                                       | `GHTeamRole`     | `GHTeam`                | y          | n/a    |
| `GHCreateRepository`                                | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHInviteMember`                                    | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHAddCollaborator`                                 | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHCreateTeam`                                      | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHTransferRepository`                              | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHManageOrganizationWebhooks`.                     | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHOrgBypassCodeScanningDismissalRequests`          | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHOrgReviewAndManageSecretScanningBypassRequests`  | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHOrgReviewAndManageSecretScanningClosureRequests` | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHReadOrganizationActionsUsageMetrics`             | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHReadOrganizationCustomOrgRole`                   | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHReadOrganizationCustomRepoRole`                  | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHResolveSecretScanningAlerts`                     | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHViewSecretScanningAlerts`                        | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHWriteOrganizationActionsSecrets`                 | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHWriteOrganizationActionsSettings`                | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHWriteOrganizationCustomOrgRole`                  | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHWriteOrganizationCustomRepoRole`                 | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHWriteOrganizationNetworkConfigurations`          | `GHOrgRole`      | `GHOrganization`        | n          | n/a    |
| `GHOwns`                                            | `GHOrganization` | `GHRepository`          | y          | n/a    |
| `GHBypassRequiredPullRequest`                       | `GHTeam`         | `GHBranch`              | n          | n/a    |
| `GHBypassRequiredPullRequest`                       | `GHUser`         | `GHBranch`              | n          | n/a    |
| `GHRestrictionsCanPush`                             | `GHTeam`         | `GHBranch`              | n          | n/a    |
| `GHRestrictionsCanPush`                             | `GHUser`         | `GHBranch`              | n          | n/a    |
| `GHHasBranch`                                       | `GHRepository`   | `GHBranch`              | n          | n/a    |
| `GHHasSecretScanningAlert`                          | `GHRepository`   | `GHSecretScanningAlert` | n          | n/a    |
| `GHHasBaseRole`                                     | `GHOrgRole`      | `GHOrgRole`             | y          | n/a    |
| `GHHasBaseRole`                                     | `GHOrgRole`      | `GHRepoRole`            | y          | n/a    |
| `GHHasBaseRole`                                     | `GHRepoRole`     | `GHRepoRole`            | y          | n/a    |
| `GHCanPull`                                         | `GHRepoRole`     | `GHRepository`          | y          | n/a    |
| `GHReadRepoContents`                                | `GHRepoRole`     | `GHRepository`          | y          | n      |
| `GHCanPush`                                         | `GHRepoRole`     | `GHRepository`          | n          | n      |
| `GHWriteRepoContents`                               | `GHRepoRole`     | `GHRepository`          | n          | n      |
| `GHWriteRepoPullRequests`                           | `GHRepoRole`     | `GHRepository`          | n          | n      |
| `GHAdminTo`                                         | `GHRepoRole`     | `GHRepository`          | n          | n      |
| `GHManageWebhooks`                                  | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHManageDeployKeys`                                | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHPushProtectedBranch`                             | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHDeleteAlertsCodeScanning`                        | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHViewSecretScanningAlerts`                        | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHRunOrgMigration`                                 | `GHRepoRole`     | `GHRepository`          | n          | n      |
| `GHBypassBranchProtection`                          | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHManageSecurityProducts`                          | `GHRepoRole`     | `GHRepository`          | n          | n      |
| `GHManageRepoSecurityProducts`                      | `GHRepoRole`     | `GHRepository`          | n          | n      |
| `GHEditRepoProtections`                             | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHJumpMergeQueue`                                  | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHCreateSoloMergeQueue`                            | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHEditRepoCustomPropertiesValue`                   | `GHRepoRole`     | `GHRepository`          | n          | y      |
| `GHHasWorkflow`                                     | `GHRepository`   | `GHWorkflow`            | n          | n/a    |
| `GHHasEnvironment`                                  | `GHRepository`   | `GHEnvironment`         | n          | n/a    |
| `GHHasEnvironment`                                  | `GHBranch`       | `GHEnvironment`         | n          | n/a    |

#### Structural Edges

This section should describe the edges that can be used to understand which prinicipals have which permissions.
It's going to be something like this `(adminUsers:GHUser)-[:GHMemberOf|GHHasRole|GHHasBaseRole|GHOwns|GHAddMember*1..3]->(:GHRepoRole)-[:GHAdminTo]->(:GHRepository)`

#### Hybrid Edges

| Edge Type                                           | Source           | Target                  | Travesable | Custom |
|-----------------------------------------------------|------------------|-------------------------|------------|--------|
| `SyncedToGHUser`                                    | `AZUser`         | `GHUser`                | y          | n/a    |
| `SyncedToGHUser`                                    | `PingOnUser`     | `GHUser`                | y          | n/a    |
| `GHCanAssumeAWSRole`                                | `GHBranch`       | `AWSRole`               | y          | n/a    |
| `GHCanAssumeAWSRole`                                | `GHEnvironment`  | `AWSRole`               | y          | n/a    |
| `GHCanAssumeAWSRole`                                | `GHRepository`   | `AWSRole`               | y          | n/a    |

## Usage Examples

### What Repos does a User have Write Access to?

Find the object identifier for your target user:

```cypher
MATCH (n:GHUser)
RETURN n
```

HINT: Select Table Layout

https://github.com/user-attachments/assets/1ddfd075-2a15-4aa9-bad7-74c43e6c82d6

Replace the `<object_id>` value in the subsequent query with the user's object identifier:

```cypher
MATCH p = (:GHUser {objectid:"<object_id>"})-[:GHMemberOf|GHAddMember|GHHasRole|GHHasBaseRole|GHOwns*1..]->(:GHRepoRole)-[:GHWriteRepoContents]->(:GHRepository)
RETURN p
```

![User to Repos](./images/user-repo.png)

### Who has Write Access to a Repo?

Obtain the object identifier for your target repository:

```cypher
MATCH (n:GHRepository)
RETURN n
```

Take the object identifier for your target repository and replace the `<object_id>` value in the subsequent query with it:

```cypher
MATCH p = (:GHUser)-[:GHMemberOf|GHHasRole|GHHasBaseRole|GHOwns|GHAddMember*1..]->(:GHRepoRole)-[:GHWriteRepoContents]->(:GHRepository {objectid:"<object_id>"})
RETURN p
```

![Repo to Users](./images/who-repo.png)

### Members of the Organization Admins (Domain Admin equivalent)?

```cypher
MATCH p = (:GHUser)-[:GHHasRole|GHHasBaseRole]->(:GHOrgRole {short_name: "owners"})
RETURN p
```

![Org Admins](./images/org-admins.png)

### Users that are managed via SSO (Entra-only)

```cypher
MATCH p = (:AZUser)-[:SyncedToGHUser]->(:GHUser)
RETURN p
```

![SSO Users](./images/sso-users.png)

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
