# GH_Contains

## Edge Schema

- Source: [GH_Organization](../NodeDescriptions/GH_Organization.md), [GH_Repository](../NodeDescriptions/GH_Repository.md), [GH_Environment](../NodeDescriptions/GH_Environment.md)
- Destination: [GH_User](../NodeDescriptions/GH_User.md), [GH_Team](../NodeDescriptions/GH_Team.md), [GH_Repository](../NodeDescriptions/GH_Repository.md), [GH_OrgRole](../NodeDescriptions/GH_OrgRole.md), [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md), [GH_TeamRole](../NodeDescriptions/GH_TeamRole.md), [GH_OrgSecret](../NodeDescriptions/GH_OrgSecret.md), [GH_AppInstallation](../NodeDescriptions/GH_AppInstallation.md), [GH_PersonalAccessToken](../NodeDescriptions/GH_PersonalAccessToken.md), [GH_PersonalAccessTokenRequest](../NodeDescriptions/GH_PersonalAccessTokenRequest.md), [GH_RepoSecret](../NodeDescriptions/GH_RepoSecret.md), [GH_EnvironmentSecret](../NodeDescriptions/GH_EnvironmentSecret.md), [GH_SecretScanningAlert](../NodeDescriptions/GH_SecretScanningAlert.md)

## General Information

The non-traversable [GH_Contains](GH_Contains.md) edge represents structural containment within the GitHub resource hierarchy. The organization serves as the top-level container for users, teams, repositories, roles, secrets, app installations, and personal access tokens. Repositories contain their own repo-level secrets, and environments contain environment-scoped secrets. This edge is created by the collector to establish the organizational hierarchy of GitHub resources and is not traversable because containment alone does not imply privilege escalation.

```mermaid
graph LR
    node1("GH_Organization SpecterOps")
    node2("GH_User alice")
    node3("GH_Team engineering")
    node4("GH_Repository GitHound")
    node5("GH_RepoSecret DEPLOY_KEY")
    node1 -- GH_Contains --> node2
    node1 -- GH_Contains --> node3
    node1 -- GH_Contains --> node4
    node4 -- GH_Contains --> node5
```
