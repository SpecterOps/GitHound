---
kind: GH_InstalledAs
is_traversable: true
---

# GH_InstalledAs

## Edge Schema

- Source: [GH_App](../Nodes/GH_App.md)
- Destination: [GH_AppInstallation](../Nodes/GH_AppInstallation.md)

## General Information

The traversable `GH_InstalledAs` edge links a GitHub App to its installation within the organization. It is created by `Git-HoundAppInstallation` during app installation enumeration. This edge is traversable because it connects the app definition to its active installation, which determines the specific set of repositories and permissions the app has been granted. Understanding the relationship between an app and its installation is essential for tracing how app-level permissions translate into repository access.

```mermaid
graph LR
    app("GH_App dependabot")
    install("GH_AppInstallation dependabot#12345")
    repo1("GH_Repository GitHound")
    repo2("GH_Repository BloodHound")
    app -- GH_InstalledAs --> install
    install -- GH_CanAccess --> repo1
    install -- GH_CanAccess --> repo2
```
