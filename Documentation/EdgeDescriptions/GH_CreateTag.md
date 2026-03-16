# GH_CreateTag

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_CreateTag](GH_CreateTag.md) edge represents a role's ability to create tags and releases. This permission is available to Maintain and Admin roles and custom roles that have been granted this specific permission. Creating tags can trigger CI/CD workflows and publish release artifacts.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\maintain")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_CreateTag --> repo
```
