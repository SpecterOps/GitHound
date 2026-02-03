# Collection

## Collector Setup & Usage

### Creating a Personal Access Token Overview

Settings -> Developer settings -> Personal access tokens -> Fine-grained tokens -> Generate new token

- Repository access -> All repositories

- "Administrator" repository permissions (read)
- "Contents" repository permissions (read)
- "Metadata" repository permissions (read)

- "Custom organization roles" organization permissions (read)
- "Custom repository roles" organization permissions (read)
- "Members" organization permissions (read)

### Generate Fine-grained Personal Access Token (Detailed)

This walkthrough is for administrators to create the Fine-grained Personal Access Token that is necessary to collect the data that is necessary for the GitHub based BloodHound Graph. These steps should be followed in the context of an organization administrator in order to ensure the resulting PAT will have full access to Repositories, Users, and Teams in the GitHub Organization.

#### Generate Token

To generate a personal access token browse to your user settings as shown in the image below:

![Profile Settings](./images/1_proile_settings.png)

In the settings menu, scroll to the bottom where you will see the "Developer settings" menu option. Click it.

![Developer Settings](./images/2_developer_settings.png)

GitHub offers many options for programmatic access. GitHound, our collector, is built to work with Fine-grained Personal Access Tokens, so click on that menu item.

![Fine Grained Access Token](./images/3_fine-grained_tokens.png)

After reaching the Fine-grained Personal Access Token page, you can click on the "Generate new token" button in the top right corner.

![Generate Personal Access Token](./images/4_generate_token.png)

#### Token Settings

Fine-grained Personal Access Tokens offer administrators the ability to specifically control what resources the PAT will have access to.

It is possible to limit the set of repositories that a Fine-grained PAT can interact with. GitHound requires access to all repositories, so we will select the "All repositories" radio button.

![Setting All Repositories](./images/5_all_repositories.png)

Next, we will define the specific repository and organization permissions that GitHound requires. GitHound is a read-only tool, so we will make sure to specify read-only access for each option as shown in the image below:

![Permissions](./images/6_permissions.png)

The following permissions are required:

| Target       | Permission                | Access    | Functions                                                                                     |
|--------------|---------------------------|-----------|-----------------------------------------------------------------------------------------------|
| Repository   | Action                    | Read-only | Git-HoundWorkflow, Git-HoundEnvironment                                                       |
| Repository   | Administration            | Read-only | Git-HoundBranch, Git-HoundRepositoryRole                                                      |
| Repository   | Contents                  | Read-only | Git-HoundBranch                                                                               |
| Repository   | Environments              | Read-only | Git-HoundEnvironment                                                                          |
| Repository   | Metadata                  | Read-only | Git-HoundRepository, Git-HoundRepositoryRole                                                  |
| Repository   | Secret scanning alerts    | Read-only | Git-HoundSecretScanningAlert                                                                  |
| Repository   | Secrets                   | Read-only | Git-HoundSecret                                                                               |
| Organization | Administration            | Read-only | Git-HoundOrganization, Git-HoundRepository, Git-HoundRepositoryRole, Git-HoundAppInstallation |
| Organization | Custom organization roles | Read-only | Git-HoundOrganizationRole                                                                     |
| Organization | Custom repository roles   | Read-only | Git-HoundRepositoryRole                                                                       |
| Organization | Members                   | Read-only | Git-HoundTeam, Git-HoundUser, Git-HoundOrganizationRole, Git-HoundTeamRole                    |
| Organization | Secrets                   | Read-only | Git-HoundSecret                                                                               |

#### Save Personal Access Token

Once the PAT is created, GitHub will present it to you as shown below. You must save this value (preferably in a password manager) at this point as you will not be able to recover it in the future.

![Save the PAT](./images/7_save_pat.png)

### Running the Collection

1. Open a PowerShell terminal
2. Load `githound.ps1` in your current PowerShell session:

    ```powershell
      . ./githound.ps1
    ```

3. Create a GitHub Session using your Personal Access Token.

    ```powershell
    $session = New-GitHubSession -OrganizationName <Name of your Organization> -Token (Get-Clipboard)
    ```

    Note: You must specify the name of your GitHub organziation. For example, this repository is part of the `SpecterOps` organization, so I would specify `SpecterOps` as the argument for the OrganizationName parameter. Additionally, you must specify your Personal Access Token. I find that it is easiest to paste it directly from the clipboard as this is where it will be after you create it or if you save it in a password manager.

