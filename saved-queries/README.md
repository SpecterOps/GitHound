# GitHound Saved Queries

Pre-built Cypher queries for identifying security-relevant configurations across your GitHub organization. Each query is stored as an individual JSON file with `name`, `query`, and `description` fields, designed to be imported into BloodHound's saved queries feature.

## Severity Levels

| Indicator | Severity | Description |
|-----------|----------|-------------|
| :red_circle: | Critical | Active threats or exposures requiring immediate action |
| :orange_circle: | High | Misconfigurations that significantly weaken security posture |
| :yellow_circle: | Medium | Settings that reduce defense-in-depth or enable privilege escalation |
| :white_circle: | Low | Hygiene issues and awareness items for ongoing governance |

## Queries

### :red_circle: Critical &mdash; Active Threats

| # | File | Name | Description |
|---|------|------|-------------|
| 1 | `active-leaked-secrets.json` | Active Leaked Secrets | Finds secret scanning alerts that are both unresolved and confirmed active. These are valid, usable credentials committed to source code and represent an immediate compromise risk. |
| 2 | `secret-scanning-alerts.json` | Secret Scanning Alerts | Returns all repositories that have open secret scanning alerts. |
| 3 | `pats-all-repo-access.json` | PATs with Access to All Repositories | Finds fine-grained personal access tokens scoped to all repositories. A single compromised token grants access to every repository in the organization. |
| 4 | `expired-pats.json` | Expired Personal Access Tokens | Finds expired personal access tokens that still exist. Expired tokens should be cleaned up to reduce credential inventory and audit noise. |
| 5 | `pending-pat-requests.json` | Pending PAT Requests | Finds pending fine-grained personal access token requests awaiting approval. Review these to ensure requested permissions are appropriate before granting access. |

### :orange_circle: High &mdash; Organization Security Posture

| # | File | Name | Description |
|---|------|------|-------------|
| 6 | `default-repository-permissions.json` | Organizations with Default Repository Permission | Finds organizations where all members receive implicit access to every repository. When set to read, write, or admin instead of none, users may have unintentional access. |
| 7 | `orgs-without-2fa.json` | Organizations without 2FA | Finds organizations that do not require two-factor authentication. Without 2FA, member accounts are vulnerable to credential theft, phishing, and brute force attacks. |
| 8 | `members-can-fork-private-repos.json` | Members Can Fork Private Repositories | Finds organizations where members can fork private repositories to personal accounts. Forked copies leave organizational control and oversight. |
| 9 | `members-can-change-repo-visibility.json` | Members Can Change Repository Visibility | Finds organizations where members can change repository visibility. This allows any member to make a private repository public, potentially exposing source code and secrets. |
| 10 | `members-can-delete-repos.json` | Members Can Delete Repositories | Finds organizations where members can delete repositories. This poses a risk of accidental or malicious destruction of code and audit history. |
| 11 | `members-can-invite-outside-collaborators.json` | Members Can Invite Outside Collaborators | Finds organizations where any member can invite external users. This can lead to unauthorized third-party access to repositories without centralized oversight. |
| 12 | `members-can-create-public-repos.json` | Members Can Create Public Repositories | Finds organizations where members can create internet-facing public repositories. This increases the risk of accidental exposure of proprietary code or secrets. |
| 13 | `secret-scanning-disabled-new-repos.json` | Secret Scanning Disabled for New Repositories | Finds organizations where secret scanning is not automatically enabled for new repositories. New repositories will not detect committed credentials until manually enabled. |
| 14 | `push-protection-disabled-new-repos.json` | Secret Scanning Push Protection Disabled for New Repositories | Finds organizations where push protection is not enabled for new repositories. Without push protection, secrets can be committed without being blocked before they reach the repository. |
| 15 | `advanced-security-disabled-new-repos.json` | Advanced Security Disabled for New Repositories | Finds organizations where GitHub Advanced Security is not automatically enabled for new repositories. New repositories will lack code scanning, secret scanning, and other GHAS features. |
| 16 | `dependabot-alerts-disabled-new-repos.json` | Dependabot Alerts Disabled for New Repositories | Finds organizations where Dependabot alerts are not enabled for new repositories. Vulnerable dependencies in new repositories will go undetected. |
| 17 | `dependabot-updates-disabled-new-repos.json` | Dependabot Security Updates Disabled for New Repositories | Finds organizations where Dependabot security update PRs are not enabled for new repositories. Known vulnerable dependencies will not receive automated fix PRs. |
| 18 | `dependency-graph-disabled-new-repos.json` | Dependency Graph Disabled for New Repositories | Finds organizations where the dependency graph is not enabled for new repositories. Without the dependency graph, transitive dependency vulnerabilities cannot be tracked. |
| 19 | `all-actions-allowed.json` | All GitHub Actions Allowed | Finds organizations that allow all GitHub Actions to run, including third-party actions from the marketplace. This creates supply chain risk if a malicious or compromised action is used. |
| 20 | `actions-sha-pinning-not-required.json` | Actions SHA Pinning Not Required | Finds organizations that do not require SHA pinning for GitHub Actions. Without pinning, actions referenced by tag can be silently replaced with malicious versions. |

