# Custom BloodHound Edges for GitHub

## Intra-Organization Edges

The following table summarizes the custom edge kinds used by `GitHound`:

| Edge Type | Source Node Kinds | Target Node Kinds | Traversable |
|-----------|-------------------|-------------------|-------------|
| [GH_Contains] | [GH_Organization] | [GH_User], [GH_Team], [GH_Repository], [GH_OrgRole], [GH_RepoRole], [GH_TeamRole], [GH_OrgSecret], [GH_AppInstallation], [GH_PersonalAccessToken], [GH_PersonalAccessTokenRequest] | ❌ |
|               | [GH_Repository]   | [GH_RepoSecret] | ❌ |
|               | [GH_Environment]  | [GH_EnvironmentSecret] | ❌ |
| [GH_Owns] | [GH_Organization] | [GH_Repository] | ✅ |
| [GH_HasRole] | [GH_User], [GH_Team] | [GH_OrgRole], [GH_RepoRole], [GH_TeamRole] | ✅ |
| [GH_MemberOf] | [GH_TeamRole] | [GH_Team] | ✅ |
|               | [GH_Team]     | [GH_Team] | ✅ |
| [GH_AddMember] | [GH_TeamRole] | [GH_Team] | ✅ |
| [GH_HasBaseRole] | [GH_OrgRole]  | [GH_OrgRole], [GH_RepoRole] | ✅ |
|                  | [GH_RepoRole] | [GH_RepoRole] | ✅ |
| [GH_CreateRepository] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_InviteMember] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_AddCollaborator] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_CreateTeam] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_TransferRepository] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_ManageOrganizationWebhooks] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_OrgBypassCodeScanningDismissalRequests] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_OrgBypassSecretScanningClosureRequests] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHWriteOrganizationActionsSecrets] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHWriteOrganizationActionsSettings] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_ViewSecretScanningAlerts] | [GH_OrgRole] | [GH_Organization] | ❌ |
|                               | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHResolveSecretScanningAlerts] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHReadOrganizationActionsUsageMetrics] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHReadOrganizationCustomOrgRole] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHReadOrganizationCustomRepoRole] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHWriteOrganizationCustomOrgRole] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHWriteOrganizationCustomRepoRole] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHWriteOrganizationNetworkConfigurations] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHOrgReviewAndManageSecretScanningBypassRequests] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GHOrgReviewAndManageSecretScanningClosureRequests] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_CanPull] | [GH_RepoRole] | [GH_Repository] | ✅ |
| [GH_ReadRepoContents] | [GH_RepoRole] | [GH_Repository] | ✅ |
| [GH_CanPush] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_WriteRepoContents] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHWriteRepoPullRequests] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_AdminTo] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_BypassProtections] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_EditProtections] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHManageWebhooks] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHManageDeployKeys] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHPushProtectedBranch] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHDeleteAlertsCodeScanning] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHRunOrgMigration] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHBypassBranchProtection] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHManageSecurityProducts] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHManageRepoSecurityProducts] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHEditRepoProtections] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHJumpMergeQueue] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHCreateSoloMergeQueueEntry] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GHEditRepoCustomPropertiesValue] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_ProtectedBy] | [GH_BranchProtectionRule] | [GH_Branch] | ✅ |
| [GH_BypassPullRequestAllowances] | [GH_User], [GH_Team] | [GH_BranchProtectionRule] | ❌ |
| [GH_RestrictionsCanPush] | [GH_User], [GH_Team] | [GH_BranchProtectionRule] | ❌ |
| [GH_HasBranch] | [GH_Repository] | [GH_Branch] | ❌ |
| [GH_HasWorkflow] | [GH_Repository] | [GH_Workflow] | ❌ |
| [GH_HasEnvironment] | [GH_Repository] | [GH_Environment] | ❌ |
|                     | [GH_Branch]     | [GH_Environment] | ❌ |
| [GH_HasSecret] | [GH_Repository] | [GH_OrgSecret], [GH_RepoSecret] | ❌ |
|                | [GH_Environment] | [GH_EnvironmentSecret] | ❌ |
| [GH_HasSecretScanningAlert] | [GH_Repository] | [GH_SecretScanningAlert] | ❌ |
| [GH_HasSamlIdentityProvider] | [GH_Organization] | [GH_SamlIdentityProvider] | ❌ |
| [GH_HasExternalIdentity] | [GH_SamlIdentityProvider] | [GH_ExternalIdentity] | ❌ |
| [GH_MapsToUser] | [GH_ExternalIdentity] | [GH_User] | ❌ |
| [GH_HasPersonalAccessToken] | [GH_User] | [GH_PersonalAccessToken] | ❌ |
| [GH_HasPersonalAccessTokenRequest] | [GH_User] | [GH_PersonalAccessTokenRequest] | ❌ |
| [GH_InstalledAs] | [GH_App] | [GH_AppInstallation] | ✅ |
| [GH_CanAccess] | [GH_PersonalAccessToken] | [GH_Repository] | ❌ |
|                 | [GH_AppInstallation]     | [GH_Repository] | ❌ |

