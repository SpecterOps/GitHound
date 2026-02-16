function Get-GitHoundFunctionBundle {
    [OutputType([hashtable])]
    param() 
    $GitHoundFunctions = @{}
    $functionsToRegister = @(
        'Normalize-Null',
        'New-GitHoundNode',
        'New-GitHoundEdge',
        'Invoke-GithubRestMethod',
        'Wait-GithubRestRateLimit',
        'Wait-GithubRateLimitReached',
        'Get-RateLimitInformation',
        'ConvertTo-PascalCase'
    )
    
    # Register each function
    foreach ($funcName in $functionsToRegister) {
        if (Get-Command $funcName -ErrorAction SilentlyContinue) {
            $GitHoundFunctions[$funcName] = ((Get-Command $funcName).Definition).ToString()
        } else {
            Write-Warning "Function $funcName not found and will be skipped"
        }
    }

    return $GitHoundFunctions
}

function New-GithubSession {
    [OutputType('GitHound.Session')] 
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory = $true)]
        [string]
        $OrganizationName,

        [Parameter(Position=1, Mandatory = $false)]
        [string]
        $ApiUri = 'https://api.github.com/',

        [Parameter(Position=2, Mandatory = $false)]
        [string]
        $Token,

        [Parameter(Position=3, Mandatory = $false)]
        [string]
        $UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/68.0.3440.106 Safari/537.36',

        [Parameter(Position=4, Mandatory = $false)]
        [HashTable]
        $Headers = @{}
    )

    if($Headers['Accept']) {
        throw "User-Agent header is specified in both the UserAgent and Headers parameter"
    } else {
        $Headers['Accept'] = 'application/vnd.github+json'
    }

    if($Headers['X-GitHub-Api-Version']) {
        throw "User-Agent header is specified in both the UserAgent and Headers parameter"
    } else {
        $Headers['X-GitHub-Api-Version'] = '2022-11-28'
    }

    if($UserAgent) {
        if($Headers['User-Agent']) {
            throw "User-Agent header is specified in both the UserAgent and Headers parameter"
        } else {
            $Headers['User-Agent'] = $UserAgent
        }
    } 

    if($Token) {
        if($Headers['Authorization']) {
            throw "Authorization header cannot be set because the Token parameter the 'Authorization' header is specified"
        } else {
            $Headers['Authorization'] = "Bearer $Token"
        }
    }

    [PSCustomObject]@{
        PSTypeName = 'GitHound.Session'
        Uri = $ApiUri
        Headers = $Headers
        OrganizationName = $OrganizationName
    }
}

# Reference: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app#example-using-powershell-to-generate-a-jwt
function New-GitHubJwtSession
{
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory = $true)]
        [string]
        $OrganizationName,
        
        [Parameter(Position=1, Mandatory = $true)]
        [string]
        $ClientId,

        [Parameter(Position=2, Mandatory = $true)]
        [string]
        $PrivateKeyPath,

        [Parameter(Position=3, Mandatory = $true)]
        [string]
        $AppId
    )

    $header = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{
    alg = "RS256"
    typ = "JWT"
    }))).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    $payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{
    iat = [System.DateTimeOffset]::UtcNow.AddSeconds(-10).ToUnixTimeSeconds()
    exp = [System.DateTimeOffset]::UtcNow.AddMinutes(10).ToUnixTimeSeconds()
    iss = $ClientId
    }))).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem((Get-Content $PrivateKeyPath -Raw))

    $signature = [Convert]::ToBase64String($rsa.SignData([System.Text.Encoding]::UTF8.GetBytes("$header.$payload"), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    
    $jwt = "$header.$payload.$signature"
    
    $jwtsession = New-GithubSession -OrganizationName $OrganizationName -Token $jwt

    $result = Invoke-GithubrestMethod -Session $jwtsession -Path "app/installations/$($AppId)/access_tokens" -Method POST 

    $session = New-GitHubSession -OrganizationName $OrganizationName -Token $result.token
    
    Write-Output $session
}

function Invoke-GithubRestMethod {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Mandatory=$true)]
        [string]
        $Path,

        [Parameter()]
        [string]
        $Method = 'GET'
    )

    $LinkHeader = $Null;
    try {
        do {
            $requestSuccessful = $false
            $retryCount = 0
            
            while (-not $requestSuccessful -and $retryCount -lt 3) {
                try {
                    if($LinkHeader) {
                        $Response = Invoke-WebRequest -Uri "$LinkHeader" -Headers $Session.Headers -Method $Method -ErrorAction Stop
                    } else {
                        Write-Verbose "https://api.github.com/$($Path)"
                        $Response = Invoke-WebRequest -Uri "$($Session.Uri)$($Path)" -Headers $Session.Headers -Method $Method -ErrorAction Stop
                    }
                    $requestSuccessful = $true
                }
                catch {
                    $httpException = $_.ErrorDetails | ConvertFrom-Json
                    if (($httpException.status -eq "403" -and $httpException.message -match "rate limit") -or $httpException.status -eq "429") {
                        Write-Warning "Rate limit hit when doing Github RestAPI call. Retry $($retryCount + 1)/3"
                        Write-Debug $_
                        Wait-GithubRestRateLimit -Session $Session
                        $retryCount++
                    }
                    else {
                        throw $_
                    }
                }
            }
            
            if (-not $requestSuccessful) {
                throw "Failed after 3 retry attempts due to rate limiting"
            }

            

            $Response.Content | ConvertFrom-Json | ForEach-Object { $_ }

            $LinkHeader = $null
            if($Response.Headers['Link']) {
                $Links = $Response.Headers['Link'].Split(',')
                foreach($Link in $Links) {
                    if($Link.EndsWith('rel="next"')) {
                        $LinkHeader = $Link.Split(';')[0].Trim() -replace '[<>]',''
                        break
                    }
                }
            }

        } while($LinkHeader)
    } catch {
        Write-Error $_
    }
} 

function Invoke-GitHubGraphQL
{
    param(
        [Parameter(Mandatory=$true)]
        [PSTypeName('GitHound.Session')]
        $Session,
        [Parameter()]
        [string]
        $Uri = "https://api.github.com/graphql",

        [Parameter()]
        [hashtable]
        $Headers,

        [Parameter()]
        [string]
        $Query,

        [Parameter()]
        [hashtable]
        $Variables
    )

    $Body = @{
        query = $Query
        variables = $Variables
    } | ConvertTo-Json -Depth 100 -Compress

    $fparams = @{
        Uri = $Uri
        Method = 'Post'
        Headers = $Headers
        Body = $Body
    }
    $requestSuccessful = $false
    $retryCount = 0
    $maxRetries = 5

    while (-not $requestSuccessful -and $retryCount -lt $maxRetries) {
        try {
            $result = Invoke-RestMethod @fparams
            $requestSuccessful = $true
        }
        catch {
            $isRateLimit = $false
            $isRetryable = $false
            $errorString = "$($_.Exception.Message) $($_.ErrorDetails)"

            try {
                $httpException = $_.ErrorDetails | ConvertFrom-Json
                if (($httpException.status -eq "403" -and $httpException.message -match "rate limit") -or $httpException.status -eq "429") {
                    $isRateLimit = $true
                }
                if ($httpException.message -match "couldn.t respond.*in time" -or $httpException.message -match "timeout") {
                    $isRetryable = $true
                }
            }
            catch {
                # ErrorDetails was not valid JSON — check the raw error string
                if ($errorString -match "rate limit" -or $errorString -match "abuse" -or $errorString -match "secondary" -or $errorString -match "429") {
                    $isRateLimit = $true
                }
            }

            # Catch server errors (502, 503), timeouts, and gateway errors as retryable
            if (-not $isRateLimit -and -not $isRetryable) {
                if ($errorString -match "502" -or $errorString -match "503" -or $errorString -match "Bad Gateway" -or $errorString -match "couldn.t respond.*in time" -or $errorString -match "timeout") {
                    $isRetryable = $true
                }
            }

            if ($isRateLimit) {
                Write-Warning "Rate limit hit when doing GraphQL call. Retry $($retryCount + 1)/$maxRetries"
                Write-Debug $_
                Wait-GithubGraphQlRateLimit -Session $Session
                $retryCount++
            }
            elseif ($isRetryable) {
                $sleepSeconds = 5 * [Math]::Pow(2, $retryCount)  # Exponential backoff: 5, 10, 20, 40...
                Write-Warning "GitHub server error on GraphQL query. Retry $($retryCount + 1)/$maxRetries after ${sleepSeconds}s..."
                Start-Sleep -Seconds $sleepSeconds
                $retryCount++
            }
            else {
                throw $_
            }
        }
    }

    if (-not $requestSuccessful) {
        throw "Failed after $maxRetries retry attempts due to server errors or rate limiting"
    }

    return $result
}

function Get-RateLimitInformation
{
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )
    $rateLimitInfo = Invoke-GithubRestMethod -Session $Session -Path "rate_limit"
    return $rateLimitInfo.resources
    
}

function Wait-GithubRateLimitReached {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSObject]
        $githubRateLimitInfo

    )

    $resetTime = $githubRateLimitInfo.reset
    $timeNow = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    $timeToSleep = $resetTime - $timeNow
    if ($githubRateLimitInfo.remaining -eq 0 -and $timeToSleep -gt 0)
    {

        Write-Host "Reached rate limit. Sleeping for $($timeToSleep) seconds. Tokens reset at unix time $($resetTime)"
        Start-Sleep -Seconds $timeToSleep
    }
}

function Wait-GithubRestRateLimit {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )
    
    Wait-GithubRateLimitReached -githubRateLimitInfo (Get-RateLimitInformation -Session $Session).core
    
}

function Wait-GithubGraphQlRateLimit {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )
    
     Wait-GithubRateLimitReached -githubRateLimitInfo (Get-RateLimitInformation -Session $Session).graphql

}

function Git-HoundRateLimit
{
    <#
    .SYNOPSIS
        Displays the current GitHub API rate limit status for REST and GraphQL.

    .DESCRIPTION
        Queries the GitHub rate limit endpoint and displays a formatted summary showing
        remaining requests, total limit, used count, and reset time for both the REST (core)
        and GraphQL APIs.

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .EXAMPLE
        Git-HoundRateLimit -Session $Session
    #>
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    $info = Get-RateLimitInformation -Session $Session

    $results = @()

    foreach ($entry in @(
        @{ Name = "REST (core)"; Data = $info.core },
        @{ Name = "GraphQL";     Data = $info.graphql }
    )) {
        $resetUtc = ([DateTimeOffset]::FromUnixTimeSeconds($entry.Data.reset)).DateTime
        $resetLocal = ([DateTimeOffset]::FromUnixTimeSeconds($entry.Data.reset)).LocalDateTime
        $timeUntilReset = $resetLocal - (Get-Date)

        $results += [PSCustomObject]@{
            API             = $entry.Name
            Remaining       = $entry.Data.remaining
            Limit           = $entry.Data.limit
            Used            = $entry.Data.used
            "Resets In"     = "{0}m {1}s" -f [math]::Floor($timeUntilReset.TotalMinutes), $timeUntilReset.Seconds
            "Reset Time"    = $resetLocal.ToString("HH:mm:ss")
        }
    }

    $results | Format-Table -AutoSize
}

function New-GitHoundNode
{
    <#
    .SYNOPSIS
        Creates a new GitHound node object.

    .DESCRIPTION
        This function constructs a GitHound node object with specified properties, including the node's identifier, kinds, and additional properties.

    .PARAMETER Id
        The unique identifier for the node.
    
    .PARAMETER Kind
        The type(s) of the node.

    .PARAMETER Properties
        A hashtable of additional properties to associate with the node.

    .EXAMPLE
        $node = New-GitHoundNode -Id 'node123' -Kind @('GH_User', 'GH_Admin') -Properties @{ name = 'John Doe'; email = 'john.doe@example.com' }

        This example creates a new node with the identifier 'node123', of kinds 'GH_User' and 'GH_Admin', and includes additional properties for name and email.
    #>

    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [String]
        $Id,

        [Parameter(Position = 1, Mandatory = $true)]
        [String[]]
        $Kind,

        [Parameter(Position = 2, Mandatory = $true)]
        [PSObject]
        $Properties
    )

    $props = [pscustomobject]@{
        id = $Id
        kinds = @($Kind)
        properties = $Properties
    }

    Write-Output $props
}

function New-GitHoundEdge
{
    <#
    .SYNOPSIS
        Creates a new GitHound edge object.

    .DESCRIPTION
        This function constructs a GitHound edge object with specified properties, including the kind of edge, start and end nodes, and any additional properties.

    .PARAMETER Kind
        The type of edge to create.

    .PARAMETER StartId
        The identifier of the start node.

    .PARAMETER EndId
        The identifier of the end node.

    .PARAMETER StartKind
        (Optional) The kind of the start node.

    .PARAMETER StartMatchBy
        (Optional) The method to match the start node, either by 'id' or 'name'. Default is 'id'.

    .PARAMETER EndKind
        (Optional) The kind of the end node.

    .PARAMETER EndMatchBy
        (Optional) The method to match the end node, either by 'id' or 'name'. Default is 'id'.

    .PARAMETER Properties
        (Optional) A hashtable of additional properties to associate with the edge.

    .EXAMPLE

        $edge = New-GitHoundEdge -Kind 'GH_Owns' -StartId 'user123' -EndId 'repo456' -StartKind 'GH_User' -EndKind 'GH_Repository' -Properties @{ traversable = $true }

        This example creates a new edge of kind 'GH_Owns' from a user node to a repository node with additional properties.
    #>
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [String]
        $Kind,

        [Parameter(Position = 1, Mandatory = $true)]
        [PSObject]
        $StartId,

        [Parameter(Position = 2, Mandatory = $true)]
        [PSObject]
        $EndId,

        [Parameter(Mandatory = $false)]
        [String]
        $StartKind,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('id', 'name')]
        [String]
        $StartMatchBy = 'id',

        [Parameter(Mandatory = $false)]
        [String]
        $EndKind,

        [Parameter(Mandatory = $false)]
        [ValidateSet('id', 'name')]
        [String]
        $EndMatchBy = 'id',

        [Parameter(Mandatory = $false)]
        [Hashtable]
        $Properties = @{}
    )

    $edge = [pscustomobject]@{
        kind = $Kind
        start = @{
            value = $StartId
        }
        end = @{
            value = $EndId
        }
        properties = $Properties
    }

    if($PSBoundParameters.ContainsKey('StartKind')) 
    {
        $edge.start.Add('kind', $StartKind)
    }
    if($PSBoundParameters.ContainsKey('StartMatchBy')) 
    {
        $edge.start.Add('match_by', $StartMatchBy)
    }
    if($PSBoundParameters.ContainsKey('EndKind'))
    {
        $edge.end.Add('kind', $EndKind)
    }
    if($PSBoundParameters.ContainsKey('EndMatchBy')) 
    {
        $edge.end.Add('match_by', $EndMatchBy)
    }

    Write-Output $edge
}

function Normalize-Null
{
    <#
    .SYNOPSIS
        Normalizes null values to empty strings.

    .DESCRIPTION
        This function checks if the provided value is null. If it is, it returns an empty string; otherwise, it returns the original value.

    .PARAMETER Value
        The value to be normalized.

    .EXAMPLE
        $normalizedValue = Normalize-Null $someValue

        This example normalizes the variable $someValue, converting it to an empty string if it is null.
    #>
    param(
        $Value
    )
    
    if ($null -eq $Value) 
    {
        return ""
    }
    else 
    {
       return $Value
    }
    
    
}

function Import-GitHoundStepOutput
{
    <#
    .SYNOPSIS
        Imports a GitHound per-function checkpoint file from disk.

    .DESCRIPTION
        Reads a JSON file written by Export-GitHoundStepOutput and returns a PSCustomObject
        with Nodes and Edges ArrayLists, matching the shape returned by collection functions.
        Returns $null if the file does not exist or is corrupt/invalid.

    .PARAMETER FilePath
        The path to the JSON file to import.

    .EXAMPLE
        $org = Import-GitHoundStepOutput -FilePath "./githound_Organization_abc123.json"
    #>
    Param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) { return $null }

    try {
        $data = Get-Content $FilePath -Raw | ConvertFrom-Json
        if (-not $data.graph) {
            Write-Warning "Checkpoint file $FilePath has invalid format (missing graph). Will re-collect."
            return $null
        }
    }
    catch {
        Write-Warning "Checkpoint file $FilePath is corrupted. Will re-collect."
        Remove-Item $FilePath -Force -ErrorAction SilentlyContinue
        return $null
    }

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList
    if ($data.graph.nodes) { $null = $nodes.AddRange(@($data.graph.nodes)) }
    if ($data.graph.edges) { $null = $edges.AddRange(@($data.graph.edges)) }

    return [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }
}

function Export-GitHoundStepOutput
{
    <#
    .SYNOPSIS
        Exports a GitHound collection step result to a JSON file.

    .DESCRIPTION
        Writes a collection function's output (Nodes and Edges) to a JSON file in the standard
        GitHound format. Filters out null entries that may have been introduced by thread-safety
        issues or API errors.

    .PARAMETER StepResult
        A PSCustomObject with Nodes and Edges properties (as returned by collection functions).

    .PARAMETER FilePath
        The path to write the JSON file to.

    .EXAMPLE
        Export-GitHoundStepOutput -StepResult $org -FilePath "./githound_Organization_abc123.json"
    #>
    Param(
        [Parameter(Mandatory)]
        [PSCustomObject]$StepResult,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = @($StepResult.Nodes | Where-Object { $_ -ne $null })
            edges = @($StepResult.Edges | Where-Object { $_ -ne $null })
        }
    }

    $payload | ConvertTo-Json -Depth 10 | Out-File -FilePath $FilePath
}

function ConvertTo-PascalCase
{
    <#
    .SYNOPSIS
        Converts a given string to PascalCase format.

    .DESCRIPTION
        Author: Jared Atkinson (@cobbler) at SpecterOps

        This function takes a string input and converts it to PascalCase format, where the first letter of each word is capitalized and all words are concatenated without spaces or delimiters.

        This function is used in 1PassHound to standardize permission names when creating edges in the graph structure.

    .PARAMETER String
        The input string to be converted to PascalCase.

    .EXAMPLE
        $pascalCaseString = ConvertTo-PascalCase -String "example_string-to_convert"

        This example converts the input string "example_string-to_convert" to "ExampleStringToConvert".
    #>
    param (
        [string]$String
    )

    if ([string]::IsNullOrEmpty($String)) {
        return $String
    }

    # Replace common delimiters with spaces and convert to lowercase to handle various input formats
    $cleanedString = $String -replace '[-_]', ' ' | ForEach-Object { $_.ToLower() }

    # Use TextInfo.ToTitleCase to capitalize the first letter of each word
    # Then remove spaces to achieve PascalCase
    $pascalCaseString = (Get-Culture).TextInfo.ToTitleCase($cleanedString).Replace(' ', '')

    return $pascalCaseString
}

