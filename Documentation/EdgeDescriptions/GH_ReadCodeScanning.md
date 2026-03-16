# GH_ReadCodeScanning

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_ReadCodeScanning](GH_ReadCodeScanning.md) edge represents a role's ability to read code scanning analysis results and alerts. This permission is available to Write, Maintain, and Admin roles and custom roles that have been granted this specific permission. Code scanning alerts may reveal exploitable vulnerabilities in the codebase.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\write")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_ReadCodeScanning --> repo
```
