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
| [GH_WriteOrganizationActionsSecrets] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_WriteOrganizationActionsSettings] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_ViewSecretScanningAlerts] | [GH_OrgRole] | [GH_Organization] | ❌ |
|                               | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_ResolveSecretScanningAlerts] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_ReadOrganizationActionsUsageMetrics] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_ReadOrganizationCustomOrgRole] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_ReadOrganizationCustomRepoRole] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_WriteOrganizationCustomOrgRole] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_WriteOrganizationCustomRepoRole] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_WriteOrganizationNetworkConfigurations] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_OrgReviewAndManageSecretScanningBypassRequests] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_OrgReviewAndManageSecretScanningClosureRequests] | [GH_OrgRole] | [GH_Organization] | ❌ |
| [GH_ReadRepoContents] | [GH_RepoRole] | [GH_Repository] | ✅ |
| [GH_WriteRepoContents] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_WriteRepoPullRequests] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_AdminTo] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_BypassBranchProtection] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_EditRepoProtections] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_ManageWebhooks] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_ManageDeployKeys] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_PushProtectedBranch] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_DeleteAlertsCodeScanning] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_RunOrgMigration] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_ManageSecurityProducts] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_ManageRepoSecurityProducts] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_JumpMergeQueue] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_CreateSoloMergeQueueEntry] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_EditRepoCustomPropertiesValue] | [GH_RepoRole] | [GH_Repository] | ❌ |
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
| [GH_CanWriteBranch] | [GH_RepoRole] | [GH_Branch] | ✅ |
|                     | [GH_User], [GH_Team] | [GH_Branch] | ✅ |
| [GH_CanCreateBranch] | [GH_RepoRole] | [GH_Repository] | ✅ |
|                      | [GH_User], [GH_Team] | [GH_Repository] | ✅ |
| [GH_CanEditProtection] | [GH_RepoRole] | [GH_BranchProtectionRule] | ❌ |

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

