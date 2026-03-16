# GH_CanAccess

## Edge Schema

- Source: [GH_PersonalAccessToken](../NodeDescriptions/GH_PersonalAccessToken.md), [GH_AppInstallation](../NodeDescriptions/GH_AppInstallation.md)
- Destination: [GH_Repository](../NodeDescriptions/GH_Repository.md)

## General Information

The non-traversable [GH_CanAccess](GH_CanAccess.md) edge indicates that a personal access token or app installation has been granted access to specific repositories. It is created by `Git-HoundPersonalAccessToken` and `Git-HoundPersonalAccessTokenRequest` for PATs, and by `Git-HoundAppInstallation` for app installations. This edge represents the scope of access granted to a token or app rather than a direct attack path, providing visibility into which repositories are reachable through non-human credentials. It is non-traversable because token and app access does not transitively extend to other principals.

```mermaid
graph LR
    pat("GH_PersonalAccessToken pat-alice-readonly")
    install("GH_AppInstallation ci-bot#6789")
    repo1("GH_Repository GitHound")
    repo2("GH_Repository BloodHound")
    pat -- GH_CanAccess --> repo1
    install -- GH_CanAccess --> repo1
    install -- GH_CanAccess --> repo2
```
