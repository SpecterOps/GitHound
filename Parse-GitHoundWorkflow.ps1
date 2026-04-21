. "$PSScriptRoot/githound.ps1"

function New-BHOGPropertyMatcher
{
    Param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        $Value,

        [Parameter()]
        [ValidateSet('equals')]
        [string]$Operator = 'equals'
    )
    @{ key = $Key; operator = $Operator; value = $Value }
}

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

function Get-WorkflowRunsOnLabels
{
    param(
        [Parameter()]
        $RunsOn
    )

    if (-not $RunsOn) { return @() }

    if ($RunsOn -is [System.Collections.IList]) {
        return @($RunsOn | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    }

    if ($RunsOn -isnot [string]) {
        return @("$RunsOn".Trim() | Where-Object { $_ })
    }

    $trimmed = $RunsOn.Trim()
    if (-not $trimmed) { return @() }

    if ($trimmed.StartsWith('[') -or $trimmed.StartsWith('{')) {
        $parsed = try { $trimmed | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $null }
        if ($parsed -is [System.Collections.IList]) {
            return @($parsed | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        }
    }

    return @($trimmed)
}

function Get-RunnerLabelNames
{
    param(
        [Parameter()]
        $Labels
    )

    if (-not $Labels) { return @() }

    $parsed = $Labels
    if ($Labels -is [string]) {
        $parsed = try { $Labels | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $Labels }
    }

    if ($parsed -is [System.Collections.IList]) {
        return @($parsed | ForEach-Object {
            if ($_ -is [string]) { "$_".Trim() }
            elseif ($_ -and $_.name) { "$($_.name)".Trim() }
        } | Where-Object { $_ })
    }

    return @()
}

function Get-WorkflowRunnerDispatchEdges
{
    <#
    .SYNOPSIS
        Computes GH_CanDispatchTo edges from workflow jobs to matching self-hosted runners.

    .DESCRIPTION
        Resolves a workflow job's runs-on labels against the set of runners the owning repository
        can use via GH_CanUseRunner. Only self-hosted jobs are considered.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [PSObject]$GraphData,

        [Parameter(Mandatory)]
        [PSObject]$WorkflowData
    )

    $edges = New-Object System.Collections.ArrayList

    $graphNodes = @($GraphData.graph.nodes ?? @())
    $graphEdges = @($GraphData.graph.edges ?? @())
    $workflowNodes = @($WorkflowData.Nodes ?? @())
    $workflowEdges = @($WorkflowData.Edges ?? @())

    $jobNodes = @($workflowNodes | Where-Object { $_.kinds -contains 'GH_WorkflowJob' })
    $jobEdges = @($workflowEdges | Where-Object { $_.kind -eq 'GH_HasJob' })
    $repoWorkflowEdges = @($graphEdges | Where-Object { $_.kind -eq 'GH_HasWorkflow' })
    $repoRunnerEdges = @($graphEdges | Where-Object { $_.kind -eq 'GH_CanUseRunner' })
    $runnerNodes = @($graphNodes | Where-Object { $_.kinds -contains 'GH_Runner' })

    $workflowToRepoId = @{}
    foreach ($edge in $repoWorkflowEdges) {
        if (-not $edge.start.value -or -not $edge.end.value) { continue }
        $workflowToRepoId[$edge.end.value] = $edge.start.value
    }

    $jobToWorkflowId = @{}
    foreach ($edge in $jobEdges) {
        if (-not $edge.start.value -or -not $edge.end.value) { continue }
        $jobToWorkflowId[$edge.end.value] = $edge.start.value
    }

    $repoToRunnerIds = @{}
    foreach ($edge in $repoRunnerEdges) {
        $repoId = $edge.start.value
        $runnerId = $edge.end.value
        if (-not $repoId -or -not $runnerId) { continue }
        if (-not $repoToRunnerIds.ContainsKey($repoId)) {
            $repoToRunnerIds[$repoId] = New-Object System.Collections.ArrayList
        }
        $null = $repoToRunnerIds[$repoId].Add($runnerId)
    }

    $runnerById = @{}
    foreach ($runner in $runnerNodes) {
        $runnerById[$runner.id] = $runner
    }

    foreach ($job in $jobNodes) {
        $requiredLabels = @(Get-WorkflowRunsOnLabels -RunsOn $job.properties.runs_on)
        if ($requiredLabels.Count -eq 0 -or $requiredLabels -notcontains 'self-hosted') { continue }

        $workflowId = $jobToWorkflowId[$job.id]
        if (-not $workflowId) { continue }

        $repoId = $workflowToRepoId[$workflowId]
        if (-not $repoId -or -not $repoToRunnerIds.ContainsKey($repoId)) { continue }

        foreach ($runnerId in $repoToRunnerIds[$repoId]) {
            if (-not $job.id -or -not $runnerId) { continue }
            if (-not $runnerById.ContainsKey($runnerId)) { continue }
            $runner = $runnerById[$runnerId]
            $runnerLabels = @(Get-RunnerLabelNames -Labels $runner.properties.labels)
            if ($runnerLabels.Count -eq 0) { continue }

            $allMatched = $true
            foreach ($label in $requiredLabels) {
                if ($runnerLabels -notcontains $label) {
                    $allMatched = $false
                    break
                }
            }
            if (-not $allMatched) { continue }

            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanDispatchTo' -StartId $job.id -EndId $runnerId -Properties @{
                traversable = $false
                required_labels = ($requiredLabels | ConvertTo-Json -Compress)
                matched_labels = ($runnerLabels | Where-Object { $requiredLabels -contains $_ } | ConvertTo-Json -Compress)
                runner_scope = $runner.properties.scope
            }))
        }
    }

    [PSCustomObject]@{
        Nodes = @()
        Edges = $edges
    }
}

