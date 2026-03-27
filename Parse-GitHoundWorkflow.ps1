. "$PSScriptRoot/githound.ps1"

function Add-GitHoundSecretEdges
{
    # Emits two GH_UsesSecret edges per secret name: one targeting GH_RepoSecret (scoped by
    # repository_id) and one targeting GH_OrgSecret (scoped by environmentid). This avoids
    # match_by:name collisions when multiple repos share the same secret name.
    # Falls back to match_by:name against GH_Secret if no scope IDs are available.
    param(
        [System.Collections.ArrayList]$Edges,
        [string]$SourceId,
        [string]$SecretName,
        [string]$Context,
        [string]$RepoId,
        [string]$EnvId
    )

    $props = @{ traversable = $false; context = $Context }

    if ($RepoId -or $EnvId) {
        if ($RepoId) {
            $null = $Edges.Add((New-GitHoundEdge -Kind 'GH_UsesSecret' `
                -StartId $SourceId `
                -EndKind 'GH_RepoSecret' `
                -EndPropertyMatchers @(
                    (New-BHOGPropertyMatcher -Key 'name'          -Value $SecretName),
                    (New-BHOGPropertyMatcher -Key 'repository_id' -Value $RepoId)
                ) `
                -Properties $props))
        }
        if ($EnvId) {
            $null = $Edges.Add((New-GitHoundEdge -Kind 'GH_UsesSecret' `
                -StartId $SourceId `
                -EndKind 'GH_OrgSecret' `
                -EndPropertyMatchers @(
                    (New-BHOGPropertyMatcher -Key 'name'          -Value $SecretName),
                    (New-BHOGPropertyMatcher -Key 'environmentid' -Value $EnvId)
                ) `
                -Properties $props))
        }
    } else {
        $null = $Edges.Add((New-GitHoundEdge -Kind 'GH_UsesSecret' `
            -StartId $SourceId -EndId $SecretName `
            -EndKind 'GH_Secret' -EndMatchBy 'name' `
            -Properties $props))
    }
}

function Add-GitHoundVariableEdges
{
    param(
        [System.Collections.ArrayList]$Edges,
        [string]$SourceId,
        [string]$VariableName,
        [string]$Context,
        [string]$RepoId,
        [string]$EnvId
    )

    $props = @{ traversable = $false; context = $Context }

    if ($RepoId -or $EnvId) {
        if ($RepoId) {
            $null = $Edges.Add((New-GitHoundEdge -Kind 'GH_UsesVariable' `
                -StartId $SourceId `
                -EndKind 'GH_RepoVariable' `
                -EndPropertyMatchers @(
                    (New-BHOGPropertyMatcher -Key 'name'          -Value $VariableName),
                    (New-BHOGPropertyMatcher -Key 'repository_id' -Value $RepoId)
                ) `
                -Properties $props))
        }
        if ($EnvId) {
            $null = $Edges.Add((New-GitHoundEdge -Kind 'GH_UsesVariable' `
                -StartId $SourceId `
                -EndKind 'GH_OrgVariable' `
                -EndPropertyMatchers @(
                    (New-BHOGPropertyMatcher -Key 'name'          -Value $VariableName),
                    (New-BHOGPropertyMatcher -Key 'environmentid' -Value $EnvId)
                ) `
                -Properties $props))
        }
    } else {
        $null = $Edges.Add((New-GitHoundEdge -Kind 'GH_UsesVariable' `
            -StartId $SourceId -EndId $VariableName `
            -EndKind 'GH_Variable' -EndMatchBy 'name' `
            -Properties $props))
    }
}