### :yellow_circle: Medium &mdash; Branch Protection & Privilege Escalation

| # | File | Name | Description |
|---|------|------|-------------|
| 21 | `web-commit-signoff-not-required.json` | Web Commit Signoff Not Required | Finds organizations that do not require sign-off for web-based commits. Without signoff, commit attribution cannot be verified. |
| 22 | `members-can-create-pages.json` | Members Can Create GitHub Pages | Finds organizations where members can create GitHub Pages sites. Pages can be used to host phishing content, data exfiltration endpoints, or other malicious resources. |
| 23 | `public-repos.json` | Public Repositories | Returns all public repositories. Public repositories expose all code, commit history, issues, and pull requests to the internet. Verify each is intentionally public. |
| 24 | `repos-secret-scanning-disabled.json` | Repositories with Secret Scanning Disabled | Finds repositories where secret scanning is disabled. Committed credentials in these repositories will not be detected by GitHub. |
| 25 | `private-repos-forking-allowed.json` | Private Repositories with Forking Allowed | Finds private repositories that allow forking. Forked copies of private repositories can leave organizational governance and visibility. |
| 26 | `branch-protection-admins-not-enforced.json` | Branch Protection Rules - Admins Not Enforced | Finds branch protection rules where administrators can bypass all protections. Admins can push directly, skip reviews, and override status checks on these branches. |
| 27 | `branch-protection-force-pushes.json` | Branch Protection Rules - Force Pushes Allowed | Finds branches where force pushes are allowed. Force pushes can rewrite commit history, potentially hiding malicious changes or destroying audit trails. |
| 28 | `branch-protection-deletions-allowed.json` | Branch Protection Rules - Deletions Allowed | Finds protected branches that can be deleted. Branch deletion can result in loss of code and removal of audit history. |
| 29 | `branch-protection-no-pr-reviews.json` | Branch Protection Rules - No Pull Request Reviews Required | Finds branches where pull request reviews are not required. Code can be merged directly without peer review, increasing the risk of undetected vulnerabilities or malicious changes. |
| 30 | `branch-protection-no-code-owner-reviews.json` | Branch Protection Rules - No Code Owner Reviews | Finds branches where code owner reviews are not required. Changes to security-critical paths can be merged without authorization from the designated code owners. |
| 31 | `branch-protection-self-approval.json` | Branch Protection Rules - Self-Approval Allowed | Finds branches where the author of the last push can approve their own pull request. This allows a single person to both write and approve code changes. |
| 32 | `branch-protection-no-status-checks.json` | Branch Protection Rules - No Status Checks Required | Finds branches where CI/CD status checks are not required before merging. Code with failing tests or security scans can be merged into protected branches. |
| 33 | `branch-protection-stale-reviews.json` | Branch Protection Rules - Stale Reviews Not Dismissed | Finds branches where stale reviews are not dismissed when new commits are pushed. An attacker could get a review approved, then push additional malicious commits that inherit the stale approval. |
| 34 | `unprotected-default-branches.json` | Unprotected Default Branches | Returns all default branches in repositories that are not protected. These branches have no review requirements, status checks, or push restrictions. |
| 35 | `unprotected-default-branch-with-workflow.json` | Repositories with Workflows and Unprotected Default Branch | Returns all repositories that have GitHub Actions workflows and an unprotected default branch. Users with write access can overwrite or change the workflow. |
| 36 | `unprotected-branches.json` | Unprotected Branches | Returns all unprotected branches in repositories. |
| 37 | `bypass-pr-requirements.json` | Users Who Can Bypass Pull Request Requirements | Finds users and teams that can bypass pull request review requirements on protected branches. These actors can merge code without any reviews. |
| 38 | `push-to-protected-branches.json` | Users Who Can Push to Protected Branches | Finds users and teams that are allowed to push directly to protected branches when push restrictions are enabled. These actors bypass the normal pull request workflow. |
| 39 | `dangerous-branch-perms.json` | Dangerous Branch Permissions | Identifies users with dangerous branch permissions in a GitHub organization, including bypass allowances on protection rules. |
| 40 | `org-roles-bypass-security-scanning.json` | Org Roles That Can Bypass Security Scanning | Finds organization roles with permissions to bypass or manage security scanning dismissals. These roles can suppress secret scanning and code scanning findings. |
| 41 | `github-to-azure-identity.json` | GitHub-to-Azure Identity Assumptions | Finds GitHub entities (repositories, branches, environments) that can assume Azure identities via OIDC federation. Verify that each trust relationship is intentional and scoped appropriately. |

