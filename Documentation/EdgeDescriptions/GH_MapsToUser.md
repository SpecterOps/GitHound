---
kind: GH_MapsToUser
is_traversable: false
---

# GH_MapsToUser

## Edge Schema

- Source: [GH_ExternalIdentity](../Nodes/GH_ExternalIdentity.md)
- Destination: [GH_User](../Nodes/GH_User.md)

## General Information

The non-traversable `GH_MapsToUser` edge maps an external identity (provisioned via SAML or SCIM) to a GitHub user within the organization, or to an external IdP user (such as AZUser, Okta_User, or PingOneUser) in hybrid graph scenarios. It is created by `Git-HoundGraphQlSamlProvider` for SAML-linked identities and `Git-HoundScimUser` for SCIM-provisioned identities. This edge represents identity correlation rather than an attack path, connecting a user's external IdP account to their GitHub account for visibility into federated identity mappings.

```mermaid
graph LR
    extId1("GH_ExternalIdentity alice@specterops.io")
    extId2("GH_ExternalIdentity bob@specterops.io")
    user1("GH_User alice")
    user2("GH_User bob")
    extId1 -- GH_MapsToUser --> user1
    extId2 -- GH_MapsToUser --> user2
```