function Parse-GitHoundWorkflow
{
    <#
    .SYNOPSIS
        Parses collected GH_Workflow YAML contents into jobs, steps, triggers, and secret/variable references.

    .DESCRIPTION
        This function takes already-collected GH_Workflow nodes (with their `contents` property containing
        raw YAML) and produces enriched graph nodes and edges:

        Node kinds enriched/created:
          - GH_Workflow        — input nodes are enriched with triggers, trigger_dispatch_inputs properties and included in output
          - GH_WorkflowJob     — one per job, with runs_on, permissions, environment
          - GH_WorkflowStep    — one per step, with action reference or run command, full step YAML in `contents`

        Edges created:
          - GH_HasJob          — GH_Workflow → GH_WorkflowJob
          - GH_HasStep         — GH_WorkflowJob → GH_WorkflowStep
          - GH_DependsOn       — GH_WorkflowJob → GH_WorkflowJob (needs: dependency)
          - GH_DeploysTo       — GH_WorkflowJob → GH_Environment (name match)
          - GH_UsesSecret      — GH_WorkflowStep → GH_RepoSecret/GH_OrgSecret (property match: name + repository_id or environmentid)
          - GH_UsesVariable    — GH_WorkflowStep → GH_RepoVariable/GH_OrgVariable (property match: name + repository_id or environmentid)
          - GH_CallsWorkflow   — GH_WorkflowJob → GH_Workflow (reusable workflow calls)

        Secret/variable references are extracted from step `with:`, `run:`, and `env:` blocks,
        as well as job-level `env:` and `secrets:` blocks.

    .PARAMETER Workflows
        An array of GH_Workflow node objects. Each must have:
          - id: The hex-encoded objectid of the workflow node
          - properties.contents: The raw YAML string of the workflow file
          - properties.repository_name: The repository name (used for environment name matching)
          - properties.node_id: The workflow's GitHub node_id

    .EXAMPLE
        $data = Get-Content "./output/githound_O_abc123.json" -Raw | ConvertFrom-Json
        $workflows = $data.graph.nodes | Where-Object { $_.kinds -contains 'GH_Workflow' }
        $result = Parse-GitHoundWorkflow -Workflows $workflows

    .EXAMPLE
        # From Invoke-GitHound output
        $result = Parse-GitHoundWorkflow -Workflows $workflowOutput.Nodes
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSObject[]]
        $Workflows
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $parsed = 0
    $skipped = 0

    foreach ($wf in $Workflows)
    {
        $contents = $wf.properties.contents
        if (-not $contents -or $contents.Trim().Length -eq 0)
        {
            $skipped++
            continue
        }

        $wfId = $wf.id
        $wfNodeId = $wf.properties.node_id
        $repoName = $wf.properties.repository_name
        $repoId   = $wf.properties.repository_id
        $envId    = $wf.properties.environmentid

        # Parse YAML
        $yaml = $null
        try {
            $yaml = ConvertFrom-Yaml $contents
        }
        catch {
            Write-Warning "Parse-GitHoundWorkflow: Failed to parse YAML for workflow '$($wf.properties.name)': $_"
            $skipped++
            continue
        }

        if (-not $yaml) {
            $skipped++
            continue
        }

        # ── Triggers ──────────────────────────────────────────────────────
        $on = $yaml['on']
        $triggerEventNames = [System.Collections.ArrayList]@()
        $triggerEvents = @{}

        if ($on)
        {
            if ($on -is [string])
            {
                # Shorthand: on: push
                $triggerEvents[$on] = @{}
            }
            elseif ($on -is [System.Collections.IList])
            {
                # Array shorthand: on: [push, pull_request]
                foreach ($t in $on) { $triggerEvents[$t] = @{} }
            }
            elseif ($on -is [System.Collections.IDictionary] -or $on -is [hashtable])
            {
                # Expanded form: on: { push: { branches: [...] } }
                foreach ($key in $on.Keys) {
                    $triggerEvents[$key] = if ($on[$key]) { $on[$key] } else { @{} }
                }
            }

            foreach ($eventName in $triggerEvents.Keys) {
                $null = $triggerEventNames.Add($eventName)
            }
        }

        # Store trigger event names as a JSON array on the workflow node
        $wf.properties | Add-Member -NotePropertyName 'triggers' -NotePropertyValue ($triggerEventNames | ConvertTo-Json -Compress) -Force

        # If workflow_dispatch has defined inputs, store the input names
        $dispatchConfig = $triggerEvents['workflow_dispatch']
        if ($dispatchConfig -and $dispatchConfig['inputs']) {
            $wf.properties | Add-Member -NotePropertyName 'trigger_dispatch_inputs' -NotePropertyValue ($dispatchConfig['inputs'].Keys | ConvertTo-Json -Compress) -Force
        }

        # Include the enriched workflow node in output
        $null = $nodes.Add($wf)

        # ── Workflow-level permissions ────────────────────────────────────
        $wfPermissions = $null
        if ($yaml['permissions'])
        {
            $wfPermissions = $yaml['permissions']
        }

        # ── Jobs ──────────────────────────────────────────────────────────
        $jobs = $yaml['jobs']
        if (-not $jobs) { $parsed++; continue }

        # Build a map of job key → job node ID for resolving needs: references
        $jobIdMap = @{}
        foreach ($jobKey in $jobs.Keys) {
            $jobIdMap[$jobKey] = "GH_WorkflowJob_${wfNodeId}_${jobKey}"
        }

        foreach ($jobKey in $jobs.Keys)
        {
            $job = $jobs[$jobKey]
            $jobId = $jobIdMap[$jobKey]

            # Determine environment name
            $jobEnvironment = $null
            if ($job['environment'])
            {
                if ($job['environment'] -is [string]) {
                    $jobEnvironment = $job['environment']
                }
                elseif ($job['environment'] -is [System.Collections.IDictionary] -or $job['environment'] -is [hashtable]) {
                    $jobEnvironment = $job['environment']['name']
                }
            }

            # Determine runs-on
            $runsOn = $null
            if ($job['runs-on'])
            {
                if ($job['runs-on'] -is [string]) {
                    $runsOn = $job['runs-on']
                } else {
                    $runsOn = $job['runs-on'] | ConvertTo-Json -Compress
                }
            }

            # Job-level permissions (inherit workflow-level if not set)
            $jobPermissions = $null
            if ($job['permissions']) {
                $jobPermissions = $job['permissions'] | ConvertTo-Json -Compress
            } elseif ($wfPermissions) {
                $jobPermissions = $wfPermissions | ConvertTo-Json -Compress
            }

            # Is this a reusable workflow call?
            $usesReusable = $null
            if ($job['uses']) {
                $usesReusable = $job['uses']
            }

            $jobProps = @{
                name             = "$repoName\$jobKey"
                node_id          = $jobId
                job_key          = $jobKey
                runs_on          = Normalize-Null $runsOn
                container        = Normalize-Null ($job['container'] -is [string] ? $job['container'] : ($job['container'] | ConvertTo-Json -Compress -ErrorAction SilentlyContinue))
                environment      = Normalize-Null $jobEnvironment
                permissions      = Normalize-Null $jobPermissions
                uses_reusable    = Normalize-Null $usesReusable
                workflow_node_id = $wfNodeId
            }

            $null = $nodes.Add((New-GitHoundNode -Id $jobId -Kind 'GH_WorkflowJob' -Properties $jobProps))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasJob' -StartId $wfId -EndId $jobId -Properties @{ traversable = $false }))

            # Edge: job needs (dependencies)
            if ($job['needs'])
            {
                $needsList = if ($job['needs'] -is [string]) { @($job['needs']) } else { @($job['needs']) }
                foreach ($dep in $needsList)
                {
                    if ($jobIdMap.ContainsKey($dep)) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DependsOn' -StartId $jobId -EndId $jobIdMap[$dep] -Properties @{ traversable = $false }))
                    }
                }
            }

            # Edge: job deploys to environment
            if ($jobEnvironment -and $repoName)
            {
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeploysTo' `
                    -StartId $jobId `
                    -EndId "$repoName\$jobEnvironment" `
                    -EndKind 'GH_Environment' `
                    -EndMatchBy 'name' `
                    -Properties @{ traversable = $true }
                ))
            }

            # Edge: reusable workflow call
            if ($usesReusable)
            {
                # Local reusable: ./.github/workflows/_ci.yml → match by repo\workflow_name
                if ($usesReusable -match '^\./\.github/workflows/(.+)$')
                {
                    $calledWorkflowFile = $Matches[1]
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CallsWorkflow' `
                        -StartId $jobId `
                        -EndId "$repoName\$calledWorkflowFile" `
                        -EndKind 'GH_Workflow' `
                        -EndMatchBy 'name' `
                        -Properties @{ traversable = $false; reusable_ref = $usesReusable }
                    ))
                }
                else
                {
                    # Remote reusable: org/repo/.github/workflows/file.yml@ref
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CallsWorkflow' `
                        -StartId $jobId `
                        -EndId $usesReusable `
                        -EndKind 'GH_Workflow' `
                        -EndMatchBy 'name' `
                        -Properties @{ traversable = $false; reusable_ref = $usesReusable }
                    ))
                }
            }

            # Job-level secrets: passthrough (for reusable workflow calls)
            if ($job['secrets'] -and $job['secrets'] -is [System.Collections.IDictionary])
            {
                foreach ($secretKey in $job['secrets'].Keys)
                {
                    $secretVal = $job['secrets'][$secretKey]
                    $referencedSecrets = Extract-SecretReferences $secretVal
                    foreach ($secretName in $referencedSecrets)
                    {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_UsesSecret' `
                            -StartId $jobId `
                            -EndId $secretName `
                            -EndKind 'GH_Secret' `
                            -EndMatchBy 'name' `
                            -Properties @{ traversable = $false; context = "secrets:$secretKey" }
                        ))
                    }
                }
            }
            elseif ($job['secrets'] -eq 'inherit')
            {
                $jobProps['secrets_inherit'] = $true
            }

            # Job-level env: extract secret/variable references
            if ($job['env'] -and ($job['env'] -is [System.Collections.IDictionary] -or $job['env'] -is [hashtable]))
            {
                foreach ($envKey in $job['env'].Keys)
                {
                    $envVal = "$($job['env'][$envKey])"
                    foreach ($secretName in (Extract-SecretReferences $envVal)) {
                        Add-GitHoundSecretEdges -Edges $edges -SourceId $jobId -SecretName $secretName -Context "env:$envKey" -RepoId $repoId -EnvId $envId
                    }
                    foreach ($varName in (Extract-VariableReferences $envVal)) {
                        Add-GitHoundVariableEdges -Edges $edges -SourceId $jobId -VariableName $varName -Context "env:$envKey" -RepoId $repoId -EnvId $envId
                    }
                }
            }

            # ── Steps ─────────────────────────────────────────────────────
            $steps = $job['steps']
            if (-not $steps) { continue }

            $stepIndex = 0
            foreach ($step in $steps)
            {
                $stepId = "GH_WorkflowStep_${wfNodeId}_${jobKey}_${stepIndex}"

                # Determine step name
                $stepName = $null
                if ($step['name']) {
                    $stepName = $step['name']
                } elseif ($step['uses']) {
                    $stepName = $step['uses']
                } elseif ($step['run']) {
                    # Use first line of run command, truncated
                    $firstLine = ($step['run'] -split "`n")[0].Trim()
                    $stepName = if ($firstLine.Length -gt 80) { $firstLine.Substring(0, 80) + "..." } else { $firstLine }
                }

                # Parse action reference
                $action = $null
                $actionOwner = $null
                $actionName = $null
                $authProvider = $null
                $actionRef = $null
                $isPinned = $false

                if ($step['uses'])
                {
                    $action = $step['uses']

                    # Parse: owner/name@ref or ./local/path
                    if ($action -match '^(?<owner>[^/]+)/(?<name>[^@]+)@(?<ref>.+)$')
                    {
                        $actionOwner = $Matches['owner']
                        $actionName = $Matches['name']
                        $actionRef = $Matches['ref']
                        $isPinned = $actionRef -match '^[0-9a-f]{40}$'
                    }

                    # Detect IdP/cloud authentication actions
                    $actionKey = "$actionOwner/$actionName".ToLower()
                    $authProvider = switch ($actionKey) {
                        'aws-actions/configure-aws-credentials' { 'AWS' }
                        'azure/login'                           { 'Azure' }
                        'azure/webapps-deploy'                  { 'Azure' }
                        'azure/arm-deploy'                      { 'Azure' }
                        'google-github-actions/auth'            { 'GCP' }
                        'google-github-actions/setup-gcloud'    { 'GCP' }
                        'hashicorp/vault-action'                { 'Vault' }
                        'docker/login-action'                   { 'Docker' }
                        default                                 { $null }
                    }
                }

                # Determine step type
                $stepType = if ($step['uses']) { 'uses' } elseif ($step['run']) { 'run' } else { 'unknown' }

                # Detect injection risks: user-controlled expressions in run: and with: blocks
                $injectionRisks = $null
                $injectionPattern = '\$\{\{\s*(github\.event\.inputs\.\w+|github\.event\.issue\.title|github\.event\.issue\.body|github\.event\.comment\.body|github\.event\.pull_request\.title|github\.event\.pull_request\.body|github\.event\.discussion\.title|github\.event\.discussion\.body|github\.head_ref|github\.event\.pages\.[^}]*\.page_name)\s*\}\}'
                $allRiskyMatches = New-Object System.Collections.ArrayList

                # Check run: block
                if ($step['run'])
                {
                    foreach ($m in [regex]::Matches($step['run'], $injectionPattern)) {
                        $null = $allRiskyMatches.Add($m.Groups[1].Value)
                    }
                }

                # Check with: block (e.g., actions/github-script script: input is code execution)
                if ($step['with'] -and ($step['with'] -is [System.Collections.IDictionary] -or $step['with'] -is [hashtable]))
                {
                    foreach ($withKey in $step['with'].Keys)
                    {
                        $withVal = "$($step['with'][$withKey])"
                        foreach ($m in [regex]::Matches($withVal, $injectionPattern)) {
                            $null = $allRiskyMatches.Add($m.Groups[1].Value)
                        }
                    }
                }

                if ($allRiskyMatches.Count -gt 0)
                {
                    $injectionRisks = @($allRiskyMatches | Select-Object -Unique) | ConvertTo-Json -Compress
                }

                $actionSlug = if ($actionOwner -and $actionName) { "$actionOwner/$actionName" } else { $null }

                $stepProps = @{
                    name            = Normalize-Null $stepName
                    node_id         = $stepId
                    step_index      = $stepIndex
                    type            = $stepType
                    action          = Normalize-Null $action
                    action_slug     = Normalize-Null $actionSlug
                    auth_provider   = Normalize-Null $authProvider
                    action_owner    = Normalize-Null $actionOwner
                    action_name     = Normalize-Null $actionName
                    action_ref      = Normalize-Null $actionRef
                    is_pinned       = $isPinned
                    run             = Normalize-Null $step['run']
                    contents        = Normalize-Null (($step | ConvertTo-Json -Compress -Depth 5 -ErrorAction SilentlyContinue) -replace '\r?\n', '')
                    injection_risks = Normalize-Null $injectionRisks
                    job_node_id     = $jobId
                }

                $null = $nodes.Add((New-GitHoundNode -Id $stepId -Kind 'GH_WorkflowStep' -Properties $stepProps))
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasStep' -StartId $jobId -EndId $stepId -Properties @{ traversable = $false }))

                # Extract secret/variable references from with:
                if ($step['with'] -and ($step['with'] -is [System.Collections.IDictionary] -or $step['with'] -is [hashtable]))
                {
                    foreach ($withKey in $step['with'].Keys)
                    {
                        $withVal = "$($step['with'][$withKey])"
                        foreach ($secretName in (Extract-SecretReferences $withVal)) {
                            Add-GitHoundSecretEdges -Edges $edges -SourceId $stepId -SecretName $secretName -Context "with:$withKey" -RepoId $repoId -EnvId $envId
                        }
                        foreach ($varName in (Extract-VariableReferences $withVal)) {
                            Add-GitHoundVariableEdges -Edges $edges -SourceId $stepId -VariableName $varName -Context "with:$withKey" -RepoId $repoId -EnvId $envId
                        }
                    }
                }

                # Extract secret/variable references from run:
                if ($step['run'])
                {
                    $runStr = "$($step['run'])"
                    foreach ($secretName in (Extract-SecretReferences $runStr)) {
                        Add-GitHoundSecretEdges -Edges $edges -SourceId $stepId -SecretName $secretName -Context "run" -RepoId $repoId -EnvId $envId
                    }
                    foreach ($varName in (Extract-VariableReferences $runStr)) {
                        Add-GitHoundVariableEdges -Edges $edges -SourceId $stepId -VariableName $varName -Context "run" -RepoId $repoId -EnvId $envId
                    }
                }

                # Extract secret/variable references from env:
                if ($step['env'] -and ($step['env'] -is [System.Collections.IDictionary] -or $step['env'] -is [hashtable]))
                {
                    foreach ($envKey in $step['env'].Keys)
                    {
                        $envVal = "$($step['env'][$envKey])"
                        foreach ($secretName in (Extract-SecretReferences $envVal)) {
                            Add-GitHoundSecretEdges -Edges $edges -SourceId $stepId -SecretName $secretName -Context "env:$envKey" -RepoId $repoId -EnvId $envId
                        }
                        foreach ($varName in (Extract-VariableReferences $envVal)) {
                            Add-GitHoundVariableEdges -Edges $edges -SourceId $stepId -VariableName $varName -Context "env:$envKey" -RepoId $repoId -EnvId $envId
                        }
                    }
                }

                $stepIndex++
            }
        }

        $parsed++
    }

    Write-Host "[*] Parse-GitHoundWorkflow: Parsed $parsed workflow(s), skipped $skipped. Created $($nodes.Count) nodes, $($edges.Count) edges."

    Write-Output ([PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    })
}

