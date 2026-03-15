---
kind: GH_HasPersonalAccessToken
is_traversable: false
---

# GH_HasPersonalAccessToken

## Edge Schema

- Source: [GH_User](../NodeDescriptions/GH_User.md)
- Destination: [GH_PersonalAccessToken](../NodeDescriptions/GH_PersonalAccessToken.md)

## General Information

The non-traversable [GH_HasPersonalAccessToken](GH_HasPersonalAccessToken.md) edge represents the relationship between a user and their fine-grained personal access tokens that have been granted access to the organization. Created by `Git-HoundPersonalAccessToken`, this edge links each approved token back to the user who created it. Fine-grained personal access tokens are security-significant because they provide programmatic access to organization resources with specific scoped permissions. Tracking token ownership is essential for understanding which users have standing API access and for identifying tokens that may need revocation.

```mermaid
graph LR
    node1("GH_User alice")
    node2("GH_PersonalAccessToken ci-deploy-token")
    node3("GH_PersonalAccessToken read-only-audit")
    node4("GH_User bob")
    node5("GH_PersonalAccessToken automation-token")
    node1 -- GH_HasPersonalAccessToken --> node2
    node1 -- GH_HasPersonalAccessToken --> node3
    node4 -- GH_HasPersonalAccessToken --> node5
```