[GH_Contains]: EdgeDescriptions/GH_Contains.md
[GH_Owns]: EdgeDescriptions/GH_Owns.md
[GH_HasRole]: EdgeDescriptions/GH_HasRole.md
[GH_MemberOf]: EdgeDescriptions/GH_MemberOf.md
[GH_AddMember]: EdgeDescriptions/GH_AddMember.md
[GH_HasBaseRole]: EdgeDescriptions/GH_HasBaseRole.md
[GH_CreateRepository]: EdgeDescriptions/GH_CreateRepository.md
[GH_InviteMember]: EdgeDescriptions/GH_InviteMember.md
[GH_AddCollaborator]: EdgeDescriptions/GH_AddCollaborator.md
[GH_CreateTeam]: EdgeDescriptions/GH_CreateTeam.md
[GH_TransferRepository]: EdgeDescriptions/GH_TransferRepository.md
[GH_ManageOrganizationWebhooks]: EdgeDescriptions/GH_ManageOrganizationWebhooks.md
[GH_OrgBypassCodeScanningDismissalRequests]: EdgeDescriptions/GH_OrgBypassCodeScanningDismissalRequests.md
[GH_OrgBypassSecretScanningClosureRequests]: EdgeDescriptions/GH_OrgBypassSecretScanningClosureRequests.md
[GH_WriteOrganizationActionsSecrets]: EdgeDescriptions/GH_WriteOrganizationActionsSecrets.md
[GH_WriteOrganizationActionsSettings]: EdgeDescriptions/GH_WriteOrganizationActionsSettings.md
[GH_ViewSecretScanningAlerts]: EdgeDescriptions/GH_ViewSecretScanningAlerts.md
[GH_ResolveSecretScanningAlerts]: EdgeDescriptions/GH_ResolveSecretScanningAlerts.md
[GH_ReadOrganizationActionsUsageMetrics]: EdgeDescriptions/GH_ReadOrganizationActionsUsageMetrics.md
[GH_ReadOrganizationCustomOrgRole]: EdgeDescriptions/GH_ReadOrganizationCustomOrgRole.md
[GH_ReadOrganizationCustomRepoRole]: EdgeDescriptions/GH_ReadOrganizationCustomRepoRole.md
[GH_WriteOrganizationCustomOrgRole]: EdgeDescriptions/GH_WriteOrganizationCustomOrgRole.md
[GH_WriteOrganizationCustomRepoRole]: EdgeDescriptions/GH_WriteOrganizationCustomRepoRole.md
[GH_WriteOrganizationNetworkConfigurations]: EdgeDescriptions/GH_WriteOrganizationNetworkConfigurations.md
[GH_OrgReviewAndManageSecretScanningBypassRequests]: EdgeDescriptions/GH_OrgReviewAndManageSecretScanningBypassRequests.md
[GH_OrgReviewAndManageSecretScanningClosureRequests]: EdgeDescriptions/GH_OrgReviewAndManageSecretScanningClosureRequests.md
[GH_ReadRepoContents]: EdgeDescriptions/GH_ReadRepoContents.md
[GH_WriteRepoContents]: EdgeDescriptions/GH_WriteRepoContents.md
[GH_WriteRepoPullRequests]: EdgeDescriptions/GH_WriteRepoPullRequests.md
[GH_AdminTo]: EdgeDescriptions/GH_AdminTo.md
[GH_BypassBranchProtection]: EdgeDescriptions/GH_BypassBranchProtection.md
[GH_EditRepoProtections]: EdgeDescriptions/GH_EditRepoProtections.md
[GH_ManageWebhooks]: EdgeDescriptions/GH_ManageWebhooks.md
[GH_ManageDeployKeys]: EdgeDescriptions/GH_ManageDeployKeys.md
[GH_PushProtectedBranch]: EdgeDescriptions/GH_PushProtectedBranch.md
[GH_DeleteAlertsCodeScanning]: EdgeDescriptions/GH_DeleteAlertsCodeScanning.md
[GH_RunOrgMigration]: EdgeDescriptions/GH_RunOrgMigration.md
[GH_ManageSecurityProducts]: EdgeDescriptions/GH_ManageSecurityProducts.md
[GH_ManageRepoSecurityProducts]: EdgeDescriptions/GH_ManageRepoSecurityProducts.md
[GH_JumpMergeQueue]: EdgeDescriptions/GH_JumpMergeQueue.md
[GH_CreateSoloMergeQueueEntry]: EdgeDescriptions/GH_CreateSoloMergeQueueEntry.md
[GH_EditRepoCustomPropertiesValue]: EdgeDescriptions/GH_EditRepoCustomPropertiesValue.md
[GH_ProtectedBy]: EdgeDescriptions/GH_ProtectedBy.md
[GH_BypassPullRequestAllowances]: EdgeDescriptions/GH_BypassPullRequestAllowances.md
[GH_RestrictionsCanPush]: EdgeDescriptions/GH_RestrictionsCanPush.md
[GH_HasBranch]: EdgeDescriptions/GH_HasBranch.md
[GH_HasWorkflow]: EdgeDescriptions/GH_HasWorkflow.md
[GH_HasEnvironment]: EdgeDescriptions/GH_HasEnvironment.md
[GH_HasSecret]: EdgeDescriptions/GH_HasSecret.md
[GH_HasSecretScanningAlert]: EdgeDescriptions/GH_HasSecretScanningAlert.md
[GH_HasSamlIdentityProvider]: EdgeDescriptions/GH_HasSamlIdentityProvider.md
[GH_HasExternalIdentity]: EdgeDescriptions/GH_HasExternalIdentity.md
[GH_MapsToUser]: EdgeDescriptions/GH_MapsToUser.md
[GH_HasPersonalAccessToken]: EdgeDescriptions/GH_HasPersonalAccessToken.md
[GH_HasPersonalAccessTokenRequest]: EdgeDescriptions/GH_HasPersonalAccessTokenRequest.md
[GH_InstalledAs]: EdgeDescriptions/GH_InstalledAs.md
[GH_CanAccess]: EdgeDescriptions/GH_CanAccess.md
[GH_CanWriteBranch]: EdgeDescriptions/GH_CanWriteBranch.md
[GH_CanCreateBranch]: EdgeDescriptions/GH_CanCreateBranch.md
[GH_CanEditProtection]: EdgeDescriptions/GH_CanEditProtection.md
[SyncedToGHUser]: EdgeDescriptions/SyncedToGHUser.md
[GH_CanAssumeAWSRole]: EdgeDescriptions/GH_CanAssumeAWSRole.md
[CanAssumeIdentity]: EdgeDescriptions/CanAssumeIdentity.md
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