function Git-HoundOrganization
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Organizations and Organization Roles.

    .DESCRIPTION
        This function retrieves organization details for the organization specified in the GitHound.Session object. It creates a node representing the organization,
        as well as nodes and edges for the default organization roles (owners, members) and any custom organization roles.

        API Reference:
        - Get an organization: https://docs.github.com/en/rest/orgs/orgs?apiVersion=2022-11-28#get-an-organization
        - Get GitHub Actions permissions for an organization: https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#get-github-actions-permissions-for-an-organization
        - Get all organization roles for an organization: https://docs.github.com/en/rest/orgs/organization-roles?apiVersion=2022-11-28#get-all-organization-roles-for-an-organization
        - List teams that are assigned to an organization role: https://docs.github.com/en/rest/orgs/organization-roles?apiVersion=2022-11-28#list-teams-that-are-assigned-to-an-organization-role
        - List users that are assigned to an organization role: https://docs.github.com/en/rest/orgs/organization-roles?apiVersion=2022-11-28#list-users-that-are-assigned-to-an-organization-role

        Fine Grained Permissions Reference:
        - "Administration" organization permissions (read)
        - "Custom organization roles" organization permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .EXAMPLE
        $organization = New-GithubSession -OrganizationName "my-org" | Git-HoundOrganization
    #>

    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $org = Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Session.OrganizationName)"
    $actions = Invoke-GithubRestMethod -Session $session -Path "orgs/$($Session.OrganizationName)/actions/permissions"

    $properties = [pscustomobject]@{
        # Common Properties
        id                                                           = Normalize-Null $org.id
        node_id                                                      = Normalize-Null $org.node_id
        name                                                         = Normalize-Null $org.login
        # Relational Properties
        # Node Specific Properties
        login                                                        = Normalize-Null $org.login
        description                                                  = Normalize-Null $org.description
        org_name                                                     = Normalize-Null $org.name
        company                                                      = Normalize-Null $org.company
        blog                                                         = Normalize-Null $org.blog
        location                                                     = Normalize-Null $org.location
        email                                                        = Normalize-Null $org.email
        is_verified                                                  = Normalize-Null $org.is_verified
        has_organization_projects                                    = Normalize-Null $org.has_organization_projects
        has_repository_projects                                      = Normalize-Null $org.has_repository_projects
        public_repos                                                 = Normalize-Null $org.public_repos
        public_gists                                                 = Normalize-Null $org.public_gists
        followers                                                    = Normalize-Null $org.followers
        following                                                    = Normalize-Null $org.following
        html_url                                                     = Normalize-Null $org.html_url
        created_at                                                   = Normalize-Null $org.created_at
        updated_at                                                   = Normalize-Null $org.updated_at
        type                                                         = Normalize-Null $org.type
        total_private_repos                                          = Normalize-Null $org.total_private_repos
        owned_private_repos                                          = Normalize-Null $org.owned_private_repos
        private_gists                                                = Normalize-Null $org.private_gists
        collaborators                                                = Normalize-Null $org.collaborators
        default_repository_permission                                = Normalize-Null $org.default_repository_permission
        members_can_create_repositories                              = Normalize-Null $org.members_can_create_repositories
        two_factor_requirement_enabled                               = Normalize-Null $org.two_factor_requirement_enabled
        members_can_create_public_repositories                       = Normalize-Null $org.members_can_create_public_repositories
        members_can_create_private_repositories                      = Normalize-Null $org.members_can_create_private_repositories
        members_can_create_internal_repositories                     = Normalize-Null $org.members_can_create_internal_repositories
        members_can_create_pages                                     = Normalize-Null $org.members_can_create_pages
        members_can_fork_private_repositories                        = Normalize-Null $org.members_can_fork_private_repositories
        web_commit_signoff_required                                  = Normalize-Null $org.web_commit_signoff_required
        deploy_keys_enabled_for_repositories                         = Normalize-Null $org.deploy_keys_enabled_for_repositories
        members_can_delete_repositories                              = Normalize-Null $org.members_can_delete_repositories
        members_can_change_repo_visibility                           = Normalize-Null $org.members_can_change_repo_visibility
        members_can_invite_outside_collaborators                     = Normalize-Null $org.members_can_invite_outside_collaborators
        members_can_delete_issues                                    = Normalize-Null $org.members_can_delete_issues
        display_commenter_full_name_setting_enabled                  = Normalize-Null $org.display_commenter_full_name_setting_enabled
        readers_can_create_discussions                               = Normalize-Null $org.readers_can_create_discussions
        members_can_create_teams                                     = Normalize-Null $org.members_can_create_teams
        members_can_view_dependency_insights                         = Normalize-Null $org.members_can_view_dependency_insights
        default_repository_branch                                    = Normalize-Null $org.default_repository_branch
        members_can_create_public_pages                              = Normalize-Null $org.members_can_create_public_pages
        members_can_create_private_pages                             = Normalize-Null $org.members_can_create_private_pages
        advanced_security_enabled_for_new_repositories               = Normalize-Null $org.advanced_security_enabled_for_new_repositories
        dependabot_alerts_enabled_for_new_repositories               = Normalize-Null $org.dependabot_alerts_enabled_for_new_repositories
        dependabot_security_updates_enabled_for_new_repositories     = Normalize-Null $org.dependabot_security_updates_enabled_for_new_repositories
        dependency_graph_enabled_for_new_repositories                = Normalize-Null $org.dependency_graph_enabled_for_new_repositories
        secret_scanning_enabled_for_new_repositories                 = Normalize-Null $org.secret_scanning_enabled_for_new_repositories
        secret_scanning_push_protection_enabled_for_new_repositories = Normalize-Null $org.secret_scanning_push_protection_enabled_for_new_repositories
        secret_scanning_push_protection_custom_link_enabled          = Normalize-Null $org.secret_scanning_push_protection_custom_link_enabled
        secret_scanning_push_protection_custom_link                  = Normalize-Null $org.secret_scanning_push_protection_custom_link_enabled
        secret_scanning_validity_checks_enabled                      = Normalize-Null $org.secret_scanning_validity_checks_enabled
        actions_enabled_repositories                                 = Normalize-Null $actions.enabled_repositories
        actions_allowed_actions                                      = Normalize-Null $actions.allowed_actions
        actions_sha_pinning_required                                 = Normalize-Null $actions.sha_pinning_required
        # Accordion Panel Queries
        query_users                                    = "MATCH (n:GH_User {environment_id:'$($org.node_id)}) RETURN n"
        query_teams                                    = "MATCH (n:GH_Team {environment_id:'$($org.node_id)}) RETURN n"
        query_repositories                             = "MATCH (n:GH_Repository {environment_id:'$($org.node_id)}) RETURN n"
        query_personal_access_tokens                   = "MATCH p=(:GH_Organization {node_id: '$($org.node_id)'})-[:GH_Contains]->(token) WHERE token:GH_PersonalAccessToken OR token:GH_PersonalAccessTokenRequest RETURN p"
    }

    $orgNode = New-GitHoundNode -Id $org.node_id -Kind 'GH_Organization' -Properties $properties
    $null = $nodes.Add($orgNode)

    # --- Organization Role Nodes and Edges ---
    # These were previously created in Git-HoundOrganizationRole but are moved here
    # because they are static properties of the organization, not per-user assignments.

    $orgAllRepoReadId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($orgNode.id)_all_repo_read"))
    $orgAllRepoTriageId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($orgNode.id)_all_repo_triage"))
    $orgAllRepoWriteId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($orgNode.id)_all_repo_write"))
    $orgAllRepoMaintainId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($orgNode.id)_all_repo_maintain"))
    $orgAllRepoAdminId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($orgNode.id)_all_repo_admin"))

    # Custom Organization Roles
    # In general parallelizing this is a bad idea, because most organizations have a small number of custom roles
    foreach($customrole in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($org.login)/organization-roles").roles)
    {
        $customRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($orgNode.id)_$($customrole.name)"))
        $customRoleProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $customRoleId
            name                   = Normalize-Null "$($org.login)/$($customrole.name)"
            # Relational Properties
            environment_name      = Normalize-Null $org.login
            environment_id        = Normalize-Null $org.node_id
            # Node Specific Properties
            short_name             = Normalize-Null $customrole.name
            type                   = Normalize-Null 'custom'
            # Accordion Panel Queries
            query_explicit_members = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_OrgRole {id:'$($customRoleId)'}) RETURN p"
            query_unrolled_members = "MATCH p=(:GH_User)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_OrgRole {id:'$($customRoleId)'}) RETURN p"
            query_repositories     = "MATCH p=(:GH_OrgRole {id:'$($customRoleId)'})-[*]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $customRoleId -Kind 'GH_OrgRole', 'GH_Role' -Properties $customRoleProps))

        foreach($team in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($org.login)/organization-roles/$($customRole.id)/teams"))
        {
            $null = $edges.Add((New-GitHoundEdge -Kind GH_HasRole -StartId $team.node_id -EndId $customRoleId -Properties @{traversable=$true}))
        }

        foreach($user in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($org.login)/organization-roles/$($customRole.id)/users"))
        {
            $null = $edges.Add((New-GitHoundEdge -Kind GH_HasRole -StartId $user.node_id -EndId $customRoleId -Properties @{traversable=$true}))
        }

        if($null -ne $customrole.base_role)
        {
            switch($customrole.base_role)
            {
                'read' {$baseId = $orgAllRepoReadId}
                'triage' {$baseId = $orgAllRepoTriageId}
                'write' {$baseId = $orgAllRepoWriteId}
                'maintain' {$baseId = $orgAllRepoMaintainId}
                'admin' {$baseId = $orgAllRepoAdminId}
            }

            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $customRoleId -EndId $baseId -Properties @{traversable=$true}))
        }

        # Need to add support for custom permissions here
        foreach($premission in $customrole.permissions)
        {
            switch($premission)
            {
                #'delete_alerts_code_scanning' {$kind = 'GH_DeleteAlertCodeScanning'}
                #'edit_org_custom_properties_values' {$kind = 'GH_EditOrgCustomPropertiesValues'}
                #'manage_org_custom_properties_definitions' {$kind = 'GH_ManageOrgCustomPropertiesDefinitions'}
                #'manage_organization_oauth_application_policy' {$kind = 'GH_ManageOrganizationOAuthApplicationPolicy'}
                #'manage_organization_ref_rules' {$kind = 'GH_ManageOrganizationRefRules'}
                'manage_organization_webhooks' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageOrganizationWebhooks' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'org_bypass_code_scanning_dismissal_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_OrgBypassCodeScanningDismissalRequests' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'org_bypass_secret_scanning_closure_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_OrgBypassSecretScanningClosureRequests' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'org_review_and_manage_secret_scanning_bypass_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_OrgReviewAndManageSecretScanningBypassRequests' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'org_review_and_manage_secret_scanning_closure_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_OrgReviewAndManageSecretScanningClosureRequests' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                #'read_audit_logs' {$kind = 'GH_ReadAuditLogs'}
                #'read_code_quality' {$kind = 'GH_ReadCodeQuality'}
                #'read_code_scanning' {$kind = 'GH_ReadCodeScanning'}
                'read_organization_actions_usage_metrics' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadOrganizationActionsUsageMetrics' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'read_organization_custom_org_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadOrganizationCustomOrgRole' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'read_organization_custom_repo_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadOrganizationCustomRepoRole' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                #'resolve_dependabot_alerts' {$kind = 'GH_ResolveDependabotAlerts'}
                'resolve_secret_scanning_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ResolveSecretScanningAlerts' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                #'review_org_code_scanning_dismissal_requests' {$kind = 'GH_ReviewOrgCodeScanningDismissalRequests'}
                #'view_dependabot_alerts' {$kind = 'GH_ViewDependabotAlerts'}
                #'view_org_code_scanning_dismissal_requests' {$kind = 'GH_ViewOrgCodeScanningDismissalRequests'}
                'view_secret_scanning_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewSecretScanningAlerts' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'write_organization_actions_secrets' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteOrganizationActionsSecrets' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'write_organization_actions_settings' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteOrganizationActionsSettings' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                #'write_organization_actions_variables' {$kind = 'GH_WriteOrganizationActionsVariables'}
                #'write_code_quality' {$kind = 'GH_WriteCodeQuality'}
                #'write_code_scanning' {$kind = 'GH_WriteCodeScanning'}
                'write_organization_custom_org_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteOrganizationCustomOrgRole' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'write_organization_custom_repo_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteOrganizationCustomRepoRole' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'write_organization_network_configurations' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteOrganizationNetworkConfigurations' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                #'write_organization_runner_custom_images' {$kind = 'GH_WriteOrganizationRunnerCustomImages'}
                #'write_organization_runners_and_runner_groups' {$kind = 'GH_WriteOrganizationRunnersAndRunnerGroups'}
            }
        }
    }

    # Default Organization Role: Owners
    $orgOwnersId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($orgNode.id)_owners"))
    $ownersProps = [pscustomobject]@{
        # Common Properties
        id                     = Normalize-Null $orgOwnersId
        name                   = Normalize-Null "$($org.login)/owners"
        # Relational Properties
        environment_name      = Normalize-Null $org.login
        environment_id        = Normalize-Null $org.node_id
        # Node Specific Properties
        short_name             = Normalize-Null 'owners'
        type                   = Normalize-Null 'default'
        # Accordion Panel Queries
        query_explicit_members = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_OrgRole {id:'$($orgOwnersId)'}) RETURN p"
        query_unrolled_members = "MATCH p=(:GH_User)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_OrgRole {id:'$($orgOwnersId)'}) RETURN p"
        query_repositories     = "MATCH p=(:GH_OrgRole {id:'$($orgOwnersId)'})-[*]->(:GH_Repository) RETURN p"
    }
    $null = $nodes.Add((New-GitHoundNode -Id $orgOwnersId -Kind 'GH_OrgRole', 'GH_Role' -Properties $ownersProps))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateRepository' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_InviteMember' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddCollaborator' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateTeam' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_TransferRepository' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgOwnersId -EndId $orgAllRepoAdminId -Properties @{traversable=$true}))

    # Default Organization Role: Members
    $orgMembersId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($orgNode.id)_members"))
    $membersProps = [pscustomobject]@{
        # Common Properties
        id                = Normalize-Null $orgMembersId
        name              = Normalize-Null "$($org.login)/members"
        # Relational Properties
        environment_name = Normalize-Null $org.login
        environment_id   = Normalize-Null $org.node_id
        # Node Specific Properties
        short_name        = Normalize-Null 'members'
        type              = Normalize-Null 'default'
        # Accordion Panel Queries
        query_explicit_members = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_OrgRole {id:'$($orgMembersId)'}) RETURN p"
        query_unrolled_members = "MATCH p=(:GH_User)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_OrgRole {id:'$($orgMembersId)'}) RETURN p"
        query_repositories     = "MATCH p=(:GH_OrgRole {id:'$($orgMembersId)'})-[*]->(:GH_Repository) RETURN p"
    }
    $null = $nodes.Add((New-GitHoundNode -Id $orgMembersId -Kind 'GH_OrgRole', 'GH_Role' -Properties $membersProps))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateRepository' -StartId $orgMembersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateTeam' -StartId $orgMembersId -EndId $orgNode.id -Properties @{traversable=$false}))

    if($org.default_repository_permission -ne 'none')
    {
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgMembersId -EndId ([Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($orgNode.id)_all_repo_$($org.default_repository_permission)"))) -Properties @{traversable=$true}))
    }

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Git-HoundTeam
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Teams, Team Roles, and Team Member assignments for an organization.

    .DESCRIPTION
        This function retrieves teams for each organization provided in the pipeline using the GitHub GraphQL API.
        It creates nodes representing teams, team role nodes (members/maintainers), and GH_HasRole edges linking
        users to their team roles — all in a single paginated GraphQL query.

        For teams with more than 100 immediate members, follow-up GraphQL queries are made to paginate through
        the remaining members.

        API Reference:
        - GitHub GraphQL API: Organization.teams connection
        - GitHub GraphQL API: Team.members connection (membership: IMMEDIATE)

        Fine Grained Permissions Reference:
        - "Members" organization permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Organization
        A GitHound.Organization object representing the organization for which teams are to be fetched.

    .EXAMPLE
        $teams = Git-HoundOrganization | Git-HoundTeam
    #>

    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $Organization
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    # Primary query: fetches teams with nested immediate members and their roles
    $TeamsQuery = @'
query Teams($login: String!, $count: Int = 100, $after: String = null) {
    organization(login: $login) {
        teams(first: $count, after: $after) {
            nodes {
                id
                databaseId
                name
                slug
                description
                privacy
                parentTeam {
                    id
                }
                members(first: 100, membership: IMMEDIATE) {
                    edges {
                        role
                        node {
                            id
                            login
                        }
                    }
                    pageInfo {
                        endCursor
                        hasNextPage
                    }
                }
            }
            pageInfo {
                endCursor
                hasNextPage
            }
        }
    }
}
'@

    # Follow-up query for teams with >100 immediate members
    $TeamMembersOverflowQuery = @'
query TeamMembersOverflow($login: String!, $slug: String!, $count: Int = 100, $after: String!) {
    organization(login: $login) {
        team(slug: $slug) {
            members(first: $count, after: $after, membership: IMMEDIATE) {
                edges {
                    role
                    node {
                        id
                        login
                    }
                }
                pageInfo {
                    endCursor
                    hasNextPage
                }
            }
        }
    }
}
'@

    $TeamsVariables = @{
        login = $Organization.properties.login
        count = 100
        after = $null
    }

    # Track teams that need follow-up member pagination
    $overflowTeams = New-Object System.Collections.ArrayList

    do {
        $result = Invoke-GitHubGraphQL -Headers $Session.Headers -Query $TeamsQuery -Variables $TeamsVariables -Session $Session

        foreach($team in $result.data.organization.teams.nodes)
        {
            # --- Team Node ---
            $properties = [pscustomobject]@{
                # Common Properties
                id                = Normalize-Null $team.databaseId
                node_id           = Normalize-Null $team.id
                name              = Normalize-Null $team.name
                # Relational Properties
                environment_name = Normalize-Null $Organization.properties.login
                environment_id   = Normalize-Null $Organization.properties.node_id
                # Node Specific Properties
                slug              = Normalize-Null $team.slug
                description       = Normalize-Null $team.description
                privacy           = Normalize-Null $team.privacy
                # Accordion Panel Queries
                query_first_degree_members     = "MATCH p=(:GH_User)-[:GH_HasRole]->(t:GH_TeamRole)-[:GH_MemberOf]->(:GH_Team {node_id:'$($team.id)'}) RETURN p"
                query_unrolled_members         = "MATCH p=(teamrole:GH_TeamRole)-[:GH_MemberOf*1..]->(:GH_Team {node_id:'$($team.id)'}) MATCH p1 = (teamrole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
                query_first_degree_maintainers = "MATCH p=(:GH_User)-[:GH_HasRole]->(t:GH_TeamRole {short_name: 'maintainers'})-[:GH_MemberOf]->(:GH_Team {node_id:'$($team.id)'}) RETURN p"
                query_unrolled_maintainers     = "MATCH p=(teamrole:GH_TeamRole {short_name: 'maintainers'})-[:GH_MemberOf*1..]->(:GH_Team {node_id:'$($team.id)'}) MATCH p1 = (teamrole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
                query_repositories             = "MATCH p=(:GH_Team {node_id:'$($team.id)'})-[:GH_HasRole]->(:GH_RepoRole)-[]->(:GH_Repository) RETURN p"
                query_child_teams              = "MATCH p=(:GH_Team)-[:GH_MemberOf*1..]->(:GH_Team {node_id:'$($team.id)'}) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $team.id -Kind 'GH_Team' -Properties $properties))

            # Parent team edge
            if($null -ne $team.parentTeam)
            {
                $null = $edges.Add((New-GitHoundEdge -Kind GH_MemberOf -StartId $team.id -EndId $team.parentTeam.id -Properties @{ traversable = $true }))
            }

            # --- Team Role Nodes (members and maintainers) ---
            $memberId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($team.id)_members"))
            $memberProps = [pscustomobject]@{
                # Common Properties
                id                 = Normalize-Null $memberId
                name               = Normalize-Null "$($Organization.properties.login)/$($team.slug)/members"
                # Relational Properties
                environment_name  = Normalize-Null $Organization.properties.login
                environment_id    = Normalize-Null $Organization.properties.node_id
                team_name          = Normalize-Null $team.name
                team_id            = Normalize-Null $team.id
                # Node Specific Properties
                short_name         = Normalize-Null 'members'
                type               = Normalize-Null 'team'
                # Accordion Panel Queries
                query_team         = "MATCH p=(:GH_TeamRole {id:'$($memberId)'})-[:GH_MemberOf]->(:GH_Team) RETURN p "
                query_members      = "MATCH p=(:GH_User)-[GH_HasRole]->(:GH_TeamRole {id:'$($memberId)'}) RETURN p"
                query_repositories = "MATCH p=(:GH_TeamRole {id:'$($memberId)'})-[:GH_MemberOf]->(:GH_Team)-[:GH_HasRole|GH_HasBaseRole*1..]->(:GH_RepoRole)-[]->(:GH_Repository) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $memberId -Kind 'GH_TeamRole','GH_Role' -Properties $memberProps))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MemberOf' -StartId $memberId -EndId $team.id -Properties @{traversable=$true}))

            $maintainerId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($team.id)_maintainers"))
            $maintainerProps = [pscustomobject]@{
                # Common Properties
                id                 = Normalize-Null $maintainerId
                name               = Normalize-Null "$($Organization.properties.login)/$($team.slug)/maintainers"
                # Relational Properties
                environment_name  = Normalize-Null $Organization.properties.login
                environment_id    = Normalize-Null $Organization.properties.node_id
                team_name          = Normalize-Null $team.name
                team_id            = Normalize-Null $team.id
                # Node Specific Properties
                short_name         = Normalize-Null 'maintainers'
                type               = Normalize-Null 'team'
                # Accordion Panel Queries
                query_team         = "MATCH p=(:GH_TeamRole {id:'$($maintainerId)'})-[:GH_MemberOf]->(:GH_Team) RETURN p "
                query_members      = "MATCH p=(:GH_User)-[GH_HasRole]->(:GH_TeamRole {id:'$($maintainerId)'}) RETURN p"
                query_repositories = "MATCH p=(:GH_TeamRole {id:'$($maintainerId)'})-[:GH_MemberOf]->(:GH_Team)-[:GH_HasRole|GH_HasBaseRole*1..]->(:GH_RepoRole)-[]->(:GH_Repository) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $maintainerId -Kind 'GH_TeamRole','GH_Role' -Properties $maintainerProps))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MemberOf' -StartId $maintainerId -EndId $team.id -Properties @{traversable=$true}))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddMember' -StartId $maintainerId -EndId $team.id -Properties @{traversable=$true}))

            # --- Member Role Assignments (from first page of members) ---
            foreach($memberEdge in $team.members.edges)
            {
                switch($memberEdge.role)
                {
                    'MEMBER' { $destId = $memberId }
                    'MAINTAINER' { $destId = $maintainerId }
                }
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasRole' -StartId $memberEdge.node.id -EndId $destId -Properties @{traversable=$true}))
            }

            # Track teams that need follow-up pagination for remaining members
            if($team.members.pageInfo.hasNextPage)
            {
                $null = $overflowTeams.Add([PSCustomObject]@{
                    slug          = $team.slug
                    teamId        = $team.id
                    memberId      = $memberId
                    maintainerId  = $maintainerId
                    endCursor     = $team.members.pageInfo.endCursor
                })
            }
        }

        $TeamsVariables['after'] = $result.data.organization.teams.pageInfo.endCursor
    }
    while($result.data.organization.teams.pageInfo.hasNextPage)

    # Phase 2: Paginate remaining members for overflow teams
    foreach($overflow in $overflowTeams)
    {
        $overflowVars = @{
            login = $Organization.properties.login
            slug  = $overflow.slug
            count = 100
            after = $overflow.endCursor
        }

        do {
            $overflowResult = Invoke-GitHubGraphQL -Headers $Session.Headers -Query $TeamMembersOverflowQuery -Variables $overflowVars -Session $Session

            foreach($memberEdge in $overflowResult.data.organization.team.members.edges)
            {
                switch($memberEdge.role)
                {
                    'MEMBER' { $destId = $overflow.memberId }
                    'MAINTAINER' { $destId = $overflow.maintainerId }
                }
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasRole' -StartId $memberEdge.node.id -EndId $destId -Properties @{traversable=$true}))
            }

            $overflowVars['after'] = $overflowResult.data.organization.team.members.pageInfo.endCursor
        }
        while($overflowResult.data.organization.team.members.pageInfo.hasNextPage)
    }

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Git-HoundUser
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Users for an organization, including their organization role assignments.

    .DESCRIPTION
        This function retrieves users for each organization provided in the pipeline using the GitHub GraphQL API's
        membersWithRole connection. This returns user details (name, email, company) and the organization role
        (ADMIN or MEMBER) in a single batched query, avoiding per-user API calls.

        It creates GH_User nodes and GH_HasRole edges linking each user to their default organization role
        (owners or members).

        API Reference:
        - GitHub GraphQL API: Organization.membersWithRole connection

        Fine Grained Permissions Reference:
        - "Members" organization permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Organization
        A GitHound.Organization object representing the organization for which users are to be fetched.

    .EXAMPLE
        $users = Git-HoundOrganization | Git-HoundUser
    #>
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $Organization
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    # Compute the owners and members role IDs using the same formula as Git-HoundOrganization
    $orgOwnersId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_owners"))
    $orgMembersId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_members"))

    $Query = @'
query MembersWithRole($login: String!, $count: Int = 100, $after: String = null) {
    organization(login: $login) {
        membersWithRole(first: $count, after: $after) {
            edges {
                role
                node {
                    id
                    databaseId
                    login
                    name
                    email
                    company
                }
            }
            pageInfo {
                endCursor
                hasNextPage
            }
        }
    }
}
'@

    $Variables = @{
        login = $Organization.properties.login
        count = 100
        after = $null
    }

    do {
        $result = Invoke-GitHubGraphQL -Headers $Session.Headers -Query $Query -Variables $Variables -Session $Session

        foreach($edge in $result.data.organization.membersWithRole.edges)
        {
            $user = $edge.node

            $properties = @{
                # Common Properties
                id                  = Normalize-Null $user.databaseId
                node_id             = Normalize-Null $user.id
                name                = Normalize-Null $user.login
                # Relational Properties
                environment_name   = Normalize-Null $Organization.properties.login
                environment_id     = Normalize-Null $Organization.properties.node_id
                # Node Specific Properties
                login               = Normalize-Null $user.login
                full_name           = Normalize-Null $user.name
                company             = Normalize-Null $user.company
                email               = Normalize-Null $user.email
                # Accordion Panel Queries
                query_personal_access_tokens = "MATCH p=(:GH_User {node_id: '$($user.id)'})-[]->(token) WHERE token:GH_PersonalAccessToken OR token:GH_PersonalAccessTokenRequest RETURN p"
                query_roles                  = "MATCH p=(t:GH_User {node_id:'$($user.id)'})-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_Role) RETURN p"
                query_teams                  = "MATCH p=(:GH_User {node_id:'$($user.id)'})-[:GH_HasRole]->(t:GH_TeamRole)-[:GH_MemberOf*1..4]->(:GH_Team) RETURN p"
                query_repositories           = "MATCH p=(t:GH_User {node_id:'$($user.id)'})-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_ReadRepoContents|GH_WriteRepoContents|GH_WriteRepoPullRequests|GH_ManageWebhooks|GH_ManageDeployKeys|GH_PushProtectedBranch|GH_DeleteAlertsCodeScanning|GH_ViewSecretScanningAlerts|GH_RunOrgMigration|GH_BypassBranchProtection|GH_EditRepoProtections]->(:GH_Repository) RETURN p"
                query_branches               = "MATCH p=(:GH_User {node_id:'$($user.id)'})-[r]->(:GH_BranchProtectionRule)-[:GH_ProtectedBy]->(:GH_Branch) RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $user.id -Kind 'GH_User' -Properties $properties))

            # Create GH_HasRole edge to the appropriate default organization role
            switch($edge.role)
            {
                'ADMIN' { $destId = $orgOwnersId }
                'MEMBER' { $destId = $orgMembersId }
            }
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasRole' -StartId $user.id -EndId $destId -Properties @{traversable=$true}))
        }

        $Variables['after'] = $result.data.organization.membersWithRole.pageInfo.endCursor
    }
    while($result.data.organization.membersWithRole.pageInfo.hasNextPage)

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Git-HoundRepository
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Repositories, Repository Roles, and role assignments for an organization.

    .DESCRIPTION
        This function retrieves repositories for each organization provided in the pipeline. It creates nodes
        representing the repositories and their default and custom repository role nodes with permission edges.

        Role assignments (collaborator and team access) are handled separately by Git-HoundRepositoryRole.

        API Reference:
        - Get GitHub Actions permissions for an organization: https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#get-github-actions-permissions-for-an-organization
        - List selected repositories enabled for GitHub Actions in an organization: https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#list-github-actions-enabled-repositories-for-an-organization
        - List organization repositories: https://docs.github.com/en/rest/repos/repos?apiVersion=2022-11-28#list-organization-repositories
        - List custom repository roles in an organization: https://docs.github.com/en/enterprise-cloud@latest/rest/orgs/custom-roles?apiVersion=2022-11-28#list-custom-repository-roles-in-an-organization

        Fine Grained Permissions Reference:
        - "Administration" organization permissions (read)
        - "Custom repository roles" organization permissions (read)
        - "Metadata" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Organization
        A GitHound.Organization object representing the organization for which repositories are to be fetched.

    .EXAMPLE
        $repositories = Git-HoundOrganization | Git-HoundRepository
    #>

    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $Organization
    )

    # ConcurrentBag is thread-safe for parallel ForEach-Object blocks
    $nodes = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    $edges = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()

    # Pre-loop setup: Actions permissions
    $actions = Invoke-GithubRestMethod -Session $session -Path "orgs/$($Organization.Properties.login)/actions/permissions"

    $enabledRepos = $null
    if($actions.enabled_repositories -ne 'all')
    {
        $enabledRepos = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/actions/permissions/repositories").repositories.node_id
    }

    # Pre-loop setup: Custom repository roles and org-level all_repo_* IDs
    $customRepoRoles = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/custom-repository-roles").custom_roles

    $orgAllRepoReadId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_read"))
    $orgAllRepoTriageId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_triage"))
    $orgAllRepoWriteId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_write"))
    $orgAllRepoMaintainId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_maintain"))
    $orgAllRepoAdminId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_admin"))

    # Per-repo processing: create repo node, role nodes, and fetch collaborator/team assignments
    Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/repos" | ForEach-Object -Parallel {

        $nodes = $using:nodes
        $edges = $using:edges
        $Session = $using:Session
        $Organization = $using:Organization
        $actions = $using:actions
        $enabledRepos = $using:enabledRepos
        $customRepoRoles = $using:customRepoRoles
        $orgAllRepoReadId = $using:orgAllRepoReadId
        $orgAllRepoTriageId = $using:orgAllRepoTriageId
        $orgAllRepoWriteId = $using:orgAllRepoWriteId
        $orgAllRepoMaintainId = $using:orgAllRepoMaintainId
        $orgAllRepoAdminId = $using:orgAllRepoAdminId

        $functionBundle = $using:GitHoundFunctionBundle
        foreach($funcName in $functionBundle.Keys) {
            Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
        }
        $repo = $_

        # --- Repository Node ---
        if($actions.enabled_repositories -eq 'all')
        {
            $actionsEnabled = $true
        }
        else
        {
            $actionsEnabled = $enabledRepos -contains $repo.node_id
        }

        $properties = @{
            # Common Properties
            id                           = Normalize-Null $repo.id
            node_id                      = Normalize-Null $repo.node_id
            name                         = Normalize-Null $repo.name
            # Relational Properties
            environment_name            = Normalize-Null $Organization.properties.login
            environment_id              = Normalize-Null $Organization.properties.node_id
            owner_id                     = Normalize-Null $repo.owner.id
            owner_node_id                = Normalize-Null $repo.owner.node_id
            owner_name                   = Normalize-Null $repo.owner.login
            # Node Specific Properties
            full_name                    = Normalize-Null $repo.full_name
            private                      = Normalize-Null $repo.private
            html_url                     = Normalize-Null $repo.html_url
            description                  = Normalize-Null $description
            created_at                   = Normalize-Null $repo.created_at
            updated_at                   = Normalize-Null $repo.updated_at
            pushed_at                    = Normalize-Null $repo.pushed_at
            archived                     = Normalize-Null $repo.archived
            disabled                     = Normalize-Null $repo.disabled
            open_issues_count            = Normalize-Null $repo.open_issues_count
            allow_forking                = Normalize-Null $repo.allow_forking
            web_commit_signoff_required  = Normalize-Null $repo.web_commit_signoff_required
            visibility                   = Normalize-Null $repo.visibility
            forks                        = Normalize-Null $repo.forks
            open_issues                  = Normalize-Null $repo.open_issues
            watchers                     = Normalize-Null $repo.watchers
            default_branch               = Normalize-Null $repo.default_branch
            actions_enabled              = Normalize-Null $actionsEnabled
            secret_scanning              = Normalize-Null $repo.security_and_analysis.secret_scanning.status
            # Accordion Panel Queries
            query_branches               = "MATCH p=(:GH_Repository {node_id: '$($repo.node_id)'})-[:GH_HasBranch]->(:GH_Branch) RETURN p"
            query_protected_branches     = "MATCH p=(:GH_Repository {node_id: '$($repo.node_id)'})-[:GH_HasBranch]->(:GH_Branch)<-[:GH_ProtectedBy]-(:GH_BranchProtectionRule) RETURN p"
            query_roles                  = "MATCH p=(:GH_RepoRole)-[*1..]->(:GH_Repository {node_id: '$($repo.node_id)'}) RETURN p"
            query_teams                  = "MATCH p=(:GH_Team)-[:GH_MemberOf|GH_HasRole*1..]->(:GH_RepoRole)-[]->(:GH_Repository {node_id: '$($repo.node_id)'}) RETURN p"
            query_workflows              = "MATCH p=(:GH_Repository {node_id:'$($repo.node_id)'})-[:GH_HasWorkflow]->(w:GH_Workflow) RETURN p"
            query_environments           = "MATCH p=(:GH_Repository {node_id: '$($repo.node_id)'})-[:GH_HasEnvironment]->(:GH_Environment) RETURN p"
            query_secrets                = "MATCH p=(:GH_Repository {node_id:'$($repo.node_id)'})-[:GH_HasSecret]->(:GH_Secret) RETURN p"
            query_secret_scanning_alerts = "MATCH p=(:GH_Repository {node_id:'$($repo.node_id)'})-[:GH_HasSecretScanningAlert]->(:GH_SecretScanningAlert) RETURN p"
            query_explicit_readers       = "MATCH p=(role:GH_Role)-[:GH_HasBaseRole|GH_ReadRepoContents*1..]->(r:GH_Repository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
            query_unrolled_readers       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(r:GH_Repository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
            query_explicit_writers       = "MATCH p=(role:GH_Role)-[:GH_HasBaseRole|GH_WriteRepoContents|GH_WriteRepoPullRequests*1..]->(r:GH_Repository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
            query_unrolled_writers       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_WriteRepoContents|GH_WriteRepoPullRequests*1..]->(r:GH_Repository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"


            #query_user_permissions       = "MATCH p=(:GH_User)-[:GH_HasRole]->()-[:GH_HasBaseRole|GH_HasRole|GH_Owns|GH_AddMember|GH_MemberOf]->(:GH_RepoRole)-[]->(:GH_Repository {node_id: '$($repo.node_id)'}) RETURN p"
            #query_first_degree_object_control  = "MATCH p=(t:GH_User)-[:GH_HasRole]->(:GH_RepoRole)-[:GH_ReadRepoContents|GH_WriteRepoContents|GH_WriteRepoPullRequests|GH_ManageWebhooks|GH_ManageDeployKeys|GH_PushProtectedBranch|GH_DeleteAlertsCodeScanning|GH_ViewSecretScanningAlerts|GH_RunOrgMigration|GH_BypassBranchProtection|GH_EditRepoProtections]->(:GH_Repository {node_id:'$($repo.node_id)'}) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repo.node_id -Kind 'GH_Repository' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Owns' -StartId $repo.owner.node_id -EndId $repo.node_id -Properties @{ traversable = $true }))

        # --- Default Repository Role Nodes ---

        # Read Role
        $repoReadId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_read"))
        $repoReadProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoReadId
            name                   = Normalize-Null "$($repo.full_name)/read"
            # Relational Properties
            environment_name      = Normalize-Null $Organization.properties.login
            environment_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'read'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoReadId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoReadId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {id:'$($repoReadId)'})-[*1..]->(:GH_Repository) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {id:'$($repoReadId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoReadId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoReadProps))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoMetadata' -StartId $repoReadId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoContents' -StartId $repoReadId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoPullRequests' -StartId $repoReadId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoReadId -EndId $repoReadId -Properties @{traversable=$true}))

        # Write Role
        $repoWriteId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_write"))
        $repoWriteProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoWriteId
            name                   = Normalize-Null "$($repo.full_name)/write"
            # Relational Properties
            environment_name      = Normalize-Null $Organization.properties.login
            environment_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'write'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoWriteId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoWriteId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {id:'$($repoWriteId)'})-[*1..]->(:GH_Repository) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {id:'$($repoWriteId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoWriteId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoWriteProps))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoMetadata' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoContents' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteRepoContents' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddLabel' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveLabel' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseIssue' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenIssue' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoPullRequests' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteRepoPullRequests' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ClosePullRequest' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenPullRequest' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddAssignee' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetIssueType' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveAssignee' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_RequestPrReview' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_MarkAsDuplicate' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetMilestone' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadCodeScanning' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteCodeScanning' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionAnswer' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionCommentMinimize' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDiscussionSpotlights' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionCategory' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionCategory' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ConvertIssuesToDiscussions' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditCategoryOnDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionComment' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionComment' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewDependabotAlerts' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ResolveDependabotAlerts' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDiscussionBadges' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoWriteId -EndId $repoWriteId -Properties @{traversable=$true}))

        # Admin Role
        $repoAdminId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_admin"))
        $repoAdminProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoAdminId
            name                   = Normalize-Null "$($repo.full_name)/admin"
            # Relational Properties
            environment_name      = Normalize-Null $Organization.properties.login
            environment_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'admin'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoAdminId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoAdminId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {id:'$($repoAdminId)'})-[*1..]->(:GH_Repository) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {id:'$($repoAdminId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoAdminId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoAdminProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AdminTo' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoMetadata' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoContents' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteRepoContents' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddLabel' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveLabel' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseIssue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenIssue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoPullRequests' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteRepoPullRequests' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ClosePullRequest' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenPullRequest' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddAssignee' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteIssue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveAssignee' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_RequestPrReview' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_MarkAsDuplicate' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetMilestone' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetIssueType' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageTopics' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsDiscussions' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsWiki' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsProjects' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsMergeTypes' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsPages' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageWebhooks' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDeployKeys' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoMetadata' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetInteractionLimits' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetSocialPreview' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_PushProtectedBranch' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadCodeScanning' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteCodeScanning' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteAlertsCodeScanning' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewSecretScanningAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ResolveSecretScanningAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RunOrgMigration' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionAnnouncement' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionCategory' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionCategory' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionCategory' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDiscussionSpotlights' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionAnswer' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionCommentMinimize' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ConvertIssuesToDiscussions' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateTag' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteTag' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewDependabotAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ResolveDependabotAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_BypassBranchProtection' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSecurityProducts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageRepoSecurityProducts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoProtections' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoAnnouncementBanners' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditCategoryOnDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDiscussionBadges' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionComment' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionComment' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_JumpMergeQueue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateSoloMergeQueueEntry' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoCustomPropertiesValue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoAdminId -EndId $repoAdminId -Properties @{traversable=$true}))

        # Triage Role
        $repoTriageId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_triage"))
        $repoTriageProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoTriageId
            name                   = Normalize-Null "$($repo.full_name)/triage"
            # Relational Properties
            environment_name      = Normalize-Null $Organization.properties.login
            environment_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'triage'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoTriageId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoTriageId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {id:'$($repoTriageId)'})-[*1..]->(:GH_Repository) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {id:'$($repoTriageId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoTriageId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoTriageProps))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddLabel' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveLabel' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseIssue' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenIssue' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ClosePullRequest' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenPullRequest' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddAssignee' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveAssignee' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_RequestPrReview' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_MarkAsDuplicate' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetMilestone' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetIssueType' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionAnswer' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionCommentMinimize' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionCategory' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionCategory' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ConvertIssuesToDiscussions' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditCategoryOnDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionComment' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionComment' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $repoTriageId -EndId $repoReadId -Properties @{traversable=$true}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoTriageId -EndId $repoTriageId -Properties @{traversable=$true}))

        # Maintain Role
        $repoMaintainId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_maintain"))
        $repoMaintainProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoMaintainId
            name                   = Normalize-Null "$($repo.full_name)/maintain"
            # Relational Properties
            environment_name      = Normalize-Null $Organization.properties.login
            environment_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'maintain'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoMaintainId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {id:'$($repoMaintainId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {id:'$($repoMaintainId)'})-[*1..]->(:GH_Repository) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {id:'$($repoMaintainId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoMaintainId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoMaintainProps))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageTopics' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsWiki' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsProjects' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsMergeTypes' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsPages' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoMetadata' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetInteractionLimits' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetSocialPreview' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_PushProtectedBranch' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionAnnouncement' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionCategory' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsDiscussion' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $repoMaintainId -EndId $repoWriteId -Properties @{traversable=$true}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoMaintainId -EndId $repoMaintainId -Properties @{traversable=$true}))

        # --- Custom Repository Roles ---
        foreach($customRepoRole in $customRepoRoles)
        {
            $customRepoRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_$($customRepoRole.name)"))
            $customRepoRoleProps = [pscustomobject]@{
                # Common Properties
                id                     = Normalize-Null $customRepoRoleId
                name                   = Normalize-Null "$($repo.full_name)/$($customRepoRole.name)"
                # Relational Properties
                environment_name      = Normalize-Null $Organization.properties.login
                environment_id        = Normalize-Null $Organization.properties.node_id
                repository_name        = Normalize-Null $repo.name
                repository_id          = Normalize-Null $repo.node_id
                # Node Specific Properties
                short_name             = Normalize-Null $customRepoRole.name
                type                   = Normalize-Null 'custom'
                # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {id:'$($customRepoRoleId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {id:'$($customRepoRoleId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {id:'$($customRepoRoleId)'})-[*1..]->(:GH_Repository) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {id:'$($customRepoRoleId)'})-[*1..]->(:GH_Repository) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $customRepoRoleId -Kind 'GH_RepoRole', 'GH_Role' -Properties $customRepoRoleProps))

            if($null -ne $customRepoRole.base_role)
            {
                $targetBaseRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_$($customRepoRole.base_role)"))
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $customRepoRoleId -EndId $targetBaseRoleId -Properties @{traversable=$true}))
            }

            foreach($permission in $customRepoRole.permissions)
            {
                $null = $edges.Add((New-GitHoundEdge -Kind "GH$(ConvertTo-PascalCase -String $permission)" -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false}))
            }
        }

    } -ThrottleLimit 25

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Git-HoundRepositoryRole
{
    <#
    .SYNOPSIS
        Fetches collaborator and team role assignments for GitHub repositories.

    .DESCRIPTION
        This function processes GitHub repositories to fetch their direct collaborators and team access,
        creating GH_HasRole edges that map users and teams to the appropriate repository role nodes.

        Role IDs are deterministic (Base64-encoded from repo node_id + role name), so this function
        can compute them independently without needing the actual role nodes from Git-HoundRepository.

        Uses a chunked parallel approach with rate limit awareness:
        - Repos are processed in chunks sized to fit within the available REST API rate limit budget
        - After each chunk, results are checkpointed to disk as JSON files
        - If rate limit is exhausted, the function sleeps until reset and continues
        - Supports resuming from a specific index via -StartIndex if a previous run was interrupted
        - Each chunk costs ~2 REST calls per repo (collaborators + teams)

        API Reference:
        - List repository collaborators: https://docs.github.com/en/rest/collaborators/collaborators?apiVersion=2022-11-28#list-repository-collaborators
        - List repository teams: https://docs.github.com/en/enterprise-cloud@latest/rest/repos/repos?apiVersion=2022-11-28#list-repository-teams

        Fine Grained Permissions Reference:
        - "Metadata" repository permissions (read)
        - "Administration" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Repository
        A GitHound.Repository output object from Git-HoundRepository (pipeline input).

    .PARAMETER StartIndex
        Optional index into the repository array to resume from. Defaults to 0.

    .PARAMETER CheckpointPath
        Optional directory path to write checkpoint JSON files after each chunk.
        Defaults to the current directory.

    .PARAMETER ChunkSize
        Number of repos to process per chunk. Defaults to 50. Each repo costs ~2 API calls,
        so the default chunk costs ~100 API calls.

    .EXAMPLE
        $reporoles = $repos | Git-HoundRepositoryRole -Session $Session

    .EXAMPLE
        # Resume from repo index 500 after a previous interruption
        $reporoles = $repos | Git-HoundRepositoryRole -Session $Session -StartIndex 500
    #>

    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline)]
        [psobject[]]
        $Repository,

        [Parameter()]
        [int]
        $StartIndex = 0,

        [Parameter()]
        [string]
        $CheckpointPath = ".",

        [Parameter()]
        [int]
        $ChunkSize = 50
    )

    begin
    {
        $allNodes = New-Object System.Collections.ArrayList
        $allEdges = New-Object System.Collections.ArrayList
    }

    process
    {
        $repoNodes = @($Repository.nodes | Where-Object {$_.kinds -eq 'GH_Repository'})
        $totalRepos = $repoNodes.Count
        $callsPerRepo = 2
        $rateLimitBuffer = 50  # reserve some calls for other operations

        $currentIndex = $StartIndex

        # Auto-detect resume from existing chunk files
        if ($currentIndex -eq 0) {
            $existingChunks = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_RepoRole_chunk_*.json" -ErrorAction SilentlyContinue | Sort-Object { [int]($_.Name -replace '.*chunk_(\d+)\.json','$1') })
            if ($existingChunks.Count -gt 0) {
                foreach ($chunk in $existingChunks) {
                    try {
                        $chunkData = Get-Content $chunk.FullName -Raw | ConvertFrom-Json
                        if ($chunkData.graph.edges) {
                            $null = $allEdges.AddRange(@($chunkData.graph.edges))
                        }
                        $currentIndex = $chunkData.metadata.next_index
                    }
                    catch {
                        Write-Warning "Skipping corrupt chunk file: $($chunk.Name)"
                    }
                }
                Write-Host "[*] Auto-resuming Git-HoundRepositoryRole from index $currentIndex ($($existingChunks.Count) chunks loaded, $($allEdges.Count) edges recovered)"
            }
        }
        else {
            Write-Host "[*] Resuming Git-HoundRepositoryRole from index $StartIndex of $totalRepos repos"
        }

        while ($currentIndex -lt $totalRepos) {

            # Check rate limit and determine chunk size
            $rateLimitInfo = (Get-RateLimitInformation -Session $Session).core
            $remaining = $rateLimitInfo.remaining
            $resetTime = $rateLimitInfo.reset

            $availableBudget = [Math]::Max(0, $remaining - $rateLimitBuffer)
            $maxReposForBudget = [Math]::Floor($availableBudget / $callsPerRepo)

            if ($maxReposForBudget -eq 0) {
                # Not enough budget — sleep until reset
                $timeNow = [DateTimeOffset]::Now.ToUnixTimeSeconds()
                $sleepSeconds = [Math]::Max(1, $resetTime - $timeNow + 5) # +5s buffer
                $resetLocal = ([DateTimeOffset]::FromUnixTimeSeconds($resetTime)).LocalDateTime.ToString("HH:mm:ss")
                Write-Host "[!] Rate limit exhausted ($remaining remaining). Sleeping $sleepSeconds seconds until reset at $resetLocal..."
                Start-Sleep -Seconds $sleepSeconds
                continue
            }

            # Size the chunk: minimum of configured ChunkSize, budget, and remaining repos
            $reposRemaining = $totalRepos - $currentIndex
            $thisChunkSize = [Math]::Min($ChunkSize, [Math]::Min($maxReposForBudget, $reposRemaining))

            $chunkEnd = $currentIndex + $thisChunkSize - 1
            Write-Host "[*] Processing repos $currentIndex..$chunkEnd of $totalRepos ($thisChunkSize repos, ~$($thisChunkSize * $callsPerRepo) API calls, $remaining calls remaining)"

            $chunkRepos = $repoNodes[$currentIndex..$chunkEnd]
            # ConcurrentBag is thread-safe for parallel ForEach-Object blocks
            $chunkEdges = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()

            $chunkRepos | ForEach-Object -Parallel {
                $edges = $using:chunkEdges
                $Session = $using:Session
                $functionBundle = $using:GitHoundFunctionBundle
                foreach($funcName in $functionBundle.Keys) {
                    Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
                }
                $repo = $_

                # Compute deterministic role IDs from repo node_id
                $repoReadId     = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.properties.node_id)_read"))
                $repoWriteId    = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.properties.node_id)_write"))
                $repoAdminId    = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.properties.node_id)_admin"))
                $repoTriageId   = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.properties.node_id)_triage"))
                $repoMaintainId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.properties.node_id)_maintain"))

                # --- Role Assignments: Direct Collaborators ---
                foreach($collaborator in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.environment_name)/$($repo.properties.name)/collaborators?affiliation=direct"))
                {
                    switch($collaborator.role_name)
                    {
                        'admin'    { $repoRoleId = $repoAdminId }
                        'maintain' { $repoRoleId = $repoMaintainId }
                        'write'    { $repoRoleId = $repoWriteId }
                        'triage'   { $repoRoleId = $repoTriageId }
                        'read'     { $repoRoleId = $repoReadId }
                        default    { $repoRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.properties.node_id)_$($collaborator.role_name)")) }
                    }
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasRole' -StartId $collaborator.node_id -EndId $repoRoleId -Properties @{traversable=$true}))
                }

                # --- Role Assignments: Teams ---
                foreach($team in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.environment_name)/$($repo.properties.name)/teams"))
                {
                    switch($team.permission)
                    {
                        'admin'    { $repoRoleId = $repoAdminId }
                        'maintain' { $repoRoleId = $repoMaintainId }
                        'push'     { $repoRoleId = $repoWriteId }
                        'triage'   { $repoRoleId = $repoTriageId }
                        'pull'     { $repoRoleId = $repoReadId }
                        default    { $repoRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.properties.node_id)_$($team.permission)")) }
                    }
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasRole' -StartId $team.node_id -EndId $repoRoleId -Properties @{traversable=$true}))
                }
            } -ThrottleLimit 25

            # Accumulate chunk results
            if ($chunkEdges.Count -gt 0) {
                $null = $allEdges.AddRange(@($chunkEdges))
            }

            # Checkpoint to disk
            $chunkPayload = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    source_kind  = "GitHub"
                    chunk_start  = $currentIndex
                    chunk_end    = $chunkEnd
                    total_repos  = $totalRepos
                    next_index   = $currentIndex + $thisChunkSize
                    timestamp    = (Get-Date -Format "o")
                }
                graph = [PSCustomObject]@{
                    nodes = @()
                    edges = @($chunkEdges)
                }
            }
            $chunkFile = Join-Path $CheckpointPath "githound_RepoRole_chunk_$($currentIndex).json"
            $chunkPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $chunkFile
            Write-Host "[+] Checkpoint saved: $chunkFile ($($chunkEdges.Count) edges, next index: $($currentIndex + $thisChunkSize))"

            $currentIndex += $thisChunkSize
        }

        # Write final consolidated output and clean up chunk files
        $finalPayload = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                source_kind  = "GitHub"
                total_repos  = $totalRepos
                total_edges  = $allEdges.Count
                timestamp    = (Get-Date -Format "o")
            }
            graph = [PSCustomObject]@{
                nodes = @()
                edges = @($allEdges)
            }
        }
        $finalFile = Join-Path $CheckpointPath "githound_RepoRole_complete.json"
        $finalPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $finalFile

        # Clean up intermediate chunk files
        $intermediateFiles = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_RepoRole_chunk_*.json" -ErrorAction SilentlyContinue)
        if ($intermediateFiles.Count -gt 0) {
            $intermediateFiles | Remove-Item -Force
            Write-Host "[+] Cleaned up $($intermediateFiles.Count) intermediate checkpoint files."
        }

        Write-Host "[+] Git-HoundRepositoryRole complete. Processed $totalRepos repos, collected $($allEdges.Count) edges. Final output: $finalFile"
    }

    end
    {
        $output = [PSCustomObject]@{
            Nodes = $allNodes
            Edges = $allEdges
        }

        Write-Output $output
    }
}

