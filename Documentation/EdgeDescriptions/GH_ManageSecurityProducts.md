# GH_ManageSecurityProducts

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_ManageSecurityProducts](GH_ManageSecurityProducts.md) edge represents a role's ability to manage security product settings on the repository. This permission is available to Admin roles and custom roles that have been granted this specific permission. Managing security products allows enabling or disabling features such as secret scanning, code scanning, and Dependabot alerts. An attacker with this permission could disable security features to prevent detection of vulnerabilities or leaked secrets, making this a high-severity permission for security posture management.

```mermaid
graph LR
    user1("GH_User bob")
    adminRole("GH_RepoRole GitHound\admin")
    customRole("GH_RepoRole GitHound\security_admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> adminRole
    adminRole -- GH_ManageSecurityProducts --> repo
    customRole -- GH_ManageSecurityProducts --> repo
```
