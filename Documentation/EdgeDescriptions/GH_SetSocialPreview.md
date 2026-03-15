---
kind: GH_SetSocialPreview
is_traversable: false
---

# GH_SetSocialPreview

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_SetSocialPreview](GH_SetSocialPreview.md) edge represents a role's ability to set the repository social preview image shown in link previews. This permission is available to Maintain and Admin roles and custom roles that have been granted this specific permission.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\maintain")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_SetSocialPreview --> repo
```