function Git-HoundBranch
{
    <#
    .SYNOPSIS
        Retrieves branches and branch protection rules for GitHub repositories.

    .DESCRIPTION
        This function uses the GitHub GraphQL API to enumerate branches and their protection
        rules across all repositories in the organization.

        This uses a three-phase approach with checkpointing and rate limit management:
        - Phase 1: Paginate organization repositories with nested refs (50 per page).
          Each ref includes only its branchProtectionRule ID to determine protection status.
          Checkpoints are written after each page.
        - Phase 2: For repos with >100 branches, paginate the remaining refs individually.
        - Phase 3: Fetch protection rule details by node ID in batches of 100.

        Creates:
        - GH_Branch nodes for each branch
        - GH_BranchProtectionRule nodes for each protection rule
        - GH_HasBranch edges (Repository → Branch)
        - GH_ProtectedBy edges (Rule → Branch)
        - GH_BypassPullRequestAllowances edges (User/Team → Rule)
        - GH_RestrictionsCanPush edges (User/Team → Rule)

        Between phases and pages, the GraphQL rate limit is checked. If exhausted, the function
        sleeps until reset and continues. Checkpoint files are written to disk after each page
        so that progress is preserved if PowerShell crashes during long-running collection.

        GraphQL API Reference:
        - Repository.refs: https://docs.github.com/en/graphql/reference/objects#repository
        - BranchProtectionRule: https://docs.github.com/en/graphql/reference/objects#branchprotectionrule

        Fine Grained Permissions Reference:
        - "Contents" repository permissions (read)
        - "Administration" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Organization
        A GitHound.Organization node object (pipeline input from Git-HoundOrganization).

    .PARAMETER CheckpointPath
        Optional directory path to write checkpoint JSON files. Defaults to the current directory.

    .OUTPUTS
        PSCustomObject with Nodes and Edges properties containing branches and protection rules.

    .EXAMPLE
        $branches = $org.nodes[0] | Git-HoundBranch -Session $Session

    .EXAMPLE
        $branches = $org.nodes[0] | Git-HoundBranch -Session $Session -CheckpointPath "./output"
    #>
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline)]
        [psobject]
        $Organization,

        [Parameter()]
        [string]
        $CheckpointPath = "."
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList
    $pageCount = 0
    $totalRepos = 0
    $totalPages = 0
    $reposProcessed = 0

    # ── Phase 1 Query ──────────────────────────────────────────────────────
    # Paginate org repos with nested refs (branches). Only fetch branchProtectionRule ID
    # to determine protection status. Full protection details are fetched in Phase 3.

    $RepoRefsQuery = @'
