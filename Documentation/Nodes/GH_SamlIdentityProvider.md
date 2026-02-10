# <img src="../images/GH_SamlIdentityProvider.png" width="50"/> GH_SamlIdentityProvider

Represents a SAML identity provider configured for the organization. This node captures the SAML SSO configuration details and serves as the parent container for external identity mappings. Through external identities, it enables linking GitHub users to their corporate identities in the identity provider.

Created by: `Git-HoundGraphQlSamlProvider`

## Properties

| Property Name          | Data Type | Description                                                |
| ---------------------- | --------- | ---------------------------------------------------------- |
| objectid               | string    | The GraphQL ID of the SAML identity provider.              |
| name                   | string    | Same as objectid.                                          |
| node_id                | string    | Same as objectid.                                          |
| environment_name       | string    | The name of the environment (GitHub organization).         |
| environment_id         | string    | The GraphQL ID of the environment (GitHub organization).                        |
| foreign_environment_id | string    | The ID of the foreign environment linked to this provider. |
| digest_method          | string    | The digest method used by the SAML provider.               |
| idp_certificate        | string    | The identity provider's X.509 certificate.                 |
| issuer                 | string    | The SAML issuer URL.                                       |
| signature_method       | string    | The signature method used by the SAML provider.            |
| sso_url                | string    | The SAML single sign-on URL.                               |

## Edges

### Outbound Edges

| Edge Kind             | Target Node        | Traversable | Description                                         |
| --------------------- | ------------------ | ----------- | --------------------------------------------------- |
| GH_HasExternalIdentity | GH_ExternalIdentity | No          | Identity provider has an external identity mapping. |

### Inbound Edges

| Edge Kind                 | Source Node    | Traversable | Description                                   |
| ------------------------- | -------------- | ----------- | --------------------------------------------- |
| GH_HasSamlIdentityProvider | GH_Organization | No          | Organization has this SAML identity provider. |

## Diagram

```mermaid
flowchart TD
    GH_Organization[fa:fa-building GH_Organization]
    GH_SamlIdentityProvider[fa:fa-id-badge GH_SamlIdentityProvider]
    GH_ExternalIdentity[fa:fa-arrows-left-right GH_ExternalIdentity]

    style GH_Organization fill:#5FED83
    style GH_SamlIdentityProvider fill:#5A6C8F
    style GH_ExternalIdentity fill:#8A8F98

    GH_Organization -.->|GH_HasSamlIdentityProvider| GH_SamlIdentityProvider
    GH_SamlIdentityProvider -.->|GH_HasExternalIdentity| GH_ExternalIdentity
```
