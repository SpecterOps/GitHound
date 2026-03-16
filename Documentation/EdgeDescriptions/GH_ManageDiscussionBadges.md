# GH_ManageDiscussionBadges

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_ManageDiscussionBadges](GH_ManageDiscussionBadges.md) edge represents a role's ability to manage discussion badges used to highlight discussion participants. This permission is available to Write, Maintain, and Admin roles and custom roles that have been granted this specific permission.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\write")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_ManageDiscussionBadges --> repo
```