function ConvertTo-BHOG
{
    <#
    .SYNOPSIS
        Converts GitHound collector output into a BloodHound OpenGraph JSON payload.

    .DESCRIPTION
        Wraps any GitHound output (Nodes + Edges) into the BloodHound OpenGraph envelope.
        Optionally hex-encodes objectids to match the encoding used by a full GitHound collection,
        and optionally writes the result to a file.

    .PARAMETER InputObject
        A PSObject with Nodes and Edges properties — the output of Parse-GitHoundWorkflow,
        Git-HoundOrganization, or any other GitHound collector.

    .PARAMETER EncodeIds
        When set, hex-encodes all objectids via Convert-GitHoundOutputIds to match the encoding
        used by a full GitHound collection. Use this when uploading alongside a main collection.

    .EXAMPLE
        Parse-GitHoundWorkflow -Workflows $nodes | ConvertTo-BHOG | ConvertTo-Json -Depth 10 | Out-File ./workflows.json

    .EXAMPLE
        Parse-GitHoundWorkflow -Workflows $nodes | ConvertTo-BHOG -EncodeIds | ConvertTo-Json -Depth 10 | Out-File ./workflows.json
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSObject]$InputObject,

        [Parameter()]
        [switch]$EncodeIds
    )

    begin {
        $nodes = [System.Collections.ArrayList]::new()
        $edges = [System.Collections.ArrayList]::new()
    }

    process {
        if ($InputObject.Nodes) { $null = $nodes.AddRange(@($InputObject.Nodes | Where-Object { $_ -ne $null })) }
        if ($InputObject.Edges) { $null = $edges.AddRange(@($InputObject.Edges | Where-Object { $_ -ne $null })) }
    }

    end {
        if ($EncodeIds) {
            Convert-GitHoundOutputIds -Nodes $nodes -Edges $edges
        }

        $payload = [PSCustomObject]@{
            '$schema' = "https://raw.githubusercontent.com/MichaelGrafnetter/EntraAuthPolicyHound/refs/heads/main/bloodhound-opengraph.schema.json"
            metadata  = [PSCustomObject]@{ source_kind = "GitHub" }
            graph     = [PSCustomObject]@{
                nodes = @($nodes)
                edges = @($edges)
            }
        }

        Write-Output $payload
    }
}

