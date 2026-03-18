# <img src="../Icons/gh_externalidentity.png" width="50"/> GH_ExternalIdentity

Represents an external identity from a SAML or SCIM identity provider that is linked to a GitHub user. External identities map corporate user accounts (from providers like Okta, Azure AD, etc.) to GitHub user accounts, enabling single sign-on authentication. Each external identity can have both SAML and SCIM identity attributes.

Created by: `Git-HoundGraphQlSamlProvider`, `Git-HoundEnterpriseSamlProvider`

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

## Diagram

```mermaid
flowchart TD
    GH_SamlIdentityProvider[fa:fa-id-badge GH_SamlIdentityProvider]
    GH_ExternalIdentity[fa:fa-arrows-left-right GH_ExternalIdentity]
    GH_User[fa:fa-user GH_User]
    AZUser[fa:fa-user AZUser]
    Okta_User[fa:fa-user Okta_User]
    PingOneUser[fa:fa-user PingOneUser]


    SCIM_User[fa:fa-user-gear SCIM_User]

    GH_SamlIdentityProvider -.->|GH_HasExternalIdentity| GH_ExternalIdentity
    GH_ExternalIdentity -.->|GH_MapsToUser| GH_User
    GH_ExternalIdentity -.->|GH_MapsToUser| AZUser
    GH_ExternalIdentity -.->|GH_MapsToUser| Okta_User
    GH_ExternalIdentity -.->|GH_MapsToUser| PingOneUser
    SCIM_User -->|SCIM_Provisioned| GH_ExternalIdentity
```
