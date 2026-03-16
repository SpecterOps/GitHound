# GH_EditRepoMetadata

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_EditRepoMetadata](GH_EditRepoMetadata.md) edge represents a role's ability to edit repository metadata including description, homepage URL, and visibility settings. This permission is available to Maintain and Admin roles and custom roles that have been granted this specific permission.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\maintain")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_EditRepoMetadata --> repo
```
