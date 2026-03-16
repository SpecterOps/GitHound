# GH_ManageDeployKeys

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_ManageDeployKeys](GH_ManageDeployKeys.md) edge represents a role's ability to create, modify, and delete deploy keys for the repository. This permission is available to Admin roles and custom roles that have been granted this specific permission. Deploy keys provide SSH-based access to the repository, and a deploy key with write access can push commits directly without going through the GitHub web interface or API authentication. Managing deploy keys is security-significant because it enables the creation of persistent, credential-based access that operates outside the normal user authentication flow.

```mermaid
graph LR
    user1("GH_User alice")
    adminRole("GH_RepoRole GitHound\admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> adminRole
    adminRole -- GH_ManageDeployKeys --> repo
    adminRole -- GH_AdminTo --> repo
```