4. Run the collection on the specified organization:

    ```powershell
    Invoke-GitHound -Session $session
    ```

    This will output the payload to the current working directory as `githound_<your_org_identifier>.json`.

5. Upload the payload via the Ingest File page in BloodHound or via the API.

### Alternative Collection for Large Environments

| Function                     | Scalar           | Estimated Requests |
|------------------------------|------------------|--------------------|
| Git-HoundOrganization        | none             | 2                  |
| Git-HoundUser                | User Count       | Count / 100        |
| Git-HoundTeam                | Team Count       | Count / 100        |
| Git-HoundRepository          | Repository Count | (Count / 100) + 2  |
| Git-HoundBranch              | Repository Count | Repo (Branch / 100) Technically, number of repositories * number of branches
| Git-HoundWorkflow            | Repository Count | Count / 100        |
| Git-HoundEnvironment         | Repository Count | 3xCount / 100      |
| Git-HoundSecret              | Repository Count | 2xCount / 100      |
| Git-HoundTeamRole            | 
| Git-HoundOrganizationRole    | User Count       | 2xCount / 100      | 
| Git-HoundRepositoryRole      |
| Git-HoundSecretScanningAlert | Alert Count      | Count / 100        |
| Git-HoundGraphQlSamlProvider | SAML Identities  | Count / 100        |

