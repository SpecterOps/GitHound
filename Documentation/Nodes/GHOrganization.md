# <img src="./images/black_GHOrganization.png" width="50"/> GHOrganization

| Property Name | Display Name | Data Type | Sample Value              | Description |
|---------------|--------------|-----------|---------------------------|-------------|
| objectid                                       | Id           | string    | | |
| id                                             | Id           | integer   | | |
| name                                           | Id           | string    | | Currently this is set as a friendly name, but should it be changed to the login property value? |
| login                                          | Id           | string    | | |
| node_id                                        | Id           | string    | | * This can be deleted because it is used as the objectid, and is thus redundant |
| blog                                           | Id           | string    | | |
| is_verified                                    | Id           | boolean   | | |
| public_repos                                   | Id           | integer   | | |
| followers                                      | Id           | integer   | | |
| html_url                                       | Id           | string    | | |
| created_at                                     | Id           | datetime  | | |
| updated_at                                     | Id           | datetime  | | |
| total_private_repos                            | Id           | integer   | | |
| owned_private_repos                            | Id           | integer   | | |
| collaborators                                  | Id           | integer   | | |
| default_repository_permission                  | Id           | string    | | This property is used to associate the members org role with the appropriate "all_repo_*" role. |
| two_factor_requirement_enabled                 | Id           | boolean   | | |
| advanced_security_enabled_for_new_repositories | Id           | boolean   | | |
| actions_enabled_repositories                   | Id           | string    | | |
| actions_allowed_actions                        | Id           | string    | | |
| actions_sha_pinning_required                   | Id           | boolean   | | |