query RepoRefs($login: String!, $count: Int = 100, $after: String = null) {
    organization(login: $login) {
        repositories(first: $count, after: $after) {
            totalCount
            nodes {
                id
                name
                nameWithOwner
                owner { login }
                refs(first: 100, refPrefix: "refs/heads/") {
                    nodes {
                        id
                        name
                        target { oid }
                        branchProtectionRule { id }
                    }
                    pageInfo { endCursor, hasNextPage }
                }
            }
            pageInfo { endCursor, hasNextPage }
        }
    }
}
'@

    # ── Phase 2 Query ──────────────────────────────────────────────────────
    # For repos with >100 branches, paginate remaining refs individually.

    $RefOverflowQuery = @'
query RefOverflow($owner: String!, $name: String!, $count: Int = 100, $after: String!) {
    repository(owner: $owner, name: $name) {
        refs(first: $count, refPrefix: "refs/heads/", after: $after) {
            nodes {
                id
                name
                target { oid }
                branchProtectionRule { id }
            }
            pageInfo { endCursor, hasNextPage }
        }
    }
}
'@

    $orgLogin = $Organization.properties.login
    $orgNodeId = $Organization.properties.node_id

    # Map: branchProtectionRule ID → list of branch IDs (for Phase 3)
    $ruleToBranches = @{}

    # ── Phase 1: Paginate repos with nested refs ───────────────────────────
    $overflowRepos = New-Object System.Collections.ArrayList
    $skipPhase1 = $false
    $skipPhase2 = $false

    $variables = @{
        login = $orgLogin
        count = 25
        after = $null
    }

    # ── Auto-resume: Check for existing checkpoints (highest precedence first) ──

    # Priority 1: Phase 2 complete → skip to Phase 3
    $phase2File = Join-Path $CheckpointPath "githound_Branch_phase2.json"
    if (Test-Path $phase2File) {
        try {
            $p2Data = Get-Content $phase2File -Raw | ConvertFrom-Json
            if ($p2Data.graph.nodes) { $null = $nodes.AddRange(@($p2Data.graph.nodes)) }
            if ($p2Data.graph.edges) { $null = $edges.AddRange(@($p2Data.graph.edges)) }
            if ($p2Data.metadata.rule_to_branches) {
                foreach ($prop in $p2Data.metadata.rule_to_branches.PSObject.Properties) {
                    $ruleToBranches[$prop.Name] = [System.Collections.ArrayList]@($prop.Value)
                }
            }
            Write-Host "[*] Auto-resume: Phase 2 checkpoint found ($($nodes.Count) branches). Skipping to Phase 3."
            $skipPhase1 = $true
            $skipPhase2 = $true
        }
        catch {
            Write-Warning "Failed to load Phase 2 checkpoint, will check Phase 1 checkpoints: $_"
        }
    }

    # Priority 2: Phase 1 page checkpoints → resume or skip Phase 1
    if (-not $skipPhase1) {
        $existingPages = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Branch_page_*.json" -ErrorAction SilentlyContinue |
            Sort-Object { [int]($_.Name -replace '.*page_(\d+)\.json','$1') })

        if ($existingPages.Count -gt 0) {
            $lastPage = $existingPages[-1]
            try {
                $resumeData = Get-Content $lastPage.FullName -Raw | ConvertFrom-Json

                # Restore cumulative nodes and edges
                if ($resumeData.graph.nodes) { $null = $nodes.AddRange(@($resumeData.graph.nodes)) }
                if ($resumeData.graph.edges) { $null = $edges.AddRange(@($resumeData.graph.edges)) }

                # Restore Phase 2/3 tracking structures
                if ($resumeData.metadata.overflow_repos) {
                    foreach ($r in $resumeData.metadata.overflow_repos) {
                        $null = $overflowRepos.Add(@{
                            owner    = $r.owner
                            name     = $r.name
                            nodeId   = $r.nodeId
                            fullName = $r.fullName
                            cursor   = $r.cursor
                        })
                    }
                }
                if ($resumeData.metadata.rule_to_branches) {
                    foreach ($prop in $resumeData.metadata.rule_to_branches.PSObject.Properties) {
                        $ruleToBranches[$prop.Name] = [System.Collections.ArrayList]@($prop.Value)
                    }
                }

                # Restore pagination state
                $pageCount = $resumeData.metadata.page
                $totalRepos = $resumeData.metadata.total_repos
                $totalPages = [Math]::Ceiling($totalRepos / 25)
                $reposProcessed = $resumeData.metadata.repos_processed
                $variables.after = $resumeData.metadata.cursor

                # If Phase 1 was complete (cursor is null / no more pages), skip to Phase 2
                if (-not $resumeData.metadata.cursor) {
                    Write-Host "[*] Auto-resume: Phase 1 was complete ($pageCount pages, $($nodes.Count) branches). Skipping to Phase 2."
                    $skipPhase1 = $true
                } else {
                    Write-Host "[*] Auto-resuming Phase 1 from page $($pageCount + 1)/$totalPages ($($nodes.Count) branches recovered from $($existingPages.Count) checkpoint files)"
                }
            }
            catch {
                Write-Warning "Failed to load checkpoint $($lastPage.Name), starting fresh: $_"
            }
        }
    }

    if (-not $skipPhase1) {
    do {
        $result = Invoke-GitHubGraphQL -Session $Session -Headers $Session.Headers -Query $RepoRefsQuery -Variables $variables

        # On first page, capture total repo count and calculate total pages
        if ($pageCount -eq 0) {
            $totalRepos = $result.data.organization.repositories.totalCount
            $totalPages = [Math]::Ceiling($totalRepos / 25)
            Write-Host "[*] Phase 1: Found $totalRepos repositories. Fetching branches ($totalPages pages of 25 repos)..."
        }

        foreach ($repo in $result.data.organization.repositories.nodes) {
            $reposProcessed++

            # Process each branch ref
            foreach ($ref in $repo.refs.nodes) {
                $branchId = $ref.id
                $rule = $ref.branchProtectionRule

                # Track rule-to-branch mapping for Phase 3
                if ($rule) {
                    if (-not $ruleToBranches.ContainsKey($rule.id)) {
                        $ruleToBranches[$rule.id] = New-Object System.Collections.ArrayList
                    }
                    $null = $ruleToBranches[$rule.id].Add($branchId)
                }

                $props = [pscustomobject]@{
                    name               = Normalize-Null "$($repo.name)\$($ref.name)"
                    id                 = Normalize-Null $branchId
                    organization       = Normalize-Null $orgLogin
                    environment_id     = Normalize-Null $orgNodeId
                    short_name         = Normalize-Null $ref.name
                    commit_hash        = Normalize-Null $ref.target.oid
                    protected          = Normalize-Null ($null -ne $rule)
                    query_branch_write = "MATCH p=(:GH_User)-[:GH_CanWriteBranch|GH_CanEditAndWriteBranch]->(:GH_Branch {objectid:'$($branchId)'}) RETURN p"
                }

                $null = $nodes.Add((New-GitHoundNode -Id $branchId -Kind GH_Branch -Properties $props))
                $null = $edges.Add((New-GitHoundEdge -Kind GH_HasBranch -StartId $repo.id -EndId $branchId -Properties @{ traversable = $true }))
            }

            # Track repos with >100 branches for Phase 2
            if ($repo.refs.pageInfo.hasNextPage) {
                $null = $overflowRepos.Add(@{
                    owner    = $repo.owner.login
                    name     = $repo.name
                    nodeId   = $repo.id
                    fullName = $repo.nameWithOwner
                    cursor   = $repo.refs.pageInfo.endCursor
                })
            }
        }

        # Checkpoint after each page
        $pageCount++
        $nextCursor = $result.data.organization.repositories.pageInfo.endCursor
        $chunkPayload = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                source_kind      = "GitHub"
                phase            = "branches_phase1"
                page             = $pageCount
                total_repos      = $totalRepos
                repos_processed  = $reposProcessed
                cursor           = if ($result.data.organization.repositories.pageInfo.hasNextPage) { $nextCursor } else { $null }
                timestamp        = (Get-Date -Format "o")
                overflow_repos   = @($overflowRepos)
                rule_to_branches = $ruleToBranches
            }
            graph = [PSCustomObject]@{
                nodes = @($nodes)
                edges = @($edges)
            }
        }
        $chunkFile = Join-Path $CheckpointPath "githound_Branch_page_$($pageCount).json"
        $chunkPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $chunkFile
        Write-Host "[+] Phase 1 page $pageCount/$totalPages complete ($reposProcessed/$totalRepos repos, $($nodes.Count) branches so far)"

        # Check GraphQL rate limit before next page
        $graphqlRateLimit = (Get-RateLimitInformation -Session $Session).graphql
        if ($graphqlRateLimit.remaining -lt 50) {
            $timeNow = [DateTimeOffset]::Now.ToUnixTimeSeconds()
            $sleepSeconds = [Math]::Max(1, $graphqlRateLimit.reset - $timeNow + 5)
            $resetLocal = ([DateTimeOffset]::FromUnixTimeSeconds($graphqlRateLimit.reset)).LocalDateTime.ToString("HH:mm:ss")
            Write-Host "[!] GraphQL rate limit low ($($graphqlRateLimit.remaining) remaining). Sleeping $sleepSeconds seconds until reset at $resetLocal..."
            Start-Sleep -Seconds $sleepSeconds
        }

        $variables.after = $result.data.organization.repositories.pageInfo.endCursor
    } while ($result.data.organization.repositories.pageInfo.hasNextPage)

    Write-Host "[*] Phase 1 complete. $reposProcessed/$totalRepos repos processed, $($nodes.Count) branches found. $($overflowRepos.Count) repos need overflow pagination (>100 branches)."
    } # end if (-not $skipPhase1)

    # ── Phase 2: Paginate remaining refs for overflow repos ────────────────
    if (-not $skipPhase2) {
    $overflowCount = 0
    foreach ($overflowRepo in $overflowRepos) {
        $overflowCount++
        Write-Host "[*] Phase 2: Fetching overflow branches for $($overflowRepo.fullName) ($overflowCount/$($overflowRepos.Count))"
        $refVars = @{
            owner = $overflowRepo.owner
            name  = $overflowRepo.name
            count = 100
            after = $overflowRepo.cursor
        }

        do {
            $refResult = Invoke-GitHubGraphQL -Session $Session -Headers $Session.Headers -Query $RefOverflowQuery -Variables $refVars

            foreach ($ref in $refResult.data.repository.refs.nodes) {
                $branchId = $ref.id
                $rule = $ref.branchProtectionRule

                # Track rule-to-branch mapping for Phase 3
                if ($rule) {
                    if (-not $ruleToBranches.ContainsKey($rule.id)) {
                        $ruleToBranches[$rule.id] = New-Object System.Collections.ArrayList
                    }
                    $null = $ruleToBranches[$rule.id].Add($branchId)
                }

                $props = [pscustomobject]@{
                    name               = Normalize-Null "$($overflowRepo.name)\$($ref.name)"
                    id                 = Normalize-Null $branchId
                    organization       = Normalize-Null $orgLogin
                    environment_id     = Normalize-Null $orgNodeId
                    short_name         = Normalize-Null $ref.name
                    commit_hash        = Normalize-Null $ref.target.oid
                    protected          = Normalize-Null ($null -ne $rule)
                    query_branch_write = "MATCH p=(:GH_User)-[:GH_CanWriteBranch|GH_CanEditAndWriteBranch]->(:GH_Branch {objectid:'$($branchId)'}) RETURN p"
                }

                $null = $nodes.Add((New-GitHoundNode -Id $branchId -Kind GH_Branch -Properties $props))
                $null = $edges.Add((New-GitHoundEdge -Kind GH_HasBranch -StartId $overflowRepo.nodeId -EndId $branchId -Properties @{ traversable = $true }))
            }

            # Check GraphQL rate limit between overflow pages
            $graphqlRateLimit = (Get-RateLimitInformation -Session $Session).graphql
            if ($graphqlRateLimit.remaining -lt 50) {
                $timeNow = [DateTimeOffset]::Now.ToUnixTimeSeconds()
                $sleepSeconds = [Math]::Max(1, $graphqlRateLimit.reset - $timeNow + 5)
                $resetLocal = ([DateTimeOffset]::FromUnixTimeSeconds($graphqlRateLimit.reset)).LocalDateTime.ToString("HH:mm:ss")
                Write-Host "[!] GraphQL rate limit low ($($graphqlRateLimit.remaining) remaining). Sleeping $sleepSeconds seconds until reset at $resetLocal..."
                Start-Sleep -Seconds $sleepSeconds
            }

            $refVars.after = $refResult.data.repository.refs.pageInfo.endCursor
        } while ($refResult.data.repository.refs.pageInfo.hasNextPage)
    }

    # Checkpoint after Phase 2
    if ($overflowRepos.Count -gt 0) {
        $chunkPayload = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                source_kind      = "GitHub"
                phase            = "branches_phase2"
                timestamp        = (Get-Date -Format "o")
                rule_to_branches = $ruleToBranches
            }
            graph = [PSCustomObject]@{
                nodes = @($nodes)
                edges = @($edges)
            }
        }
        $chunkFile = Join-Path $CheckpointPath "githound_Branch_phase2.json"
        $chunkPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $chunkFile
        Write-Host "[+] Phase 2 checkpoint saved: $chunkFile ($($nodes.Count) nodes, $($edges.Count) edges)"
    }

    Write-Host "[*] Phase 2 complete. $($nodes.Count) total branch nodes. $($ruleToBranches.Count) protection rules found."
    } # end if (-not $skipPhase2)

    # ── Phase 3: Fetch protection rules by node ID ─────────────────────────
    # Query protection rule details in batches using GraphQL nodes() query.
    # This is much more efficient than querying per-repository.

    $ruleIds = @($ruleToBranches.Keys)
    if ($ruleIds.Count -gt 0) {
        Write-Host "[*] Phase 3: Fetching $($ruleIds.Count) branch protection rules..."

        $ProtectionRulesQuery = @'
query ProtectionRulesByIds($ids: [ID!]!) {
    nodes(ids: $ids) {
        ... on BranchProtectionRule {
            id
            pattern
            isAdminEnforced
            lockBranch
            requiresApprovingReviews
            requiredApprovingReviewCount
            requiresCodeOwnerReviews
            requireLastPushApproval
            restrictsPushes
            requiresStatusChecks
            requiresStrictStatusChecks
            dismissesStaleReviews
            allowsForcePushes
            allowsDeletions
            bypassPullRequestAllowances(first: 100) {
                nodes {
                    actor {
                        ... on User { id login }
                        ... on Team { id slug }
                    }
                }
            }
            pushAllowances(first: 100) {
                nodes {
                    actor {
                        ... on User { id login }
                        ... on Team { id slug }
                    }
                }
            }
        }
    }
}
'@

        $batchSize = 100
        $batchCount = 0

        for ($i = 0; $i -lt $ruleIds.Count; $i += $batchSize) {
            $batchCount++
            $batch = $ruleIds[$i..[Math]::Min($i + $batchSize - 1, $ruleIds.Count - 1)]

            # Check GraphQL rate limit before each batch
            $graphqlRateLimit = (Get-RateLimitInformation -Session $Session).graphql
            if ($graphqlRateLimit.remaining -lt 50) {
                $timeNow = [DateTimeOffset]::Now.ToUnixTimeSeconds()
                $sleepSeconds = [Math]::Max(1, $graphqlRateLimit.reset - $timeNow + 5)
                $resetLocal = ([DateTimeOffset]::FromUnixTimeSeconds($graphqlRateLimit.reset)).LocalDateTime.ToString("HH:mm:ss")
                Write-Host "[!] GraphQL rate limit low ($($graphqlRateLimit.remaining) remaining). Sleeping $sleepSeconds seconds until reset at $resetLocal..."
                Start-Sleep -Seconds $sleepSeconds
            }

            Write-Host "[*] Phase 3 batch $batchCount ($($batch.Count) rules)..."

            $result = Invoke-GitHubGraphQL -Session $Session -Headers $Session.Headers -Query $ProtectionRulesQuery -Variables @{ ids = $batch }

            foreach ($rule in $result.data.nodes) {
                if (-not $rule) { continue }  # Skip null entries (deleted/invalid rule IDs)

                $ruleId = $rule.id

                # Create GH_BranchProtectionRule node
                $props = [pscustomobject]@{
                    name                            = Normalize-Null $rule.pattern
                    id                              = Normalize-Null $ruleId
                    environment_name                = Normalize-Null $orgLogin
                    environment_id                  = Normalize-Null $orgNodeId
                    pattern                         = Normalize-Null $rule.pattern
                    enforce_admins                  = Normalize-Null $rule.isAdminEnforced
                    lock_branch                     = Normalize-Null $rule.lockBranch
                    required_pull_request_reviews   = Normalize-Null $rule.requiresApprovingReviews
                    required_approving_review_count = Normalize-Null $rule.requiredApprovingReviewCount
                    require_code_owner_reviews      = Normalize-Null $rule.requiresCodeOwnerReviews
                    require_last_push_approval      = Normalize-Null $rule.requireLastPushApproval
                    push_restrictions               = Normalize-Null $rule.restrictsPushes
                    requires_status_checks          = Normalize-Null $rule.requiresStatusChecks
                    requires_strict_status_checks   = Normalize-Null $rule.requiresStrictStatusChecks
                    dismisses_stale_reviews         = Normalize-Null $rule.dismissesStaleReviews
                    allows_force_pushes             = Normalize-Null $rule.allowsForcePushes
                    allows_deletions                = Normalize-Null $rule.allowsDeletions
                    # Accordion Panel Queries
                    query_user_exceptions           = "MATCH p=(:GH_User)-[]->(:GH_BranchProtectionRule {id:'$($rule.id)'}) RETURN p"
                    query_branches                  = "MATCH p=(:GH_BranchProtectionRule {id:'$($rule.id)'})-[:GH_ProtectedBy]->(:GH_Branch) RETURN p"
                }

                $null = $nodes.Add((New-GitHoundNode -Id $ruleId -Kind GH_BranchProtectionRule -Properties $props))

                # Create GH_ProtectedBy edges from this rule to its branches
                foreach ($branchId in $ruleToBranches[$ruleId]) {
                    $null = $edges.Add((New-GitHoundEdge -Kind GH_ProtectedBy -StartId $ruleId -EndId $branchId -Properties @{ traversable = $true }))
                }

                # Create GH_BypassPullRequestAllowances edges from actors to this rule
                foreach ($allowance in $rule.bypassPullRequestAllowances.nodes) {
                    if ($allowance.actor.id) {
                        $null = $edges.Add((New-GitHoundEdge -Kind GH_BypassPullRequestAllowances -StartId $allowance.actor.id -EndId $ruleId -Properties @{ traversable = $false }))
                    }
                }

                # Create GH_RestrictionsCanPush edges from actors to this rule
                foreach ($allowance in $rule.pushAllowances.nodes) {
                    if ($allowance.actor.id) {
                        $null = $edges.Add((New-GitHoundEdge -Kind GH_RestrictionsCanPush -StartId $allowance.actor.id -EndId $ruleId -Properties @{ traversable = $false }))
                    }
                }
            }
        }

        Write-Host "[+] Phase 3 complete. $($ruleIds.Count) protection rules processed."
    }
    else {
        Write-Host "[*] Phase 3: No protected branches found, skipping protection rule fetch."
    }

    # Final checkpoint
    $finalPayload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
            phase       = "branches_complete"
            timestamp   = (Get-Date -Format "o")
        }
        graph = [PSCustomObject]@{
            nodes = @($nodes)
            edges = @($edges)
        }
    }
    $finalFile = Join-Path $CheckpointPath "githound_Branch_complete.json"
    $finalPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $finalFile

    # Clean up intermediate checkpoint files
    $intermediateFiles = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Branch_page_*.json" -ErrorAction SilentlyContinue)
    $phase2File = Join-Path $CheckpointPath "githound_Branch_phase2.json"
    if (Test-Path $phase2File) { $intermediateFiles += Get-Item $phase2File }
    if ($intermediateFiles.Count -gt 0) {
        $intermediateFiles | Remove-Item -Force
        Write-Host "[+] Cleaned up $($intermediateFiles.Count) intermediate checkpoint files."
    }

    Write-Host "[+] Git-HoundBranch complete. $($nodes.Count) nodes, $($edges.Count) edges. Final output: $finalFile"

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Git-HoundWorkflow
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Workflows (Actions) for repositories.

    .DESCRIPTION
        This function retrieves workflows for each repository provided in the pipeline. Only repos
        with Actions enabled (actions_enabled = true) are queried — repos without Actions are skipped
        to avoid wasted API calls. Uses chunked parallel execution with rate limit awareness and
        checkpoint files for crash recovery.

        API Reference:
        - List repository workflows: https://docs.github.com/en/rest/actions/workflows?apiVersion=2022-11-28#list-repository-workflows

        Fine Grained Permissions Reference:
        - "Actions" repository permissions (read)

    .PARAMETER Session
     A GitHound.Session object used for authentication and API requests.

    .PARAMETER Repository
        An array of repository objects to process.

    .PARAMETER StartIndex
        Index to resume processing from (default 0). Use this to resume after an interruption.

    .PARAMETER CheckpointPath
        Directory to write checkpoint files to (default current directory).

    .PARAMETER ChunkSize
        Number of repos to process per chunk (default 50).

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the workflows and their relationships.

    .EXAMPLE
        $workflows = $repos | Git-HoundWorkflow -Session $Session
    #>
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline)]
        [psobject[]]
        $Repository,

        [Parameter()]
        [int]
        $StartIndex = 0,

        [Parameter()]
        [string]
        $CheckpointPath = ".",

        [Parameter()]
        [int]
        $ChunkSize = 50
    )

    begin
    {
        $allNodes = New-Object System.Collections.ArrayList
        $allEdges = New-Object System.Collections.ArrayList
    }

    process
    {
        # Filter to only repos with Actions enabled — no point querying repos that have Actions disabled
        $allRepoNodes = @($Repository.nodes | Where-Object {$_.kinds -eq 'GH_Repository'})
        $repoNodes = @($allRepoNodes | Where-Object {$_.properties.actions_enabled -eq $true})
        $skippedCount = $allRepoNodes.Count - $repoNodes.Count

        $totalRepos = $repoNodes.Count
        $callsPerRepo = 1
        $rateLimitBuffer = 50

        if ($skippedCount -gt 0) {
            Write-Host "[*] Git-HoundWorkflow: Skipping $skippedCount repos with Actions disabled"
        }

        $currentIndex = $StartIndex

        # Auto-detect resume from existing chunk files
        if ($currentIndex -eq 0) {
            $existingChunks = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Workflow_chunk_*.json" -ErrorAction SilentlyContinue | Sort-Object { [int]($_.Name -replace '.*chunk_(\d+)\.json','$1') })
            if ($existingChunks.Count -gt 0) {
                foreach ($chunk in $existingChunks) {
                    try {
                        $chunkData = Get-Content $chunk.FullName -Raw | ConvertFrom-Json
                        if ($chunkData.graph.nodes) { $null = $allNodes.AddRange(@($chunkData.graph.nodes)) }
                        if ($chunkData.graph.edges) { $null = $allEdges.AddRange(@($chunkData.graph.edges)) }
                        $currentIndex = $chunkData.metadata.next_index
                    }
                    catch {
                        Write-Warning "Skipping corrupt chunk file: $($chunk.Name)"
                    }
                }
                Write-Host "[*] Auto-resuming Git-HoundWorkflow from index $currentIndex ($($existingChunks.Count) chunks loaded, $($allNodes.Count) nodes, $($allEdges.Count) edges recovered)"
            }
        }

        if ($currentIndex -gt 0 -and $existingChunks.Count -eq 0) {
            Write-Host "[*] Resuming Git-HoundWorkflow from index $StartIndex of $totalRepos repos"
        } elseif ($currentIndex -eq 0) {
            Write-Host "[*] Git-HoundWorkflow: Enumerating workflows for $totalRepos repos (Actions enabled)"
        }

        while ($currentIndex -lt $totalRepos) {

            # Check rate limit and determine chunk size
            $rateLimitInfo = (Get-RateLimitInformation -Session $Session).core
            $remaining = $rateLimitInfo.remaining
            $resetTime = $rateLimitInfo.reset

            $availableBudget = [Math]::Max(0, $remaining - $rateLimitBuffer)
            $maxReposForBudget = [Math]::Floor($availableBudget / $callsPerRepo)

            if ($maxReposForBudget -eq 0) {
                # Not enough budget — sleep until reset
                $timeNow = [DateTimeOffset]::Now.ToUnixTimeSeconds()
                $sleepSeconds = [Math]::Max(1, $resetTime - $timeNow + 5)
                $resetLocal = ([DateTimeOffset]::FromUnixTimeSeconds($resetTime)).LocalDateTime.ToString("HH:mm:ss")
                Write-Host "[!] Rate limit exhausted ($remaining remaining). Sleeping $sleepSeconds seconds until reset at $resetLocal..."
                Start-Sleep -Seconds $sleepSeconds
                continue
            }

            # Size the chunk: minimum of configured ChunkSize, budget, and remaining repos
            $reposRemaining = $totalRepos - $currentIndex
            $thisChunkSize = [Math]::Min($ChunkSize, [Math]::Min($maxReposForBudget, $reposRemaining))

            $chunkEnd = $currentIndex + $thisChunkSize - 1
            Write-Host "[*] Processing repos $currentIndex..$chunkEnd of $totalRepos ($thisChunkSize repos, ~$($thisChunkSize * $callsPerRepo) API calls, $remaining calls remaining)"

            $chunkRepos = $repoNodes[$currentIndex..$chunkEnd]
            # ConcurrentBag is thread-safe for parallel ForEach-Object blocks
            $chunkNodes = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
            $chunkEdges = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()

            $chunkRepos | ForEach-Object -Parallel {
                $nodes = $using:chunkNodes
                $edges = $using:chunkEdges
                $Session = $using:Session
                $functionBundle = $using:GitHoundFunctionBundle
                foreach($funcName in $functionBundle.Keys) {
                    Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
                }
                $repo = $_

                foreach($workflow in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/actions/workflows").workflows)
                {
                    $props = [pscustomobject]@{
                        # Common Properties
                        name              = Normalize-Null "$($repo.properties.name)\$($workflow.name)"
                        id                = Normalize-Null $workflow.id
                        node_id           = Normalize-Null $workflow.node_id
                        # Relational Properties
                        environment_name = Normalize-Null $repo.properties.environment_name
                        environment_id   = Normalize-Null $repo.properties.environment_id
                        repository_name   = Normalize-Null $repo.properties.full_name
                        repository_id     = Normalize-Null $repo.properties.node_id
                        # Node Specific Properties
                        short_name        = Normalize-Null $workflow.name
                        path              = Normalize-Null $workflow.path
                        state             = Normalize-Null $workflow.state
                        url               = Normalize-Null $workflow.url
                        # Accordion Panel Queries
                        query_repository = "MATCH p=(:GH_Repository)-[:GH_HasWorkflow]->(:GH_Workflow {node_id: '$($workflow.node_id)'}) RETURN p"
                        query_editors    = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_WriteRepoContents|GH_WriteRepoPullRequests*1..]->(r:GH_Repository)-[:GH_HasWorkflow]->(:GH_Workflow {node_id:'$($workflow.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
                    }

                    $null = $nodes.Add((New-GitHoundNode -Id $workflow.node_id -Kind GH_Workflow -Properties $props))
                    $null = $edges.Add((New-GitHoundEdge -Kind GH_HasWorkflow -StartId $repo.properties.node_id -EndId $workflow.node_id -Properties @{ traversable = $false }))
                }
            } -ThrottleLimit 25

            # Accumulate chunk results
            if ($chunkNodes.Count -gt 0) {
                $null = $allNodes.AddRange(@($chunkNodes))
            }
            if ($chunkEdges.Count -gt 0) {
                $null = $allEdges.AddRange(@($chunkEdges))
            }

            # Checkpoint to disk
            $chunkPayload = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    source_kind  = "GitHub"
                    chunk_start  = $currentIndex
                    chunk_end    = $chunkEnd
                    total_repos  = $totalRepos
                    next_index   = $currentIndex + $thisChunkSize
                    timestamp    = (Get-Date -Format "o")
                }
                graph = [PSCustomObject]@{
                    nodes = @($chunkNodes)
                    edges = @($chunkEdges)
                }
            }
            $chunkFile = Join-Path $CheckpointPath "githound_Workflow_chunk_$($currentIndex).json"
            $chunkPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $chunkFile
            Write-Host "[+] Checkpoint saved: $chunkFile ($($chunkNodes.Count) nodes, $($chunkEdges.Count) edges, next index: $($currentIndex + $thisChunkSize))"

            $currentIndex += $thisChunkSize
        }

        # Write final consolidated output and clean up chunk files
        $finalPayload = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                source_kind  = "GitHub"
                total_repos  = $totalRepos
                skipped_repos = $skippedCount
                total_nodes  = $allNodes.Count
                total_edges  = $allEdges.Count
                timestamp    = (Get-Date -Format "o")
            }
            graph = [PSCustomObject]@{
                nodes = @($allNodes)
                edges = @($allEdges)
            }
        }
        $finalFile = Join-Path $CheckpointPath "githound_Workflow_complete.json"
        $finalPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $finalFile

        # Clean up intermediate chunk files
        $intermediateFiles = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Workflow_chunk_*.json" -ErrorAction SilentlyContinue)
        if ($intermediateFiles.Count -gt 0) {
            $intermediateFiles | Remove-Item -Force
            Write-Host "[+] Cleaned up $($intermediateFiles.Count) intermediate checkpoint files."
        }

        Write-Host "[+] Git-HoundWorkflow complete. Processed $totalRepos repos (skipped $skippedCount), collected $($allNodes.Count) nodes, $($allEdges.Count) edges. Final output: $finalFile"
    }

    end
    {
        $output = [PSCustomObject]@{
            Nodes = $allNodes
            Edges = $allEdges
        }

        Write-Output $output
    }
}

