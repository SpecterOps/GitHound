# GH_DeleteAlertsCodeScanning

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_DeleteAlertsCodeScanning](GH_DeleteAlertsCodeScanning.md) edge represents a role's ability to delete code scanning alerts from the repository. This permission is available to Admin roles and custom roles that have been granted this specific permission. Deleting code scanning alerts can obscure security vulnerabilities that have been detected in the codebase, which is significant from an audit and compliance perspective. An attacker with this permission could suppress evidence of vulnerabilities they have introduced.

```mermaid
graph LR
    user1("GH_User alice")
    adminRole("GH_RepoRole GitHound\admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> adminRole
    adminRole -- GH_DeleteAlertsCodeScanning --> repo
```
