# GH_HasSamlIdentityProvider

## Edge Schema

- Source: [GH_Organization](../NodeDescriptions/GH_Organization.md), [GH_Enterprise](../NodeDescriptions/GH_Enterprise.md)
- Destination: [GH_SamlIdentityProvider](../NodeDescriptions/GH_SamlIdentityProvider.md)

## General Information

The non-traversable [GH_HasSamlIdentityProvider](GH_HasSamlIdentityProvider.md) edge represents the relationship between an organization or enterprise and its SAML identity provider configuration. Created by `Git-HoundGraphQlSamlProvider` and `Git-HoundEnterpriseSamlProvider`, this edge links the GitHub scope to the SAML SSO provider used for authentication and user provisioning. SAML identity providers are a critical security component because they establish the trust boundary between an external identity provider (such as Entra ID or Okta) and the GitHub environment. Understanding this relationship is essential for mapping cross-platform attack paths where compromise of the identity provider could lead to access within GitHub.

```mermaid
graph LR
    node0("GH_Enterprise Example-Enterprise")
    node1("GH_Organization SpecterOps")
    node2("GH_SamlIdentityProvider entra-id-sso")
    node3("GH_ExternalIdentity alice@specterops.io")
    node0 -- GH_HasSamlIdentityProvider --> node2
    node1 -- GH_HasSamlIdentityProvider --> node2
    node2 -- GH_HasExternalIdentity --> node3
```