function Invoke-GitHoundWorkflowScan
{
    <#
    .SYNOPSIS
        Fetches and scans GitHub Actions workflow files from a repository for security issues.

    .DESCRIPTION
        Fetches all .yml/.yaml files from a repository's .github/workflows/ directory via the
        GitHub API, parses them through Parse-GitHoundWorkflow, and generates prioritized security
        findings covering:

          - Expression injection risks (user-controlled inputs in run:/with: blocks)
          - pull_request_target triggers with secret access (fork PR exfiltration)
          - Unpinned actions (supply chain risk)
          - Cloud auth actions without OIDC (possible static credentials)
          - workflow_dispatch inputs (potential injection surface)

        Works on public repositories without authentication. Provide -Token to scan private
        repositories or to avoid rate limiting.

    .PARAMETER Repository
        The repository to scan in "owner/repo" format.

    .PARAMETER Token
        Optional GitHub token (classic PAT or fine-grained). Required for private repositories.

    .PARAMETER Ref
        The branch, tag, or commit SHA to scan. Defaults to the repository's default branch.

    .EXAMPLE
        Invoke-GitHoundWorkflowScan -Repository "octocat/Hello-World"

    .EXAMPLE
        Invoke-GitHoundWorkflowScan -Repository "my-org/private-repo" -Token $env:GITHUB_TOKEN

    .OUTPUTS
        PSCustomObject with properties: Nodes, Edges, Findings
        Findings are also printed to the console, sorted by severity.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Repository,

        [Parameter()]
        [string]$Token,

        [Parameter()]
        [string]$Ref
    )

    $headers = @{ 'Accept' = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }

    # Fetch workflow directory listing
    $listUri = "https://api.github.com/repos/$Repository/contents/.github/workflows"
    if ($Ref) { $listUri += "?ref=$Ref" }

    Write-Host "[*] Scanning $Repository..."
    try {
        $files = Invoke-RestMethod -Uri $listUri -Headers $headers -Method GET -ErrorAction Stop
    } catch {
        Write-Error "Failed to list workflows for '$Repository': $_"
        return
    }

    $workflowFiles = @($files | Where-Object { $_.name -match '\.(yml|yaml)$' -and $_.type -eq 'file' })

    if ($workflowFiles.Count -eq 0) {
        Write-Host "[*] No workflow files found in $Repository/.github/workflows/"
        return
    }

    Write-Host "[*] Found $($workflowFiles.Count) workflow file(s)"

    # Fetch and decode each workflow file, shape into nodes for the parser
    $workflowNodes = New-Object System.Collections.ArrayList

    foreach ($file in $workflowFiles)
    {
        try {
            $fileResponse = Invoke-RestMethod -Uri $file.url -Headers $headers -Method GET -ErrorAction Stop
            # GitHub API returns base64 with newlines; strip them before decoding
            $cleanBase64 = $fileResponse.content -replace '[\r\n\s]', ''
            $yaml = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($cleanBase64))

            # Synthesize a workflow node in the format Parse-GitHoundWorkflow expects
            $syntheticNodeId = "scan_$($file.sha)"
            $repoName = $Repository.Split('/')[1]

            $wfNode = [PSCustomObject]@{
                id         = ConvertTo-HexObjectId "GH_Workflow_$($file.sha)"
                properties = [PSCustomObject]@{
                    contents        = $yaml
                    repository_name = $repoName
                    node_id         = "scan_$($file.name)"
                    name            = $file.name
                    path            = $file.path
                }
            }

            $null = $workflowNodes.Add($wfNode)
            Write-Host "  [+] $($file.name)"
        } catch {
            Write-Warning "  [!] Failed to fetch $($file.name): $_"
        }
    }

    if ($workflowNodes.Count -eq 0) {
        Write-Host "[*] No workflow files could be fetched."
        return
    }

    # Parse
    $parseResult = Parse-GitHoundWorkflow -Workflows $workflowNodes

    # Generate findings
    $findings = Get-GitHoundWorkflowFindings -ParseResult $parseResult

    # Print findings to console
    if ($findings.Count -gt 0)
    {
        $severityOrder = @{ 'Critical' = 0; 'High' = 1; 'Medium' = 2; 'Low' = 3; 'Info' = 4 }
        $sorted = $findings | Sort-Object { $severityOrder[$_.severity] }

        Write-Host "`n[!] $($findings.Count) finding(s) — $Repository`n"

        foreach ($f in $sorted)
        {
            $prefix = switch ($f.severity) {
                'Critical' { '[CRITICAL]' }
                'High'     { '[HIGH]    ' }
                'Medium'   { '[MEDIUM]  ' }
                'Low'      { '[LOW]     ' }
                default    { '[INFO]    ' }
            }
            Write-Host "$prefix $($f.title)"
            Write-Host "           Workflow : $($f.workflow)"
            if ($f.job)    { Write-Host "           Job      : $($f.job)" }
            if ($f.step)   { Write-Host "           Step     : $($f.step)" }
            if ($f.detail) { Write-Host "           Detail   : $($f.detail)" }
            Write-Host ""
        }
    }
    else
    {
        Write-Host "`n[*] No issues found."
    }

    return [PSCustomObject]@{
        Nodes    = $parseResult.Nodes
        Edges    = $parseResult.Edges
        Findings = $findings
    }
}

