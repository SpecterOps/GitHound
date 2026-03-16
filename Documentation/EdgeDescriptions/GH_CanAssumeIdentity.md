# GH_CanAssumeIdentity

## Edge Schema

- Source: [GH_Repository](../NodeDescriptions/GH_Repository.md), [GH_Branch](../NodeDescriptions/GH_Branch.md), [GH_Environment](../NodeDescriptions/GH_Environment.md)
- Destination: [AZFederatedIdentityCredential](https://bloodhound.specterops.io/resources/nodes/az-federated-identity-credential), [AWSRole](https://bloodhound.specterops.io/resources/nodes/aws-role)

## General Information

The traversable [GH_CanAssumeIdentity](GH_CanAssumeIdentity.md) edge is a hybrid edge connecting GitHub OIDC token sources to cloud identity targets configured for GitHub Actions federation. Created by the collector when matching GitHub OIDC subject claims to cloud workload identity federation configurations, this edge represents a verified path from GitHub Actions to cloud resource access. It is traversable because an attacker who can execute workflows in the source repository, branch, or environment can obtain an OIDC token that the cloud provider will accept, granting access to the associated cloud identity and its permissions. This edge is critical for identifying cross-cloud lateral movement paths from GitHub into Azure and AWS.

```mermaid
graph LR
    repo("GH_Repository GitHound")
    branch("GH_Branch main")
    env("GH_Environment production")
    azFic("AZFederatedIdentityCredential gh-deploy-prod")
    awsRole("AWSRole gh-actions-deploy-prod")
    repo -- GH_CanAssumeIdentity --> azFic
    branch -- GH_CanAssumeIdentity --> awsRole
    env -- GH_CanAssumeIdentity --> azFic
```
