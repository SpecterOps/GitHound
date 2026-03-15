# Custom BloodHound Edges for GitHub

## Intra-Organization Edges

The following table summarizes the custom edge kinds used by `GitHound`:

| Edge Type | Source Node Kinds | Target Node Kinds | Traversable |
|-----------|-------------------|-------------------|-------------|
| [GH_Contains] | [GH_Organization] | [GH_User], [GH_Team], [GH_Repository], [GH_OrgRole], [GH_RepoRole], [GH_TeamRole], [GH_OrgSecret], [GH_OrgVariable], [GH_AppInstallation], [GH_PersonalAccessToken], [GH_PersonalAccessTokenRequest] | ❌ |
|               | [GH_Repository]   | [GH_RepoSecret], [GH_RepoVariable], [GH_SecretScanningAlert] | ❌ |
|               | [GH_Environment]  | [GH_EnvironmentSecret], [GH_EnvironmentVariable] | ❌ |
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
| [GH_WriteOrganizationActionsVariables] | [GH_OrgRole] | [GH_Organization] | ❌ |
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
| [GH_ReadRepoContents] | [GH_RepoRole] | [GH_Repository] | ❌ |
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
| [GH_EditRepoCustomPropertiesValues] | [GH_RepoRole] | [GH_Repository] | ❌ |
| [GH_AddLabel] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_RemoveLabel] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_CloseIssue] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ReopenIssue] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ClosePullRequest] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ReopenPullRequest] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_AddAssignee] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_DeleteIssue] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_RemoveAssignee] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_RequestPrReview] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_MarkAsDuplicate] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_SetMilestone] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_SetIssueType] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ManageTopics] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ManageSettingsWiki] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ManageSettingsProjects] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ManageSettingsMergeTypes] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ManageSettingsPages] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_EditRepoMetadata] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_SetInteractionLimits] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_SetSocialPreview] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_EditRepoAnnouncementBanners] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ReadCodeScanning] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_WriteCodeScanning] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ViewDependabotAlerts] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ResolveDependabotAlerts] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_DeleteDiscussion] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ToggleDiscussionAnswer] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ToggleDiscussionCommentMinimize] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_EditDiscussionCategory] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_CreateDiscussionCategory] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ConvertIssuesToDiscussions] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_CloseDiscussion] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ReopenDiscussion] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_EditCategoryOnDiscussion] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ManageDiscussionBadges] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_EditDiscussionComment] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_DeleteDiscussionComment] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_CreateTag] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_DeleteTag] | [GH_RepoRole] | [GH_Repository] | :x: |
| [GH_ProtectedBy] | [GH_BranchProtectionRule] | [GH_Branch] | ❌ |
| [GH_BypassPullRequestAllowances] | [GH_User], [GH_Team] | [GH_BranchProtectionRule] | ❌ |
| [GH_RestrictionsCanPush] | [GH_User], [GH_Team] | [GH_BranchProtectionRule] | ❌ |
| [GH_HasBranch] | [GH_Repository] | [GH_Branch] | ❌ |
| [GH_HasWorkflow] | [GH_Repository] | [GH_Workflow] | ❌ |
| [GH_HasEnvironment] | [GH_Repository] | [GH_Environment] | ❌ |
|                     | [GH_Branch]     | [GH_Environment] | ❌ |
| [GH_HasSecret] | [GH_Repository] | [GH_OrgSecret], [GH_RepoSecret] | ✅ |
|                | [GH_Environment] | [GH_EnvironmentSecret] | ✅ |
| [GH_HasVariable] | [GH_Repository] | [GH_OrgVariable], [GH_RepoVariable] | ✅ |
| [GH_ValidToken] | [GH_SecretScanningAlert] | [GH_User] | ✅ |
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
| [GH_CanEditProtection] | [GH_RepoRole] | [GH_Branch] | ✅ |
| [GH_CanReadSecretScanningAlert] | [GH_OrgRole] | [GH_SecretScanningAlert] | ✅ |
|                                 | [GH_RepoRole] | [GH_SecretScanningAlert] | ✅ |