function Git-HoundEnvironment
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Environments for repositories.

    .DESCRIPTION
        This function retrieves environments for each repository provided in the pipeline. It creates nodes and edges representing the environments and their relationships to repositories. If a repository has custom branch policies for deployments, edges are created from the branch policies to the environment; otherwise, an edge is created directly from the repository to the environment.

        API Reference: 
        - List environments: https://docs.github.com/en/rest/deployments/environments?apiVersion=2022-11-28#list-environments
        - List deployment branch policies: https://docs.github.com/en/rest/deployments/branch-policies?apiVersion=2022-11-28#list-deployment-branch-policies
        - List environment secrets: https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-environment-secrets

        Fine Grained Permissions Reference:
        - "Actions" repository permissions (read)
        - "Environments" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Repository
        An array of repository objects to process.

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the environments and their relationships.

    .EXAMPLE
        $environments = Git-HoundRepository | Git-HoundEnvironment
    #>
        Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline)]
        [psobject[]]
        $Repository
    )
    
    begin
    {
        # ConcurrentBag is thread-safe for parallel ForEach-Object blocks
        $nodes = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
        $edges = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    }

    process
    {
        $Repository.nodes | Where-Object {$_.kinds -eq 'GH_Repository'} | ForEach-Object -Parallel {
            $nodes = $using:nodes
            $edges = $using:edges
            $Session = $using:Session
            $functionBundle = $using:GitHoundFunctionBundle
            foreach($funcName in $functionBundle.Keys) {
                Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
            }
            $repo = $_

            Write-Verbose "Fetching environments for $($repo.properties.full_name)"
            # List environments
            # https://docs.github.com/en/rest/deployments/environments?apiVersion=2022-11-28&versionId=free-pro-team%40latest&category=repos&subcategory=repos#list-environments
            # "Actions" repository permissions (read)
            foreach($environment in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/environments").environments)
            {
                $props = [pscustomobject]@{
                    # Common Properties
                    name              = Normalize-Null "$($repo.properties.name)\$($environment.name)"
                    id                = Normalize-Null $environment.id
                    node_id           = Normalize-Null $environment.node_id
                    # Relational Properties
                    environment_name  = Normalize-Null $repo.properties.environment_name
                    environment_id    = Normalize-Null $repo.properties.environment_id
                    repository_name   = Normalize-Null $repo.properties.full_name
                    repository_id     = Normalize-Null $repo.properties.node_id
                    # Node Specific Properties
                    short_name        = Normalize-Null $environment.name
                    can_admins_bypass = Normalize-Null $environment.can_admins_bypass
                    # Accordion Panel Queries
                }

                $null = $nodes.Add((New-GitHoundNode -Id $environment.node_id -Kind GH_Environment -Properties $props))

                if($environment.deployment_branch_policy.custom_branch_policies -eq $true)
                {
                    foreach($policy in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/environments/$($environment.name)/deployment-branch-policies").branch_policies)
                    {
                        $branchId = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$($repo.properties.environment_id)_$($repo.properties.full_name)_$($policy.name)"))).Replace('-', '')
                        $null = $edges.Add((New-GitHoundEdge -Kind GH_HasEnvironment -StartId $branchId -EndId $environment.node_id -Properties @{ traversable = $false }))
                    }
                }
                else 
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GH_HasEnvironment -StartId $repo.Properties.node_id -EndId $environment.node_id -Properties @{ traversable = $true }))
                }

                # List environment secrets
                # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-environment-secrets
                # "Environments" repository permissions (read)
                foreach($secret in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/environments/$($environment.name)/secrets").secrets)
                {
                    $secretId = "GH_EnvironmentSecret_$($environment.node_id)_$($secret.name)"
                    $properties = @{
                        # Common Properties
                        id                              = Normalize-Null $secretId
                        name                            = Normalize-Null $secret.name
                        # Relational Properties
                        environment_name                = Normalize-Null $repo.properties.environment_name
                        environment_id                  = Normalize-Null $repo.properties.environment_id
                        deployment_environment_name     = Normalize-Null $environment.name
                        deployment_environment_id       = Normalize-Null $environment.node_id
                        # Node Specific Properties
                        created_at                      = Normalize-Null $secret.created_at
                        updated_at                      = Normalize-Null $secret.updated_at
                        # Accordion Panel Queries
                    }

                    $null = $nodes.Add((New-GitHoundNode -Id $secretId -Kind 'GH_EnvironmentSecret' -Properties $properties))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $environment.node_id -EndId $secretId -Properties @{ traversable = $false }))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecret' -StartId $environment.node_id -EndId $secretId -Properties @{ traversable = $false }))
                }
            }
        } -ThrottleLimit 25
    }

    end
    {
        $output = [PSCustomObject]@{
            Nodes = $nodes
            Edges = $edges
        }
    
        Write-Output $output
    }
}

