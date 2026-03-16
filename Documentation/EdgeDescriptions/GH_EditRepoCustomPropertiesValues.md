# GH_EditRepoCustomPropertiesValues

## Edge Schema

- Source: [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_EditRepoCustomPropertiesValues](GH_EditRepoCustomPropertiesValues.md) edge represents a role's ability to edit custom property values on the repository. This permission is available to Admin roles and custom roles that have been granted this specific permission. Custom properties are organization-defined metadata fields on repositories that can be used for classification, compliance tagging, or policy enforcement via rulesets. Modifying custom property values could alter which organization-level rulesets apply to the repository, potentially bypassing security controls that are scoped by property-based targeting.

```mermaid
graph LR
    user1("GH_User alice")
    adminRole("GH_RepoRole GitHound\admin")
    repo("GH_Repository GitHound")
    user1 -- GH_HasRole --> adminRole
    adminRole -- GH_EditRepoCustomPropertiesValues --> repo
    adminRole -- GH_AdminTo --> repo
```