function Test-PwnRequestable
{
    <#
    .SYNOPSIS
        Determines if a parsed workflow is susceptible to pwn requests.

    .DESCRIPTION
        A workflow is pwn-requestable when:
          1. It has a pull_request_target trigger
          2. A step uses actions/checkout with a ref pointing to the PR head
             (github.event.pull_request.head.sha, github.event.pull_request.head.ref,
              or github.head_ref)

    .PARAMETER TriggerEventNames
        The list of trigger event names for the workflow.

    .PARAMETER StepNodes
        The parsed step nodes for this workflow.
    #>
    Param(
        [System.Collections.ArrayList]$TriggerEventNames,
        [System.Collections.ArrayList]$StepNodes
    )

    # Condition 1: must have pull_request_target trigger
    if ($TriggerEventNames -notcontains 'pull_request_target') { return $false }

    # Condition 2: a step must checkout the attacker-controlled ref
    $pwnRefPatterns = @(
        'github.event.pull_request.head.sha',
        'github.event.pull_request.head.ref',
        'github.head_ref'
    )

    foreach ($step in $StepNodes)
    {
        if ($step.properties.action_slug -ne 'actions/checkout') { continue }
        if (-not $step.properties.with_args) { continue }

        $withArgs = try { $step.properties.with_args | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue } catch { $null }
        if (-not $withArgs -or -not $withArgs['ref']) { continue }

        $refVal = "$($withArgs['ref'])"
        foreach ($pattern in $pwnRefPatterns) {
            if ($refVal -like "*$pattern*") { return $true }
        }
    }

    return $false
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
            $skipped = $skipped + 1
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
            $skipped = $skipped + 1
            continue
        }

        if (-not $yaml) {
            $skipped = $skipped + 1
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
        $wf.properties | Add-Member -NotePropertyName 'triggers' -NotePropertyValue (@($triggerEventNames) | ConvertTo-Json -Compress) -Force

        # If workflow_dispatch has defined inputs, store the input names
        $dispatchConfig = $triggerEvents['workflow_dispatch']
        if ($dispatchConfig -and $dispatchConfig['inputs']) {
            $wf.properties | Add-Member -NotePropertyName 'trigger_dispatch_inputs' -NotePropertyValue (@($dispatchConfig['inputs'].Keys) | ConvertTo-Json -Compress) -Force
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
        $wfStepNodes = New-Object System.Collections.ArrayList
        if (-not $jobs) {
            $wf.properties | Add-Member -NotePropertyName 'is_pwn_requestable' -NotePropertyValue $false -Force
            $parsed = $parsed + 1
            continue
        }

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

            # Detect self-hosted runner
            $isSelfHosted = $false
            if ($runsOn) {
                if ($runsOn -eq 'self-hosted') {
                    $isSelfHosted = $true
                } else {
                    $parsed = try { $runsOn | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $null }
                    if ($parsed -and ($parsed -contains 'self-hosted')) { $isSelfHosted = $true }
                }
            }

            $jobProps = @{
                name             = "$repoName\$jobKey"
                node_id          = $jobId
                job_key          = $jobKey
                runs_on          = Normalize-Null $runsOn
                is_self_hosted   = $isSelfHosted
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
                    -Properties @{ traversable = $false }
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

                # Detect local script execution in run: blocks
                $localScriptRefs = $null
                if ($step['run'])
                {
                    $scriptMatches = New-Object System.Collections.ArrayList
                    # Pattern covers:
                    #   ./path/to/script.ext              (direct execution)
                    #   bash|sh|zsh|python|python3|node|ruby|perl|pwsh|powershell  path/to/script.ext
                    #   source|.  ./path/to/script.ext    (shell sourcing)
                    #   go run ./path/to/file.go
                    $localScriptPattern = '(?m)(?:^|\s|&&|\|\||;)\s*(?:(?:bash|sh|zsh|python3?|node|ruby|perl|pwsh|powershell)\s+|(?:source|\.)\s+|go\s+run\s+)?(\./[^\s;|&\r\n]+|\.github/[^\s;|&\r\n]+)'
                    foreach ($m in [regex]::Matches($step['run'], $localScriptPattern)) {
                        $scriptPath = $m.Groups[1].Value
                        # Filter out expression-only refs and common false positives
                        if ($scriptPath -notmatch '^\$\{\{' -and $scriptPath -match '\.\w+$') {
                            $null = $scriptMatches.Add($scriptPath)
                        }
                    }
                    if ($scriptMatches.Count -gt 0) {
                        $localScriptRefs = @($scriptMatches | Select-Object -Unique) | ConvertTo-Json -Compress
                    }
                }

                $actionSlug = if ($actionOwner -and $actionName) { "$actionOwner/$actionName" } else { $null }

                # Capture with: arguments as compact JSON for uses steps
                $withArgs = $null
                if ($step['with'] -and ($step['with'] -is [System.Collections.IDictionary] -or $step['with'] -is [hashtable]))
                {
                    $withArgs = $step['with'] | ConvertTo-Json -Compress -Depth 5 -ErrorAction SilentlyContinue
                }

                $stepProps = @{
                    name              = Normalize-Null $stepName
                    node_id           = $stepId
                    step_index        = $stepIndex
                    type              = $stepType
                    action            = Normalize-Null $action
                    action_slug       = Normalize-Null $actionSlug
                    auth_provider     = Normalize-Null $authProvider
                    action_owner      = Normalize-Null $actionOwner
                    action_name       = Normalize-Null $actionName
                    action_ref        = Normalize-Null $actionRef
                    is_pinned         = $isPinned
                    has_injection_risk = [bool]$injectionRisks
                    runs_local_script = [bool]$localScriptRefs
                    run               = Normalize-Null $step['run']
                    with_args         = Normalize-Null $withArgs
                    contents          = Normalize-Null (($step | ConvertTo-Json -Compress -Depth 5 -ErrorAction SilentlyContinue) -replace '\r?\n', '')
                    injection_risks   = Normalize-Null $injectionRisks
                    local_script_refs = Normalize-Null $localScriptRefs
                    job_node_id       = $jobId
                }

                $stepNode = New-GitHoundNode -Id $stepId -Kind 'GH_WorkflowStep' -Properties $stepProps
                $null = $nodes.Add($stepNode)
                $null = $wfStepNodes.Add($stepNode)
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

        # ── Pwn request detection ────────────────────────────────────────
        $isPwnRequestable = Test-PwnRequestable -TriggerEventNames $triggerEventNames -StepNodes $wfStepNodes
        $wf.properties | Add-Member -NotePropertyName 'is_pwn_requestable' -NotePropertyValue $isPwnRequestable -Force

        # Capture pull_request_target branch constraints (if any)
        $prtBranches = $null
        if ($isPwnRequestable) {
            $prtConfig = $triggerEvents['pull_request_target']
            if ($prtConfig -and $prtConfig['branches']) {
                $prtBranches = @($prtConfig['branches']) | ConvertTo-Json -Compress
            }
        }
        $wf.properties | Add-Member -NotePropertyName 'prt_branches' -NotePropertyValue (Normalize-Null $prtBranches) -Force

        $parsed = $parsed + 1
        Write-Verbose "Parsed [$parsed]: $($wf.properties.name) — pwn_requestable=$isPwnRequestable"
    }

    Write-Host "[*] Parse-GitHoundWorkflow: Parsed $parsed workflow(s), skipped $skipped. Created $($nodes.Count) nodes, $($edges.Count) edges."

    Write-Output ([PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    })
}

function Get-PwnRequestEdges
{
    <#
    .SYNOPSIS
        Computes GH_CanPwnRequest edges from repo roles to repositories and branches.

    .DESCRIPTION
        For each pwn-requestable workflow, identifies which GH_RepoRole nodes have
        GH_ReadRepoContents access to the owning repository and draws GH_CanPwnRequest
        edges to the repository and its branches.

        For private/internal repos, forkability is checked:
          - Org: members_can_fork_private_repositories must be true
          - Repo: allow_forking must be true

        For public repos, forkability is always true (anyone can fork).

        Branch targeting:
          - If the workflow's pull_request_target has branches: constraints,
            edges are drawn only to matching branches (and the repo).
          - If unconstrained, edges are drawn to the repo and all its branches.

    .PARAMETER GraphData
        The full collected graph data (from the consolidated output file).
        Must have graph.nodes and graph.edges.

    .PARAMETER WorkflowData
        The parsed workflow output from Parse-GitHoundWorkflow.
        Must have Nodes and Edges.

    .EXAMPLE
        $data = Get-Content ./githound_output.json | ConvertFrom-Json
        $wfResult = Parse-GitHoundWorkflow -Workflows $workflowNodes
        $pwnEdges = Get-PwnRequestEdges -GraphData $data -WorkflowData $wfResult
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [PSObject]$GraphData,

        [Parameter(Mandatory)]
        [PSObject]$WorkflowData
    )

    $edges = New-Object System.Collections.ArrayList

    # ── Index collected graph data ────────────────────────────────────
    $allNodes = $GraphData.graph.nodes
    $allEdges = $GraphData.graph.edges

    # Org node — check fork policy
    $orgNode = $allNodes | Where-Object { $_.kinds -contains 'GH_Organization' } | Select-Object -First 1
    $orgAllowsFork = $orgNode -and $orgNode.properties.members_can_fork_private_repositories -eq $true

    # Repo nodes indexed by node_id
    $repoMap = @{}
    foreach ($r in ($allNodes | Where-Object { $_.kinds -contains 'GH_Repository' })) {
        $repoMap[$r.properties.node_id] = $r
    }

    # Branch nodes indexed by repo — build from GH_HasBranch edges
    $repoBranches = @{}
    foreach ($e in ($allEdges | Where-Object { $_.kind -eq 'GH_HasBranch' })) {
        $repoId = if ($e.start.value) { $e.start.value } else { $e.start }
        $branchId = if ($e.end.value) { $e.end.value } else { $e.end }
        if (-not $repoBranches.ContainsKey($repoId)) { $repoBranches[$repoId] = [System.Collections.ArrayList]@() }
        $null = $repoBranches[$repoId].Add($branchId)
    }

    # Branch nodes indexed by id (for name lookup)
    $branchMap = @{}
    foreach ($b in ($allNodes | Where-Object { $_.kinds -contains 'GH_Branch' })) {
        $branchMap[$b.id] = $b
        if ($b.properties.node_id) { $branchMap[$b.properties.node_id] = $b }
    }

    # GH_ReadRepoContents edges: role_id → repo_id
    $readEdges = @{}
    foreach ($e in ($allEdges | Where-Object { $_.kind -eq 'GH_ReadRepoContents' })) {
        $roleId = if ($e.start.value) { $e.start.value } else { $e.start }
        $repoId = if ($e.end.value) { $e.end.value } else { $e.end }
        if (-not $readEdges.ContainsKey($repoId)) { $readEdges[$repoId] = [System.Collections.ArrayList]@() }
        $null = $readEdges[$repoId].Add($roleId)
    }

    # GH_HasWorkflow edges: repo_id → workflow_id
    $repoWorkflows = @{}
    foreach ($e in ($allEdges | Where-Object { $_.kind -eq 'GH_HasWorkflow' })) {
        $repoId = if ($e.start.value) { $e.start.value } else { $e.start }
        $wfId = if ($e.end.value) { $e.end.value } else { $e.end }
        if (-not $repoWorkflows.ContainsKey($wfId)) { $repoWorkflows[$wfId] = $repoId }
    }

    # ── Find pwn-requestable workflows ────────────────────────────────
    $pwnWorkflows = @($WorkflowData.Nodes | Where-Object {
        $_.kinds -contains 'GH_Workflow' -and $_.properties.is_pwn_requestable -eq $true
    })

    $edgeCount = 0
    foreach ($wf in $pwnWorkflows)
    {
        # Find the owning repo
        $repoId = $repoWorkflows[$wf.id]
        if (-not $repoId) { $repoId = $repoWorkflows[$wf.properties.node_id] }
        if (-not $repoId -and $wf.properties.repository_id) { $repoId = $wf.properties.repository_id }
        if (-not $repoId) {
            Write-Warning "Get-PwnRequestEdges: Could not find repo for workflow '$($wf.properties.name)'"
            continue
        }

        $repo = $repoMap[$repoId]
        if (-not $repo) {
            Write-Warning "Get-PwnRequestEdges: Repo node not found for id '$repoId'"
            continue
        }

        # Check forkability
        $isPublic = $repo.properties.visibility -eq 'public'
        if (-not $isPublic) {
            # Private/internal: both org and repo must allow forking
            if (-not $orgAllowsFork) { continue }
            if ($repo.properties.allow_forking -ne $true) { continue }
        }

        # Get roles with read access to this repo
        $roleIds = $readEdges[$repoId]
        if (-not $roleIds -or $roleIds.Count -eq 0) { continue }

        # Determine target branches
        $prtBranches = $null
        if ($wf.properties.prt_branches) {
            $prtBranches = try { $wf.properties.prt_branches | ConvertFrom-Json } catch { $null }
        }

        # Resolve branch node IDs for this repo
        $targetBranchIds = [System.Collections.ArrayList]@()
        $branches = $repoBranches[$repoId]
        if ($branches) {
            if ($prtBranches) {
                # Constrained: only matching branches
                foreach ($branchId in $branches) {
                    $branch = $branchMap[$branchId]
                    if ($branch) {
                        $branchName = $branch.properties.name -replace '^.*\\', ''  # Strip repo prefix if present
                        foreach ($pattern in $prtBranches) {
                            if ($branchName -like $pattern) {
                                $null = $targetBranchIds.Add($branchId)
                                break
                            }
                        }
                    }
                }
            } else {
                # Unconstrained: all branches
                $targetBranchIds.AddRange(@($branches))
            }
        }

        # Draw edges from each role to the repo and target branches
        $edgeProps = @{ traversable = $true; workflow = $wf.properties.name }

        foreach ($roleId in $roleIds) {
            # Edge to repo
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanPwnRequest' -StartId $roleId -EndId $repoId -Properties $edgeProps))
            $edgeCount = $edgeCount + 1

            # Edges to branches
            foreach ($branchId in $targetBranchIds) {
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanPwnRequest' -StartId $roleId -EndId $branchId -Properties $edgeProps))
                $edgeCount = $edgeCount + 1
            }
        }
    }

    Write-Host "[*] Get-PwnRequestEdges: $($pwnWorkflows.Count) pwn-requestable workflow(s), $edgeCount edges created."

    Write-Output ([PSCustomObject]@{
        Nodes = @()
        Edges = $edges
    })
}

