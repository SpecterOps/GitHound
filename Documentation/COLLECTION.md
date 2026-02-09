# Collection

## Collector Setup & Usage

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
| Organization | Custom organization roles | Read-only | Git-HoundOrganization                                                                         |
| Organization | Custom repository roles   | Read-only | Git-HoundRepository                                                                           |
| Organization | Members                   | Read-only | Git-HoundTeam, Git-HoundUser, Git-HoundOrganization                                           |
| Organization | Secrets                   | Read-only | Git-HoundOrganizationSecret, Git-HoundSecret                                                  |

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

    `Invoke-GitHound` writes a per-step output file after each collection function completes (e.g. `githound_Organization_*.json`, `githound_User_*.json`, etc.), then consolidates them into a single file at the end. If PowerShell crashes mid-collection, the completed steps are preserved on disk. See [Resuming After a Crash](#resuming-after-a-crash) below.

5. Upload the payload via the Ingest File page in BloodHound or via the API.

### Resuming After a Crash

If collection is interrupted (crash, terminal closed, etc.), you can resume from where you left off:

```powershell
Invoke-GitHound -Session $session -Resume
```

The `-Resume` flag tells GitHound to check for existing per-step output files in the current directory. Any step that already has a completed output file on disk will be loaded from the file instead of re-collected. Collection picks up from the first step that doesn't have an output file.

#### Available parameters

| Parameter               | Type             | Default    | Description                                                                  |
|-------------------------|------------------|------------|------------------------------------------------------------------------------|
| `-Session`              | GitHound.Session | (required) | Authentication session                                                       |
| `-CheckpointPath`       | String           | `"."`      | Directory for output files and intermediate checkpoints                      |
| `-Resume`               | Switch           | `$false`   | Load completed steps from disk instead of re-collecting                      |
| `-CleanupIntermediates` | Switch           | `$false`   | Delete per-step files after final consolidation                              |
| `-CollectAll`           | Switch           | `$false`   | Include optional steps (Workflows, Environments, Repo Secrets, App Installs) |

#### How it works

1. Each collection step writes its output to a file immediately after completing (e.g. `githound_Repository_<orgId>.json`). By default 8 steps run; with `-CollectAll`, all 12 steps run
2. On `-Resume`, if a step's file exists, it's loaded from disk. If not, the step is collected fresh
3. Functions with internal checkpointing (RepositoryRole, Branch, Workflow, Secret) can also auto-resume from their intermediate chunk files if the function itself was interrupted mid-execution
4. After all steps complete, everything is consolidated into a single `githound_<orgId>.json`
5. SAML and OIDC data remain in separate files (`githound_saml_<orgId>.json`, `githound_oidc_<orgId>.json`)

#### Example: Resume with a custom output directory

```powershell
Invoke-GitHound -Session $session -Resume -CheckpointPath "./output"
```

#### Example: Resume and clean up intermediate files after consolidation

```powershell
Invoke-GitHound -Session $session -Resume -CleanupIntermediates
```

### Alternative Collection for Large Environments

For organizations with thousands of repositories, collection can exceed the hourly rate limit multiple times. The following table shows the API request estimates for each function:

| Function                     | API     | Scaling Factor           | Estimated Requests                        | Rate Limit Aware | Checkpointing |
|------------------------------|---------|--------------------------|-------------------------------------------|------------------|---------------|
| Git-HoundOrganization        | REST    | Custom Org Roles (C)     | 3 + 2C                                    | No               | No            |
| Git-HoundUser                | GraphQL | User Count (U)           | ceil(U / 100)                             | No               | No            |
| Git-HoundTeam                | GraphQL | Team Count (T)           | ceil(T / 100) + overflow pages            | No               | No            |
| Git-HoundRepository          | REST    | Repository Count (R)     | 3 + ceil(R / 30)                          | No               | No            |
| Git-HoundRepositoryRole      | REST    | Repository Count (R)     | 2R (chunked)                              | Yes              | Yes           |
| Git-HoundBranch              | GraphQL | Repository Count (R)     | ceil(R / 10) + overflow + protected repos | Yes              | Yes           |
| Git-HoundWorkflow            | REST    | Actions-Enabled Repos (A)| A (skips repos with Actions disabled)     | Yes              | Yes           |
| Git-HoundEnvironment         | REST    | Repository Count (R)     | R + environments + branch policies        | Yes              | Yes           |
| Git-HoundOrganizationSecret  | REST    | Selected Secrets (S)     | 1 + S                                     | No               | No            |
| Git-HoundSecret              | REST    | Repository Count (R)     | R (chunked)                               | Yes              | Yes           |
| Git-HoundSecretScanningAlert | REST    | Alert Count              | ceil(Count / 100)                         | No               | No            |
| Git-HoundAppInstallation     | REST    | None                     | 1                                         | No               | No            |
| Git-HoundGraphQlSamlProvider | GraphQL | SAML Identities (I)      | ceil(I / 100)                             | No               | No            |

**Understanding the Table:**

- **Rate Limit Aware**: Functions that monitor remaining API calls and pause before hitting the limit
- **Checkpointing**: Functions that save intermediate chunk/page files during execution and can auto-resume from them if interrupted mid-function

Note: Even functions without internal checkpointing are protected by `Invoke-GitHound`'s step-level resume. Each function's output is saved to disk immediately after completion, so the `-Resume` flag can skip any fully completed step.

**Example Calculation for 1,000 Repositories:**

- Git-HoundRepository: ~37 requests
- Git-HoundRepositoryRole: ~2,000 requests (chunked with checkpointing)
- Git-HoundBranch: ~100+ requests (varies by branch count)
- Git-HoundWorkflow: ~1,000 requests (for repos with Actions enabled)
- Git-HoundSecret: ~1,000 requests (chunked with checkpointing)
- **Total**: ~4,000+ requests (may require rate limit pauses)

### Rate Limiting Behavior

GitHub Personal Access Tokens have a [rate limit](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api?apiVersion=2022-11-28#primary-rate-limit-for-authenticated-users) of 5,000 API requests per hour. In production-scale environments, this limit will be reached (possibly several times) during collection.

GitHound handles rate limiting automatically:

1. The `Invoke-GitHubRestMethod` function monitors rate limit headers
2. When limits are exhausted, collection pauses until the limit resets
3. Functions with checkpointing save progress before pausing

For very large environments (10,000+ repos), consider:

- Using [App Installation authentication](./APP-COLLECTION.md) for 15,000 requests/hour
- Running collection during off-peak hours
- Using the step-by-step manual collection below

### Step-by-Step Manual Collection

For maximum control and reliability in large environments, run each collection function independently:

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

9. Run the `Git-HoundRepositoryRole` function:

    ```powershell
    Write-Host "[*] Enumerating Repository Roles"
    $reporoles = $repos | Git-HoundRepositoryRole -Session $Session
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

10. Run the `Git-HoundBranch` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Branches"
    $branches = $org.nodes[0] | Git-HoundBranch -Session $Session
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

11. Run the `Git-HoundWorkflow` function:

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

12. Run the `Git-HoundEnvironment` function:

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

13. Run the `Git-HoundOrganizationSecret` function:

    ```powershell
    Write-Host "[*] Enumerating Organization Secrets"
    $orgsecrets = $repos | Git-HoundOrganizationSecret -Session $Session
    if($orgsecrets.nodes) { $nodes.AddRange(@($orgsecrets.nodes)) }
    if($orgsecrets.edges) { $edges.AddRange(@($orgsecrets.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $orgsecrets.Nodes.ToArray()
            edges = $orgsecrets.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_OrgSecret_$($org.nodes[0].id).json"
    ```

14. Run the `Git-HoundSecret` function:

    ```powershell
    Write-Host "[*] Enumerating Repository Secrets"
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

15. Run the `Git-HoundSecretScanningAlert` function:

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

16. Run the `Git-HoundAppInstallation` function:

    ```powershell
    Write-Host "[*] Enumerating App Installations"
    $appInstallations = $org.nodes[0] | Git-HoundAppInstallation -Session $Session
    if($appInstallations.nodes) { $nodes.AddRange(@($appInstallations.nodes)) }
    if($appInstallations.edges) { $edges.AddRange(@($appInstallations.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $appInstallations.Nodes.ToArray()
            edges = $appInstallations.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_AppInstallation_$($org.nodes[0].id).json"
    ```

17. Run the `Git-HoundGraphQlSamlProvider` function:

    ```powershell
    Write-Host "[*] Enumerating SAML Identity Provider"
    $saml = Git-HoundGraphQlSamlProvider -Session $Session
    if($saml.nodes) { $nodes.AddRange(@($saml.nodes)) }
    if($saml.edges) { $edges.AddRange(@($saml.edges)) }

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $saml.Nodes.ToArray()
            edges = $saml.Edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_Saml_$($org.nodes[0].id).json"
    ```

### Combining Manual Collection Output

When using the step-by-step collection, each function outputs a separate JSON file. You can combine them into a single file for BloodHound upload:

```powershell
# Combine all individual collection files into one
$allNodes = @()
$allEdges = @()

Get-ChildItem -Path "./githound_*.json" | ForEach-Object {
    $data = Get-Content $_.FullName | ConvertFrom-Json
    if ($data.graph.nodes) { $allNodes += $data.graph.nodes }
    if ($data.graph.edges) { $allEdges += $data.graph.edges }
}

$combinedPayload = [PSCustomObject]@{
    metadata = [PSCustomObject]@{
        source_kind = "GitHub"
    }
    graph = [PSCustomObject]@{
        nodes = $allNodes
        edges = $allEdges
    }
} | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_combined.json"

Write-Host "Combined $($allNodes.Count) nodes and $($allEdges.Count) edges"
```

Alternatively, you can upload each file individually to BloodHound—the graph database will merge the nodes and edges automatically.

### Sample

If you do not have a GitHub Enterprise environment or if you want to test out GitHound before collecting from your own production environment, we've included sample data sets in the `./samples/` directory.

### Troubleshooting

For common issues and solutions, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
