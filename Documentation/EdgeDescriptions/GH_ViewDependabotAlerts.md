# GH_ViewDependabotAlerts

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_ViewDependabotAlerts](GH_ViewDependabotAlerts.md) edge represents a role's ability to view Dependabot security alerts, which reveal known vulnerabilities in the repository's dependencies. This permission is available to Write, Maintain, and Admin roles and custom roles that have been granted this specific permission. This information could be used to identify and exploit unpatched vulnerabilities.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\write")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_ViewDependabotAlerts --> repo
```