function Git-HoundOrganizationSecret
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub organization-level Actions secrets and resolves repository access.

    .DESCRIPTION
        This function retrieves organization-level Actions secrets and determines which repositories
        have access to each secret based on the secret's visibility setting:
        - "all": accessible to all organization repositories
        - "private": accessible to private and internal repositories only
        - "selected": accessible to specifically selected repositories (fetched via API)

        This replaces the per-repo organization-secrets lookup with a much more efficient org-scoped
        approach: 1 + S API calls (S = number of "selected" visibility secrets) instead of R calls
        (R = number of repos).

        API Reference:
        - List organization secrets: https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-organization-secrets
        - List selected repositories for an organization secret: https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-selected-repositories-for-an-organization-secret

        Fine Grained Permissions Reference:
        - "Secrets" organization permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Repository
        Repository output from Git-HoundRepository. Used to resolve which repos get access edges.

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the organization secrets and their relationships.

    .EXAMPLE
        $orgsecrets = $repos | Git-HoundOrganizationSecret -Session $Session

    #>
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline)]
        [psobject[]]
        $Repository
    )

    begin
    {
        $nodes = New-Object System.Collections.ArrayList
        $edges = New-Object System.Collections.ArrayList
        $repoNodes = New-Object System.Collections.ArrayList
    }

    process
    {
        # Collect repo nodes from the pipeline
        $Repository.nodes | Where-Object {$_.kinds -eq 'GH_Repository'} | ForEach-Object {
            $null = $repoNodes.Add($_)
        }
    }

    end
    {
        $orgLogin = $Session.OrganizationName
        $org = Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin"
        $orgNodeId = $org.node_id

        # List organization secrets
        # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-organization-secrets
        $orgSecrets = @((Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/actions/secrets").secrets)

        $allCount = 0
        $privateCount = 0
        $selectedCount = 0

        foreach ($secret in $orgSecrets) {
            switch ($secret.visibility) {
                'all'      { $allCount++ }
                'private'  { $privateCount++ }
                'selected' { $selectedCount++ }
            }
        }

        Write-Host "[*] Git-HoundOrganizationSecret: Found $($orgSecrets.Count) org secrets (all: $allCount, private: $privateCount, selected: $selectedCount) across $($repoNodes.Count) repos"

        # Pre-compute repo lookup sets for "all" and "private" visibility
        $allRepoNodeIds = @($repoNodes | ForEach-Object { $_.properties.node_id })
        $privateRepoNodeIds = @($repoNodes | Where-Object { $_.properties.visibility -eq 'private' -or $_.properties.visibility -eq 'internal' } | ForEach-Object { $_.properties.node_id })

        $selectedProcessed = 0

        foreach ($secret in $orgSecrets) {
            $secretId = "GH_OrgSecret_$($orgNodeId)_$($secret.name)"
            $properties = @{
                # Common Properties
                id                   = Normalize-Null $secretId
                name                 = Normalize-Null $secret.name
                # Relational Properties
                environment_name    = Normalize-Null $orgLogin
                environment_id      = Normalize-Null $orgNodeId
                # Node Specific Properties
                created_at           = Normalize-Null $secret.created_at
                updated_at           = Normalize-Null $secret.updated_at
                visibility           = Normalize-Null $secret.visibility
                # Accordion Panel Queries
                query_visible_repositories = "MATCH p=(:GH_OrgSecret {id:'$secretId'})<-[:GH_HasSecret]-(:GH_Repository) RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $secretId -Kind 'GH_OrgSecret', 'GH_Secret' -Properties $properties))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNodeId -EndId $secretId -Properties @{ traversable = $false }))

            # Resolve repository access based on visibility
            switch ($secret.visibility) {
                'all' {
                    foreach ($repoNodeId in $allRepoNodeIds) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecret' -StartId $repoNodeId -EndId $secretId -Properties @{ traversable = $false }))
                    }
                }
                'private' {
                    foreach ($repoNodeId in $privateRepoNodeIds) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecret' -StartId $repoNodeId -EndId $secretId -Properties @{ traversable = $false }))
                    }
                }
                'selected' {
                    $selectedProcessed++
                    Write-Host "[*]   Fetching selected repos for secret '$($secret.name)' ($selectedProcessed/$selectedCount)"
                    # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-selected-repositories-for-an-organization-secret
                    $selectedRepos = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/actions/secrets/$($secret.name)/repositories").repositories
                    foreach ($selectedRepo in $selectedRepos) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecret' -StartId $selectedRepo.node_id -EndId $secretId -Properties @{ traversable = $false }))
                    }
                }
            }
        }

        Write-Host "[+] Git-HoundOrganizationSecret complete. $($nodes.Count) nodes, $($edges.Count) edges."

        $output = [PSCustomObject]@{
            Nodes = $nodes
            Edges = $edges
        }

        Write-Output $output
    }
}

function Git-HoundSecret
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub repository-level Actions secrets.

    .DESCRIPTION
        This function retrieves repository-level Actions secrets (not org secrets — those are handled
        by Git-HoundOrganizationSecret). Uses chunked parallel execution with rate limit awareness
        and checkpoint files for crash recovery.

        API Reference:
        - List repository secrets: https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-repository-secrets

        Fine Grained Permissions Reference:
        - "Secrets" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Repository
        An array of repository objects to process.

    .PARAMETER StartIndex
        Index to resume processing from (default 0). Use this to resume after an interruption.

    .PARAMETER CheckpointPath
        Directory to write checkpoint files to (default current directory).

    .PARAMETER ChunkSize
        Number of repos to process per chunk (default 50).

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the repository secrets and their relationships.

    .EXAMPLE
        $secrets = $repos | Git-HoundSecret -Session $Session

    #>
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline)]
        [psobject[]]
        $Repository,

        [Parameter()]
        [int]
        $StartIndex = 0,

        [Parameter()]
        [string]
        $CheckpointPath = ".",

        [Parameter()]
        [int]
        $ChunkSize = 50
    )

    begin
    {
        $allNodes = New-Object System.Collections.ArrayList
        $allEdges = New-Object System.Collections.ArrayList
    }

    process
    {
        $repoNodes = @($Repository.nodes | Where-Object {$_.kinds -eq 'GH_Repository'})
        $totalRepos = $repoNodes.Count
        $callsPerRepo = 1
        $rateLimitBuffer = 50

        $currentIndex = $StartIndex

        # Auto-detect resume from existing chunk files
        if ($currentIndex -eq 0) {
            $existingChunks = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Secret_chunk_*.json" -ErrorAction SilentlyContinue | Sort-Object { [int]($_.Name -replace '.*chunk_(\d+)\.json','$1') })
            if ($existingChunks.Count -gt 0) {
                foreach ($chunk in $existingChunks) {
                    try {
                        $chunkData = Get-Content $chunk.FullName -Raw | ConvertFrom-Json
                        if ($chunkData.graph.nodes) { $null = $allNodes.AddRange(@($chunkData.graph.nodes)) }
                        if ($chunkData.graph.edges) { $null = $allEdges.AddRange(@($chunkData.graph.edges)) }
                        $currentIndex = $chunkData.metadata.next_index
                    }
                    catch {
                        Write-Warning "Skipping corrupt chunk file: $($chunk.Name)"
                    }
                }
                Write-Host "[*] Auto-resuming Git-HoundSecret from index $currentIndex ($($existingChunks.Count) chunks loaded, $($allNodes.Count) nodes, $($allEdges.Count) edges recovered)"
            }
        }

        if ($currentIndex -gt 0 -and $existingChunks.Count -eq 0) {
            Write-Host "[*] Resuming Git-HoundSecret from index $StartIndex of $totalRepos repos"
        } elseif ($currentIndex -eq 0) {
            Write-Host "[*] Git-HoundSecret: Enumerating repo-level secrets for $totalRepos repos"
        }

        while ($currentIndex -lt $totalRepos) {

            # Check rate limit and determine chunk size
            $rateLimitInfo = (Get-RateLimitInformation -Session $Session).core
            $remaining = $rateLimitInfo.remaining
            $resetTime = $rateLimitInfo.reset

            $availableBudget = [Math]::Max(0, $remaining - $rateLimitBuffer)
            $maxReposForBudget = [Math]::Floor($availableBudget / $callsPerRepo)

            if ($maxReposForBudget -eq 0) {
                # Not enough budget — sleep until reset
                $timeNow = [DateTimeOffset]::Now.ToUnixTimeSeconds()
                $sleepSeconds = [Math]::Max(1, $resetTime - $timeNow + 5)
                $resetLocal = ([DateTimeOffset]::FromUnixTimeSeconds($resetTime)).LocalDateTime.ToString("HH:mm:ss")
                Write-Host "[!] Rate limit exhausted ($remaining remaining). Sleeping $sleepSeconds seconds until reset at $resetLocal..."
                Start-Sleep -Seconds $sleepSeconds
                continue
            }

            # Size the chunk: minimum of configured ChunkSize, budget, and remaining repos
            $reposRemaining = $totalRepos - $currentIndex
            $thisChunkSize = [Math]::Min($ChunkSize, [Math]::Min($maxReposForBudget, $reposRemaining))

            $chunkEnd = $currentIndex + $thisChunkSize - 1
            Write-Host "[*] Processing repos $currentIndex..$chunkEnd of $totalRepos ($thisChunkSize repos, ~$($thisChunkSize * $callsPerRepo) API calls, $remaining calls remaining)"

            $chunkRepos = $repoNodes[$currentIndex..$chunkEnd]
            # ConcurrentBag is thread-safe for parallel ForEach-Object blocks
            $chunkNodes = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
            $chunkEdges = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
            $orgName = $Session.OrganizationName

            $chunkRepos | ForEach-Object -Parallel {
                $nodes = $using:chunkNodes
                $edges = $using:chunkEdges
                $Session = $using:Session
                $orgName = $using:orgName
                $functionBundle = $using:GitHoundFunctionBundle
                foreach($funcName in $functionBundle.Keys) {
                    Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
                }
                $repo = $_

                # List repository secrets
                # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-repository-secrets
                foreach($secret in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/actions/secrets").secrets)
                {
                    $secretId = "GH_Secret_$($repo.properties.node_id)_$($secret.name)"
                    $properties = @{
                        # Common Properties
                        id                   = Normalize-Null $secretId
                        name                 = Normalize-Null $secret.name
                        # Relational Properties
                        environment_name    = Normalize-Null $orgName
                        environment_id      = Normalize-Null $repo.properties.environment_id
                        repository_name      = Normalize-Null $repo.properties.name
                        repository_id        = Normalize-Null $repo.properties.node_id
                        # Node Specific Properties
                        created_at           = Normalize-Null $secret.created_at
                        updated_at           = Normalize-Null $secret.updated_at
                        visibility           = Normalize-Null $secret.visibility
                        # Accordion Panel Queries
                        query_visible_repositories = "MATCH p=(:GH_RepoSecret {id:'$secretId'})<-[:GH_HasSecret]-(:GH_Repository) RETURN p"
                        # There could be a query for workflows that use this secret
                        # There could be a query for users that can overwrite workflows to use this secret
                    }

                    $null = $nodes.Add((New-GitHoundNode -Id $secretId -Kind 'GH_RepoSecret', 'GH_Secret' -Properties $properties))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $repo.properties.node_id -EndId $secretId -Properties @{ traversable = $false }))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecret' -StartId $repo.properties.node_id -EndId $secretId -Properties @{ traversable = $false }))
                }
            } -ThrottleLimit 25

            # Accumulate chunk results
            if ($chunkNodes.Count -gt 0) {
                $null = $allNodes.AddRange(@($chunkNodes))
            }
            if ($chunkEdges.Count -gt 0) {
                $null = $allEdges.AddRange(@($chunkEdges))
            }

            # Checkpoint to disk
            $chunkPayload = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    source_kind  = "GitHub"
                    chunk_start  = $currentIndex
                    chunk_end    = $chunkEnd
                    total_repos  = $totalRepos
                    next_index   = $currentIndex + $thisChunkSize
                    timestamp    = (Get-Date -Format "o")
                }
                graph = [PSCustomObject]@{
                    nodes = @($chunkNodes)
                    edges = @($chunkEdges)
                }
            }
            $chunkFile = Join-Path $CheckpointPath "githound_Secret_chunk_$($currentIndex).json"
            $chunkPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $chunkFile
            Write-Host "[+] Checkpoint saved: $chunkFile ($($chunkNodes.Count) nodes, $($chunkEdges.Count) edges, next index: $($currentIndex + $thisChunkSize))"

            $currentIndex += $thisChunkSize
        }

        # Write final consolidated output and clean up chunk files
        $finalPayload = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                source_kind  = "GitHub"
                total_repos  = $totalRepos
                total_nodes  = $allNodes.Count
                total_edges  = $allEdges.Count
                timestamp    = (Get-Date -Format "o")
            }
            graph = [PSCustomObject]@{
                nodes = @($allNodes)
                edges = @($allEdges)
            }
        }
        $finalFile = Join-Path $CheckpointPath "githound_Secret_complete.json"
        $finalPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $finalFile

        # Clean up intermediate chunk files
        $intermediateFiles = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Secret_chunk_*.json" -ErrorAction SilentlyContinue)
        if ($intermediateFiles.Count -gt 0) {
            $intermediateFiles | Remove-Item -Force
            Write-Host "[+] Cleaned up $($intermediateFiles.Count) intermediate checkpoint files."
        }

        Write-Host "[+] Git-HoundSecret complete. Processed $totalRepos repos, collected $($allNodes.Count) nodes, $($allEdges.Count) edges. Final output: $finalFile"
    }

    end
    {
        $output = [PSCustomObject]@{
            Nodes = $allNodes
            Edges = $allEdges
        }

        Write-Output $output
    }
}

# This is a second order data type after GH_Organization
# Inspired by https://github.com/SpecterOps/GitHound/issues/3
# The GH_HasSecretScanningAlert edge is used to link the alert to the repository
# However, that edge is not traversable because the GH_ReadSecretScanningAlerts permission is necessary to read the alerts and the GH_ReadRepositoryContents permission is necessary to read the repository
function Git-HoundSecretScanningAlert
{
    <#
    .SYNOPSIS
        Retrieves secret scanning alerts for a given GitHub organization.

    .DESCRIPTION
        This function fetches secret scanning alerts for the specified organization using the provided GitHound session and constructs nodes and edges representing the alerts and their relationships to repositories.

        Requires the GitHub API permission: GH_ReadSecretScanningAlerts on the organization and GH_ReadRepositoryContents on the repository.

        API Reference: 
        - List secret scanning alerts for an organization: https://docs.github.com/en/rest/secret-scanning/secret-scanning?apiVersion=2022-11-28#list-secret-scanning-alerts-for-an-organization

        Fine Grained Permissions Reference:
        - "Secret scanning alerts" repository permissions (read)

    .PARAMETER Session
        A GitHound session object used to authenticate and interact with the GitHub API.

    .PARAMETER Organization
        A PSObject representing the GitHub organization for which to retrieve secret scanning alerts.

    .OUTPUTS
        A PSObject containing two properties: Nodes and Edges. Nodes is an array of GH_SecretScanningAlert nodes, and Edges is an array of GH_HasSecretScanningAlert edges.

    .EXAMPLE
        $session = New-GitHoundSession -Token "your_github_token"
        $organization = Get-GitHoundOrganization -Session $session -Login "your_org_login"
        $alerts = $organization | Git-HoundSecretScanningAlert -Session $session
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $Organization
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    foreach($alert in (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/secret-scanning/alerts"))
    {
        $alertId = "SSA_$($Organization.id)_$($alert.repository.node_id)_$($alert.number)"
        $properties =[pscustomobject]@{
            # Common Properties
            node_id                  = Normalize-Null $alertId
            name                     = Normalize-Null $alert.number
            # Relational Properties
            environment_name         = Normalize-Null $alert.repository.owner.login
            environment_id           = Normalize-Null $alert.repository.owner.node_id
            repository_name          = Normalize-Null $alert.repository.name
            repository_id            = Normalize-Null $alert.repository.node_id
            repository_url           = Normalize-Null $alert.repository.html_url
            # Node Specific Properties
            secret_type              = Normalize-Null $alert.secret_type
            secret_type_display_name = Normalize-Null $alert.secret_type_display_name
            validity                 = Normalize-Null $alert.validity
            state                    = Normalize-Null $alert.state
            created_at               = Normalize-Null $alert.created_at
            updated_at               = Normalize-Null $alert.updated_at
            url                      = Normalize-Null $alert.html_url
            # Accordion Panel Queries
            query_repository         = "MATCH p=(r:GH_SecretScanningAlert {id:'$alertId'})<-[:GH_HasSecretScanningAlert]-(repo:GH_Repository) RETURN p"
            # This currently doesn't take into account that there is an organization-level permission that can allow users to view alerts without having any repository permissions, but it's a start. We can iterate on the queries in future releases.
            query_alert_viewers      = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ViewSecretScanningAlerts*1..]->(:GH_Repository)-[:GH_HasSecretScanningAlert]->(:GH_SecretScanningAlert {id:'$alertId'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
        }

        $null = $nodes.Add((New-GitHoundNode -Id $alertId -Kind 'GH_SecretScanningAlert' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecretScanningAlert' -StartId $alert.repository.node_id -EndId $alertId -Properties @{ traversable = $false }))
    }

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Git-HoundAppInstallation
{
    <#
    .SYNOPSIS
        Retrieves repositories for a given GitHub App installation.
    
    .DESCRIPTION
        This function fetches GitHub App installations for the specified organization using the provided GitHound session and constructs nodes representing the installations.

        API Reference:
        - List app installations for an organization: https://docs.github.com/en/rest/orgs/orgs?apiVersion=2022-11-28#list-app-installations-for-an-organization

        Fine Grained Permissions Reference:
        - "Administration" organization permissions (read)

    .PARAMETER Session
        A GitHound session object used to authenticate and interact with the GitHub API.

    .PARAMETER Organization
        A PSObject representing the GitHub organization for which to retrieve GitHub App installations.

    .OUTPUTS
        A PSObject containing two properties: Nodes and Edges. Nodes is an array of GH_AppInstallation nodes, and Edges is an array of edges (currently empty).
    
    .EXAMPLE
        $session = New-GitHoundSession -Token "your_github_token"
        $organization = Get-GitHoundOrganization -Session $session -Login "your_org_login"
        $appInstallations = $organization | Git-HoundAppInstallation -Session $session
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $Organization
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    foreach($app in (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/installations").installations)
    {
        $properties = @{
            # Common Properties
            id                   = Normalize-Null $app.client_id
            name                 = Normalize-Null $app.app_slug
            # Relational Properties
            environment_name    = Normalize-Null $app.account.login
            environment_id      = Normalize-Null $app.account.node_id
            repositories_url     = Normalize-Null $app.repositories_url
            # Node Specific Properties
            repository_selection = Normalize-Null $app.repository_selection
            access_tokens_url    = Normalize-Null $app.access_tokens_url
            description          = Normalize-Null $app.description
            html_url             = Normalize-Null $app.html_url
            created_at           = Normalize-Null $app.created_at
            updated_at           = Normalize-Null $app.updated_at
            permissions          = Normalize-Null ($app.permissions | ConvertTo-Json -Depth 10)
            #events               = Normalize-Null ($app.events | ConvertTo-Json -Depth 10)
            # Accordion Panel Queries
        }

        $null = $nodes.Add((New-GitHoundNode -Id $app.client_id -Kind 'GH_AppInstallation' -Properties $properties))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $app.account.node_id -EndId $app.client_id -Properties @{ traversable = $false }))
    }

    Write-Output ([PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    })
}

function Git-HoundPersonalAccessToken
{
    <#
    .SYNOPSIS
        Retrieves fine-grained personal access tokens granted access to organization resources.

    .DESCRIPTION
        This function fetches fine-grained personal access tokens (PATs) that have been granted access
        to the specified organization. For each PAT, it creates a node and edges linking the PAT to its
        owner (GH_User), the organization (GH_Contains), and accessible repositories (GH_CanAccess).

        For PATs with repository_selection "subset", it makes an additional API call per PAT to enumerate
        the specific repositories. For PATs with repository_selection "all", it uses the pre-collected
        repository nodes to create edges.

        API Reference:
        - List fine-grained PATs with access to org resources: https://docs.github.com/en/rest/orgs/personal-access-tokens#list-fine-grained-personal-access-tokens-with-access-to-organization-resources
        - List repositories a fine-grained PAT has access to: https://docs.github.com/en/rest/orgs/personal-access-tokens#list-repositories-a-fine-grained-personal-access-token-has-access-to

        Fine Grained Permissions Reference:
        - "Personal access tokens" organization permissions (read)

    .PARAMETER Session
        A GitHound session object used to authenticate and interact with the GitHub API.

    .PARAMETER Organization
        A PSObject representing the GitHub organization node.

    .PARAMETER Repository
        Repository output from Git-HoundRepository. Used to resolve repo access edges for PATs
        with repository_selection "all".

    .OUTPUTS
        A PSObject containing two properties: Nodes and Edges.

    .EXAMPLE
        $pats = $repos | Git-HoundPersonalAccessToken -Session $session -Organization $org.nodes[0]
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true)]
        [PSObject]
        $Organization,

        [Parameter(Position = 2, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]
        $Repository
    )

    begin
    {
        $nodes = New-Object System.Collections.ArrayList
        $edges = New-Object System.Collections.ArrayList
        $repoNodes = New-Object System.Collections.ArrayList
    }

    process
    {
        $Repository.nodes | Where-Object { $_.kinds -eq 'GH_Repository' } | ForEach-Object {
            $null = $repoNodes.Add($_)
        }
    }

    end
    {
        $orgLogin = $Organization.properties.login
        $orgNodeId = $Organization.properties.node_id

        # Pre-compute all repo node IDs for "all" repository_selection
        $allRepoNodeIds = @($repoNodes | ForEach-Object { $_.properties.node_id })

        $pats = @(Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/personal-access-tokens")

        Write-Host "[*] Git-HoundPersonalAccessToken: Found $($pats.Count) fine-grained PATs"

        $subsetCount = 0
        $allCount = 0

        foreach ($pat in $pats) {
            $patId = "GH_PAT_$($orgNodeId)_$($pat.id)"

            $properties = @{
                # Common Properties
                id                   = Normalize-Null $patId
                name                 = Normalize-Null $pat.token_name
                # Relational Properties
                environment_name     = Normalize-Null $orgLogin
                environment_id       = Normalize-Null $orgNodeId
                owner_login          = Normalize-Null $pat.owner.login
                owner_id             = Normalize-Null $pat.owner.id
                owner_node_id        = Normalize-Null $pat.owner.node_id
                # Node Specific Properties
                token_id             = Normalize-Null $pat.token_id
                token_name           = Normalize-Null $pat.token_name
                token_expired        = Normalize-Null $pat.token_expired
                token_expires_at     = Normalize-Null $pat.token_expires_at
                token_last_used_at   = Normalize-Null $pat.token_last_used_at
                repository_selection = Normalize-Null $pat.repository_selection
                access_granted_at    = Normalize-Null $pat.access_granted_at
                permissions          = Normalize-Null ($pat.permissions | ConvertTo-Json -Depth 10)
                # Accordion Panel Queries
                query_organization_permissions = "MATCH p=(:GH_PersonalAccessToken {id: '$($patId)'})-[:GH_CanAccess]->(:GH_Organization) RETURN p"
                query_user                     = "MATCH p=(:GH_User)-[:GH_HasPersonalAccessToken]->(:GH_PersonalAccessToken {id: '$($patId)'}) RETURN p"
                query_repositories             = "MATCH p=(:GH_PersonalAccessToken {id: '$($patId)'})-[:GH_CanAccess]->(:GH_Repository) RETURN p LIMIT 1000"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $patId -Kind 'GH_PersonalAccessToken' -Properties $properties))

            # Edge: User owns the PAT
            if ($pat.owner.node_id) {
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasPersonalAccessToken' -StartId $pat.owner.node_id -EndId $patId -Properties @{ traversable = $false }))
            }

            # Edge: Org contains the PAT
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNodeId -EndId $patId -Properties @{ traversable = $false }))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanAccess' -StartId $patId -EndId $orgNodeId -Properties @{ traversable = $false }))

            # Repository access edges
            switch ($pat.repository_selection) {
                'all' {
                    $allCount++
                    foreach ($repoNodeId in $allRepoNodeIds) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanAccess' -StartId $patId -EndId $repoNodeId -Properties @{ traversable = $false }))
                    }
                }
                'subset' {
                    $subsetCount++
                    Write-Host "[*]   Fetching repositories for PAT '$($pat.token_name)' ($subsetCount subset PATs)"
                    $patRepos = @(Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/personal-access-tokens/$($pat.id)/repositories")
                    foreach ($repo in $patRepos) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanAccess' -StartId $patId -EndId $repo.node_id -Properties @{ traversable = $false }))
                    }
                }
            }
        }

        Write-Host "[+] Git-HoundPersonalAccessToken complete. $($nodes.Count) nodes, $($edges.Count) edges (all: $allCount, subset: $subsetCount)."

        Write-Output ([PSCustomObject]@{
            Nodes = $nodes
            Edges = $edges
        })
    }
}

function Git-HoundPersonalAccessTokenRequest
{
    <#
    .SYNOPSIS
        Retrieves pending fine-grained personal access token requests for organization resources.

    .DESCRIPTION
        This function fetches pending requests from organization members to access organization resources
        with fine-grained personal access tokens. For each request, it creates a node and edges linking
        the request to its owner (GH_User) and the organization (GH_Contains).

        API Reference:
        - List requests to access organization resources with fine-grained PATs: https://docs.github.com/en/rest/orgs/personal-access-token-requests#list-requests-to-access-organization-resources-with-fine-grained-personal-access-tokens

        Fine Grained Permissions Reference:
        - "Personal access token requests" organization permissions (read)

    .PARAMETER Session
        A GitHound session object used to authenticate and interact with the GitHub API.

    .PARAMETER Organization
        A PSObject representing the GitHub organization node.

    .OUTPUTS
        A PSObject containing two properties: Nodes and Edges.

    .EXAMPLE
        $patRequests = $org.nodes[0] | Git-HoundPersonalAccessTokenRequest -Session $session
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $Organization
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $orgLogin = $Organization.properties.login
    $orgNodeId = $Organization.properties.node_id

    $patRequests = @(Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/personal-access-token-requests")

    Write-Host "[*] Git-HoundPersonalAccessTokenRequest: Found $($patRequests.Count) pending PAT requests"

    foreach ($request in $patRequests) {
        $requestId = "GH_PATRequest_$($orgNodeId)_$($request.id)"

        $properties = @{
            # Common Properties
            id                   = Normalize-Null $requestId
            name                 = Normalize-Null $request.token_name
            # Relational Properties
            environment_name     = Normalize-Null $orgLogin
            environment_id       = Normalize-Null $orgNodeId
            owner_login          = Normalize-Null $request.owner.login
            owner_id             = Normalize-Null $request.owner.id
            owner_node_id        = Normalize-Null $request.owner.node_id
            # Node Specific Properties
            token_id             = Normalize-Null $request.token_id
            token_name           = Normalize-Null $request.token_name
            token_expired        = Normalize-Null $request.token_expired
            token_expires_at     = Normalize-Null $request.token_expires_at
            token_last_used_at   = Normalize-Null $request.token_last_used_at
            repository_selection = Normalize-Null $request.repository_selection
            reason               = Normalize-Null $request.reason
            created_at           = Normalize-Null $request.created_at
            permissions          = Normalize-Null ($request.permissions | ConvertTo-Json -Depth 10)
            # Accordion Panel Queries
            query_organization_permissions = "MATCH p=(:GH_PersonalAccessTokenRequest {id: '$($requestId)'})-[:GH_CanAccess]->(:GH_Organization) RETURN p"
            query_user                     = "MATCH p=(:GH_User)-[:GH_HasPersonalAccessTokenRequest]->(:GH_PersonalAccessTokenRequest {id: '$($requestId)'}) RETURN p"
            query_repositories             = "MATCH p=(:GH_PersonalAccessTokenRequest {id: '$($requestId)'})-[:GH_CanAccess]->(:GH_Repository) RETURN p LIMIT 1000"
        }

        $null = $nodes.Add((New-GitHoundNode -Id $requestId -Kind 'GH_PersonalAccessTokenRequest' -Properties $properties))

        # Edge: User owns the PAT request
        if ($request.owner.node_id) {
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasPersonalAccessTokenRequest' -StartId $request.owner.node_id -EndId $requestId -Properties @{ traversable = $false }))
        }

        # Edge: Org contains the PAT request
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNodeId -EndId $requestId -Properties @{ traversable = $false }))
    }

    Write-Host "[+] Git-HoundPersonalAccessTokenRequest complete. $($nodes.Count) nodes, $($edges.Count) edges."

    Write-Output ([PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    })
}

