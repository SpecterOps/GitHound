---
kind: GH_ManageSettingsPages
is_traversable: false
---

# GH_ManageSettingsPages

## Edge Schema

- Source: [GH_RepoRole](../Nodes/GH_RepoRole.md)
- Destination: [GH_Repository](../Nodes/GH_Repository.md)

## General Information

The non-traversable `GH_ManageSettingsPages` edge represents a role's ability to manage GitHub Pages settings including enabling, disabling, and configuring the source. This permission is available to Maintain and Admin roles and custom roles that have been granted this specific permission.

```mermaid
graph LR
    user1("GH_User alice")
    role("GH_RepoRole GitHound\\maintain")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> role
    role -- GH_ManageSettingsPages --> repo
```