## Hybrid Edges

Hybrid edges connect GitHub entities to entities from other supported BloodHound collectors, such as Azure (Entra ID), AWS, Okta, and PingOne.

### Microsoft Entra ID (Azure Active Directory)

| Edge Type           | Source Node Kinds     | Target Node Kinds               | Traversable |
|---------------------|-----------------------|---------------------------------|-------------|
| [SyncedToGHUser]    | [AZUser]              | [GH_User]                       | ✅          |
| [GH_MapsToUser]     | [GH_ExternalIdentity] | [AZUser]                        | ❌          |
| [CanAssumeIdentity] | [GH_Repository]       | [AZFederatedIdentityCredential] | ✅          |
|                     | [GH_Branch]           | [AZFederatedIdentityCredential] | ✅          |
|                     | [GH_Environment]      | [AZFederatedIdentityCredential] | ✅          |

### Amazon Web Services

| Edge Type             | Source Node Kinds | Target Node Kinds | Traversable |
|-----------------------|-------------------|-------------------|-------------|
| [GH_CanAssumeAWSRole] | [GH_Repository]   | [AWSRole]         | ✅          |
|                       | [GH_Branch]       | [AWSRole]         | ✅          |
|                       | [GH_Environment]  | [AWSRole]         | ✅          |

### Okta

| Edge Type        | Source Node Kinds     | Target Node Kinds | Traversable |
|------------------|-----------------------|-------------------|-------------|
| [SyncedToGHUser] | [OktaUser]            | [GH_User]         | ✅          |
| [GH_MapsToUser]  | [GH_ExternalIdentity] | [OktaUser]        | ❌          |

### PingOne

| Edge Type        | Source Node Kinds     | Target Node Kinds | Traversable |
|------------------|-----------------------|-------------------|-------------|
| [SyncedToGHUser] | [PingOneUser]         | [GH_User]         | ✅          |
| [GH_MapsToUser]  | [GH_ExternalIdentity] | [PingOneUser]     | ❌          |