### :white_circle: Low &mdash; Hygiene & Governance

| # | File | Name | Description |
|---|------|------|-------------|
| 42 | `environments-admin-bypass.json` | Environments Where Admins Can Bypass Protections | Finds deployment environments where administrators can bypass protection rules such as required reviewers and wait timers. Admins can deploy to these environments without any approval. |
| 43 | `app-installations-all-repos.json` | App Installations with Access to All Repositories | Finds GitHub App installations that have access to every repository in the organization. A compromised app credential would affect all repositories. |
| 44 | `users-without-external-identity.json` | GitHub Users Without External Identity Mapping | Finds GitHub users that are not linked to any external identity via SAML or SCIM. These users cannot be centrally offboarded through the identity provider and may retain access after employment ends. |
| 45 | `external-identities-without-scim.json` | External Identities Without SCIM Provisioning | Finds external identities that lack SCIM synchronization. Without SCIM, user deprovisioning in the identity provider will not automatically revoke GitHub access. |
| 46 | `org-owners.json` | Organization Owners | Returns all users who hold the organization owners role. |
| 47 | `privileged-custom-org-roles.json` | Privileged Custom Org Roles | Returns all custom organization roles that are privileged (i.e., have permissions that are not default). |
| 48 | `global-repo-perms.json` | Global Repo Permissions | Returns all users who hold a global repository permission role (i.e., roles that are not default). |
| 49 | `hybrid-identities.json` | External Identities | Returns all external identities (e.g., Azure or Okta users) that are associated with GitHub users. |
| 50 | `privileged-hybrid-identities.json` | Privileged Hybrid Identities | Returns all hybrid identities (e.g., Azure or Okta users) that are associated with GitHub users who hold the organization owners role. |
| 51 | `saml-configuration.json` | SAML Configuration Mapping | Finds SAML Identity Providers, their external identities, and mapped users. |
| 52 | `team-membership-admin.json` | Team Membership Admins | Returns all users who hold the maintainer role over a team, including team nesting. |
| 53 | `team-structure.json` | Team Structure | Returns the structure of teams within organizations, including team roles and their members. |
| 54 | `repository-workflows.json` | Repository Workflows | Returns all repository workflows. |
