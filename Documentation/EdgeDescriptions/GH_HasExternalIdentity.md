# GH_HasExternalIdentity

## Edge Schema

- Source: [GH_SamlIdentityProvider](../NodeDescriptions/GH_SamlIdentityProvider.md)
- Destination: [GH_ExternalIdentity](../NodeDescriptions/GH_ExternalIdentity.md)

## General Information

The non-traversable [GH_HasExternalIdentity](GH_HasExternalIdentity.md) edge represents the relationship between a SAML identity provider and the external identities (SSO users) it manages. Created by `Git-HoundGraphQlSamlProvider` and `Git-HoundEnterpriseSamlProvider`, this edge links each external identity to the SAML provider that authenticated it. External identities are a key component in cross-platform attack path analysis because they bridge the gap between corporate identity providers and GitHub user accounts via the [GH_MapsToUser](GH_MapsToUser.md) edge. Enumerating external identities reveals which corporate users have linked GitHub accounts and enables mapping from IdP compromise to GitHub access.

In the hybrid SAML layer, this edge also participates in the derivation of `SAML_HasAccount`. When the same provider is normalized to `SAML_ServiceProvider` through `SAML_Implements`, GitHound combines `GH_HasExternalIdentity` with `GH_MapsToUser` to emit `SAML_ServiceProvider -[:SAML_HasAccount]-> GH_User`.

```mermaid
graph LR
    node1("GH_SamlIdentityProvider entra-id-sso")
    node2("GH_ExternalIdentity alice@specterops.io")
    node3("GH_ExternalIdentity bob@specterops.io")
    node4("GH_User alice")
    node5("SAML_ServiceProvider github.com")
    node1 -- GH_HasExternalIdentity --> node2
    node1 -- GH_HasExternalIdentity --> node3
    node2 -- GH_MapsToUser --> node4
    node1 -- SAML_Implements --> node5
    node5 -- SAML_HasAccount --> node4
```
