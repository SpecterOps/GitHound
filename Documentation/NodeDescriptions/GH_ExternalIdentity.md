# <img src="../Icons/gh_externalidentity.png" width="50"/> GH_ExternalIdentity

Represents an external identity from a SAML or SCIM identity provider that is linked to a GitHub user. External identities map corporate user accounts (from providers like Okta, Azure AD, etc.) to GitHub user accounts, enabling single sign-on authentication. Each external identity can have both SAML and SCIM identity attributes.

Created by: `Git-HoundGraphQlSamlProvider`

## Properties

| Property Name             | Data Type | Description                                              |
| ------------------------- | --------- | -------------------------------------------------------- |
| objectid                  | string    | The GraphQL ID of the external identity.                 |
| node_id                   | string    | The GraphQL ID of the external identity.                 |
| name                      | string    | Same as objectid.                                        |
| guid                      | string    | The GUID of the external identity.                       |
| environmentid             | string    | The GraphQL ID of the environment (GitHub organization). |
| environment_name          | string    | The name of the environment (GitHub organization).       |
| saml_identity_family_name | string    | The family name from the SAML identity.                  |
| saml_identity_given_name  | string    | The given name from the SAML identity.                   |
| saml_identity_name_id     | string    | The SAML NameID attribute.                               |
| saml_identity_username    | string    | The username from the SAML identity.                     |
| scim_identity_family_name | string    | The family name from the SCIM identity.                  |
| scim_identity_given_name  | string    | The given name from the SCIM identity.                   |
| scim_identity_username    | string    | The username from the SCIM identity.                     |
| github_username           | string    | The GitHub login of the linked user.                     |
| github_user_id            | string    | The GraphQL ID of the linked GitHub user.                |

## Edges

### Outbound Edges

| Edge Kind                                             | Target Node           | Traversable | Description                                                                         |
| ----------------------------------------------------- | --------------------- | ----------- | ----------------------------------------------------------------------------------- |
| [GH_MapsToUser](../EdgeDescriptions/GH_MapsToUser.md) | [GH_User](GH_User.md) | No          | External identity maps to a GitHub user (via GitHub user ID).                       |
| [GH_MapsToUser](../EdgeDescriptions/GH_MapsToUser.md) | Foreign User Node     | No          | External identity maps to a user in a foreign environment (via SAML/SCIM username). |

### Inbound Edges

| Edge Kind                                                               | Source Node                                           | Traversable | Description                                        |
| ----------------------------------------------------------------------- | ----------------------------------------------------- | ----------- | -------------------------------------------------- |
| [GH_HasExternalIdentity](../EdgeDescriptions/GH_HasExternalIdentity.md) | [GH_SamlIdentityProvider](GH_SamlIdentityProvider.md) | No          | SAML identity provider has this external identity. |

## Diagram

```mermaid
flowchart TD
    GH_SamlIdentityProvider[fa:fa-id-badge GH_SamlIdentityProvider]
    GH_ExternalIdentity[fa:fa-arrows-left-right GH_ExternalIdentity]
    GH_User[fa:fa-user GH_User]
    AZUser[fa:fa-user AZUser]
    Okta_User[fa:fa-user Okta_User]
    PingOneUser[fa:fa-user PingOneUser]


    GH_SamlIdentityProvider -.->|GH_HasExternalIdentity| GH_ExternalIdentity
    GH_ExternalIdentity -.->|GH_MapsToUser| GH_User
    GH_ExternalIdentity -.->|GH_MapsToUser| AZUser
    GH_ExternalIdentity -.->|GH_MapsToUser| Okta_User
    GH_ExternalIdentity -.->|GH_MapsToUser| PingOneUser
```
