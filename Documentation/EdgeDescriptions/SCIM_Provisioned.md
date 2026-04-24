# SCIM_Provisioned

## Edge Schema

- Source: `SCIM_User`
- Destination: [GH_ExternalIdentity](../NodeDescriptions/GH_ExternalIdentity.md)

## General Information

The traversable `SCIM_Provisioned` edge correlates a SCIM-provisioned user record to the matching GitHub external identity. In GitHound, this edge is created by `Git-HoundScimUser` and `Git-HoundEnterpriseScimUser` when a SCIM user can be matched to a `GH_ExternalIdentity` using both the SCIM resource identifier and the SCIM username.

This edge is intentionally stronger than a loose name-only match. The current correlation uses:

- `SCIM_User.id`
- `GH_ExternalIdentity.guid`
- `SCIM_User.userName`
- `GH_ExternalIdentity.scim_identity_username`

That gives us a reliable bridge from the raw SCIM layer into GitHub's native external identity object without skipping straight to `GH_User`.

```mermaid
graph LR
    scimUser("SCIM_User d3c9cc90-1e3a-11f1-9caf-aeaf7c29665a")
    extId("GH_ExternalIdentity grace.roberts@k-nexusglobal.com")
    ghUser("GH_User grace-roberts_knexus")

    scimUser -- SCIM_Provisioned --> extId
    extId -. GH_MapsToUser .-> ghUser
```