## Hybrid Edges

Hybrid edges connect GitHub entities to entities from other supported BloodHound collectors, such as Azure (Entra ID), AWS, Okta, and PingOne.

### Microsoft Entra ID (Azure Active Directory)

| Edge Type           | Source Node Kinds     | Target Node Kinds               | Traversable |
|---------------------|-----------------------|---------------------------------|-------------|
| [GH_SyncedTo]    | [AZUser]              | [GH_User]                       | ✅          |
| [GH_MapsToUser]     | [GH_ExternalIdentity] | [AZUser]                        | ❌          |
| [GH_CanAssumeIdentity] | [GH_Repository]       | [AZFederatedIdentityCredential], [AWSRole] | ✅          |
|                        | [GH_Branch]           | [AZFederatedIdentityCredential], [AWSRole] | ✅          |
|                        | [GH_Environment]      | [AZFederatedIdentityCredential], [AWSRole] | ✅          |

### Amazon Web Services

AWS IAM role assumption uses the same `GH_CanAssumeIdentity` edge (see Microsoft Entra ID section above).

### Okta

| Edge Type        | Source Node Kinds     | Target Node Kinds | Traversable |
|------------------|-----------------------|-------------------|-------------|
| [GH_SyncedTo] | [Okta_User]            | [GH_User]         | ✅          |
| [GH_MapsToUser]  | [GH_ExternalIdentity] | [Okta_User]        | ❌          |

### PingOne

