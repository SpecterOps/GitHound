# SCIM / SAML Provider Comparison

This note captures the current differences between two useful reference outputs:

- Enterprise-scoped Okta:
  - `output/k-nexusglobal/githound_saml_E_kgDOAAiv9g.json`
  - `output/k-nexusglobal/githound_scim_E_kgDOAAiv9g.json`
- Organization-scoped Entra:
  - `output/specterops-pre-gearset/githound_saml_MDEyOk9yZ2FuaXphdGlvbjI1NDA2NTYw.json`
  - `output/specterops-pre-gearset/githound_scim_MDEyOk9yZ2FuaXphdGlvbjI1NDA2NTYw.json`

The main goal is to understand what upstream IdP hybrid edges GitHound can justify today and what additional provider-specific work would be needed.

## Scope Differences

- Enterprise SCIM includes both `SCIM_User` and `SCIM_Group`.
- Organization SCIM currently includes only `SCIM_User`.
- Enterprise SCIM therefore supports:
  - `SCIM_MemberOf`
  - `SCIM_Group -> GH_EnterpriseTeam` via `SCIM_Provisioned`
- Organization SCIM does not currently have a GitHub-native group layer to correlate against.
- This is a GitHub product limitation, not just a current GitHound omission: organization-level SCIM does not expose a Group -> Team mapping comparable to the enterprise `SCIM_Group -> GH_EnterpriseTeam` path.

## Common Ground

Both outputs support the provider-agnostic GitHub bridge:

- `SCIM_User -> GH_ExternalIdentity`

That correlation is based on:

- `SCIM_User.id -> GH_ExternalIdentity.guid`
- `SCIM_User.userName -> GH_ExternalIdentity.scim_identity_username`

This is the stable shared layer and should remain provider-agnostic.

## Okta Enterprise Pattern

The enterprise Okta SAML provider exposes:

- `issuer = http://www.okta.com/...`
- `sso_url = https://<tenant>.oktapreview.com/...`
- `foreign_environmentid = <okta domain>`

The enterprise Okta SCIM users expose:

- `externalId = 00u...`

That gives GitHound a clean upstream-user correlation:

- `Okta_User -> SCIM_User`
  - `Okta_User.id = SCIM_User.externalId`

Enterprise SCIM groups expose:

- `SCIM_Group.externalId = <group name>`

Combined with the Okta SAML provider tenant, that supports:

- `Okta_Group -> SCIM_Group`
  - `Okta_Group.name = SCIM_Group.externalId`
  - `Okta_Group.oktaDomain = GH_SamlIdentityProvider.foreign_environmentid`

This is why `Resolve-GitHoundScimIdpCorrelations` currently produces upstream hybrid edges for Okta.

## Entra Organization Pattern

The organization Entra SAML provider exposes:

- `issuer = https://sts.windows.net/<tenant-guid>/`
- `sso_url = https://login.microsoftonline.com/<tenant-guid>/saml2`
- `foreign_environmentid = <tenant guid>`

The organization Entra SCIM users expose:

- `externalId = <GUID>`

That supports an upstream-user hybrid edge of the form:

- `AZUser -> SCIM_User`
  - keyed by the Entra object id / GUID

GitHound can derive that edge from the collected `GH_SamlIdentityProvider` context by matching:

- `AZUser.objectid = SCIM_User.externalId`
- `AZUser.tenantid = GH_SamlIdentityProvider.foreign_environmentid`

## Current Recommendation

Keep the current split:

- Always emit the provider-agnostic bridge:
  - `SCIM_User -> GH_ExternalIdentity`
- Emit provider-aware upstream hybrid edges only when the SAML provider shape gives us a strong match strategy.

That means today:

- supported:
  - `AZUser -> SCIM_User`
  - `Okta_User -> SCIM_User`
  - `Okta_Group -> SCIM_Group`
- not yet implemented:
  - any Entra group correlation

## Current Boundary

Entra support should remain organization/user focused until we have a validated enterprise Entra example with group semantics comparable to the Okta enterprise reference.