function Git-HoundScimUser
{
    <#
    .SYNOPSIS

    .DESCRIPTION

    #>

    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $startIndex = 1

    do
    {
        $result = [System.Text.Encoding]::ASCII.GetString((Invoke-GithubRestMethod -Session $Session -Path "scim/v2/organizations/$($Session.OrganizationName)/Users?startIndex=$($startIndex)")) | ConvertFrom-Json
        foreach($scimIdentity in $result.Resources)
        {
            $props = [pscustomobject]@{
                id = Normalize-Null $scimIdentity.id
                name = Normalize-Null $scimIdentity.externalId
                externalId = Normalize-Null $scimIdentity.externalId
                userName = Normalize-Null $scimIdentity.userName
                enabled = Normalize-Null $scimIdentity.active
                # displayName is not provided
                givenName = Normalize-Null $scimIdentity.name.givenName
                familyName = Normalize-Null $scimIdentity.name.familyName
                # middleName is not provided
                # honorificPrefix is not provided
                # honorificSuffix is not provided
                # title is not provided
                # userType is not provided
                profileUrl = Normalize-Null $scimIdentity.meta.location
                mail = Normalize-Null ($scimIdentity.emails | Where-Object { $_.primary -eq $true }).value
                # otherMails is not implemented
                # roles are provided but not implemented in GitHound graph yet
                # employeeNumber is not provided
                organization = $session.OrganizationName
                # department is not provided
                # managerId is not provided
                #created = Normalize-Null $scimIdentity.meta.created
                #lastModified = Normalize-Null $scimIdentity.meta.lastModified
                #schemas = Normalize-Null $scimIdentity.schemas
            }
            
            $null = $nodes.Add((New-GitHoundNode -Kind SCIM_User -Id $scimIdentity.id -Properties $props))
            $null = $edges.Add((New-GitHoundEdge -Kind SCIM_Provisioned -StartId $scimIdentity.id -EndId $scimIdentity.id -EndKind GH_ExternalIdentity -EndMatchBy name -Properties @{ traversable = $true }))
        }

        $startIndex = $result.startIndex + $result.itemsPerPage
    } while($startIndex -lt $result.totalResults)
    
    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Parse-GitHoundOIDCSubject
{
    <#
    .SYNOPSIS
        Parses GitHub OIDC subject claims from AZFederatedIdentityCredential nodes and creates CanAssumeIdentity edges.

    .DESCRIPTION
        This function processes AZFederatedIdentityCredential nodes that have GitHub OIDC subject claims
        (subjects beginning with "repo:") and creates CanAssumeIdentity edges from the appropriate GitHub
        node (GH_Branch, GH_Environment, or GH_Repository) to the AZFederatedIdentityCredential node.

        GitHub OIDC subject claim format: repo:{org}/{repo}:{qualifier}

        Supported qualifiers:
          - ref:refs/heads/{branch}    → GH_Branch    (name: {repo}\{branch})
          - ref:refs/tags/{tag}        → GH_Repository (name: {repo}) [tag-level not tracked, falls back to repo]
          - environment:{envName}      → GH_Environment (name: {repo}\{envName})
          - *                          → GH_Repository (name: {repo})
          - pull_request               → GH_Repository (name: {repo}) [PR-level not tracked, falls back to repo]
          - job_workflow_ref:{path}    → GH_Repository (name: {repo}) [workflow ref not tracked, falls back to repo]

    .PARAMETER FederatedIdentityCredentials
        An array of AZFederatedIdentityCredential node objects. Each node must have:
          - id: The objectid of the federated identity credential
          - properties.subject: The OIDC subject claim string

    .EXAMPLE
        $fidcNodes = @(
            [PSCustomObject]@{
                id = '6739d77d-ec59-468d-8505-bd9f9f139183'
                properties = @{ subject = 'repo:SpecterTst/oidc-actions-test-1:ref:refs/heads/prod' }
            }
        )
        $result = Parse-GitHoundOIDCSubject -FederatedIdentityCredentials $fidcNodes
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSObject[]]
        $FederatedIdentityCredentials
    )

    $edges = New-Object System.Collections.ArrayList

    $ghSubjects = @($FederatedIdentityCredentials | Where-Object { $_.properties.subject -like 'repo:*' })

    if($ghSubjects.Count -eq 0)
    {
        Write-Host "[*] OIDC Subject Parser: No GitHub OIDC subjects found"
        Write-Output ([PSCustomObject]@{
            Nodes = @()
            Edges = $edges
        })
        return
    }

    Write-Host "[*] OIDC Subject Parser: Processing $($ghSubjects.Count) GitHub OIDC subject(s)"

    $parsed = 0
    $skipped = 0

    foreach($fidc in $ghSubjects)
    {
        $subject = $fidc.properties.subject
        $fidcId = $fidc.id

        # Parse: repo:{org}/{repo}:{qualifier}
        # The subject always starts with "repo:" and the org/repo is separated by "/"
        # The qualifier follows after the second ":"
        $withoutPrefix = $subject.Substring(5)  # Remove "repo:"
        $slashIndex = $withoutPrefix.IndexOf('/')
        if($slashIndex -lt 0)
        {
            Write-Verbose "OIDC Subject Parser: Skipping malformed subject (no org/repo separator): $subject"
            $skipped++
            continue
        }

        $org = $withoutPrefix.Substring(0, $slashIndex)
        $remainder = $withoutPrefix.Substring($slashIndex + 1)

        # Find the colon that separates repo from qualifier
        $colonIndex = $remainder.IndexOf(':')
        if($colonIndex -lt 0)
        {
            Write-Verbose "OIDC Subject Parser: Skipping malformed subject (no qualifier separator): $subject"
            $skipped++
            continue
        }

        $repo = $remainder.Substring(0, $colonIndex)
        $qualifier = $remainder.Substring($colonIndex + 1)

        # Determine the start node kind and value based on the qualifier
        $startKind = $null
        $startValue = $null

        switch -Wildcard ($qualifier)
        {
            'ref:refs/heads/*' {
                # Branch reference: repo:{org}/{repo}:ref:refs/heads/{branch}
                $branch = $qualifier.Substring(15)  # Remove "ref:refs/heads/"
                $startKind = 'GH_Branch'
                $startValue = "$repo\$branch"
                break
            }
            'environment:*' {
                # Environment reference: repo:{org}/{repo}:environment:{envName}
                $envName = $qualifier.Substring(12)  # Remove "environment:"
                $startKind = 'GH_Environment'
                $startValue = "$repo\$envName"
                break
            }
            default {
                # Wildcard or any other qualifier falls back to repository
                # This handles: *, pull_request, ref:refs/tags/*, job_workflow_ref:*, etc.
                $startKind = 'GH_Repository'
                $startValue = $repo
            }
        }

        if($null -eq $startKind)
        {
            Write-Verbose "OIDC Subject Parser: Skipping unrecognized qualifier in subject: $subject"
            $skipped++
            continue
        }

        $null = $edges.Add((New-GitHoundEdge `
            -Kind 'CanAssumeIdentity' `
            -StartId $startValue `
            -StartKind $startKind `
            -StartMatchBy 'name' `
            -EndId $fidcId `
            -EndKind 'AZFederatedIdentityCredential' `
            -Properties @{
                traversable = $true
                subject     = $subject
            }
        ))

        $parsed++
    }

    Write-Host "[*] OIDC Subject Parser: Created $parsed edge(s), skipped $skipped subject(s)"

    Write-Output ([PSCustomObject]@{
        Nodes = @()
        Edges = $edges
    })
}

# This is a second order data type after GH_Organization
function Git-HoundGraphQlSamlProvider
{
    <#
    
    #>
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    $Query = @'
query SAML($login: String!, $count: Int = 100, $after: String = null) {
    organization(login: $login) {
        id
        name
        samlIdentityProvider
        {
            digestMethod
            externalIdentities(first: $count, after: $after)
            {
                nodes
                {
                    guid
                    id
                    samlIdentity
                    {
                        attributes
                        {
                            metadata
                            name
                            value
                        }
                        familyName
                        givenName
                        groups
                        nameId
                        username
                    }
                    scimIdentity
                    {
                        emails
                        {
                            primary
                            type
                            value
                        }
                        familyName
                        givenName
                        groups
                        username
                    }
                    user
                    {
                        id
                        login
                    }
                }
                pageInfo
                {
                    endCursor
                    hasNextPage
                }
                totalCount
            }
            id
            idpCertificate
            issuer
            signatureMethod
            ssoUrl
        }
    }
}
'@

    $Variables = @{
        login = $Session.OrganizationName
        count = 100
        after = $null
    }
    
    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    do{
        $result = Invoke-GitHubGraphQL -Headers $Session.Headers -Query $Query -Variables $Variables -Session $Session

        if($result.data.organization.samlIdentityProvider.id -ne $null)
        {
            # We must first understand which type of identity provider we are dealing with to create the correct foreign identity nodes and edges
            # One issue with this approach is in cases where the IdP has changed and old external identities are still present, the issuer may not match the current IdP
            # Supported identity providers (IdPs) for SAML SSO with GitHub Organizations: AD FS, Microsoft Entra ID (Azure AD), Okta, OneLogin, PingOne, Shibboleth.
            # In all of these examples, we should also get the IdP tenant information from the Issuer field to reduce collisions
            switch -Wildcard ($result.data.organization.samlIdentityProvider.issuer)
            {
                # The identity provider is PingOne
                'https://auth.pingone.com/*' {
                    $ForeignUserNodeKind = 'PingOneUser'
                    $ForeginEnvironmentNodeKind = 'PingOneOrganization'
                    $ForeignEnvironmentId = $result.data.organization.samlIdentityProvider.issuer.Split('/')[3]
                }
                # The identity provider is Entra ID
                'https://sts.windows.net/*' {
                    $ForeignUserNodeKind = 'AZUser'
                    $ForeginEnvironmentNodeKind = 'AZTenant'
                    $ForeignEnvironmentId = $result.data.organization.samlIdentityProvider.issuer.Split('/')[3]
                }
                # The identity provider is Okta
                # This is particularly tested with SAML SSO from Okta to GitHub Organization only (GitHub Enterprise Cloud - Organization)
                # It has not been tested with GitHub Enterprise Managed Users (aka SCIM implementations)
                'http://www.okta.com/*'
                {
                    $ForeignUserNodeKind = 'OktaUser'
                    $ForeginEnvironmentNodeKind = 'OktaOrganization'
                    $ForeignEnvironmentId = $result.data.organization.samlIdentityProvider.ssoUrl.Split('/')[2]
                    #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_SyncedToEnvironment' -StartId $result.data.organization.samlIdentityProvider.id -EndId $ForeignEnvironmentName -EndKind $ForeginEnvironmentNodeKind -EndMatchBy name -Properties @{traversable=$false}))
                }
                default { Write-Verbose "Issuer: $($_)"; break }
            }

            # Add the identity provider node and associate it with the organization
            # This helps to easily identify the active SAML identity provider for the organization and its associated external identities
            $identityProviderProps = [pscustomobject]@{
                # Common Properties
                name                      = $result.data.organization.samlIdentityProvider.id
                node_id                   = $result.data.organization.samlIdentityProvider.id
                # Relational Properties
                environment_name         = $result.data.organization.name
                environment_id           = $result.data.organization.id
                foreign_environment_id   = $ForeignEnvironmentId
                # Node Specific Properties
                digest_method             = $result.data.organization.samlIdentityProvider.digestMethod
                idp_certificate           = $result.data.organization.samlIdentityProvider.idpCertificate
                issuer                    = $result.data.organization.samlIdentityProvider.issuer
                signature_method          = $result.data.organization.samlIdentityProvider.signatureMethod
                sso_url                   = $result.data.organization.samlIdentityProvider.ssoUrl
                # Accordion Panel Queries
                query_environments        = "MATCH p=(:GH_SamlIdentityProvider {objectid: '$($result.data.organization.samlIdentityProvider.id.ToUpper())'})<-[:GH_HasSamlIdentityProvider]->(:GH_Organization) RETURN p"
                query_external_identities = "MATCH p=(:GH_SamlIdentityProvider {objectid: '$($result.data.organization.samlIdentityProvider.id.ToUpper())'})-[:GH_HasExternalIdentity]->() RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $result.data.organization.samlIdentityProvider.id -Kind 'GH_SamlIdentityProvider' -Properties $identityProviderProps))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSamlIdentityProvider' -StartId $result.data.organization.id -EndId $result.data.organization.samlIdentityProvider.id -Properties @{traversable=$false}))

            # Iterate through each External Identity and create GH_ExternalIdentity Nodes and relevant Edges
            foreach($identity in $result.data.organization.samlIdentityProvider.externalIdentities.nodes)
            {
                # Create GH_ExternalIdentity Node and Connect it to GH_SamlIdentityProvider Node via GH_HasExternalIdentity Edge
                # We may discover in the future that we need to capture more properties from the external identity

                $EIprops = [pscustomobject]@{
                    # Common Properties
                    name                      = Normalize-Null $identity.guid
                    guid                      = Normalize-Null $identity.guid
                    # Relational Properties
                    environment_id           = Normalize-Null $result.data.organization.id
                    environment_name         = Normalize-Null $result.data.organization.name
                    # Node Specific Properties
                    saml_identity_family_name = Normalize-Null $identity.samlIdentity.familyName
                    saml_identity_given_name  = Normalize-Null $identity.samlIdentity.givenName
                    saml_identity_name_id     = Normalize-Null $identity.samlIdentity.nameId
                    saml_identity_username    = Normalize-Null $identity.samlIdentity.username
                    scim_identity_family_name = Normalize-Null $identity.scimIdentity.familyName
                    scim_identity_given_name  = Normalize-Null $identity.scimIdentity.givenName
                    scim_identity_username    = Normalize-Null $identity.scimIdentity.username
                    github_username           = Normalize-Null $(if ($identity.user) { $identity.user.login } else { $null })
                    github_user_id            = Normalize-Null $(if ($identity.user) { $identity.user.id } else { $null })
                    # Accordion Panel Queries
                    query_mapped_users = "MATCH p=(:GH_ExternalIdentity {objectid: '$($identity.id.ToUpper())'})-[:GH_MapsToUser]->() RETURN p"
                }

                $null = $nodes.Add((New-GitHoundNode -Id $identity.id -Kind 'GH_ExternalIdentity' -Properties $EIprops))
                $null = $edges.Add((New-GitHoundEdge -Kind GH_HasExternalIdentity -StartId $result.data.organization.samlIdentityProvider.id -EndId $identity.id -Properties @{traversable=$false}))
                
                if($identity.samlIdentity.username -ne $null)
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GH_MapsToUser -StartId $identity.id -EndId $identity.samlIdentity.username -EndKind $ForeignUserNodeKind -EndMatchBy name -Properties @{traversable=$false}))
                }
                elseif($identity.scimIdentity.username -ne $null)
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GH_MapsToUser -StartId $identity.id -EndId $identity.scimIdentity.username -EndKind $ForeignUserNodeKind -EndMatchBy name -Properties @{traversable=$false}))
                }

                if($identity.user -ne $null -and $identity.user.id -ne $null)
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GH_MapsToUser -StartId $identity.id -EndId $identity.user.id -Properties @{traversable=$false}))
                    
                    # Create SyncedToGHUser Edge from Foreign Identity to GH_User
                    # This might need to be something that happens during post-processing since we do not control whether the foreign user node already exists in the graph
                    $null = $edges.Add((New-GitHoundEdge -Kind SyncedToGHUser -StartId $identity.samlIdentity.username -StartKind $ForeignUserNodeKind -StartMatchBy name -EndId $identity.user.id -Properties @{traversable=$true; composition="MATCH p=()<-[:GH_SyncedToEnvironment]-(:GH_SamlIdentityProvider)-[:GH_HasExternalIdentity]->(:GH_ExternalIdentity)-[:GH_MapsToUser]->(n) WHERE n.objectid = '$($identity.user.id.ToUpper())' OR n.name = '$($identity.samlIdentity.username.ToUpper())' RETURN p"}))
                }
            }
        }

        $Variables['after'] = $result.data.organization.samlIdentityProvider.externalIdentities.pageInfo.endCursor
    }
    while($result.data.organization.samlIdentityProvider.externalIdentities.pageInfo.hasNextPage)

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Invoke-GitHound
{
    <#
    .SYNOPSIS
        Orchestrates a full GitHound collection for an organization.

    .DESCRIPTION
        Runs all collection functions sequentially, writing per-step output files to disk after each step.
        Supports crash recovery via the -Resume switch: if a per-step file already exists on disk, that
        step is loaded from the file instead of re-collected.

        The final consolidated payload is written to githound_<orgId>.json, combining all per-step data
        (except SAML/OIDC which remain in separate files).

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER CheckpointPath
        Directory for per-step output files and intermediate checkpoints. Defaults to the current directory.

    .PARAMETER Resume
        When set, detects existing per-step output files and skips completed steps instead of re-collecting.

    .PARAMETER CleanupIntermediates
        When set, deletes per-step output files after the final consolidated payload is written.

    .EXAMPLE
        Invoke-GitHound -Session $Session

    .EXAMPLE
        # Resume after a crash
        Invoke-GitHound -Session $Session -Resume

    .EXAMPLE
        # Resume and clean up per-step files after consolidation
        Invoke-GitHound -Session $Session -Resume -CleanupIntermediates
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter()]
        [string]
        $CheckpointPath = ".",

        [Parameter()]
        [switch]
        $Resume,

        [Parameter()]
        [switch]
        $CleanupIntermediates,

        [Parameter()]
        [switch]
        $CollectAll
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $Global:GitHoundFunctionBundle = Get-GitHoundFunctionBundle

    Write-Host "[*] Starting GitHound for $($Session.OrganizationName)"

    # ── Step 1: Organization ───────────────────────────────────────────────
    # Bootstrap: discover org ID for file naming. Check for existing file first on resume.
    $orgId = $null
    if ($Resume) {
        $orgFiles = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Organization_*.json" -ErrorAction SilentlyContinue)
        if ($orgFiles.Count -eq 1) {
            $org = Import-GitHoundStepOutput -FilePath $orgFiles[0].FullName
            if ($org) {
                $orgId = $org.nodes[0].id
                Write-Host "[*] Resuming: Loaded Organization from $($orgFiles[0].Name)"
            }
        }
    }

    if (-not $orgId) {
        Write-Host "[*] Enumerating Organization"
        $org = Git-HoundOrganization -Session $Session
        $orgId = $org.nodes[0].id
        Export-GitHoundStepOutput -StepResult $org -FilePath (Join-Path $CheckpointPath "githound_Organization_$orgId.json")
        Write-Host "[+] Saved: githound_Organization_$orgId.json"
    }

    if($org.nodes) { $nodes.AddRange(@($org.nodes)) }
    if($org.edges) { $edges.AddRange(@($org.edges)) }

    # ── Step 2: Users ──────────────────────────────────────────────────────
    $stepFile = Join-Path $CheckpointPath "githound_User_$orgId.json"
    if ($Resume -and (Test-Path $stepFile)) {
        Write-Host "[*] Resuming: Loaded Users from githound_User_$orgId.json"
        $users = Import-GitHoundStepOutput -FilePath $stepFile
    } else {
        Write-Host "[*] Enumerating Organization Users"
        $users = $org.nodes[0] | Git-HoundUser -Session $Session
        Export-GitHoundStepOutput -StepResult $users -FilePath $stepFile
        Write-Host "[+] Saved: githound_User_$orgId.json"
    }
    if($users.nodes) { $nodes.AddRange(@($users.nodes)) }
    if($users.edges) { $edges.AddRange(@($users.edges)) }

    # ── Step 3: Teams ──────────────────────────────────────────────────────
    $stepFile = Join-Path $CheckpointPath "githound_Team_$orgId.json"
    if ($Resume -and (Test-Path $stepFile)) {
        Write-Host "[*] Resuming: Loaded Teams from githound_Team_$orgId.json"
        $teams = Import-GitHoundStepOutput -FilePath $stepFile
    } else {
        Write-Host "[*] Enumerating Organization Teams"
        $teams = $org.nodes[0] | Git-HoundTeam -Session $Session
        Export-GitHoundStepOutput -StepResult $teams -FilePath $stepFile
        Write-Host "[+] Saved: githound_Team_$orgId.json"
    }
    if($teams.nodes) { $nodes.AddRange(@($teams.nodes)) }
    if($teams.edges) { $edges.AddRange(@($teams.edges)) }

    # ── Step 4: Repositories ──────────────────────────────────────────────
    $stepFile = Join-Path $CheckpointPath "githound_Repository_$orgId.json"
    if ($Resume -and (Test-Path $stepFile)) {
        Write-Host "[*] Resuming: Loaded Repositories from githound_Repository_$orgId.json"
        $repos = Import-GitHoundStepOutput -FilePath $stepFile
    } else {
        Write-Host "[*] Enumerating Organization Repositories"
        $repos = $org.nodes[0] | Git-HoundRepository -Session $Session
        Export-GitHoundStepOutput -StepResult $repos -FilePath $stepFile
        Write-Host "[+] Saved: githound_Repository_$orgId.json"
    }
    if($repos.nodes) { $nodes.AddRange(@($repos.nodes)) }
    if($repos.edges) { $edges.AddRange(@($repos.edges)) }

    # ── Step 5: Repository Roles ──────────────────────────────────────────
    # Check for per-step file, then _complete.json from internal checkpointing
    $stepFile = Join-Path $CheckpointPath "githound_RepoRole_$orgId.json"
    $completeFile = Join-Path $CheckpointPath "githound_RepoRole_complete.json"
    if ($Resume -and (Test-Path $stepFile)) {
        Write-Host "[*] Resuming: Loaded Repository Roles from githound_RepoRole_$orgId.json"
        $reporoles = Import-GitHoundStepOutput -FilePath $stepFile
    } elseif ($Resume -and (Test-Path $completeFile)) {
        Write-Host "[*] Resuming: Found RepoRole complete file, converting to per-step output"
        $reporoles = Import-GitHoundStepOutput -FilePath $completeFile
        Export-GitHoundStepOutput -StepResult $reporoles -FilePath $stepFile
        Write-Host "[+] Saved: githound_RepoRole_$orgId.json"
    } else {
        Write-Host "[*] Enumerating Repository Roles"
        $reporoles = $repos | Git-HoundRepositoryRole -Session $Session -CheckpointPath $CheckpointPath
        Export-GitHoundStepOutput -StepResult $reporoles -FilePath $stepFile
        Write-Host "[+] Saved: githound_RepoRole_$orgId.json"
    }
    if($reporoles.nodes) { $nodes.AddRange(@($reporoles.nodes)) }
    if($reporoles.edges) { $edges.AddRange(@($reporoles.edges)) }

    # ── Step 6: Branches ──────────────────────────────────────────────────
    $stepFile = Join-Path $CheckpointPath "githound_Branch_$orgId.json"
    $completeFile = Join-Path $CheckpointPath "githound_Branch_complete.json"
    if ($Resume -and (Test-Path $stepFile)) {
        Write-Host "[*] Resuming: Loaded Branches from githound_Branch_$orgId.json"
        $branches = Import-GitHoundStepOutput -FilePath $stepFile
    } elseif ($Resume -and (Test-Path $completeFile)) {
        Write-Host "[*] Resuming: Found Branch complete file, converting to per-step output"
        $branches = Import-GitHoundStepOutput -FilePath $completeFile
        Export-GitHoundStepOutput -StepResult $branches -FilePath $stepFile
        Write-Host "[+] Saved: githound_Branch_$orgId.json"
    } else {
        Write-Host "[*] Enumerating Organization Branches"
        $branches = $org.nodes[0] | Git-HoundBranch -Session $Session -CheckpointPath $CheckpointPath
        Export-GitHoundStepOutput -StepResult $branches -FilePath $stepFile
        Write-Host "[+] Saved: githound_Branch_$orgId.json"
    }
    if($branches.nodes) { $nodes.AddRange(@($branches.nodes)) }
    if($branches.edges) { $edges.AddRange(@($branches.edges)) }

    # ── Step 7: Workflows (requires -CollectAll) ────────────────────────────
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_Workflow_$orgId.json"
        $completeFile = Join-Path $CheckpointPath "githound_Workflow_complete.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded Workflows from githound_Workflow_$orgId.json"
            $workflows = Import-GitHoundStepOutput -FilePath $stepFile
        } elseif ($Resume -and (Test-Path $completeFile)) {
            Write-Host "[*] Resuming: Found Workflow complete file, converting to per-step output"
            $workflows = Import-GitHoundStepOutput -FilePath $completeFile
            Export-GitHoundStepOutput -StepResult $workflows -FilePath $stepFile
            Write-Host "[+] Saved: githound_Workflow_$orgId.json"
        } else {
            Write-Host "[*] Enumerating Organization Workflows"
            $workflows = $repos | Git-HoundWorkflow -Session $Session -CheckpointPath $CheckpointPath
            Export-GitHoundStepOutput -StepResult $workflows -FilePath $stepFile
            Write-Host "[+] Saved: githound_Workflow_$orgId.json"
        }
        if($workflows.nodes) { $nodes.AddRange(@($workflows.nodes)) }
        if($workflows.edges) { $edges.AddRange(@($workflows.edges)) }
    } else {
        Write-Host "[*] Skipping Workflows (use -CollectAll to include)"
    }

    # ── Step 8: Environments (requires -CollectAll) ───────────────────────
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_Environment_$orgId.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded Environments from githound_Environment_$orgId.json"
            $environments = Import-GitHoundStepOutput -FilePath $stepFile
        } else {
            Write-Host "[*] Enumerating Organization Environments"
            $environments = $repos | Git-HoundEnvironment -Session $Session
            Export-GitHoundStepOutput -StepResult $environments -FilePath $stepFile
            Write-Host "[+] Saved: githound_Environment_$orgId.json"
        }
        if($environments.nodes) { $nodes.AddRange(@($environments.nodes)) }
        if($environments.edges) { $edges.AddRange(@($environments.edges)) }
    } else {
        Write-Host "[*] Skipping Environments (use -CollectAll to include)"
    }

    # ── Step 9: Organization Secrets ───────────────────────────────────────
    $stepFile = Join-Path $CheckpointPath "githound_OrgSecret_$orgId.json"
    if ($Resume -and (Test-Path $stepFile)) {
        Write-Host "[*] Resuming: Loaded Organization Secrets from githound_OrgSecret_$orgId.json"
        $orgsecrets = Import-GitHoundStepOutput -FilePath $stepFile
    } else {
        Write-Host "[*] Enumerating Organization Secrets"
        $orgsecrets = $repos | Git-HoundOrganizationSecret -Session $Session
        Export-GitHoundStepOutput -StepResult $orgsecrets -FilePath $stepFile
        Write-Host "[+] Saved: githound_OrgSecret_$orgId.json"
    }
    if($orgsecrets.nodes) { $nodes.AddRange(@($orgsecrets.nodes)) }
    if($orgsecrets.edges) { $edges.AddRange(@($orgsecrets.edges)) }

    # ── Step 10: Repository Secrets (requires -CollectAll) ─────────────────
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_Secret_$orgId.json"
        $completeFile = Join-Path $CheckpointPath "githound_Secret_complete.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded Repository Secrets from githound_Secret_$orgId.json"
            $secrets = Import-GitHoundStepOutput -FilePath $stepFile
        } elseif ($Resume -and (Test-Path $completeFile)) {
            Write-Host "[*] Resuming: Found Secret complete file, converting to per-step output"
            $secrets = Import-GitHoundStepOutput -FilePath $completeFile
            Export-GitHoundStepOutput -StepResult $secrets -FilePath $stepFile
            Write-Host "[+] Saved: githound_Secret_$orgId.json"
        } else {
            Write-Host "[*] Enumerating Repository Secrets"
            $secrets = $repos | Git-HoundSecret -Session $Session -CheckpointPath $CheckpointPath
            Export-GitHoundStepOutput -StepResult $secrets -FilePath $stepFile
            Write-Host "[+] Saved: githound_Secret_$orgId.json"
        }
        if($secrets.nodes) { $nodes.AddRange(@($secrets.nodes)) }
        if($secrets.edges) { $edges.AddRange(@($secrets.edges)) }
    } else {
        Write-Host "[*] Skipping Repository Secrets (use -CollectAll to include)"
    }

    # ── Step 11: Secret Scanning Alerts ─────────────────────────────────
    $stepFile = Join-Path $CheckpointPath "githound_SecretAlerts_$orgId.json"
    if ($Resume -and (Test-Path $stepFile)) {
        Write-Host "[*] Resuming: Loaded Secret Scanning Alerts from githound_SecretAlerts_$orgId.json"
        $secretalerts = Import-GitHoundStepOutput -FilePath $stepFile
    } else {
        Write-Host "[*] Enumerating Secret Scanning Alerts"
        $secretalerts = $org.nodes[0] | Git-HoundSecretScanningAlert -Session $Session
        Export-GitHoundStepOutput -StepResult $secretalerts -FilePath $stepFile
        Write-Host "[+] Saved: githound_SecretAlerts_$orgId.json"
    }
    if($secretalerts.nodes) { $nodes.AddRange(@($secretalerts.nodes)) }
    if($secretalerts.edges) { $edges.AddRange(@($secretalerts.edges)) }

    # ── Step 12: App Installations (requires -CollectAll) ──────────────────
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_AppInstallation_$orgId.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded App Installations from githound_AppInstallation_$orgId.json"
            $appInstallations = Import-GitHoundStepOutput -FilePath $stepFile
        } else {
            Write-Host "[*] Enumerating App Installations"
            $appInstallations = $org.nodes[0] | Git-HoundAppInstallation -Session $Session
            Export-GitHoundStepOutput -StepResult $appInstallations -FilePath $stepFile
            Write-Host "[+] Saved: githound_AppInstallation_$orgId.json"
        }
        if($appInstallations.nodes) { $nodes.AddRange(@($appInstallations.nodes)) }
        if($appInstallations.edges) { $edges.AddRange(@($appInstallations.edges)) }
    } else {
        Write-Host "[*] Skipping App Installations (use -CollectAll to include)"
    }

    # ── Step 13: Personal Access Tokens (requires -CollectAll) ──────────
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_PersonalAccessToken_$orgId.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded Personal Access Tokens from githound_PersonalAccessToken_$orgId.json"
            $personalAccessTokens = Import-GitHoundStepOutput -FilePath $stepFile
        } else {
            Write-Host "[*] Enumerating Personal Access Tokens"
            $personalAccessTokens = $repos | Git-HoundPersonalAccessToken -Session $Session -Organization $org.nodes[0]
            Export-GitHoundStepOutput -StepResult $personalAccessTokens -FilePath $stepFile
            Write-Host "[+] Saved: githound_PersonalAccessToken_$orgId.json"
        }
        if($personalAccessTokens.nodes) { $nodes.AddRange(@($personalAccessTokens.nodes)) }
        if($personalAccessTokens.edges) { $edges.AddRange(@($personalAccessTokens.edges)) }
    } else {
        Write-Host "[*] Skipping Personal Access Tokens (use -CollectAll to include)"
    }

    # ── Step 14: Personal Access Token Requests (requires -CollectAll) ──
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_PersonalAccessTokenRequest_$orgId.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded Personal Access Token Requests from githound_PersonalAccessTokenRequest_$orgId.json"
            $personalAccessTokenRequests = Import-GitHoundStepOutput -FilePath $stepFile
        } else {
            Write-Host "[*] Enumerating Personal Access Token Requests"
            $personalAccessTokenRequests = $org.nodes[0] | Git-HoundPersonalAccessTokenRequest -Session $Session
            Export-GitHoundStepOutput -StepResult $personalAccessTokenRequests -FilePath $stepFile
            Write-Host "[+] Saved: githound_PersonalAccessTokenRequest_$orgId.json"
        }
        if($personalAccessTokenRequests.nodes) { $nodes.AddRange(@($personalAccessTokenRequests.nodes)) }
        if($personalAccessTokenRequests.edges) { $edges.AddRange(@($personalAccessTokenRequests.edges)) }
    } else {
        Write-Host "[*] Skipping Personal Access Token Requests (use -CollectAll to include)"
    }

    # ── Final Consolidation ───────────────────────────────────────────────
    Write-Host "[*] Consolidating to OpenGraph JSON Payload"
    # Filter out any null entries that may have been introduced by thread-safety issues or API errors
    $filteredNodes = @($nodes | Where-Object { $_ -ne $null })
    $filteredEdges = @($edges | Where-Object { $_ -ne $null })
    $nullNodes = $nodes.Count - $filteredNodes.Count
    $nullEdges = $edges.Count - $filteredEdges.Count
    if ($nullNodes -gt 0 -or $nullEdges -gt 0) {
        Write-Warning "Filtered out $nullNodes null node(s) and $nullEdges null edge(s) from payload"
    }
    $consolidatedFile = Join-Path $CheckpointPath "githound_$orgId.json"
    $payload = [PSCustomObject]@{
        '$schema' = "https://raw.githubusercontent.com/MichaelGrafnetter/EntraAuthPolicyHound/refs/heads/main/bloodhound-opengraph.schema.json"
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $filteredNodes
            edges = $filteredEdges
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath $consolidatedFile
    Write-Host "[+] Consolidated payload: $consolidatedFile ($($filteredNodes.Count) nodes, $($filteredEdges.Count) edges)"

    # ── Cleanup Intermediates ─────────────────────────────────────────────
    if ($CleanupIntermediates) {
        $stepFileNames = @(
            "githound_Organization_$orgId.json",
            "githound_User_$orgId.json",
            "githound_Team_$orgId.json",
            "githound_Repository_$orgId.json",
            "githound_RepoRole_$orgId.json",
            "githound_Branch_$orgId.json",
            "githound_Workflow_$orgId.json",
            "githound_Environment_$orgId.json",
            "githound_OrgSecret_$orgId.json",
            "githound_Secret_$orgId.json",
            "githound_SecretAlerts_$orgId.json",
            "githound_AppInstallation_$orgId.json",
            "githound_PersonalAccessToken_$orgId.json",
            "githound_PersonalAccessTokenRequest_$orgId.json"
        )
        $completeFilePatterns = @(
            "githound_RepoRole_complete.json",
            "githound_Branch_complete.json",
            "githound_Workflow_complete.json",
            "githound_Secret_complete.json"
        )
        $cleanedCount = 0
        foreach ($fileName in ($stepFileNames + $completeFilePatterns)) {
            $filePath = Join-Path $CheckpointPath $fileName
            if (Test-Path $filePath) {
                Remove-Item $filePath -Force
                $cleanedCount++
            }
        }
        if ($cleanedCount -gt 0) {
            Write-Host "[+] Cleaned up $cleanedCount intermediate file(s)."
        }
    }

    # ── SAML (separate output, not included in consolidated payload) ──────
    Write-Host "[*] Enumerating SAML Identity Provider"
    $samlNodes = New-Object System.Collections.ArrayList
    $samlEdges = New-Object System.Collections.ArrayList
    $saml = Git-HoundGraphQlSamlProvider -Session $Session
    if($saml.nodes) { $samlNodes.AddRange(@($saml.nodes)) }
    if($saml.edges) { $samlEdges.AddRange(@($saml.edges)) }

    $payload = [PSCustomObject]@{
        graph = [PSCustomObject]@{
            nodes = @($samlNodes | Where-Object { $_ -ne $null })
            edges = @($samlEdges | Where-Object { $_ -ne $null })
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $CheckpointPath "githound_saml_$orgId.json")

    # ── SCIM (separate output, not included in consolidated payload) ──────
    if ($CollectAll) {
        Write-Host "[*] Enumerating SCIM Users"
        $scimNodes = New-Object System.Collections.ArrayList
        $scimEdges = New-Object System.Collections.ArrayList
        $scim = Git-HoundScimUser -Session $Session
        if($scim.nodes) { $scimNodes.AddRange(@($scim.nodes)) }
        if($scim.edges) { $scimEdges.AddRange(@($scim.edges)) }

        $payload = [PSCustomObject]@{
            graph = [PSCustomObject]@{
                nodes = @($scimNodes | Where-Object { $_ -ne $null })
                edges = @($scimEdges | Where-Object { $_ -ne $null })
            }
        } | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $CheckpointPath "githound_scim_$orgId.json")
        Write-Host "[+] SCIM payload: githound_scim_$orgId.json ($($scimNodes.Count) nodes, $($scimEdges.Count) edges)"
    } else {
        Write-Host "[*] Skipping SCIM Users (use -CollectAll to include)"
    }

    # ── OIDC (separate output, not included in consolidated payload) ──────
    $fidcJsonPath = Join-Path $CheckpointPath "azurehound_federatedidentitycredentials.json"
    if(Test-Path $fidcJsonPath)
    {
        Write-Host "[*] Parsing GitHub OIDC Subjects from Federated Identity Credentials"
        $fidcData = Get-Content $fidcJsonPath -Raw | ConvertFrom-Json
        $fidcNodes = @($fidcData.graph.nodes | Where-Object { $_.kind -contains 'AZFederatedIdentityCredential' })
        if($fidcNodes.Count -gt 0)
        {
            $oidc = Parse-GitHoundOIDCSubject -FederatedIdentityCredentials $fidcNodes
            if($oidc.edges.Count -gt 0)
            {
                $payload = [PSCustomObject]@{
                    graph = [PSCustomObject]@{
                        nodes = @()
                        edges = @($oidc.Edges | Where-Object { $_ -ne $null })
                    }
                } | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $CheckpointPath "githound_oidc_$orgId.json")
            }
        }
    }
    else
    {
        Write-Host "[*] Skipping OIDC Subject Parsing (no federated identity credential data found at $fidcJsonPath)"
        Write-Host "    To enable, provide AZFederatedIdentityCredential data in: $fidcJsonPath"
    }

    Write-Host "[+] GitHound collection complete for $($Session.OrganizationName)."
}