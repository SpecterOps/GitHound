# Privilege Zone Rules
The following Cypher rules define the default Privilege Zone for the GitHound extension.
Each rule is defined in a JSON file located in the [PrivilegeZoneRules](../pz-rules) directory of the GitHound repository.

## Tier Zero All-Repo Admin Role

The synthetic all_repo_admin role grants admin access to every repository in the organization. This role is inherited by the owners role via GH_HasBaseRole and cascades admin permissions including branch protection editing, secret access, and deploy key management to all repositories.

```cypher
MATCH (n:GH_OrgRole)
WHERE n.name ENDS
WITH '/all_repo_admin'
RETURN n
```

This rule is defined in the [t0-all-repo-admin-role.json](../pz-rules/t0-all-repo-admin-role.json) file.

## Tier Zero App Installations (All Repositories)

GitHub App installations scoped to all repositories in the organization that have at least one write permission. A compromised app credential grants write access to every repository. Installations with only read permissions are excluded — they pose a data exfiltration risk but do not grant control over the organization.

```cypher
MATCH (n:GH_AppInstallation {repository_selection:'all'})
WHERE n.permissions CONTAINS '"write"'
RETURN n
```

This rule is defined in the [t0-app-installations-all-repos.json](../pz-rules/t0-app-installations-all-repos.json) file.

## Tier Zero Apps (All-Repository Installations)

GitHub App definitions whose installations have write access to all repositories. The app owner controls the private key that can generate tokens for any installation. Compromise of the app's private key grants write access to every repository in organizations where it is installed. Apps whose installations have only read permissions are excluded.

```cypher
MATCH (n:GH_App)-[:GH_InstalledAs]->(i:GH_AppInstallation {repository_selection:'all'})
WHERE i.permissions CONTAINS '"write"'
RETURN n
```

This rule is defined in the [t0-apps-all-repos.json](../pz-rules/t0-apps-all-repos.json) file.

## Tier Zero External Identities (Owner-Mapped)

External identities from SAML/SCIM providers that map to GitHub users holding the owners role. Compromise of these external identities in the identity provider grants organizational owner access to GitHub via SSO.

```cypher
MATCH (n:GH_ExternalIdentity)-[:GH_MapsToUser]->(:GH_User)-[:GH_HasRole]->(:GH_OrgRole {short_name:'owners'})
RETURN n
```

This rule is defined in the [t0-external-identities-owners.json](../pz-rules/t0-external-identities-owners.json) file.

## Tier Zero Organizations

GitHub organizations are the root trust boundary for all repositories, teams, users, and settings. Compromise of the organization grants full administrative control over all contained assets.

```cypher
MATCH (n:GH_Organization)
RETURN n
```

This rule is defined in the [t0-organizations.json](../pz-rules/t0-organizations.json) file.

## Tier Zero Owner Users

Users who hold the organization owners role have full administrative control over the GitHub organization. Compromise of any owner account grants control over all repositories, secrets, SSO configuration, and cloud identities.

```cypher
MATCH (n:GH_User)-[:GH_HasRole]->(:GH_OrgRole {short_name:'owners'})
RETURN n
```

This rule is defined in the [t0-owner-users.json](../pz-rules/t0-owner-users.json) file.

## Tier Zero Owners Role

The owners organization role grants full administrative control including all repository admin, member management, SSO configuration, app management, and billing. Owners inherit all_repo_admin, cascading admin access to every repository, secret, environment, and cloud identity in the organization.

```cypher
MATCH (n:GH_OrgRole {short_name:'owners'})
RETURN n
```

This rule is defined in the [t0-owners-role.json](../pz-rules/t0-owners-role.json) file.

## Tier Zero PATs (All Repositories)

Fine-grained personal access tokens scoped to all repositories in the organization that have at least one write permission. A single compromised token grants write access to every repository. PATs with only read permissions are excluded — they pose a data exfiltration risk but do not grant control over the organization.

```cypher
MATCH (n:GH_PersonalAccessToken {repository_selection:'all'})
WHERE n.permissions CONTAINS '"write"'
RETURN n
```

This rule is defined in the [t0-pats-all-repos.json](../pz-rules/t0-pats-all-repos.json) file.

## Tier Zero Privilege Escalation Roles

Custom organization roles with write_organization_custom_org_role permission can modify organization role definitions, including setting the base_role to inherit all_repo_admin. Since this permission only exists on custom organization roles, the holder can escalate the role they already hold — a guaranteed self-escalation path to full organizational control.

```cypher
MATCH (n:GH_OrgRole)-[:GH_WriteOrganizationCustomOrgRole]->(:GH_Organization)
RETURN n
```

This rule is defined in the [t0-privilege-escalation-roles.json](../pz-rules/t0-privilege-escalation-roles.json) file.

## Tier Zero Privilege Escalation Users

Users who hold custom organization roles with write_organization_custom_org_role permission. These users can modify organization role definitions — including the role they hold — to set the base_role to all_repo_admin, granting themselves admin access to every repository in the organization.

```cypher
MATCH (n:GH_User)-[:GH_HasRole|GH_HasBaseRole*1..]->(:GH_OrgRole)-[:GH_WriteOrganizationCustomOrgRole]->(:GH_Organization)
RETURN n
```

This rule is defined in the [t0-privilege-escalation-users.json](../pz-rules/t0-privilege-escalation-users.json) file.

## Tier Zero SAML Identity Providers

SAML identity providers control authentication for all organization members via SSO. Compromise of the identity provider grants the ability to impersonate any user, including organization owners, by manipulating SAML assertions or resetting credentials.

```cypher
MATCH (n:GH_SamlIdentityProvider)
RETURN n
```

This rule is defined in the [t0-saml-identity-providers.json](../pz-rules/t0-saml-identity-providers.json) file.

