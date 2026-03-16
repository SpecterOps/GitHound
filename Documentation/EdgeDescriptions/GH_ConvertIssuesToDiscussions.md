# GH_ConvertIssuesToDiscussions

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_ConvertIssuesToDiscussions](GH_ConvertIssuesToDiscussions.md) edge represents a role's ability to convert issues to discussions, moving them from the issue tracker to the discussions forum. This permission is available to Triage, Write, Maintain, and Admin roles and custom roles that have been granted this specific permission.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\triage")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_ConvertIssuesToDiscussions --> repo
```
