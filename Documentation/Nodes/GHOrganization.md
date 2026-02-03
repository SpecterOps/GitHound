# <img src="../../images/black_GHOrganization.png" width="50"/> GHOrganization

| Property Name                                  | Display Name                                   | Data Type | Sample Value              | Description |
|------------------------------------------------|------------------------------------------------|-----------|---------------------------|-------------|
| objectid                                       | Object Id                                      | string    | | |
| id                                             | Id                                             | integer   | | |
| name                                           | Name                                           | string    | | Currently this is set as a friendly name, but should it be changed to the login property value? |
| login                                          | Login                                          | string    | | |
| node_id                                        | Node Id                                        | string    | | * This can be deleted because it is used as the objectid, and is thus redundant |
| blog                                           | Blog                                           | string    | | |
| is_verified                                    | Is Verified                                    | boolean   | | |
| public_repos                                   | Public Repos                                   | integer   | | |
| followers                                      | Followers                                      | integer   | | |
| html_url                                       | Html Url                                       | string    | | |
| created_at                                     | Created At                                     | datetime  | | |
| updated_at                                     | Updated At                                     | datetime  | | |
| total_private_repos                            | Total Private Repos                            | integer   | | |
| owned_private_repos                            | Owned Private Repos                            | integer   | | |
| collaborators                                  | Collaborators                                  | integer   | | |
| default_repository_permission                  | Default Repository Permission                  | string    | | This property is used to associate the members org role with the appropriate "all_repo_*" role. |
| two_factor_requirement_enabled                 | Two Factor Requirement Enabled                 | boolean   | | |
| advanced_security_enabled_for_new_repositories | Advanced Security Enabled For New Repositories | boolean   | | |
| actions_enabled_repositories                   | Actions Enabled Repositories                   | string    | | |
| actions_allowed_actions                        | Actions Allowed Actions                        | string    | | |
| actions_sha_pinning_required                   | Actions Sha Pinning Required                   | boolean   | | |