[GH_Contains]: Nodes/GH_Organization.md#outbound-edges
[GH_Owns]: Nodes/GH_Organization.md#outbound-edges
[GH_HasRole]: Nodes/GH_User.md#outbound-edges
[GH_MemberOf]: Nodes/GH_TeamRole.md#outbound-edges
[GH_AddMember]: Nodes/GH_TeamRole.md#outbound-edges
[GH_HasBaseRole]: Nodes/GH_OrgRole.md#outbound-edges
[GH_CreateRepository]: Nodes/GH_OrgRole.md#outbound-edges
[GH_InviteMember]: Nodes/GH_OrgRole.md#outbound-edges
[GH_AddCollaborator]: Nodes/GH_OrgRole.md#outbound-edges
[GH_CreateTeam]: Nodes/GH_OrgRole.md#outbound-edges
[GH_TransferRepository]: Nodes/GH_OrgRole.md#outbound-edges
[GH_ManageOrganizationWebhooks]: Nodes/GH_OrgRole.md#outbound-edges
[GH_OrgBypassCodeScanningDismissalRequests]: Nodes/GH_OrgRole.md#outbound-edges
[GH_OrgBypassSecretScanningClosureRequests]: Nodes/GH_OrgRole.md#outbound-edges
[GHWriteOrganizationActionsSecrets]: Nodes/GH_OrgRole.md#outbound-edges
[GHWriteOrganizationActionsSettings]: Nodes/GH_OrgRole.md#outbound-edges
[GH_ViewSecretScanningAlerts]: Nodes/GH_OrgRole.md#outbound-edges
[GHResolveSecretScanningAlerts]: Nodes/GH_OrgRole.md#outbound-edges
[GHReadOrganizationActionsUsageMetrics]: Nodes/GH_OrgRole.md#outbound-edges
[GHReadOrganizationCustomOrgRole]: Nodes/GH_OrgRole.md#outbound-edges
[GHReadOrganizationCustomRepoRole]: Nodes/GH_OrgRole.md#outbound-edges
[GHWriteOrganizationCustomOrgRole]: Nodes/GH_OrgRole.md#outbound-edges
[GHWriteOrganizationCustomRepoRole]: Nodes/GH_OrgRole.md#outbound-edges
[GHWriteOrganizationNetworkConfigurations]: Nodes/GH_OrgRole.md#outbound-edges
[GHOrgReviewAndManageSecretScanningBypassRequests]: Nodes/GH_OrgRole.md#outbound-edges
[GHOrgReviewAndManageSecretScanningClosureRequests]: Nodes/GH_OrgRole.md#outbound-edges
[GH_CanPull]: Nodes/GH_RepoRole.md#outbound-edges
[GH_ReadRepoContents]: Nodes/GH_RepoRole.md#outbound-edges
[GH_CanPush]: Nodes/GH_RepoRole.md#outbound-edges
[GH_WriteRepoContents]: Nodes/GH_RepoRole.md#outbound-edges
[GHWriteRepoPullRequests]: Nodes/GH_RepoRole.md#outbound-edges
[GH_AdminTo]: Nodes/GH_RepoRole.md#outbound-edges
[GH_BypassProtections]: Nodes/GH_RepoRole.md#outbound-edges
[GH_EditProtections]: Nodes/GH_RepoRole.md#outbound-edges
[GHManageWebhooks]: Nodes/GH_RepoRole.md#outbound-edges
[GHManageDeployKeys]: Nodes/GH_RepoRole.md#outbound-edges
[GHPushProtectedBranch]: Nodes/GH_RepoRole.md#outbound-edges
[GHDeleteAlertsCodeScanning]: Nodes/GH_RepoRole.md#outbound-edges
[GHRunOrgMigration]: Nodes/GH_RepoRole.md#outbound-edges
[GHBypassBranchProtection]: Nodes/GH_RepoRole.md#outbound-edges
[GHManageSecurityProducts]: Nodes/GH_RepoRole.md#outbound-edges
[GHManageRepoSecurityProducts]: Nodes/GH_RepoRole.md#outbound-edges
[GHEditRepoProtections]: Nodes/GH_RepoRole.md#outbound-edges
[GHJumpMergeQueue]: Nodes/GH_RepoRole.md#outbound-edges
[GHCreateSoloMergeQueueEntry]: Nodes/GH_RepoRole.md#outbound-edges
[GHEditRepoCustomPropertiesValue]: Nodes/GH_RepoRole.md#outbound-edges
[GH_ProtectedBy]: Nodes/GH_BranchProtectionRule.md#outbound-edges
[GH_BypassPullRequestAllowances]: Nodes/GH_User.md#outbound-edges
[GH_RestrictionsCanPush]: Nodes/GH_User.md#outbound-edges
[GH_HasBranch]: Nodes/GH_Repository.md#outbound-edges
[GH_HasWorkflow]: Nodes/GH_Repository.md#outbound-edges
[GH_HasEnvironment]: Nodes/GH_Repository.md#outbound-edges
[GH_HasSecret]: Nodes/GH_Repository.md#outbound-edges
[GH_HasSecretScanningAlert]: Nodes/GH_Repository.md#outbound-edges
[GH_HasSamlIdentityProvider]: Nodes/GH_Organization.md#outbound-edges
[GH_HasExternalIdentity]: Nodes/GH_SamlIdentityProvider.md#outbound-edges
[GH_MapsToUser]: Nodes/GH_ExternalIdentity.md#outbound-edges
[GH_HasPersonalAccessToken]: Nodes/GH_User.md#outbound-edges
[GH_HasPersonalAccessTokenRequest]: Nodes/GH_User.md#outbound-edges
[GH_InstalledAs]: Nodes/GH_App.md#outbound-edges
[GH_CanAccess]: Nodes/GH_PersonalAccessToken.md#outbound-edges
[SyncedToGHUser]: Nodes/GH_User.md#inbound-edges
[GH_CanAssumeAWSRole]: Nodes/GH_Repository.md#outbound-edges
[CanAssumeIdentity]: Nodes/GH_Branch.md#outbound-edges
[GH_Organization]: Nodes/GH_Organization.md
[GH_User]: Nodes/GH_User.md
[GH_Team]: Nodes/GH_Team.md
[GH_Repository]: Nodes/GH_Repository.md
[GH_Branch]: Nodes/GH_Branch.md
[GH_BranchProtectionRule]: Nodes/GH_BranchProtectionRule.md
[GH_OrgRole]: Nodes/GH_OrgRole.md
[GH_TeamRole]: Nodes/GH_TeamRole.md
[GH_RepoRole]: Nodes/GH_RepoRole.md
[GH_Workflow]: Nodes/GH_Workflow.md
[GH_Environment]: Nodes/GH_Environment.md
[GH_OrgSecret]: Nodes/GH_OrgSecret.md
[GH_RepoSecret]: Nodes/GH_RepoSecret.md
[GH_EnvironmentSecret]: Nodes/GH_EnvironmentSecret.md
[GH_SecretScanningAlert]: Nodes/GH_SecretScanningAlert.md
[GH_SamlIdentityProvider]: Nodes/GH_SamlIdentityProvider.md
[GH_ExternalIdentity]: Nodes/GH_ExternalIdentity.md
[GH_App]: Nodes/GH_App.md
[GH_AppInstallation]: Nodes/GH_AppInstallation.md
[GH_PersonalAccessToken]: Nodes/GH_PersonalAccessToken.md
[GH_PersonalAccessTokenRequest]: Nodes/GH_PersonalAccessTokenRequest.md
[AZUser]: https://bloodhound.specterops.io/resources/nodes/az-user
[AZFederatedIdentityCredential]: https://bloodhound.specterops.io/resources/nodes/az-federated-identity-credential
[AWSRole]: https://bloodhound.specterops.io/resources/nodes/aws-role
[OktaUser]: https://github.com/SpecterOps/OktaHound
[PingOneUser]: https://github.com/SpecterOps/PingHound