function Get-GitHoundWorkflowFindings
{
    <#
    .SYNOPSIS
        Generates security findings from the output of Parse-GitHoundWorkflow.

    .DESCRIPTION
        Analyses parsed workflow graph data to identify security issues:

        Severity levels:
          Critical — injection risk in pull_request_target trigger (fork PR exfiltration)
          High     — injection risk in other triggers; pull_request_target with secret access
          Medium   — cloud auth actions without OIDC; self-hosted runner exposure
          Low      — unpinned actions (supply chain risk)
          Info     — informational findings (workflow_dispatch inputs, etc.)

    .PARAMETER ParseResult
        The output of Parse-GitHoundWorkflow (object with Nodes and Edges properties).
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSObject]$ParseResult
    )

    $findings = New-Object System.Collections.ArrayList
    $nodes = $ParseResult.Nodes
    $edges = $ParseResult.Edges

    # Index nodes by kind
    $workflowNodes = @($nodes | Where-Object { $_.kinds -contains 'GH_Workflow' })
    $jobNodes      = @($nodes | Where-Object { $_.kinds -contains 'GH_WorkflowJob' })
    $stepNodes     = @($nodes | Where-Object { $_.kinds -contains 'GH_WorkflowStep' })

    # Build lookup: workflow_node_id → list of trigger event names (from triggers property)
    $wfTriggerMap = @{}
    foreach ($wf in $workflowNodes) {
        $wfId = $wf.properties.node_id
        $triggerList = try { $wf.properties.triggers | ConvertFrom-Json } catch { @() }
        $wfTriggerMap[$wfId] = [System.Collections.ArrayList]@($triggerList)
    }

    # Build lookup: workflow_node_id → list of job node IDs
    $wfJobMap = @{}
    foreach ($j in $jobNodes) {
        $wfId = $j.properties.workflow_node_id
        if (-not $wfJobMap.ContainsKey($wfId)) { $wfJobMap[$wfId] = [System.Collections.ArrayList]@() }
        $null = $wfJobMap[$wfId].Add($j.id)
    }

    # Build lookup: job node ID → list of step nodes
    $jobStepMap = @{}
    foreach ($s in $stepNodes) {
        $jobId = $s.properties.job_node_id
        if (-not $jobStepMap.ContainsKey($jobId)) { $jobStepMap[$jobId] = [System.Collections.ArrayList]@() }
        $null = $jobStepMap[$jobId].Add($s)
    }

    # Build set of step IDs that use secrets (from GH_UsesSecret edges)
    $stepsWithSecrets = @{}
    foreach ($edge in ($edges | Where-Object { $_.kind -eq 'GH_UsesSecret' })) {
        $stepsWithSecrets[$edge.start.value] = $true
    }

    # Helper: get all steps in a workflow
    $getWfSteps = {
        Param($wfId)
        $result = [System.Collections.ArrayList]@()
        foreach ($jobId in ($wfJobMap[$wfId] ?? @())) {
            foreach ($step in ($jobStepMap[$jobId] ?? @())) {
                $null = $result.Add($step)
            }
        }
        return ,$result
    }

    # ── Finding 1: Expression injection risks ─────────────────────────────
    foreach ($step in ($stepNodes | Where-Object { $_.properties.injection_risks }))
    {
        $jobId  = $step.properties.job_node_id
        $job    = $jobNodes | Where-Object { $_.id -eq $jobId } | Select-Object -First 1
        $wfId   = $job.properties.workflow_node_id
        $wfName = $job.properties.workflow_node_id -replace '^scan_', ''
        $triggers = @($wfTriggerMap[$wfId] ?? @())

        $hasPRT = $triggers -contains 'pull_request_target'
        $hasPR  = $triggers -contains 'pull_request'
        $hasWD  = $triggers -contains 'workflow_dispatch'

        $severity = if ($hasPRT)            { 'Critical' }
                    elseif ($hasWD -or $hasPR) { 'High' }
                    else                       { 'Medium' }

        $risks = try { $step.properties.injection_risks | ConvertFrom-Json } catch { @($step.properties.injection_risks) }

        $null = $findings.Add([PSCustomObject]@{
            severity = $severity
            type     = 'ExpressionInjection'
            title    = "Expression injection in step '$($step.properties.name)'"
            workflow = $wfName
            job      = $job.properties.job_key
            step     = $step.properties.name
            detail   = "User-controlled expressions: $($risks -join ', ') | Triggers: $($triggers -join ', ')"
        })
    }

    # ── Finding 2: pull_request_target with secret access ─────────────────
    foreach ($wf in ($workflowNodes | Where-Object { ($wfTriggerMap[$_.properties.node_id] ?? @()) -contains 'pull_request_target' }))
    {
        $wfId   = $wf.properties.node_id
        $wfName = $wfId -replace '^scan_', ''

        # Check if any step in this workflow accesses secrets
        $wfSteps = & $getWfSteps $wfId
        $secretStepCount = @($wfSteps | Where-Object { $stepsWithSecrets.ContainsKey($_.id) }).Count

        if ($secretStepCount -gt 0)
        {
            $null = $findings.Add([PSCustomObject]@{
                severity = 'High'
                type     = 'PullRequestTargetWithSecrets'
                title    = "pull_request_target trigger with access to $secretStepCount secret reference(s)"
                workflow = $wfName
                job      = $null
                step     = $null
                detail   = "Workflows triggered by pull_request_target run in the base branch context and can access repository secrets. Fork PRs can trigger this workflow."
            })
        }
        else
        {
            # Still noteworthy even without detected secrets — GITHUB_TOKEN has write perms
            $null = $findings.Add([PSCustomObject]@{
                severity = 'Medium'
                type     = 'PullRequestTarget'
                title    = "pull_request_target trigger (write-permissioned GITHUB_TOKEN)"
                workflow = $wfName
                job      = $null
                step     = $null
                detail   = "pull_request_target runs in the base branch context with a write-permissioned GITHUB_TOKEN by default, even for fork PRs."
            })
        }
    }

    # ── Finding 3: Unpinned third-party actions ────────────────────────────
    foreach ($step in ($stepNodes | Where-Object {
        $_.properties.type -eq 'uses' -and
        $_.properties.is_pinned -eq $false -and
        $_.properties.action -and
        $_.properties.action -notmatch '^\./'}))
    {
        $jobId  = $step.properties.job_node_id
        $job    = $jobNodes | Where-Object { $_.id -eq $jobId } | Select-Object -First 1
        $wfName = $job.properties.workflow_node_id -replace '^scan_', ''

        $null = $findings.Add([PSCustomObject]@{
            severity = 'Low'
            type     = 'UnpinnedAction'
            title    = "Unpinned action: $($step.properties.action)"
            workflow = $wfName
            job      = $job.properties.job_key
            step     = $step.properties.action
            detail   = "Not pinned to a full commit SHA. A tag or branch can be moved to point at malicious code. Pin to a commit SHA to mitigate supply chain risk."
        })
    }

    # ── Finding 4: Cloud auth without OIDC (possible static credentials) ──
    foreach ($step in ($stepNodes | Where-Object { $_.properties.auth_provider }))
    {
        $jobId = $step.properties.job_node_id
        $job   = $jobNodes | Where-Object { $_.id -eq $jobId } | Select-Object -First 1
        $wfName = $job.properties.workflow_node_id -replace '^scan_', ''

        # Check job permissions for id-token: write
        $hasOidc = $false
        if ($job.properties.permissions)
        {
            $rawPerms = $job.properties.permissions
            if ($rawPerms -eq 'write-all') {
                $hasOidc = $true
            } else {
                $perms = try { $rawPerms | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue } catch { $null }
                if ($perms -and $perms['id-token'] -eq 'write') { $hasOidc = $true }
            }
        }

        if (-not $hasOidc)
        {
            $null = $findings.Add([PSCustomObject]@{
                severity = 'Medium'
                type     = 'PossibleStaticCredentials'
                title    = "Possible static $($step.properties.auth_provider) credentials via $($step.properties.action_slug)"
                workflow = $wfName
                job      = $job.properties.job_key
                step     = $step.properties.action
                detail   = "Uses a $($step.properties.auth_provider) authentication action without id-token:write permission. This suggests static long-lived credentials rather than OIDC federation."
            })
        }
    }

    # ── Finding 5: Self-hosted runners ────────────────────────────────────
    foreach ($job in ($jobNodes | Where-Object { $_.properties.runs_on }))
    {
        $runsOn = $job.properties.runs_on

        # Detect self-hosted: plain string, or JSON array containing "self-hosted"
        $isSelfHosted = $false
        if ($runsOn -eq 'self-hosted') {
            $isSelfHosted = $true
        } else {
            $parsed = try { $runsOn | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $null }
            if ($parsed -and ($parsed -contains 'self-hosted')) { $isSelfHosted = $true }
        }

        if ($isSelfHosted)
        {
            $wfName = $job.properties.workflow_node_id -replace '^scan_', ''

            $null = $findings.Add([PSCustomObject]@{
                severity = 'Medium'
                type     = 'SelfHostedRunner'
                title    = "Job '$($job.properties.job_key)' runs on a self-hosted runner"
                workflow = $wfName
                job      = $job.properties.job_key
                step     = $null
                detail   = "runs-on: $runsOn. Self-hosted runners are not ephemeral by default and may be reachable by untrusted fork PRs. If pull_request or pull_request_target triggers exist, this runner could be compromised."
            })
        }
    }

    # ── Finding 6: workflow_dispatch with user-controlled inputs ──────────
    foreach ($wf in ($workflowNodes | Where-Object {
        ($wfTriggerMap[$_.properties.node_id] ?? @()) -contains 'workflow_dispatch' -and $_.properties.trigger_dispatch_inputs }))
    {
        $wfId   = $wf.properties.node_id
        $wfName = $wfId -replace '^scan_', ''
        $inputs = try { $wf.properties.trigger_dispatch_inputs | ConvertFrom-Json } catch { @() }

        $null = $findings.Add([PSCustomObject]@{
            severity = 'Info'
            type     = 'WorkflowDispatchInputs'
            title    = "workflow_dispatch with $($inputs.Count) user-controlled input(s)"
            workflow = $wfName
            job      = $null
            step     = $null
            detail   = "Inputs: $($inputs -join ', '). Verify these are not interpolated unsafely into run: or with: blocks (check ExpressionInjection findings)."
        })
    }

    return ,$findings
}