GitHub Personal Access Tokens have a [rate limit](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api?apiVersion=2022-11-28#primary-rate-limit-for-authenticated-users) of 5000 API requests per hour. In many production scale environments, this rate limit will be reached (possibly several times) during collection. The Invoke-GitHound function is built upon the Invoke-GithubRestMethod function which takes account of rate limit exhaustions and manages a sleep interval until the rate limit is renewed. However, long sleep periods during script execution can be unreliable. With that in mind, I recommend a slightly different approach to collection for large environments where each collection function is run independently and the results are output on a function by function basis. The steps are described below:

1. Open a PowerShell terminal

2. Load `githound.ps1` in your current PowerShell session:

    ```powershell
      . ./githound.ps1
    ```

3. Create a GitHub Session using your Personal Access Token.

    ```powershell
    $session = New-GitHubSession -OrganizationName <Name of your Organization> -Token (Get-Clipboard)
    ```

    Note: You must specify the name of your GitHub organziation. For example, this repository is part of the `SpecterOps` organization, so I would specify `SpecterOps` as the argument for the OrganizationName parameter. Additionally, you must specify your Personal Access Token. I find that it is easiest to paste it directly from the clipboard as this is where it will be after you create it or if you save it in a password manager.

4. Set up the environment:

    ```powershell
    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList
    
    $Global:GitHoundFunctionBundle = Get-GitHoundFunctionBundle
    ```

5. Run the `Git-HoundOrganization` function:

    ```powershell
    Write-Host "[*] Starting GitHound for $($Session.OrganizationName)"
    $org = Git-HoundOrganization -Session $Session
    if($org.nodes) { $nodes.AddRange(@($org.nodes)) }
    if($org.edges) { $edges.AddRange(@($org.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $org.Nodes.ToArray()
            edges = $org.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_Organization_$($org.nodes[0].id).json"
    ```

6. Run the `Git-HoundUser` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Users"
    $users = $org.nodes[0] | Git-HoundUser -Session $Session
    if($users) { $nodes.AddRange(@($users)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $users
            edges = @()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_User_$($org.nodes[0].id).json"
    ```

7. Run the `Git-HoundTeam` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Teams"
    $teams = $org.nodes[0] | Git-HoundTeam -Session $Session
    if($teams.nodes) { $nodes.AddRange(@($teams.nodes)) }
    if($teams.edges) { $edges.AddRange(@($teams.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $teams.Nodes.ToArray()
            edges = $teams.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_Team_$($org.nodes[0].id).json"
    ```

8. Run the `Git-HoundRepository` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Repositories"
    $repos = $org.nodes[0] | Git-HoundRepository -Session $Session
    if($repos.nodes) { $nodes.AddRange(@($repos.nodes)) }
    if($repos.edges) { $edges.AddRange(@($repos.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $repos.Nodes.ToArray()
            edges = $repos.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_Repository_$($org.nodes[0].id).json"
    ```

9. Run the `Git-HoundOrganizationRole` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Roles"
    $orgroles = $org.nodes[0] | Git-HoundOrganizationRole -Session $Session
    if($orgroles.nodes) { $nodes.AddRange(@($orgroles.nodes)) }
    if($orgroles.edges) { $edges.AddRange(@($orgroles.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $orgroles.Nodes.ToArray()
            edges = $orgroles.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_OrgRole_$($org.nodes[0].id).json"
    ```

10. Run the `Git-HoundTeamRole` function:

    ```powershell
    Write-Host "[*] Enumerating Team Roles"
    $teamroles = $teams | Git-HoundTeamRole -Session $Session
    if($teamroles.nodes) { $nodes.AddRange(@($teamroles.nodes)) }
    if($teamroles.edges) { $edges.AddRange(@($teamroles.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $branches.Nodes.ToArray()
            edges = $branches.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_TeamRoles_$($org.nodes[0].id).json"
    ```

11. Run the `Git-HoundRepositoryRole` function:

    ```powershell
    Write-Host "[*] Enumerating Repository Roles"
    $reporoles = $org.nodes[0] | Git-HoundRepositoryRole -Session $Session
    if($reporoles.nodes) { $nodes.AddRange(@($reporoles.nodes)) }
    if($reporoles.edges) { $edges.AddRange(@($reporoles.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $reporoles.Nodes.ToArray()
            edges = $reporoles.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_RepoRole_$($org.nodes[0].id).json"
    ```

12. Run the `Git-HoundGraphQlSamlProvider` :

    ```powershell
    Write-Host "[*] Enumerating SAML Identity Provider"
    $samlNodes = New-Object System.Collections.ArrayList
    $samlEdges = New-Object System.Collections.ArrayList
    $saml = Git-HoundGraphQlSamlProvider -Session $Session
    if($saml.nodes) { $samlNodes.AddRange(@($saml.nodes)) }
    if($saml.edges) { $samlEdges.AddRange(@($saml.edges)) }

    $payload = [PSCustomObject]@{
        graph = [PSCustomObject]@{
            nodes = $samlNodes.ToArray()
            edges = $samlEdges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_saml_$($org.nodes[0].id).json"
    ```

13. Run the `Git-HoundSecretScanningAlert` function:

    ```powershell
    Write-Host "[*] Enumerating Secret Scanning Alerts"
    $secretalerts = $org.nodes[0] | Git-HoundSecretScanningAlert -Session $Session
    if($secretalerts.nodes) { $nodes.AddRange(@($secretalerts.nodes)) }
    if($secretalerts.edges) { $edges.AddRange(@($secretalerts.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $secretalerts.Nodes.ToArray()
            edges = $secretalerts.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_SecretAlerts_$($org.nodes[0].id).json"
    ```

14. Run the `Git-HoundBranch` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Branches"
    $branches = $repos | Git-HoundBranch -Session $Session
    if($branches.nodes) { $nodes.AddRange(@($branches.nodes)) }
    if($branches.edges) { $edges.AddRange(@($branches.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $branches.Nodes.ToArray()
            edges = $branches.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_Branch_$($org.nodes[0].id).json"
    ```

15. Run the `Git-HoundWorkflow` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Workflows"
    $workflows = $repos | Git-HoundWorkflow -Session $Session
    if($workflows.nodes) { $nodes.AddRange(@($workflows.nodes)) }
    if($workflows.edges) { $edges.AddRange(@($workflows.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $workflows.Nodes.ToArray()
            edges = $workflows.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_Workflow_$($org.nodes[0].id).json"
    ```

16. Run the `Git-HoundEnvironment` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Environments"
    $environments = $repos | Git-HoundEnvironment -Session $Session
    if($environments.nodes) { $nodes.AddRange(@($environments.nodes)) }
    if($environments.edges) { $edges.AddRange(@($environments.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $environments.Nodes.ToArray()
            edges = $environments.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_Environment_$($org.nodes[0].id).json"
    ```

17. Run the `Git-HoundSecret` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Secrets"
    $secrets = $repos | Git-HoundSecret -Session $Session
    if($secrets.nodes) { $nodes.AddRange(@($secrets.nodes)) }
    if($secrets.edges) { $edges.AddRange(@($secrets.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $secrets.Nodes.ToArray()
            edges = $secrets.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_Secret_$($org.nodes[0].id).json"
    ```

### Sample

If you do not have a GitHub Enterprise environment or if you want to test out GitHound before collecting from your own production environment, we've included a sample data set at `./samples/example.json`.