function Invoke-GitHoundWorkflowAnalysis
{
    <#
    .SYNOPSIS
        Runs the full workflow analysis pipeline: parse workflows, compute pwn request edges,
        and output a BloodHound OpenGraph JSON file.

    .DESCRIPTION
        One-step wrapper that:
          1. Loads the collected GitHound output file
          2. Filters for GH_Workflow nodes with contents
          3. Runs Parse-GitHoundWorkflow to produce jobs, steps, edges, and findings
          4. Runs Get-PwnRequestEdges to compute GH_CanPwnRequest edges
          5. Combines everything into an OpenGraph payload
          6. Writes to a JSON file alongside the input file

    .PARAMETER Path
        Path to the collected GitHound output JSON file (e.g., githound_O_kgDO....json).

    .PARAMETER OutputPath
        Optional. Path for the output file. Defaults to the input file's directory
        with '_workflows' appended to the filename.

    .EXAMPLE
        Invoke-GitHoundWorkflowAnalysis -Path ./output/spectertst/githound_O_kgDOCoV2OQ.json

    .EXAMPLE
        Invoke-GitHoundWorkflowAnalysis -Path ./output.json -OutputPath ./workflows.json
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$OutputPath
    )

    # Load collected data
    if (-not (Test-Path $Path)) {
        Write-Error "File not found: $Path"
        return
    }
    Write-Host "[*] Loading collected data from $Path..."
    $data = Get-Content $Path -Raw | ConvertFrom-Json

    # Filter workflow nodes with contents
    $workflowNodes = @($data.graph.nodes | Where-Object {
        $_.kinds -contains 'GH_Workflow' -and $_.properties.contents -and $_.properties.contents.Trim().Length -gt 0
    })

    if ($workflowNodes.Count -eq 0) {
        Write-Warning "No workflow nodes with contents found. Ensure workflow content collection is enabled."
        return
    }
    Write-Host "[*] Found $($workflowNodes.Count) workflow(s) with contents."

    # Parse workflows
    $wfResult = Parse-GitHoundWorkflow -Workflows $workflowNodes

    # Compute pwn request and runner dispatch edges
    $pwnResult = Get-PwnRequestEdges -GraphData $data -WorkflowData $wfResult
    $dispatchResult = Get-WorkflowRunnerDispatchEdges -GraphData $data -WorkflowData $wfResult

    # Combine and convert to BHOG
    $payload = $wfResult, $pwnResult, $dispatchResult | ConvertTo-BHOG
    $json = $payload | ConvertTo-Json -Depth 10

    # Determine output path
    if (-not $OutputPath) {
        $dir = Split-Path $Path -Parent
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $OutputPath = Join-Path $dir "${base}_workflows.json"
    }

    $json | Out-File $OutputPath
    Write-Host "[+] Workflow analysis complete. Output written to $OutputPath"

    # Summary
    $pwnCount = @($wfResult.Nodes | Where-Object {
        $_.kinds -contains 'GH_Workflow' -and $_.properties.is_pwn_requestable -eq $true
    }).Count
    $dispatchCount = @($dispatchResult.Edges).Count
    Write-Host "[+] Summary: $($wfResult.Nodes.Count) nodes, $($wfResult.Edges.Count + $pwnResult.Edges.Count + $dispatchCount) edges, $pwnCount pwn-requestable workflow(s), $dispatchCount job-to-runner dispatch edge(s)"
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
          High     — injection risk in other triggers; pull_request_target with secret access;
                     local script execution in pull_request_target workflow
          Medium   — cloud auth actions without OIDC; self-hosted runner exposure;
                     local script execution in pull_request workflow
          Low      — unpinned actions (supply chain risk); local script execution in other triggers
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
    foreach ($job in ($jobNodes | Where-Object { $_.properties.is_self_hosted }))
    {
        $wfName = $job.properties.workflow_node_id -replace '^scan_', ''

        $null = $findings.Add([PSCustomObject]@{
            severity = 'Medium'
            type     = 'SelfHostedRunner'
            title    = "Job '$($job.properties.job_key)' runs on a self-hosted runner"
            workflow = $wfName
            job      = $job.properties.job_key
            step     = $null
            detail   = "runs-on: $($job.properties.runs_on). Self-hosted runners are not ephemeral by default and may be reachable by untrusted fork PRs. If pull_request or pull_request_target triggers exist, this runner could be compromised."
        })
    }

    # ── Finding 6: Local script execution (pwn request ingredient) ───────
    foreach ($step in ($stepNodes | Where-Object { $_.properties.runs_local_script }))
    {
        $jobId  = $step.properties.job_node_id
        $job    = $jobNodes | Where-Object { $_.id -eq $jobId } | Select-Object -First 1
        $wfId   = $job.properties.workflow_node_id
        $wfName = $wfId -replace '^scan_', ''
        $triggers = @($wfTriggerMap[$wfId] ?? @())

        $hasPRT = $triggers -contains 'pull_request_target'
        $hasPR  = $triggers -contains 'pull_request'

        $refs = try { $step.properties.local_script_refs | ConvertFrom-Json } catch { @($step.properties.local_script_refs) }

        $severity = if ($hasPRT) { 'High' }
                    elseif ($hasPR) { 'Medium' }
                    else            { 'Low' }

        $null = $findings.Add([PSCustomObject]@{
            severity = $severity
            type     = 'LocalScriptExecution'
            title    = "Step '$($step.properties.name)' executes local repo script(s)"
            workflow = $wfName
            job      = $job.properties.job_key
            step     = $step.properties.name
            detail   = "Scripts: $($refs -join ', '). Triggers: $($triggers -join ', '). An attacker who can modify these files (via PR or branch push) gains code execution in the workflow context with access to its secrets and permissions."
        })
    }

    # ── Finding 7: workflow_dispatch with user-controlled inputs ──────────
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