function Export-GitHoundWorkflowPayload
{
    <#
    .SYNOPSIS
        Converts Parse-GitHoundWorkflow output into a BloodHound OpenGraph JSON payload.

    .DESCRIPTION
        Wraps the nodes and edges produced by Parse-GitHoundWorkflow (or Invoke-GitHoundWorkflowScan)
        into the standard BloodHound OpenGraph format and writes the result to a JSON file.

        The output file can be imported directly into BloodHound CE alongside a full GitHound
        collection, or used standalone for workflow-only analysis.

    .PARAMETER ParseResult
        The output of Parse-GitHoundWorkflow or the Nodes/Edges from Invoke-GitHoundWorkflowScan.
        Must have Nodes and Edges properties.

    .PARAMETER OutputPath
        The file path to write the JSON payload to. Defaults to "githound_Workflow_<timestamp>.json"
        in the current directory.

    .EXAMPLE
        $result = Invoke-GitHoundWorkflowScan -Repository "owner/repo"
        Export-GitHoundWorkflowPayload -ParseResult $result -OutputPath "./output/workflows.json"

    .EXAMPLE
        $result = Parse-GitHoundWorkflow -Workflows $workflowNodes
        Export-GitHoundWorkflowPayload -ParseResult $result
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSObject]$ParseResult,

        [Parameter()]
        [string]$OutputPath
    )

    if (-not $OutputPath) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $OutputPath = "githound_Workflow_$timestamp.json"
    }

    $filteredNodes = @($ParseResult.Nodes | Where-Object { $_ -ne $null })
    $filteredEdges = @($ParseResult.Edges | Where-Object { $_ -ne $null })

    $payload = [PSCustomObject]@{
        '$schema' = "https://raw.githubusercontent.com/MichaelGrafnetter/EntraAuthPolicyHound/refs/heads/main/bloodhound-opengraph.schema.json"
        metadata  = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $filteredNodes
            edges = $filteredEdges
        }
    }

    $payload | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "[+] Workflow payload: $OutputPath ($($filteredNodes.Count) nodes, $($filteredEdges.Count) edges)"
}

function Extract-SecretReferences
{
    <#
    .SYNOPSIS
        Extracts secret names from GitHub Actions expression strings.
    .DESCRIPTION
        Matches ${{ secrets.NAME }} patterns and returns an array of unique secret names.
    #>
    Param(
        [Parameter(Position = 0)]
        [string]$Text
    )

    if (-not $Text) { return @() }

    $matches = [regex]::Matches($Text, '\$\{\{\s*secrets\.(\w+)\s*\}\}')
    $names = @($matches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    return $names
}

function Extract-VariableReferences
{
    <#
    .SYNOPSIS
        Extracts variable names from GitHub Actions expression strings.
    .DESCRIPTION
        Matches ${{ vars.NAME }} patterns and returns an array of unique variable names.
    #>
    Param(
        [Parameter(Position = 0)]
        [string]$Text
    )

    if (-not $Text) { return @() }

    $matches = [regex]::Matches($Text, '\$\{\{\s*vars\.(\w+)\s*\}\}')
    $names = @($matches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    return $names
}
