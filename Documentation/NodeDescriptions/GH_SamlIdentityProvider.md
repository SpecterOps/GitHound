# <img src="../Icons/gh_samlidentityprovider.png" width="50"/> GH_SamlIdentityProvider

Represents a SAML identity provider configured for either an organization or an enterprise. This node captures the SAML SSO configuration details and serves as the parent container for external identity mappings. Through external identities, it enables linking GitHub users to their corporate identities in the identity provider.

Created by: `Git-HoundGraphQlSamlProvider`, `Git-HoundEnterpriseSamlProvider`

## Properties

| Property Name         | Data Type | Description                                                |
| --------------------- | --------- | ---------------------------------------------------------- |
| objectid              | string    | The GraphQL ID of the SAML identity provider.              |
| name                  | string    | Same as objectid.                                          |
| node_id               | string    | Same as objectid.                                          |
| environment_name      | string    | The name of the environment where the provider is configured (GitHub organization or enterprise). |
| environmentid         | string    | The GraphQL ID of the environment where the provider is configured (GitHub organization or enterprise). |
| foreign_environmentid | string    | The ID of the foreign environment linked to this provider. |
| digest_method         | string    | The digest method used by the SAML provider.               |
| idp_certificate       | string    | The identity provider's X.509 certificate.                 |
| issuer                | string    | The SAML issuer URL.                                       |
| signature_method      | string    | The signature method used by the SAML provider.            |
| sso_url               | string    | The SAML single sign-on URL.                               |

## Diagram

```mermaid
flowchart TD
    GH_Enterprise[fa:fa-globe GH_Enterprise]
    GH_Organization[fa:fa-building GH_Organization]
    GH_SamlIdentityProvider[fa:fa-id-badge GH_SamlIdentityProvider]
    GH_ExternalIdentity[fa:fa-arrows-left-right GH_ExternalIdentity]


    GH_Enterprise -.->|GH_HasSamlIdentityProvider| GH_SamlIdentityProvider
    GH_Organization -.->|GH_HasSamlIdentityProvider| GH_SamlIdentityProvider
    GH_SamlIdentityProvider -.->|GH_HasExternalIdentity| GH_ExternalIdentity
```