| Edge Type        | Source Node Kinds     | Target Node Kinds | Traversable |
|------------------|-----------------------|-------------------|-------------|
| [GH_SyncedTo] | [PingOneUser]         | [GH_User]         | ✅          |
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
[GH_WriteOrganizationActionsVariables]: EdgeDescriptions/GH_WriteOrganizationActionsVariables.md
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
[GH_EditRepoCustomPropertiesValues]: EdgeDescriptions/GH_EditRepoCustomPropertiesValues.md
[GH_AddLabel]: EdgeDescriptions/GH_AddLabel.md
[GH_RemoveLabel]: EdgeDescriptions/GH_RemoveLabel.md
[GH_CloseIssue]: EdgeDescriptions/GH_CloseIssue.md
[GH_ReopenIssue]: EdgeDescriptions/GH_ReopenIssue.md
[GH_ClosePullRequest]: EdgeDescriptions/GH_ClosePullRequest.md
[GH_ReopenPullRequest]: EdgeDescriptions/GH_ReopenPullRequest.md
[GH_AddAssignee]: EdgeDescriptions/GH_AddAssignee.md
[GH_DeleteIssue]: EdgeDescriptions/GH_DeleteIssue.md
[GH_RemoveAssignee]: EdgeDescriptions/GH_RemoveAssignee.md
[GH_RequestPrReview]: EdgeDescriptions/GH_RequestPrReview.md
[GH_MarkAsDuplicate]: EdgeDescriptions/GH_MarkAsDuplicate.md
[GH_SetMilestone]: EdgeDescriptions/GH_SetMilestone.md
[GH_SetIssueType]: EdgeDescriptions/GH_SetIssueType.md
[GH_ManageTopics]: EdgeDescriptions/GH_ManageTopics.md
[GH_ManageSettingsWiki]: EdgeDescriptions/GH_ManageSettingsWiki.md
[GH_ManageSettingsProjects]: EdgeDescriptions/GH_ManageSettingsProjects.md
[GH_ManageSettingsMergeTypes]: EdgeDescriptions/GH_ManageSettingsMergeTypes.md
[GH_ManageSettingsPages]: EdgeDescriptions/GH_ManageSettingsPages.md
[GH_EditRepoMetadata]: EdgeDescriptions/GH_EditRepoMetadata.md
[GH_SetInteractionLimits]: EdgeDescriptions/GH_SetInteractionLimits.md
[GH_SetSocialPreview]: EdgeDescriptions/GH_SetSocialPreview.md
[GH_EditRepoAnnouncementBanners]: EdgeDescriptions/GH_EditRepoAnnouncementBanners.md
[GH_ReadCodeScanning]: EdgeDescriptions/GH_ReadCodeScanning.md
[GH_WriteCodeScanning]: EdgeDescriptions/GH_WriteCodeScanning.md
[GH_ViewDependabotAlerts]: EdgeDescriptions/GH_ViewDependabotAlerts.md
[GH_ResolveDependabotAlerts]: EdgeDescriptions/GH_ResolveDependabotAlerts.md
[GH_DeleteDiscussion]: EdgeDescriptions/GH_DeleteDiscussion.md
[GH_ToggleDiscussionAnswer]: EdgeDescriptions/GH_ToggleDiscussionAnswer.md
[GH_ToggleDiscussionCommentMinimize]: EdgeDescriptions/GH_ToggleDiscussionCommentMinimize.md
[GH_EditDiscussionCategory]: EdgeDescriptions/GH_EditDiscussionCategory.md
[GH_CreateDiscussionCategory]: EdgeDescriptions/GH_CreateDiscussionCategory.md
[GH_ConvertIssuesToDiscussions]: EdgeDescriptions/GH_ConvertIssuesToDiscussions.md
[GH_CloseDiscussion]: EdgeDescriptions/GH_CloseDiscussion.md
[GH_ReopenDiscussion]: EdgeDescriptions/GH_ReopenDiscussion.md
[GH_EditCategoryOnDiscussion]: EdgeDescriptions/GH_EditCategoryOnDiscussion.md
[GH_ManageDiscussionBadges]: EdgeDescriptions/GH_ManageDiscussionBadges.md
[GH_EditDiscussionComment]: EdgeDescriptions/GH_EditDiscussionComment.md
[GH_DeleteDiscussionComment]: EdgeDescriptions/GH_DeleteDiscussionComment.md
[GH_CreateTag]: EdgeDescriptions/GH_CreateTag.md
[GH_DeleteTag]: EdgeDescriptions/GH_DeleteTag.md
[GH_ProtectedBy]: EdgeDescriptions/GH_ProtectedBy.md
[GH_BypassPullRequestAllowances]: EdgeDescriptions/GH_BypassPullRequestAllowances.md
[GH_RestrictionsCanPush]: EdgeDescriptions/GH_RestrictionsCanPush.md
[GH_HasBranch]: EdgeDescriptions/GH_HasBranch.md
[GH_HasWorkflow]: EdgeDescriptions/GH_HasWorkflow.md
[GH_HasEnvironment]: EdgeDescriptions/GH_HasEnvironment.md
[GH_HasSecret]: EdgeDescriptions/GH_HasSecret.md
[GH_HasVariable]: EdgeDescriptions/GH_HasVariable.md
[GH_ValidToken]: EdgeDescriptions/GH_ValidToken.md
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
[GH_CanReadSecretScanningAlert]: EdgeDescriptions/GH_CanReadSecretScanningAlert.md
[GH_SyncedTo]: EdgeDescriptions/GH_SyncedTo.md
[GH_CanAssumeIdentity]: EdgeDescriptions/GH_CanAssumeIdentity.md
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
[GH_OrgVariable]: Nodes/GH_OrgVariable.md
[GH_RepoSecret]: Nodes/GH_RepoSecret.md
[GH_RepoVariable]: Nodes/GH_RepoVariable.md
[GH_EnvironmentSecret]: Nodes/GH_EnvironmentSecret.md
[GH_EnvironmentVariable]: Nodes/GH_EnvironmentVariable.md
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
[Okta_User]: https://github.com/SpecterOps/OktaHound
[PingOneUser]: https://github.com/SpecterOps/PingHound
