---
kind: GH_ValidToken
is_traversable: true
---

# GH_ValidToken

## Edge Schema

- Source: [GH_SecretScanningAlert](../NodeDescriptions/GH_SecretScanningAlert.md)
- Destination: [GH_User](../NodeDescriptions/GH_User.md)

## General Information

The traversable [GH_ValidToken](GH_ValidToken.md) edge represents a secret scanning alert that contains a valid, active GitHub Personal Access Token belonging to a specific user. Created by `Git-HoundSecretScanningAlert`, this edge is only emitted when the alert's state is `open`, the secret type is `github_personal_access_token`, and the token is confirmed valid by calling the GitHub API. This edge is traversable because possessing the leaked token grants the ability to act as the token's owner, effectively compromising that user's identity and all permissions granted to the token.

```mermaid
graph LR
    node1("GH_SecretScanningAlert #42")
    node2("GH_User jdoe")
    node1 -- GH_ValidToken --> node2
```
