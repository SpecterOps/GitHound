# Privilege Zone Classification Rules

This directory contains Tier Zero (T0) classification rules for GitHub organizations collected by GitHound. These rules identify assets whose compromise grants control over the entire organization or the ability to compromise everything else.

For the full rationale and classification methodology, see [Documentation/TIER_ZERO.md](../Documentation/TIER_ZERO.md).

## Rule Format

Each rule is a JSON file with the following schema:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Display name prefixed with `GitHub: Tier Zero` |
| `description` | string | Explanation of why this asset is T0 |
| `cypher` | string | Cypher query that returns nodes to classify as T0 |
| `enabled` | boolean | Whether the rule is active |
| `allow_disable` | boolean | Whether the rule can be disabled by the user |

All rules use `RETURN n` (returning individual nodes for classification) rather than `RETURN p` (returning paths for visualization).

## Rules

### Control Plane — Organizational Authority

| Rule | File | Description |
|------|------|-------------|
| Tier Zero Organizations | [t0-organizations.json](t0-organizations.json) | The organization itself — root trust boundary |
| Tier Zero Owners Role | [t0-owners-role.json](t0-owners-role.json) | The owners org role — full administrative control |
| Tier Zero Owner Users | [t0-owner-users.json](t0-owner-users.json) | Users holding the owners role |
| Tier Zero SAML Identity Providers | [t0-saml-identity-providers.json](t0-saml-identity-providers.json) | SAML IdP — controls SSO authentication |
| Tier Zero External Identities (Owner-Mapped) | [t0-external-identities-owners.json](t0-external-identities-owners.json) | IdP identities mapped to org owners |
| Tier Zero Privilege Escalation Roles | [t0-privilege-escalation-roles.json](t0-privilege-escalation-roles.json) | Custom roles with `write_organization_custom_org_role` — guaranteed self-escalation to all_repo_admin |
| Tier Zero Privilege Escalation Users | [t0-privilege-escalation-users.json](t0-privilege-escalation-users.json) | Users holding privilege escalation roles |

### Data Plane — Universal Repository Access

| Rule | File | Description |
|------|------|-------------|
| Tier Zero All-Repo Admin Role | [t0-all-repo-admin-role.json](t0-all-repo-admin-role.json) | Synthetic role granting admin on every repository |
| Tier Zero App Installations (All Repositories) | [t0-app-installations-all-repos.json](t0-app-installations-all-repos.json) | App installations scoped to all repositories |
| Tier Zero Apps (All-Repository Installations) | [t0-apps-all-repos.json](t0-apps-all-repos.json) | App definitions with all-repository installations |
| Tier Zero PATs (All Repositories) | [t0-pats-all-repos.json](t0-pats-all-repos.json) | Personal access tokens scoped to all repositories |
