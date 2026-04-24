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
        'ConvertTo-PascalCase',
        'New-BHOGPropertyMatcher',
        'Get-GitHoundOrganizationTeamPropertyMatchers'
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
        [Parameter(Position=0, Mandatory = $false)]
        [string]
        $OrganizationName,

        [Parameter(Mandatory = $false)]
        [string]
        $EnterpriseName,

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
        $Headers = @{},

        [Parameter(Mandatory = $false)]
        [HashTable]
        $JwtHeaders,

        [Parameter(Mandatory = $false)]
        [HashTable]
        $PatHeaders,

        [Parameter(Mandatory = $false)]
        [string]
        $ClientId,

        [Parameter(Mandatory = $false)]
        [string]
        $InstallationId,

        [Parameter(Mandatory = $false)]
        [string]
        $PrivateKeyPath
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
        EnterpriseName = $EnterpriseName
        JwtHeaders = $JwtHeaders
        PatHeaders = $PatHeaders
        ClientId = $ClientId
        InstallationId = $InstallationId
        PrivateKeyPath = $PrivateKeyPath
        HasPersonalAccessToken = ($null -ne $PatHeaders)
        TargetType = if ($EnterpriseName) { 'Enterprise' } elseif ($OrganizationName) { 'Organization' } else { 'Application' }
    }
}

function Get-GitHoundAuthHeaders
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter()]
        [ValidateSet('App', 'JWT', 'PAT')]
        [string]
        $AuthType = 'App'
    )

    switch ($AuthType) {
        'App' {
            if (-not $Session.Headers) { throw "Session does not contain app installation headers." }
            return $Session.Headers
        }
        'JWT' {
            if (-not $Session.JwtHeaders) { throw "Session does not contain JWT headers." }
            return $Session.JwtHeaders
        }
        'PAT' {
            if (-not $Session.PatHeaders) { throw "Session does not contain PAT headers." }
            return $Session.PatHeaders
        }
    }
}

# Reference: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app#example-using-powershell-to-generate-a-jwt
function New-GitHubJwtSession
{
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory = $true, ParameterSetName = 'Organization')]
        [string]
        $OrganizationName,

        [Parameter(Mandatory = $true, ParameterSetName = 'Enterprise')]
        [string]
        $EnterpriseName,
        
        [Parameter(Position=1, Mandatory = $true)]
        [string]
        $ClientId,

        [Parameter(Position=2, Mandatory = $true)]
        [string]
        $PrivateKeyPath,

        [Parameter(Position=3, Mandatory = $true)]
        [Alias('AppId')]
        [string]
        $InstallationId,

        [Parameter(Mandatory = $false)]
        [Alias('Token')]
        [string]
        $PersonalAccessToken
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

    $jwtSession = New-GithubSession -Token $jwt
    $jwtHeaders = $jwtSession.Headers

    $result = Invoke-GithubRestMethod -Session $jwtSession -Path "app/installations/$($InstallationId)/access_tokens" -Method POST

    $patHeaders = $null
    if ($PersonalAccessToken) {
        $patHeaders = (New-GithubSession -Token $PersonalAccessToken).Headers
    }

    $session = New-GitHubSession `
        -OrganizationName $OrganizationName `
        -EnterpriseName $EnterpriseName `
        -Token $result.token `
        -JwtHeaders $jwtHeaders `
        -PatHeaders $patHeaders `
        -ClientId $ClientId `
        -InstallationId $InstallationId `
        -PrivateKeyPath $PrivateKeyPath
    
    Write-Output $session
}

function Get-GitHubAppInstallation
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    $jwtHeaders = Get-GitHoundAuthHeaders -Session $Session -AuthType JWT
    $installations = Invoke-GithubRestMethod -Session $Session -Headers $jwtHeaders -Path "app/installations"

    foreach ($inst in $installations) {
        $login = if ($inst.account.login) { $inst.account.login } else { $inst.account.slug }
        $name = if ($inst.account.name) { $inst.account.name } else { $inst.account.login }

        [PSCustomObject]@{
            InstallationId = $inst.id
            ClientId       = $inst.client_id
            TargetType     = $inst.target_type
            Login          = $login
            Name           = $name
            NodeId         = $inst.account.node_id
            AppSlug        = $inst.app_slug
            Permissions    = $inst.permissions
            SuspendedAt    = $inst.suspended_at
        }
    }
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
        $Method = 'GET',

        [Parameter()]
        [hashtable]
        $Headers
    )

    if (-not $Headers) {
        $Headers = $Session.Headers
    }

    $LinkHeader = $Null;
    try {
        do {
            $requestSuccessful = $false
            $retryCount = 0
            
            while (-not $requestSuccessful -and $retryCount -lt 3) {
                try {
                    if($LinkHeader) {
                        $Response = Invoke-WebRequest -Uri "$LinkHeader" -Headers $Headers -Method $Method -ErrorAction Stop
                    } else {
                        Write-Verbose "https://api.github.com/$($Path)"
                        $Response = Invoke-WebRequest -Uri "$($Session.Uri)$($Path)" -Headers $Headers -Method $Method -ErrorAction Stop
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

    if (-not $Headers) {
        $Headers = $Session.Headers
    }

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

    .PARAMETER StartPropertyMatchers
        (Optional) Property matchers used to resolve the start node by property instead of by id/name.

    .PARAMETER EndPropertyMatchers
        (Optional) Property matchers used to resolve the end node by property instead of by id/name.

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

        [Parameter(Position = 1, Mandatory = $false)]
        [PSObject]
        $StartId,

        [Parameter(Position = 2, Mandatory = $false)]
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
        [array]
        $StartPropertyMatchers,

        [Parameter(Mandatory = $false)]
        [array]
        $EndPropertyMatchers,

        [Parameter(Mandatory = $false)]
        [Hashtable]
        $Properties = @{}
    )

    if (-not $PSBoundParameters.ContainsKey('StartPropertyMatchers') -and -not $PSBoundParameters.ContainsKey('StartId')) {
        throw "New-GitHoundEdge requires either StartId or StartPropertyMatchers."
    }

    if (-not $PSBoundParameters.ContainsKey('EndPropertyMatchers') -and -not $PSBoundParameters.ContainsKey('EndId')) {
        throw "New-GitHoundEdge requires either EndId or EndPropertyMatchers."
    }

    $startEndpoint = if ($PSBoundParameters.ContainsKey('StartPropertyMatchers')) {
        $ep = @{ match_by = 'property'; property_matchers = $StartPropertyMatchers }
        if ($PSBoundParameters.ContainsKey('StartKind')) { $ep['kind'] = $StartKind }
        $ep
    } else {
        $ep = @{ value = $StartId }
        if ($PSBoundParameters.ContainsKey('StartKind'))    { $ep['kind']     = $StartKind }
        if ($PSBoundParameters.ContainsKey('StartMatchBy')) { $ep['match_by'] = $StartMatchBy }
        $ep
    }

    $endEndpoint = if ($PSBoundParameters.ContainsKey('EndPropertyMatchers')) {
        $ep = @{ match_by = 'property'; property_matchers = $EndPropertyMatchers }
        if ($PSBoundParameters.ContainsKey('EndKind')) { $ep['kind'] = $EndKind }
        $ep
    } else {
        $ep = @{ value = $EndId }
        if ($PSBoundParameters.ContainsKey('EndKind'))    { $ep['kind']     = $EndKind }
        if ($PSBoundParameters.ContainsKey('EndMatchBy')) { $ep['match_by'] = $EndMatchBy }
        $ep
    }

    Write-Output ([pscustomobject]@{
        kind       = $Kind
        start      = $startEndpoint
        end        = $endEndpoint
        properties = $Properties
    })
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

function Get-GitHoundEnterpriseTeamNodeId
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnterpriseId,

        [Parameter(Mandatory = $true)]
        [string]$TeamId
    )

    "GH_EnterpriseTeam_${EnterpriseId}_${TeamId}"
}

function Get-GitHoundOrganizationTeamNodeId
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$OrganizationId,

        [Parameter(Mandatory = $true)]
        [string]$TeamNodeId,

        [Parameter(Mandatory = $false)]
        [string]$TeamSlug
    )

    return $TeamNodeId
}

function Get-GitHoundOrganizationTeamPropertyMatchers
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$OrganizationId,

        [Parameter(Mandatory = $true)]
        [string]$TeamSlug
    )

    if ($TeamSlug -notlike 'ent:*') {
        return $null
    }

    @(
        (New-BHOGPropertyMatcher -Key 'environmentid' -Value $OrganizationId),
        (New-BHOGPropertyMatcher -Key 'slug' -Value $TeamSlug)
    )
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

function Git-HoundEnterprise
{
    <#
    .SYNOPSIS
        Fetches and processes a GitHub Enterprise node and its member organizations.

    .DESCRIPTION
        This function retrieves enterprise profile details and enumerates the organizations
        that belong to the enterprise. It creates a GH_Enterprise node, minimal GH_Organization
        stub nodes for discovered member organizations, and GH_Contains edges from the enterprise
        to each organization.

        The organization nodes emitted here are intentionally lightweight. They are meant to
        establish the enterprise-to-organization structure and can later be enriched by the
        normal organization collection path.

    .PARAMETER Session
        A GitHound.Session object with EnterpriseName set.

    .EXAMPLE
        $enterprise = Git-HoundEnterprise -Session $session
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    if (-not $Session.EnterpriseName) {
        throw "Git-HoundEnterprise requires Session.EnterpriseName to be set."
    }

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $enterpriseSlug = $Session.EnterpriseName
    $enterprise = $null
    $allOrganizations = New-Object System.Collections.ArrayList
    $cursor = $null

    Write-Host "[*] Git-HoundEnterprise: Collecting enterprise '$enterpriseSlug'"

    do {
        $query = @'
query($slug: String!, $after: String) {
  enterprise(slug: $slug) {
    id
    databaseId
    name
    slug
    description
    location
    url
    websiteUrl
    createdAt
    updatedAt
    billingEmail
    securityContactEmail
    viewerIsAdmin
    organizations(first: 100, after: $after) {
      nodes {
        id
        login
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
'@

        $variables = @{
            slug = $enterpriseSlug
            after = $cursor
        }

        $result = Invoke-GitHubGraphQL -Session $Session -Query $query -Variables $variables
        $enterpriseResult = $result.data.enterprise

        if (-not $enterpriseResult) {
            throw "Enterprise '$enterpriseSlug' was not returned by the GraphQL API."
        }

        if (-not $enterprise) {
            $enterprise = $enterpriseResult
        }

        foreach ($org in @($enterpriseResult.organizations.nodes)) {
            $null = $allOrganizations.Add($org)
        }

        if ($enterpriseResult.organizations.pageInfo.hasNextPage) {
            $cursor = $enterpriseResult.organizations.pageInfo.endCursor
        } else {
            $cursor = $null
        }
    } while ($cursor)

    $enterpriseNodeId = $enterprise.id
    $enterpriseProps = [pscustomobject]@{
        name                   = Normalize-Null $enterprise.slug
        node_id                = Normalize-Null $enterprise.id
        collected              = $true
        environmentid          = Normalize-Null $enterprise.id
        environment_name       = Normalize-Null $enterprise.slug
        slug                   = Normalize-Null $enterprise.slug
        enterprise_name        = Normalize-Null $enterprise.name
        description            = Normalize-Null $enterprise.description
        location               = Normalize-Null $enterprise.location
        url                    = Normalize-Null $enterprise.url
        website_url            = Normalize-Null $enterprise.websiteUrl
        created_at             = Normalize-Null $enterprise.createdAt
        updated_at             = Normalize-Null $enterprise.updatedAt
        billing_email          = Normalize-Null $enterprise.billingEmail
        security_contact_email = Normalize-Null $enterprise.securityContactEmail
        viewer_is_admin        = Normalize-Null $enterprise.viewerIsAdmin
        query_organizations    = "MATCH p=(:GH_Enterprise {node_id:'$($enterprise.id)'})-[:GH_Contains]->(:GH_Organization) RETURN p"
    }

    $null = $nodes.Add((New-GitHoundNode -Id $enterpriseNodeId -Kind 'GH_Enterprise' -Properties $enterpriseProps))

    foreach ($org in @($allOrganizations)) {
        $orgProps = [pscustomobject]@{
            name             = Normalize-Null $org.login
            node_id          = Normalize-Null $org.id
            collected        = $false
            environmentid    = Normalize-Null $org.id
            environment_name = Normalize-Null $org.login
            login            = Normalize-Null $org.login
            query_enterprise = "MATCH p=(:GH_Enterprise {node_id:'$($enterprise.id)'})-[:GH_Contains]->(:GH_Organization {node_id:'$($org.id)'}) RETURN p"
        }

        $null = $nodes.Add((New-GitHoundNode -Id $org.id -Kind 'GH_Organization' -Properties $orgProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $enterpriseNodeId -EndId $org.id -Properties @{ traversable = $false }))
    }

    Write-Host "[+] Git-HoundEnterprise complete. 1 enterprise, $($allOrganizations.Count) organization stub(s), $($edges.Count) containment edge(s)."

    [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }
}

function Git-HoundEnterpriseUser
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Users for an enterprise.

    .DESCRIPTION
        This function retrieves enterprise members using the GitHub GraphQL API `enterprise.members`
        connection. It creates GH_User nodes that match the shape used by Git-HoundUser and emits
        GH_HasMember edges linking the enterprise to each discovered user.

        Enterprise members can be returned either as normal `User` objects or as
        `EnterpriseUserAccount` objects in Enterprise Managed Users (EMU) environments. When an
        `EnterpriseUserAccount` is returned, the nested `user` object is preferred when available
        so that the GH_User node identity matches org-level collection. If the nested `user` object
        is absent, the enterprise account fields are used as a fallback.

    .PARAMETER Session
        A GitHound.Session object with EnterpriseName set.

    .PARAMETER Enterprise
        A GH_Enterprise node object from Git-HoundEnterprise.

    .EXAMPLE
        $enterpriseUsers = Git-HoundEnterpriseUser -Session $session -Enterprise $enterprise.Nodes[0]
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true)]
        [PSObject]
        $Enterprise
    )

    if (-not $Session.EnterpriseName) {
        throw "Git-HoundEnterpriseUser requires Session.EnterpriseName to be set."
    }

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $enterpriseSlug = $Session.EnterpriseName
    $enterpriseNodeId = Normalize-Null $(if ($Enterprise.id) { $Enterprise.id } elseif ($Enterprise.properties.node_id) { $Enterprise.properties.node_id } else { $null })

    if (-not $enterpriseNodeId) {
        throw "Git-HoundEnterpriseUser requires a GH_Enterprise node object with an id or properties.node_id."
    }

    Write-Host "[*] Git-HoundEnterpriseUser: Collecting enterprise members for '$enterpriseSlug'"

    $Query = @'
query EnterpriseMembers($slug: String!, $count: Int = 100, $after: String = null) {
    enterprise(slug: $slug) {
        members(first: $count, after: $after) {
            edges {
                node {
                    ... on User {
                        id
                        databaseId
                        login
                        name
                        email
                        company
                    }
                    ... on EnterpriseUserAccount {
                        id
                        login
                        name
                        user {
                            id
                            databaseId
                            login
                            name
                            email
                            company
                        }
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

    $Variables = @{
        slug = $enterpriseSlug
        count = 100
        after = $null
    }

    do {
        $result = Invoke-GitHubGraphQL -Session $Session -Query $Query -Variables $Variables

        foreach ($edge in @($result.data.enterprise.members.edges)) {
            $member = $edge.node
            $user = if ($member.user) { $member.user } else { $member }

            if (-not $user.id) {
                Write-Warning "Git-HoundEnterpriseUser: Skipping member '$($member.login)' because no user id was returned."
                continue
            }

            $properties = @{
                name                         = Normalize-Null $user.login
                node_id                      = Normalize-Null $user.id
                environment_name             = Normalize-Null $enterpriseSlug
                environmentid                = Normalize-Null $enterpriseNodeId
                login                        = Normalize-Null $user.login
                full_name                    = Normalize-Null $user.name
                company                      = Normalize-Null $user.company
                email                        = Normalize-Null $user.email
                query_personal_access_tokens = "MATCH p=(:GH_User {node_id: '$($user.id)'})-[]->(token) WHERE token:GH_PersonalAccessToken OR token:GH_PersonalAccessTokenRequest RETURN p"
                query_roles                  = "MATCH p=(t:GH_User {node_id:'$($user.id)'})-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_Role) RETURN p"
                query_teams                  = "MATCH p=(:GH_User {node_id:'$($user.id)'})-[:GH_HasRole]->(t:GH_TeamRole)-[:GH_MemberOf*1..4]->(:GH_Team) RETURN p"
                query_repositories           = "MATCH p=(t:GH_User {node_id:'$($user.id)'})-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_ReadRepoContents|GH_WriteRepoContents|GH_WriteRepoPullRequests|GH_ManageWebhooks|GH_ManageDeployKeys|GH_PushProtectedBranch|GH_DeleteAlertsCodeScanning|GH_ViewSecretScanningAlerts|GH_RunOrgMigration|GH_BypassBranchProtection|GH_EditRepoProtections]->(:GH_Repository) RETURN p"
                query_branches               = "MATCH p=(:GH_User {node_id:'$($user.id)'})-[r]->(:GH_BranchProtectionRule)-[:GH_ProtectedBy]->(:GH_Branch) RETURN p"
                query_enterprises            = "MATCH p=(:GH_Enterprise)-[:GH_HasMember]->(:GH_User {node_id:'$($user.id)'}) RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $user.id -Kind 'GH_User' -Properties $properties))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasMember' -StartId $enterpriseNodeId -EndId $user.id -Properties @{ traversable = $false }))
        }

        $Variables['after'] = $result.data.enterprise.members.pageInfo.endCursor
    }
    while ($result.data.enterprise.members.pageInfo.hasNextPage)

    Write-Host "[+] Git-HoundEnterpriseUser complete. $($nodes.Count) nodes, $($edges.Count) edges."

    [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }
}

function Git-HoundEnterpriseTeam
{
    <#
    .SYNOPSIS
        Retrieves enterprise-level teams for a GitHub enterprise.

    .DESCRIPTION
        This function enumerates enterprise teams from the enterprise REST API and models
        their structural relationship to assigned organizations. For each enterprise team,
        it creates a GH_EnterpriseTeam node, a members GH_TeamRole, GH_HasRole edges from
        enterprise members to that role, and GH_AssignedTo edges to organizations returned
        by the enterprise team organization assignment API.

        Because GitHub projects assigned enterprise teams into organizations using the
        `ent:` slug prefix, this function also emits GH_MemberOf edges that property-match
        those organization-scoped teams by organization and slug once they exist in the graph.

    .PARAMETER Session
        A GitHound.Session object with EnterpriseName set.

    .PARAMETER Enterprise
        A GH_Enterprise node object from Git-HoundEnterprise.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true)]
        [PSObject]
        $Enterprise
    )

    if (-not $Session.EnterpriseName) {
        throw "Git-HoundEnterpriseTeam requires Session.EnterpriseName to be set."
    }

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $enterpriseSlug = $Session.EnterpriseName
    $enterpriseNodeId = Normalize-Null $(if ($Enterprise.id) { $Enterprise.id } elseif ($Enterprise.properties.node_id) { $Enterprise.properties.node_id } else { $null })

    if (-not $enterpriseNodeId) {
        throw "Git-HoundEnterpriseTeam requires a GH_Enterprise node object with an id or properties.node_id."
    }

    Write-Host "[*] Git-HoundEnterpriseTeam: Collecting enterprise teams for '$enterpriseSlug'"

    $teams = @(Invoke-GithubRestMethod -Session $Session -Path "enterprises/$enterpriseSlug/teams")

    foreach ($team in $teams) {
        $enterpriseTeamId = Get-GitHoundEnterpriseTeamNodeId -EnterpriseId $enterpriseNodeId -TeamId $team.id
        $projectedTeamSlug = $team.slug

        $properties = [pscustomobject]@{
            name                        = Normalize-Null $team.name
            node_id                     = Normalize-Null $enterpriseTeamId
            github_team_id              = Normalize-Null $team.id
            environment_name            = Normalize-Null $enterpriseSlug
            environmentid               = Normalize-Null $enterpriseNodeId
            enterpriseid                = Normalize-Null $enterpriseNodeId
            slug                        = Normalize-Null $team.slug
            projected_slug              = Normalize-Null $projectedTeamSlug
            description                 = Normalize-Null $team.description
            created_at                  = Normalize-Null $team.created_at
            updated_at                  = Normalize-Null $team.updated_at
            query_enterprise            = "MATCH p=(:GH_Enterprise {node_id:'$enterpriseNodeId'})-[:GH_Contains]->(:GH_EnterpriseTeam {node_id:'$enterpriseTeamId'}) RETURN p"
            query_assigned_organizations = "MATCH p=(:GH_EnterpriseTeam {node_id:'$enterpriseTeamId'})-[:GH_AssignedTo]->(:GH_Organization) RETURN p"
            query_projected_teams       = "MATCH p=(:GH_EnterpriseTeam {node_id:'$enterpriseTeamId'})-[:GH_MemberOf]->(:GH_Team) RETURN p"
            query_members               = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_TeamRole)-[:GH_MemberOf]->(:GH_EnterpriseTeam {node_id:'$enterpriseTeamId'}) RETURN p"
        }

        $null = $nodes.Add((New-GitHoundNode -Id $enterpriseTeamId -Kind 'GH_EnterpriseTeam' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $enterpriseNodeId -EndId $enterpriseTeamId -Properties @{ traversable = $false }))

        $membersRoleId = "${enterpriseTeamId}_members"
        $membersRoleProps = [pscustomobject]@{
            name             = Normalize-Null "$enterpriseSlug/$($team.slug)/members"
            node_id          = Normalize-Null $membersRoleId
            environment_name = Normalize-Null $enterpriseSlug
            environmentid    = Normalize-Null $enterpriseNodeId
            enterpriseid     = Normalize-Null $enterpriseNodeId
            team_name        = Normalize-Null $team.name
            team_id          = Normalize-Null $enterpriseTeamId
            short_name       = Normalize-Null 'members'
            type             = Normalize-Null 'team'
            query_team       = "MATCH p=(:GH_TeamRole {node_id:'$membersRoleId'})-[:GH_MemberOf]->(:GH_EnterpriseTeam {node_id:'$enterpriseTeamId'}) RETURN p"
            query_members    = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_TeamRole {node_id:'$membersRoleId'}) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $membersRoleId -Kind 'GH_TeamRole', 'GH_Role' -Properties $membersRoleProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MemberOf' -StartId $membersRoleId -EndId $enterpriseTeamId -Properties @{ traversable = $true }))

        $members = @(Invoke-GithubRestMethod -Session $Session -Path "enterprises/$enterpriseSlug/teams/$($team.id)/memberships")
        foreach ($member in $members) {
            if ($member.node_id) {
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasRole' -StartId $member.node_id -EndId $membersRoleId -Properties @{ traversable = $true }))
            }
        }

        $assignedOrganizations = @(Invoke-GithubRestMethod -Session $Session -Path "enterprises/$enterpriseSlug/teams/$($team.id)/organizations")
        foreach ($org in $assignedOrganizations) {
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AssignedTo' -StartId $enterpriseTeamId -EndId $org.node_id -Properties @{ traversable = $false }))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MemberOf' -StartId $enterpriseTeamId -EndKind 'GH_Team' -EndPropertyMatchers @(
                (New-BHOGPropertyMatcher -Key 'environmentid' -Value $org.node_id),
                (New-BHOGPropertyMatcher -Key 'slug' -Value $projectedTeamSlug)
            ) -Properties @{ traversable = $true }))
        }
    }

    Write-Host "[+] Git-HoundEnterpriseTeam complete. $($nodes.Count) nodes, $($edges.Count) edges."

    [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }
}

function Git-HoundEnterpriseSamlProvider
{
    <#
    .SYNOPSIS
        Retrieves the enterprise SAML identity provider and external identities.

    .DESCRIPTION
        This function queries the enterprise `ownerInfo.samlIdentityProvider` GraphQL path
        to collect enterprise-scoped SAML configuration and external identity mappings.
        It creates GH_SamlIdentityProvider and GH_ExternalIdentity nodes, links the
        enterprise to the provider with GH_HasSamlIdentityProvider, and emits the same
        identity-correlation edges used by the organization-scoped SAML collector.

        This path requires a PAT-backed session because `enterprise.ownerInfo` is not
        accessible through GitHub App installation tokens.

    .PARAMETER Session
        A GitHound.Session object with EnterpriseName and PatHeaders set.

    .EXAMPLE
        $saml = Git-HoundEnterpriseSamlProvider -Session $session
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    if (-not $Session.EnterpriseName) {
        throw "Git-HoundEnterpriseSamlProvider requires Session.EnterpriseName to be set."
    }

    $patHeaders = Get-GitHoundAuthHeaders -Session $Session -AuthType PAT

    $Query = @'
query EnterpriseSAML($slug: String!, $count: Int = 100, $after: String = null) {
    enterprise(slug: $slug) {
        id
        name
        slug
        ownerInfo {
            samlIdentityProvider {
                id
                issuer
                ssoUrl
                digestMethod
                signatureMethod
                idpCertificate
                externalIdentities(first: $count, after: $after) {
                    totalCount
                    nodes {
                        guid
                        id
                        samlIdentity {
                            familyName
                            givenName
                            nameId
                            username
                        }
                        scimIdentity {
                            username
                            givenName
                            familyName
                            emails {
                                value
                                primary
                                type
                            }
                        }
                        user {
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
}
'@

    $Variables = @{
        slug = $Session.EnterpriseName
        count = 100
        after = $null
    }

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $firstPage = $true
    $ForeignUserNodeKind = $null
    $ForeignEnvironmentId = $null

    Write-Host "[*] Git-HoundEnterpriseSamlProvider: Collecting enterprise SAML for '$($Session.EnterpriseName)'"

    do {
        $result = Invoke-GitHubGraphQL -Session $Session -Headers $patHeaders -Query $Query -Variables $Variables

        $enterprise = $result.data.enterprise
        $samlProvider = $enterprise.ownerInfo.samlIdentityProvider

        if ($null -eq $samlProvider) {
            Write-Host "[-] Git-HoundEnterpriseSamlProvider: No SAML identity provider found."
            Write-Output ([PSCustomObject]@{ Nodes = $nodes; Edges = $edges })
            return
        }

        if ($firstPage) {
            $firstPage = $false

            switch -Wildcard ($samlProvider.issuer) {
                'https://auth.pingone.com/*' {
                    $ForeignUserNodeKind = 'PingOneUser'
                    $ForeignEnvironmentId = $samlProvider.issuer.Split('/')[3]
                }
                'https://sts.windows.net/*' {
                    $ForeignUserNodeKind = 'AZUser'
                    $ForeignEnvironmentId = $samlProvider.issuer.Split('/')[3]
                }
                'http://www.okta.com/*' {
                    $ForeignUserNodeKind = 'Okta_User'
                    $ForeignEnvironmentId = $samlProvider.ssoUrl.Split('/')[2]
                }
                default {
                    Write-Warning "Git-HoundEnterpriseSamlProvider: Unknown IdP issuer: $($samlProvider.issuer)"
                }
            }

            $providerProps = [pscustomobject]@{
                name                   = Normalize-Null $samlProvider.id
                node_id                = Normalize-Null $samlProvider.id
                environment_name       = Normalize-Null $enterprise.slug
                environmentid          = Normalize-Null $enterprise.id
                foreign_environmentid  = Normalize-Null $ForeignEnvironmentId
                digest_method          = Normalize-Null $samlProvider.digestMethod
                idp_certificate        = Normalize-Null $samlProvider.idpCertificate
                issuer                 = Normalize-Null $samlProvider.issuer
                signature_method       = Normalize-Null $samlProvider.signatureMethod
                sso_url                = Normalize-Null $samlProvider.ssoUrl
                query_environments     = "MATCH p=(:GH_SamlIdentityProvider {objectid: '$($samlProvider.id.ToUpper())'})<-[:GH_HasSamlIdentityProvider]->(:GH_Enterprise) RETURN p"
                query_external_identities = "MATCH p=(:GH_SamlIdentityProvider {objectid: '$($samlProvider.id.ToUpper())'})-[:GH_HasExternalIdentity]->() RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $samlProvider.id -Kind 'GH_SamlIdentityProvider' -Properties $providerProps))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSamlIdentityProvider' -StartId $enterprise.id -EndId $samlProvider.id -Properties @{ traversable = $false }))
        }

        foreach ($identity in @($samlProvider.externalIdentities.nodes)) {
            $EIprops = [pscustomobject]@{
                node_id                   = Normalize-Null $identity.id
                name                      = Normalize-Null $identity.guid
                guid                      = Normalize-Null $identity.guid
                environmentid             = Normalize-Null $enterprise.id
                environment_name          = Normalize-Null $enterprise.slug
                saml_identity_family_name = Normalize-Null $identity.samlIdentity.familyName
                saml_identity_given_name  = Normalize-Null $identity.samlIdentity.givenName
                saml_identity_name_id     = Normalize-Null $identity.samlIdentity.nameId
                saml_identity_username    = Normalize-Null $identity.samlIdentity.username
                scim_identity_family_name = Normalize-Null $identity.scimIdentity.familyName
                scim_identity_given_name  = Normalize-Null $identity.scimIdentity.givenName
                scim_identity_username    = Normalize-Null $identity.scimIdentity.username
                github_username           = Normalize-Null $(if ($identity.user) { $identity.user.login } else { $null })
                github_user_id            = Normalize-Null $(if ($identity.user) { $identity.user.id } else { $null })
                query_mapped_users        = "MATCH p=(:GH_ExternalIdentity {objectid: '$($identity.id.ToUpper())'})-[:GH_MapsToUser]->() RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $identity.id -Kind 'GH_ExternalIdentity' -Properties $EIprops))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasExternalIdentity' -StartId $samlProvider.id -EndId $identity.id -Properties @{ traversable = $false }))

            $foreignUsername = if ($identity.samlIdentity.username) { $identity.samlIdentity.username } elseif ($identity.scimIdentity.username) { $identity.scimIdentity.username } else { $null }
            $foreignUserMatchers = Get-GitHoundForeignUserPropertyMatchers -ForeignUserNodeKind $ForeignUserNodeKind -Username $foreignUsername -ForeignEnvironmentId $ForeignEnvironmentId

            if ($foreignUsername -and $ForeignUserNodeKind) {
                if ($foreignUserMatchers) {
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MapsToUser' -StartId $identity.id -EndKind $ForeignUserNodeKind -EndPropertyMatchers $foreignUserMatchers -Properties @{ traversable = $false }))
                }
                else {
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MapsToUser' -StartId $identity.id -EndId $foreignUsername -EndKind $ForeignUserNodeKind -EndMatchBy 'name' -Properties @{ traversable = $false }))
                }
            }

            if ($identity.user -ne $null -and $identity.user.id -ne $null) {
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MapsToUser' -StartId $identity.id -EndId $identity.user.id -Properties @{ traversable = $false }))

                $matchUsername = if ($identity.samlIdentity.username) { $identity.samlIdentity.username } elseif ($identity.scimIdentity.username) { $identity.scimIdentity.username } else { $null }
                if ($ForeignUserNodeKind -and $matchUsername) {
                    if ($foreignUserMatchers) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SyncedTo' -StartKind $ForeignUserNodeKind -StartPropertyMatchers $foreignUserMatchers -EndId $identity.user.id -Properties @{ traversable = $true }))
                    }
                    else {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SyncedTo' -StartId $matchUsername -StartKind $ForeignUserNodeKind -StartMatchBy 'name' -EndId $identity.user.id -Properties @{ traversable = $true }))
                    }
                }
            }
        }

        $Variables['after'] = $samlProvider.externalIdentities.pageInfo.endCursor
    }
    while ($samlProvider.externalIdentities.pageInfo.hasNextPage)

    Write-Host "[+] Git-HoundEnterpriseSamlProvider complete. $($nodes.Count) nodes, $($edges.Count) edges."

    [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }
}

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

function Get-GitHoundForeignUserPropertyMatchers
{
    param(
        [Parameter(Mandatory = $false)]
        [string]$ForeignUserNodeKind,

        [Parameter(Mandatory = $false)]
        [string]$Username,

        [Parameter(Mandatory = $false)]
        [string]$ForeignEnvironmentId
    )

    if (-not $ForeignUserNodeKind -or -not $Username) {
        return $null
    }

    switch ($ForeignUserNodeKind) {
        'AZUser' {
            $matchers = @(
                (New-BHOGPropertyMatcher -Key 'userprincipalname' -Value $Username)
            )

            if ($ForeignEnvironmentId) {
                $matchers += (New-BHOGPropertyMatcher -Key 'tenantid' -Value $ForeignEnvironmentId)
            }

            return $matchers
        }
        'Okta_User' {
            $matchers = @(
                (New-BHOGPropertyMatcher -Key 'login' -Value $Username)
            )

            if ($ForeignEnvironmentId) {
                $matchers += (New-BHOGPropertyMatcher -Key 'oktaDomain' -Value $ForeignEnvironmentId)
            }

            return $matchers
        }
        default {
            return $null
        }
    }
}

function Add-GitHoundSecretEdges
{
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
                    (New-BHOGPropertyMatcher -Key 'name' -Value $SecretName),
                    (New-BHOGPropertyMatcher -Key 'repository_id' -Value $RepoId)
                ) `
                -Properties $props))
        }
        if ($EnvId) {
            $null = $Edges.Add((New-GitHoundEdge -Kind 'GH_UsesSecret' `
                -StartId $SourceId `
                -EndKind 'GH_OrgSecret' `
                -EndPropertyMatchers @(
                    (New-BHOGPropertyMatcher -Key 'name' -Value $SecretName),
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
                    (New-BHOGPropertyMatcher -Key 'name' -Value $VariableName),
                    (New-BHOGPropertyMatcher -Key 'repository_id' -Value $RepoId)
                ) `
                -Properties $props))
        }
        if ($EnvId) {
            $null = $Edges.Add((New-GitHoundEdge -Kind 'GH_UsesVariable' `
                -StartId $SourceId `
                -EndKind 'GH_OrgVariable' `
                -EndPropertyMatchers @(
                    (New-BHOGPropertyMatcher -Key 'name' -Value $VariableName),
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

function Get-GitHoundWorkflowDispatchEdges
{
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
    Param(
        [System.Collections.ArrayList]$TriggerEventNames,
        [System.Collections.ArrayList]$StepNodes
    )

    if ($TriggerEventNames -notcontains 'pull_request_target') { return $false }

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

function Expand-GitHoundWorkflowGraph
{
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

        $yaml = $null
        try {
            $yaml = ConvertFrom-Yaml $contents
        }
        catch {
            Write-Warning "Expand-GitHoundWorkflowGraph: Failed to parse YAML for workflow '$($wf.properties.name)': $_"
            $skipped = $skipped + 1
            continue
        }

        if (-not $yaml) {
            $skipped = $skipped + 1
            continue
        }

        $on = $yaml['on']
        $triggerEventNames = [System.Collections.ArrayList]@()
        $triggerEvents = @{}

        if ($on)
        {
            if ($on -is [string])
            {
                $triggerEvents[$on] = @{}
            }
            elseif ($on -is [System.Collections.IList])
            {
                foreach ($t in $on) { $triggerEvents[$t] = @{} }
            }
            elseif ($on -is [System.Collections.IDictionary] -or $on -is [hashtable])
            {
                foreach ($key in $on.Keys) {
                    $triggerEvents[$key] = if ($on[$key]) { $on[$key] } else { @{} }
                }
            }

            foreach ($eventName in $triggerEvents.Keys) {
                $null = $triggerEventNames.Add($eventName)
            }
        }

        $wf.properties | Add-Member -NotePropertyName 'triggers' -NotePropertyValue (@($triggerEventNames) | ConvertTo-Json -Compress) -Force

        $dispatchConfig = $triggerEvents['workflow_dispatch']
        if ($dispatchConfig -and $dispatchConfig['inputs']) {
            $wf.properties | Add-Member -NotePropertyName 'trigger_dispatch_inputs' -NotePropertyValue (@($dispatchConfig['inputs'].Keys) | ConvertTo-Json -Compress) -Force
        }

        $null = $nodes.Add($wf)

        $wfPermissions = $null
        if ($yaml['permissions'])
        {
            $wfPermissions = $yaml['permissions']
        }

        $jobs = $yaml['jobs']
        $wfStepNodes = New-Object System.Collections.ArrayList
        if (-not $jobs) {
            $wf.properties | Add-Member -NotePropertyName 'is_pwn_requestable' -NotePropertyValue $false -Force
            $parsed = $parsed + 1
            continue
        }

        $jobIdMap = @{}
        foreach ($jobKey in $jobs.Keys) {
            $jobIdMap[$jobKey] = "GH_WorkflowJob_${wfNodeId}_${jobKey}"
        }

        foreach ($jobKey in $jobs.Keys)
        {
            $job = $jobs[$jobKey]
            $jobId = $jobIdMap[$jobKey]

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

            $runsOn = $null
            if ($job['runs-on'])
            {
                if ($job['runs-on'] -is [string]) {
                    $runsOn = $job['runs-on']
                } else {
                    $runsOn = $job['runs-on'] | ConvertTo-Json -Compress
                }
            }

            $jobPermissions = $null
            if ($job['permissions']) {
                $jobPermissions = $job['permissions'] | ConvertTo-Json -Compress
            } elseif ($wfPermissions) {
                $jobPermissions = $wfPermissions | ConvertTo-Json -Compress
            }

            $usesReusable = $null
            if ($job['uses']) {
                $usesReusable = $job['uses']
            }

            $isSelfHosted = $false
            if ($runsOn) {
                if ($runsOn -eq 'self-hosted') {
                    $isSelfHosted = $true
                } else {
                    $parsedRunsOn = try { $runsOn | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $null }
                    if ($parsedRunsOn -and ($parsedRunsOn -contains 'self-hosted')) { $isSelfHosted = $true }
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

            if ($usesReusable)
            {
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
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CallsWorkflow' `
                        -StartId $jobId `
                        -EndId $usesReusable `
                        -EndKind 'GH_Workflow' `
                        -EndMatchBy 'name' `
                        -Properties @{ traversable = $false; reusable_ref = $usesReusable }
                    ))
                }
            }

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

            $steps = $job['steps']
            if (-not $steps) { continue }

            $stepIndex = 0
            foreach ($step in $steps)
            {
                $stepId = "GH_WorkflowStep_${wfNodeId}_${jobKey}_${stepIndex}"

                $stepName = $null
                if ($step['name']) {
                    $stepName = $step['name']
                } elseif ($step['uses']) {
                    $stepName = $step['uses']
                } elseif ($step['run']) {
                    $firstLine = ($step['run'] -split "`n")[0].Trim()
                    $stepName = if ($firstLine.Length -gt 80) { $firstLine.Substring(0, 80) + "..." } else { $firstLine }
                }

                $action = $null
                $actionOwner = $null
                $actionName = $null
                $authProvider = $null
                $actionRef = $null
                $isPinned = $false

                if ($step['uses'])
                {
                    $action = $step['uses']

                    if ($action -match '^(?<owner>[^/]+)/(?<name>[^@]+)@(?<ref>.+)$')
                    {
                        $actionOwner = $Matches['owner']
                        $actionName = $Matches['name']
                        $actionRef = $Matches['ref']
                        $isPinned = $actionRef -match '^[0-9a-f]{40}$'
                    }

                    $actionKey = "$actionOwner/$actionName".ToLower()
                    $authProvider = switch ($actionKey) {
                        'aws-actions/configure-aws-credentials' { 'AWS' }
                        'azure/login' { 'Azure' }
                        'azure/webapps-deploy' { 'Azure' }
                        'azure/arm-deploy' { 'Azure' }
                        'google-github-actions/auth' { 'GCP' }
                        'google-github-actions/setup-gcloud' { 'GCP' }
                        'hashicorp/vault-action' { 'Vault' }
                        'docker/login-action' { 'Docker' }
                        default { $null }
                    }
                }

                $stepType = if ($step['uses']) { 'uses' } elseif ($step['run']) { 'run' } else { 'unknown' }

                $injectionRisks = $null
                $injectionPattern = '\$\{\{\s*(github\.event\.inputs\.\w+|github\.event\.issue\.title|github\.event\.issue\.body|github\.event\.comment\.body|github\.event\.pull_request\.title|github\.event\.pull_request\.body|github\.event\.discussion\.title|github\.event\.discussion\.body|github\.head_ref|github\.event\.pages\.[^}]*\.page_name)\s*\}\}'
                $allRiskyMatches = New-Object System.Collections.ArrayList

                if ($step['run'])
                {
                    foreach ($m in [regex]::Matches($step['run'], $injectionPattern)) {
                        $null = $allRiskyMatches.Add($m.Groups[1].Value)
                    }
                }

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

                $localScriptRefs = $null
                if ($step['run'])
                {
                    $scriptMatches = New-Object System.Collections.ArrayList
                    $localScriptPattern = '(?m)(?:^|\s|&&|\|\||;)\s*(?:(?:bash|sh|zsh|python3?|node|ruby|perl|pwsh|powershell)\s+|(?:source|\.)\s+|go\s+run\s+)?(\./[^\s;|&\r\n]+|\.github/[^\s;|&\r\n]+)'
                    foreach ($m in [regex]::Matches($step['run'], $localScriptPattern)) {
                        $scriptPath = $m.Groups[1].Value
                        if ($scriptPath -notmatch '^\$\{\{' -and $scriptPath -match '\.\w+$') {
                            $null = $scriptMatches.Add($scriptPath)
                        }
                    }
                    if ($scriptMatches.Count -gt 0) {
                        $localScriptRefs = @($scriptMatches | Select-Object -Unique) | ConvertTo-Json -Compress
                    }
                }

                $actionSlug = if ($actionOwner -and $actionName) { "$actionOwner/$actionName" } else { $null }

                $withArgs = $null
                if ($step['with'] -and ($step['with'] -is [System.Collections.IDictionary] -or $step['with'] -is [hashtable]))
                {
                    $withArgs = $step['with'] | ConvertTo-Json -Compress -Depth 5 -ErrorAction SilentlyContinue
                }

                $stepProps = @{
                    name               = Normalize-Null $stepName
                    node_id            = $stepId
                    step_index         = $stepIndex
                    type               = $stepType
                    action             = Normalize-Null $action
                    action_slug        = Normalize-Null $actionSlug
                    auth_provider      = Normalize-Null $authProvider
                    action_owner       = Normalize-Null $actionOwner
                    action_name        = Normalize-Null $actionName
                    action_ref         = Normalize-Null $actionRef
                    is_pinned          = $isPinned
                    has_injection_risk = [bool]$injectionRisks
                    runs_local_script  = [bool]$localScriptRefs
                    run                = Normalize-Null $step['run']
                    with_args          = Normalize-Null $withArgs
                    contents           = Normalize-Null (($step | ConvertTo-Json -Compress -Depth 5 -ErrorAction SilentlyContinue) -replace '\r?\n', '')
                    injection_risks    = Normalize-Null $injectionRisks
                    local_script_refs  = Normalize-Null $localScriptRefs
                    job_node_id        = $jobId
                }

                $stepNode = New-GitHoundNode -Id $stepId -Kind 'GH_WorkflowStep' -Properties $stepProps
                $null = $nodes.Add($stepNode)
                $null = $wfStepNodes.Add($stepNode)
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasStep' -StartId $jobId -EndId $stepId -Properties @{ traversable = $false }))

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

        $isPwnRequestable = Test-PwnRequestable -TriggerEventNames $triggerEventNames -StepNodes $wfStepNodes
        $wf.properties | Add-Member -NotePropertyName 'is_pwn_requestable' -NotePropertyValue $isPwnRequestable -Force

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

    Write-Host "[*] Expand-GitHoundWorkflowGraph: Parsed $parsed workflow(s), skipped $skipped. Created $($nodes.Count) nodes, $($edges.Count) edges."

    Write-Output ([PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    })
}

function Get-GitHoundPwnRequestEdges
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [PSObject]$GraphData,

        [Parameter(Mandatory)]
        [PSObject]$WorkflowData
    )

    $edges = New-Object System.Collections.ArrayList

    $allNodes = $GraphData.graph.nodes
    $allEdges = $GraphData.graph.edges

    $orgNode = $allNodes | Where-Object { $_.kinds -contains 'GH_Organization' } | Select-Object -First 1
    $orgAllowsFork = $orgNode -and $orgNode.properties.members_can_fork_private_repositories -eq $true

    $repoMap = @{}
    foreach ($r in ($allNodes | Where-Object { $_.kinds -contains 'GH_Repository' })) {
        $repoMap[$r.properties.node_id] = $r
    }

    $repoBranches = @{}
    foreach ($e in ($allEdges | Where-Object { $_.kind -eq 'GH_HasBranch' })) {
        $repoId = if ($e.start.value) { $e.start.value } else { $e.start }
        $branchId = if ($e.end.value) { $e.end.value } else { $e.end }
        if (-not $repoBranches.ContainsKey($repoId)) { $repoBranches[$repoId] = [System.Collections.ArrayList]@() }
        $null = $repoBranches[$repoId].Add($branchId)
    }

    $branchMap = @{}
    foreach ($b in ($allNodes | Where-Object { $_.kinds -contains 'GH_Branch' })) {
        $branchMap[$b.id] = $b
        if ($b.properties.node_id) { $branchMap[$b.properties.node_id] = $b }
    }

    $readEdges = @{}
    foreach ($e in ($allEdges | Where-Object { $_.kind -eq 'GH_ReadRepoContents' })) {
        $roleId = if ($e.start.value) { $e.start.value } else { $e.start }
        $repoId = if ($e.end.value) { $e.end.value } else { $e.end }
        if (-not $readEdges.ContainsKey($repoId)) { $readEdges[$repoId] = [System.Collections.ArrayList]@() }
        $null = $readEdges[$repoId].Add($roleId)
    }

    $repoWorkflows = @{}
    foreach ($e in ($allEdges | Where-Object { $_.kind -eq 'GH_HasWorkflow' })) {
        $repoId = if ($e.start.value) { $e.start.value } else { $e.start }
        $wfId = if ($e.end.value) { $e.end.value } else { $e.end }
        if (-not $repoWorkflows.ContainsKey($wfId)) { $repoWorkflows[$wfId] = $repoId }
    }

    $pwnWorkflows = @($WorkflowData.Nodes | Where-Object {
        $_.kinds -contains 'GH_Workflow' -and $_.properties.is_pwn_requestable -eq $true
    })

    $edgeCount = 0
    foreach ($wf in $pwnWorkflows)
    {
        $repoId = $repoWorkflows[$wf.id]
        if (-not $repoId) { $repoId = $repoWorkflows[$wf.properties.node_id] }
        if (-not $repoId -and $wf.properties.repository_id) { $repoId = $wf.properties.repository_id }
        if (-not $repoId) {
            Write-Warning "Get-GitHoundPwnRequestEdges: Could not find repo for workflow '$($wf.properties.name)'"
            continue
        }

        $repo = $repoMap[$repoId]
        if (-not $repo) {
            Write-Warning "Get-GitHoundPwnRequestEdges: Repo node not found for id '$repoId'"
            continue
        }

        $isPublic = $repo.properties.visibility -eq 'public'
        if (-not $isPublic) {
            if (-not $orgAllowsFork) { continue }
            if ($repo.properties.allow_forking -ne $true) { continue }
        }

        $roleIds = $readEdges[$repoId]
        if (-not $roleIds -or $roleIds.Count -eq 0) { continue }

        $prtBranches = $null
        if ($wf.properties.prt_branches) {
            $prtBranches = try { $wf.properties.prt_branches | ConvertFrom-Json } catch { $null }
        }

        $targetBranchIds = [System.Collections.ArrayList]@()
        $branches = $repoBranches[$repoId]
        if ($branches) {
            if ($prtBranches) {
                foreach ($branchId in $branches) {
                    $branch = $branchMap[$branchId]
                    if ($branch) {
                        $branchName = $branch.properties.name -replace '^.*\\', ''
                        foreach ($pattern in $prtBranches) {
                            if ($branchName -like $pattern) {
                                $null = $targetBranchIds.Add($branchId)
                                break
                            }
                        }
                    }
                }
            } else {
                $targetBranchIds.AddRange(@($branches))
            }
        }

        $edgeProps = @{ traversable = $true; workflow = $wf.properties.name }

        foreach ($roleId in $roleIds) {
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanPwnRequest' -StartId $roleId -EndId $repoId -Properties $edgeProps))
            $edgeCount = $edgeCount + 1

            foreach ($branchId in $targetBranchIds) {
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanPwnRequest' -StartId $roleId -EndId $branchId -Properties $edgeProps))
                $edgeCount = $edgeCount + 1
            }
        }
    }

    Write-Host "[*] Get-GitHoundPwnRequestEdges: $($pwnWorkflows.Count) pwn-requestable workflow(s), $edgeCount edges created."

    Write-Output ([PSCustomObject]@{
        Nodes = @()
        Edges = $edges
    })
}

function Extract-SecretReferences
{
    Param(
        [Parameter(Position = 0)]
        [string]$Text
    )

    if (-not $Text) { return @() }

    $matches = [regex]::Matches($Text, '\$\{\{\s*secrets\.(\w+)\s*\}\}')
    @($matches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

function Extract-VariableReferences
{
    Param(
        [Parameter(Position = 0)]
        [string]$Text
    )

    if (-not $Text) { return @() }

    $matches = [regex]::Matches($Text, '\$\{\{\s*vars\.(\w+)\s*\}\}')
    @($matches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

function Get-GitHoundWorkflowAnalysis
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [PSObject]$GraphData
    )

    $workflowNodes = @($GraphData.graph.nodes | Where-Object {
        $_.kinds -contains 'GH_Workflow' -and $_.properties.contents -and $_.properties.contents.Trim().Length -gt 0
    })

    if ($workflowNodes.Count -eq 0) {
        Write-Warning "No workflow nodes with contents found. Ensure workflow content collection is enabled."
        return [PSCustomObject]@{
            Nodes = (New-Object System.Collections.ArrayList)
            Edges = (New-Object System.Collections.ArrayList)
        }
    }

    Write-Host "[*] Found $($workflowNodes.Count) workflow(s) with contents."

    $wfResult = Expand-GitHoundWorkflowGraph -Workflows $workflowNodes
    $pwnResult = Get-GitHoundPwnRequestEdges -GraphData $GraphData -WorkflowData $wfResult
    $dispatchResult = Get-GitHoundWorkflowDispatchEdges -GraphData $GraphData -WorkflowData $wfResult

    $analysisNodes = New-Object System.Collections.ArrayList
    $analysisEdges = New-Object System.Collections.ArrayList
    if ($wfResult.Nodes) { $null = $analysisNodes.AddRange(@($wfResult.Nodes)) }
    if ($wfResult.Edges) { $null = $analysisEdges.AddRange(@($wfResult.Edges)) }
    if ($pwnResult.Edges) { $null = $analysisEdges.AddRange(@($pwnResult.Edges)) }
    if ($dispatchResult.Edges) { $null = $analysisEdges.AddRange(@($dispatchResult.Edges)) }

    $pwnCount = @($wfResult.Nodes | Where-Object {
        $_.kinds -contains 'GH_Workflow' -and $_.properties.is_pwn_requestable -eq $true
    }).Count
    $dispatchCount = @($dispatchResult.Edges).Count
    Write-Host "[+] Workflow analysis summary: $($analysisNodes.Count) nodes, $($analysisEdges.Count) edges, $pwnCount pwn-requestable workflow(s), $dispatchCount job-to-runner dispatch edge(s)"

    [PSCustomObject]@{
        Nodes = $analysisNodes
        Edges = $analysisEdges
    }
}

function Merge-GitHoundWorkflowAnalysis
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [System.Collections.ArrayList]$GraphNodes,

        [Parameter(Mandatory)]
        [System.Collections.ArrayList]$GraphEdges,

        [Parameter(Mandatory)]
        [PSCustomObject]$AnalysisResult
    )

    $existingNodesById = @{}
    foreach ($node in $GraphNodes) {
        if ($null -ne $node -and $node.id) {
            $existingNodesById[$node.id] = $node
        }
    }

    foreach ($analysisNode in @($AnalysisResult.Nodes)) {
        if ($null -eq $analysisNode) { continue }

        if (($analysisNode.kinds -contains 'GH_Workflow') -and $existingNodesById.ContainsKey($analysisNode.id)) {
            $existingNode = $existingNodesById[$analysisNode.id]
            $existingNode.kinds = $analysisNode.kinds
            $existingNode.properties = $analysisNode.properties
            continue
        }

        $null = $GraphNodes.Add($analysisNode)
        if ($analysisNode.id) {
            $existingNodesById[$analysisNode.id] = $analysisNode
        }
    }

    if ($AnalysisResult.Edges) {
        $null = $GraphEdges.AddRange(@($AnalysisResult.Edges))
    }
}

function Export-GitHoundWorkflowAnalysis
{
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$OutputPath
    )

    if (-not (Test-Path $Path)) {
        Write-Error "File not found: $Path"
        return
    }

    Write-Host "[*] Loading collected data from $Path..."
    $data = Get-Content $Path -Raw | ConvertFrom-Json
    $analysisResult = Get-GitHoundWorkflowAnalysis -GraphData $data

    if (-not $OutputPath) {
        $dir = Split-Path $Path -Parent
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $OutputPath = Join-Path $dir "${base}_workflows.json"
    }

    $payload = [PSCustomObject]@{
        '$schema' = "https://raw.githubusercontent.com/MichaelGrafnetter/EntraAuthPolicyHound/refs/heads/main/bloodhound-opengraph.schema.json"
        graph = [PSCustomObject]@{
            nodes = @($analysisResult.Nodes | Where-Object { $_ -ne $null })
            edges = @($analysisResult.Edges | Where-Object { $_ -ne $null })
        }
    }

    $payload | ConvertTo-Json -Depth 10 | Out-File $OutputPath
    Write-Host "[+] Workflow analysis complete. Output written to $OutputPath"
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
        - Get self-hosted runners settings for an organization: https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#get-self-hosted-runners-settings-for-an-organization
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
    $workflowPerms = Invoke-GithubRestMethod -Session $session -Path "orgs/$($Session.OrganizationName)/actions/permissions/workflow"
    $selfHostedRunnerSettings = Invoke-GithubRestMethod -Session $session -Path "orgs/$($Session.OrganizationName)/actions/permissions/self-hosted-runners"

    $properties = [pscustomobject]@{
        # Common Properties
        name                                                         = Normalize-Null $org.login
        node_id                                                      = Normalize-Null $org.node_id
        collected                                                    = $true
        # Relational Properties
        environmentid                                                = Normalize-Null $org.node_id
        environment_name                                             = Normalize-Null $org.login
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
        secret_scanning_push_protection_custom_link                  = Normalize-Null $org.secret_scanning_push_protection_custom_link
        secret_scanning_validity_checks_enabled                      = Normalize-Null $org.secret_scanning_validity_checks_enabled
        actions_enabled_repositories                                 = Normalize-Null $actions.enabled_repositories
        actions_allowed_actions                                      = Normalize-Null $actions.allowed_actions
        actions_sha_pinning_required                                 = Normalize-Null $actions.sha_pinning_required
        self_hosted_runners_enabled_repositories                     = Normalize-Null $selfHostedRunnerSettings.enabled_repositories
        default_workflow_permissions                                 = Normalize-Null $workflowPerms.default_workflow_permissions
        can_approve_pull_request_reviews                             = Normalize-Null $workflowPerms.can_approve_pull_request_reviews
        # Accordion Panel Queries
        query_organization_roles                       = "MATCH (:GH_Organization {node_id:'$($org.node_id)'})-[:GH_Contains]->(n:GH_OrgRole) RETURN n"
        query_users                                    = "MATCH (n:GH_User {environmentid:'$($org.node_id)'}) RETURN n"
        query_teams                                    = "MATCH (n:GH_Team {environmentid:'$($org.node_id)'}) RETURN n"
        query_repositories                             = "MATCH (n:GH_Repository {environmentid:'$($org.node_id)'}) RETURN n"
        query_runner_groups                           = "MATCH p=(:GH_Organization {node_id:'$($org.node_id)'})-[:GH_Contains]->(:GH_RunnerGroup) RETURN p"
        query_runners                                 = "MATCH p=(:GH_Organization {node_id:'$($org.node_id)'})-[:GH_Contains]->(:GH_RunnerGroup)-[:GH_Contains]->(:GH_Runner) RETURN p"
        query_personal_access_tokens                   = "MATCH p=(:GH_Organization {node_id: '$($org.node_id)'})-[:GH_Contains]->(token) WHERE token:GH_PersonalAccessToken OR token:GH_PersonalAccessTokenRequest RETURN p"
        query_secret_scanning_alerts                   = "MATCH p=(:GH_Organization {node_id: '$($org.node_id)'})-[:GH_Contains]->(alert:GH_SecretScanningAlert) RETURN p"
        query_identity_provider                        = "MATCH p=(OIP:GH_SamlIdentityProvider)-[:GH_HasExternalIdentity]->(EI:GH_ExternalIdentity) MATCH p1=(OIP)<-[:GH_HasSamlIdentityProvider]-(:GH_Organization {node_id:'$($org.node_id)'}) MATCH p2=(EI)-[:GH_MapsToUser]->() RETURN p,p1,p2"
        query_app_installations                        = "MATCH p=(:GH_Organization)-[:GH_Contains]->(:GH_AppInstallation) RETURN p"
        query_organization_secrets                     = "MATCH p=(:GH_Organization {node_id: '$($org.node_id)'})-[:GH_Contains]->(secret:GH_OrgSecret) RETURN p"
    }

    $orgNode = New-GitHoundNode -Id $org.node_id -Kind 'GH_Organization' -Properties $properties
    $null = $nodes.Add($orgNode)

    # --- Organization Role Nodes and Edges ---
    # These were previously created in Git-HoundOrganizationRole but are moved here
    # because they are static properties of the organization, not per-user assignments.

    $orgAllRepoReadId = "$($orgNode.id)_all_repo_read"
    $orgAllRepoTriageId = "$($orgNode.id)_all_repo_triage"
    $orgAllRepoWriteId = "$($orgNode.id)_all_repo_write"
    $orgAllRepoMaintainId = "$($orgNode.id)_all_repo_maintain"
    $orgAllRepoAdminId = "$($orgNode.id)_all_repo_admin"

    # Custom Organization Roles
    # In general parallelizing this is a bad idea, because most organizations have a small number of custom roles
    foreach($customrole in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($org.login)/organization-roles").roles)
    {
        $customRoleId = "$($orgNode.id)_$($customrole.name)"
        $customRoleProps = [pscustomobject]@{
            # Common Properties
            name                   = Normalize-Null "$($org.login)/$($customrole.name)"
            node_id                = Normalize-Null $customRoleId
            # Relational Properties
            environment_name       = Normalize-Null $org.login
            environmentid         = Normalize-Null $org.node_id
            # Node Specific Properties
            short_name             = Normalize-Null $customrole.namehttps://research.bloodhoundenterprise.io/ui/graphview?environmentId=S-1-5-21-1273778777-4208638582-2921056243
            type                   = Normalize-Null 'custom'
            # Accordion Panel Queries
            query_explicit_members = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_OrgRole {node_id:'$($customRoleId)'}) RETURN p"
            query_unrolled_members = "MATCH p=(:GH_User)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_OrgRole {node_id:'$($customRoleId)'}) RETURN p"
            query_org_permissions  = "MATCH p=(:GH_OrgRole {node_id:'$($customRoleId)'})-[]->(:GH_Organization) RETURN p"
            query_repo_permissions = "MATCH p=(s:GH_OrgRole {node_id:'$($customRoleId)'})-[:GH_HasBaseRole]->(d:GH_OrgRole) WHERE s<>d RETURN p"

        }
        $null = $nodes.Add((New-GitHoundNode -Id $customRoleId -Kind 'GH_OrgRole', 'GH_Role' -Properties $customRoleProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNode.id -EndId $customRoleId -Properties @{traversable=$false}))

        foreach($team in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($org.login)/organization-roles/$($customRole.id)/teams"))
        {
            $teamMatchers = Get-GitHoundOrganizationTeamPropertyMatchers -OrganizationId $org.node_id -TeamSlug $team.slug
            if($teamMatchers)
            {
                $null = $edges.Add((New-GitHoundEdge -Kind GH_HasRole -StartKind 'GH_Team' -StartPropertyMatchers $teamMatchers -EndId $customRoleId -Properties @{traversable=$true}))
            }
            else
            {
                $null = $edges.Add((New-GitHoundEdge -Kind GH_HasRole -StartId $team.node_id -EndId $customRoleId -Properties @{traversable=$true}))
            }
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
                'write_organization_actions_variables' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteOrganizationActionsVariables' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                #'write_code_quality' {$kind = 'GH_WriteCodeQuality'}
                #'write_code_scanning' {$kind = 'GH_WriteCodeScanning'}
                'write_organization_custom_org_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteOrganizationCustomOrgRole' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$true})) }
                'write_organization_custom_repo_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteOrganizationCustomRepoRole' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                'write_organization_network_configurations' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteOrganizationNetworkConfigurations' -StartId $customRoleId -EndId $orgNode.id -Properties @{traversable=$false})) }
                #'write_organization_runner_custom_images' {$kind = 'GH_WriteOrganizationRunnerCustomImages'}
                #'write_organization_runners_and_runner_groups' {$kind = 'GH_WriteOrganizationRunnersAndRunnerGroups'}
            }
        }
    }

    # Default Organization Role: Owners
    $orgOwnersId = "$($orgNode.id)_owners"
    $ownersProps = [pscustomobject]@{
        # Common Properties
        name                   = Normalize-Null "$($org.login)/owners"
        node_id                = Normalize-Null $orgOwnersId
        # Relational Properties
        environment_name       = Normalize-Null $org.login
        environmentid          = Normalize-Null $org.node_id
        # Node Specific Properties
        short_name             = Normalize-Null 'owners'
        type                   = Normalize-Null 'default'
        # Accordion Panel Queries
        query_explicit_members = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_OrgRole {node_id:'$($orgOwnersId)'}) RETURN p"
        query_unrolled_members = "MATCH p=(:GH_User)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_OrgRole {node_id:'$($orgOwnersId)'}) RETURN p"
        query_org_permissions  = "MATCH p=(:GH_OrgRole {node_id:'$($orgOwnersId)'})-[]->(:GH_Organization) RETURN p"
        query_repo_permissions = "MATCH p=(s:GH_OrgRole {node_id:'$($orgOwnersId)'})-[:GH_HasBaseRole]->(d:GH_OrgRole) WHERE s<>d RETURN p"
    }
    $null = $nodes.Add((New-GitHoundNode -Id $orgOwnersId -Kind 'GH_OrgRole', 'GH_Role' -Properties $ownersProps))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNode.id -EndId $orgOwnersId -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateRepository' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_InviteMember' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddCollaborator' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateTeam' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_TransferRepository' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewSecretScanningAlerts' -StartId $orgOwnersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgOwnersId -EndId $orgAllRepoAdminId -Properties @{traversable=$true}))

    # Default Organization Role: Members
    $orgMembersId = "$($orgNode.id)_members"
    $membersProps = [pscustomobject]@{
        # Common Properties
        name              = Normalize-Null "$($org.login)/members"
        node_id           = Normalize-Null $orgMembersId
        # Relational Properties
        environment_name  = Normalize-Null $org.login
        environmentid    = Normalize-Null $org.node_id
        # Node Specific Properties
        short_name        = Normalize-Null 'members'
        type              = Normalize-Null 'default'
        # Accordion Panel Queries
        query_explicit_members = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_OrgRole {node_id:'$($orgMembersId)'}) RETURN p"
        query_unrolled_members = "MATCH p=(:GH_User)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_OrgRole {node_id:'$($orgMembersId)'}) RETURN p"
        query_org_permissions  = "MATCH p=(:GH_OrgRole {node_id:'$($orgMembersId)'})-[]->(:GH_Organization) RETURN p"
        query_repo_permissions = "MATCH p=(s:GH_OrgRole {node_id:'$($orgMembersId)'})-[:GH_HasBaseRole]->(d:GH_OrgRole) WHERE s<>d RETURN p"
    }
    $null = $nodes.Add((New-GitHoundNode -Id $orgMembersId -Kind 'GH_OrgRole', 'GH_Role' -Properties $membersProps))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNode.id -EndId $orgMembersId -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateRepository' -StartId $orgMembersId -EndId $orgNode.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateTeam' -StartId $orgMembersId -EndId $orgNode.id -Properties @{traversable=$false}))

    if($org.default_repository_permission -ne 'none')
    {
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgMembersId -EndId "$($orgNode.id)_all_repo_$($org.default_repository_permission)" -Properties @{traversable=$true}))
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
            $teamNodeId = Get-GitHoundOrganizationTeamNodeId -OrganizationId $Organization.properties.node_id -TeamNodeId $team.id -TeamSlug $team.slug

            # --- Team Node ---
            $properties = [pscustomobject]@{
                # Common Properties
                #id                = Normalize-Null $team.databaseId
                name              = Normalize-Null $team.name
                node_id           = Normalize-Null $teamNodeId
                github_team_id    = Normalize-Null $team.id
                # Relational Properties
                environment_name  = Normalize-Null $Organization.properties.login
                environmentid    = Normalize-Null $Organization.properties.node_id
                # Node Specific Properties
                slug              = Normalize-Null $team.slug
                description       = Normalize-Null $team.description
                privacy           = Normalize-Null $team.privacy
                type              = Normalize-Null $(if ($team.slug -like 'ent:*') { 'enterprise' } else { '' })
                # Accordion Panel Queries
                query_first_degree_members     = "MATCH p=(:GH_User)-[:GH_HasRole]->(t:GH_TeamRole)-[:GH_MemberOf]->(:GH_Team {node_id:'$teamNodeId'}) RETURN p"
                query_unrolled_members         = "MATCH p=(teamrole:GH_TeamRole)-[:GH_MemberOf*1..]->(:GH_Team {node_id:'$teamNodeId'}) MATCH p1 = (teamrole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
                query_first_degree_maintainers = "MATCH p=(:GH_User)-[:GH_HasRole]->(t:GH_TeamRole {short_name: 'maintainers'})-[:GH_MemberOf]->(:GH_Team {node_id:'$teamNodeId'}) RETURN p"
                query_unrolled_maintainers     = "MATCH p=(teamrole:GH_TeamRole {short_name: 'maintainers'})-[:GH_MemberOf*1..]->(:GH_Team {node_id:'$teamNodeId'}) MATCH p1 = (teamrole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
                query_repositories             = "MATCH p=(:GH_Team {node_id:'$teamNodeId'})-[:GH_HasRole]->(:GH_RepoRole)-[]->(:GH_Repository) RETURN p"
                query_child_teams              = "MATCH p=(:GH_Team)-[:GH_MemberOf*1..]->(:GH_Team {node_id:'$teamNodeId'}) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $teamNodeId -Kind 'GH_Team' -Properties $properties))

            # Parent team edge
            if($null -ne $team.parentTeam)
            {
                $parentTeamNodeId = Get-GitHoundOrganizationTeamNodeId -OrganizationId $Organization.properties.node_id -TeamNodeId $team.parentTeam.id -TeamSlug ''
                $null = $edges.Add((New-GitHoundEdge -Kind GH_MemberOf -StartId $teamNodeId -EndId $parentTeamNodeId -Properties @{ traversable = $true }))
            }

            # --- Team Role Nodes (members and maintainers) ---
            $memberId = "${teamNodeId}_members"
            $memberProps = [pscustomobject]@{
                # Common Properties
                name               = Normalize-Null "$($Organization.properties.login)/$($team.slug)/members"
                node_id            = Normalize-Null $memberId
                # Relational Properties
                environment_name   = Normalize-Null $Organization.properties.login
                environmentid     = Normalize-Null $Organization.properties.node_id
                team_name          = Normalize-Null $team.name
                team_id            = Normalize-Null $teamNodeId
                # Node Specific Properties
                short_name         = Normalize-Null 'members'
                type               = Normalize-Null 'team'
                # Accordion Panel Queries
                query_team         = "MATCH p=(:GH_TeamRole {node_id:'$($memberId)'})-[:GH_MemberOf]->(:GH_Team) RETURN p "
                query_members      = "MATCH p=(:GH_User)-[GH_HasRole]->(:GH_TeamRole {node_id:'$($memberId)'}) RETURN p"
                query_repositories = "MATCH p=(:GH_TeamRole {node_id:'$($memberId)'})-[:GH_MemberOf]->(:GH_Team)-[:GH_HasRole|GH_HasBaseRole*1..]->(:GH_RepoRole)-[]->(:GH_Repository) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $memberId -Kind 'GH_TeamRole','GH_Role' -Properties $memberProps))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MemberOf' -StartId $memberId -EndId $teamNodeId -Properties @{traversable=$true}))

            $maintainerId = "${teamNodeId}_maintainers"
            $maintainerProps = [pscustomobject]@{
                # Common Properties
                name               = Normalize-Null "$($Organization.properties.login)/$($team.slug)/maintainers"
                node_id            = Normalize-Null $maintainerId
                # Relational Properties
                environment_name   = Normalize-Null $Organization.properties.login
                environmentid     = Normalize-Null $Organization.properties.node_id
                team_name          = Normalize-Null $team.name
                team_id            = Normalize-Null $teamNodeId
                # Node Specific Properties
                short_name         = Normalize-Null 'maintainers'
                type               = Normalize-Null 'team'
                # Accordion Panel Queries
                query_team         = "MATCH p=(:GH_TeamRole {node_id:'$($maintainerId)'})-[:GH_MemberOf]->(:GH_Team) RETURN p "
                query_members      = "MATCH p=(:GH_User)-[GH_HasRole]->(:GH_TeamRole {node_id:'$($maintainerId)'}) RETURN p"
                query_repositories = "MATCH p=(:GH_TeamRole {node_id:'$($maintainerId)'})-[:GH_MemberOf]->(:GH_Team)-[:GH_HasRole|GH_HasBaseRole*1..]->(:GH_RepoRole)-[]->(:GH_Repository) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $maintainerId -Kind 'GH_TeamRole','GH_Role' -Properties $maintainerProps))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MemberOf' -StartId $maintainerId -EndId $teamNodeId -Properties @{traversable=$true}))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddMember' -StartId $maintainerId -EndId $teamNodeId -Properties @{traversable=$true}))

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
                    teamId        = $teamNodeId
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

    # Phase 3: Enterprise-projected org teams visible via REST.
    $restTeams = @(Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.properties.login)/teams")
    foreach($team in @($restTeams | Where-Object { $_.slug -like 'ent:*' }))
    {
        $teamNodeId = Get-GitHoundOrganizationTeamNodeId -OrganizationId $Organization.properties.node_id -TeamNodeId $team.node_id -TeamSlug $team.slug

        $properties = [pscustomobject]@{
            name               = Normalize-Null $team.name
            node_id            = Normalize-Null $teamNodeId
            github_team_id     = Normalize-Null $team.node_id
            collected          = $false
            environment_name   = Normalize-Null $Organization.properties.login
            environmentid      = Normalize-Null $Organization.properties.node_id
            slug               = Normalize-Null $team.slug
            description        = Normalize-Null $team.description
            privacy            = Normalize-Null $team.privacy
            type               = Normalize-Null 'enterprise'
            query_repositories = "MATCH p=(:GH_Team {node_id:'$teamNodeId'})-[:GH_HasRole]->(:GH_RepoRole)-[]->(:GH_Repository) RETURN p"
        }

        $null = $nodes.Add((New-GitHoundNode -Id $teamNodeId -Kind 'GH_Team' -Properties $properties))
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
    $orgOwnersId = "$($Organization.id)_owners"
    $orgMembersId = "$($Organization.id)_members"

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
                #id                  = Normalize-Null $user.databaseId
                name                = Normalize-Null $user.login
                node_id             = Normalize-Null $user.id
                # Relational Properties
                environment_name    = Normalize-Null $Organization.properties.login
                environmentid      = Normalize-Null $Organization.properties.node_id
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
        - Get self-hosted runners settings for an organization: https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#get-self-hosted-runners-settings-for-an-organization
        - List repositories allowed to use self-hosted runners in an organization: https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#list-repositories-allowed-to-use-self-hosted-runners-in-an-organization
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
    $selfHostedRunnerSettings = Invoke-GithubRestMethod -Session $session -Path "orgs/$($Organization.Properties.login)/actions/permissions/self-hosted-runners"

    $enabledRepos = $null
    if($actions.enabled_repositories -ne 'all')
    {
        $enabledRepos = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/actions/permissions/repositories").repositories.node_id
    }

    $selfHostedRunnerEnabledRepos = $null
    if($selfHostedRunnerSettings.enabled_repositories -eq 'selected')
    {
        $selfHostedRunnerEnabledRepos = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/actions/permissions/self-hosted-runners/repositories").repositories.node_id
    }

    # Pre-loop setup: Custom repository roles and org-level all_repo_* IDs
    $customRepoRoles = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/custom-repository-roles").custom_roles

    $orgAllRepoReadId = "$($Organization.id)_all_repo_read"
    $orgAllRepoTriageId = "$($Organization.id)_all_repo_triage"
    $orgAllRepoWriteId = "$($Organization.id)_all_repo_write"
    $orgAllRepoMaintainId = "$($Organization.id)_all_repo_maintain"
    $orgAllRepoAdminId = "$($Organization.id)_all_repo_admin"

    # Per-repo processing: create repo node, role nodes, and fetch collaborator/team assignments
    Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/repos" | ForEach-Object -Parallel {

        $nodes = $using:nodes
        $edges = $using:edges
        $Session = $using:Session
        $Organization = $using:Organization
        $actions = $using:actions
        $selfHostedRunnerSettings = $using:selfHostedRunnerSettings
        $enabledRepos = $using:enabledRepos
        $selfHostedRunnerEnabledRepos = $using:selfHostedRunnerEnabledRepos
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

        if($selfHostedRunnerSettings.enabled_repositories -eq 'all')
        {
            $selfHostedRunnersEnabled = $true
        }
        elseif($selfHostedRunnerSettings.enabled_repositories -eq 'selected')
        {
            $selfHostedRunnersEnabled = $selfHostedRunnerEnabledRepos -contains $repo.node_id
        }
        else
        {
            $selfHostedRunnersEnabled = $false
        }

        $orgMembersId = "$($Organization.id)_members"

        $properties = @{
            # Common Properties
            #id                           = Normalize-Null $repo.id
            name                          = Normalize-Null $repo.name
            node_id                       = Normalize-Null $repo.node_id
            # Relational Properties
            environment_name              = Normalize-Null $Organization.properties.login
            environmentid                = Normalize-Null $Organization.properties.node_id
            owner_name                    = Normalize-Null $repo.owner.login
            #owner_id                     = Normalize-Null $repo.owner.id
            owner_id                      = Normalize-Null $repo.owner.node_id
            # Node Specific Properties
            full_name                     = Normalize-Null $repo.full_name
            private                       = Normalize-Null $repo.private
            html_url                      = Normalize-Null $repo.html_url
            description                   = Normalize-Null $description
            created_at                    = Normalize-Null $repo.created_at
            updated_at                    = Normalize-Null $repo.updated_at
            pushed_at                     = Normalize-Null $repo.pushed_at
            archived                      = Normalize-Null $repo.archived
            disabled                      = Normalize-Null $repo.disabled
            open_issues_count             = Normalize-Null $repo.open_issues_count
            allow_forking                 = Normalize-Null $repo.allow_forking
            web_commit_signoff_required   = Normalize-Null $repo.web_commit_signoff_required
            visibility                    = Normalize-Null $repo.visibility
            forks                         = Normalize-Null $repo.forks
            open_issues                   = Normalize-Null $repo.open_issues
            watchers                      = Normalize-Null $repo.watchers
            default_branch                = Normalize-Null $repo.default_branch
            actions_enabled               = Normalize-Null $actionsEnabled
            self_hosted_runners_enabled   = Normalize-Null $selfHostedRunnersEnabled
            secret_scanning               = Normalize-Null $repo.security_and_analysis.secret_scanning.status
            # Accordion Panel Queries
            query_branches                = "MATCH p=(:GH_Repository {node_id: '$($repo.node_id)'})-[:GH_HasBranch]->(:GH_Branch) RETURN p"
            query_protected_branches      = "MATCH p=(:GH_Repository {node_id: '$($repo.node_id)'})-[:GH_HasBranch]->(:GH_Branch)<-[:GH_ProtectedBy]-(:GH_BranchProtectionRule) RETURN p"
            query_branch_protection_rules = "MATCH p=(:GH_Repository {node_id: '$($repo.node_id)'})-[:GH_Contains]->(:GH_BranchBranchProtectionRule) RETURN p"
            query_roles                   = "MATCH p=(:GH_RepoRole)-[*1..2]->(:GH_Repository {node_id: '$($repo.node_id)'}) RETURN p"
            query_teams                   = "MATCH p=(:GH_Team)-[:GH_MemberOf|GH_HasRole*1..]->(:GH_RepoRole)-[]->(:GH_Repository {node_id: '$($repo.node_id)'}) RETURN p"
            query_workflows               = "MATCH p=(:GH_Repository {node_id:'$($repo.node_id)'})-[:GH_HasWorkflow]->(w:GH_Workflow) RETURN p"
            query_runners                 = "MATCH p=(:GH_Repository {node_id:'$($repo.node_id)'})-[:GH_CanUseRunner]->(:GH_Runner) RETURN p"
            query_environments            = "MATCH p=(:GH_Repository {node_id: '$($repo.node_id)'})-[:GH_HasEnvironment]->(:GH_Environment) RETURN p"
            query_secrets                 = "MATCH p=(:GH_Repository {node_id:'$($repo.node_id)'})-[:GH_HasSecret]->(:GH_Secret) RETURN p"
            query_variables               = "MATCH p=(:GH_Repository {node_id:'$($repo.node_id)'})-[:GH_HasVariable]->(:GH_Variable) RETURN p"
            query_secret_scanning_alerts  = "MATCH p=(:GH_Repository {node_id:'$($repo.node_id)'})-[:GH_Contains]->(:GH_SecretScanningAlert) RETURN p"
            query_explicit_readers        = "MATCH p=(role:GH_Role)-[:GH_HasBaseRole|GH_ReadRepoContents*1..]->(r:GH_Repository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
            query_unrolled_readers        = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(r:GH_Repository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
            query_explicit_writers        = "MATCH p=(role:GH_Role)-[:GH_HasBaseRole|GH_WriteRepoContents|GH_WriteRepoPullRequests*1..]->(r:GH_Repository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
            query_unrolled_writers        = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_WriteRepoContents|GH_WriteRepoPullRequests*1..]->(r:GH_Repository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"


            #query_user_permissions       = "MATCH p=(:GH_User)-[:GH_HasRole]->()-[:GH_HasBaseRole|GH_HasRole|GH_Owns|GH_AddMember|GH_MemberOf]->(:GH_RepoRole)-[]->(:GH_Repository {node_id: '$($repo.node_id)'}) RETURN p"
            #query_first_degree_object_control  = "MATCH p=(t:GH_User)-[:GH_HasRole]->(:GH_RepoRole)-[:GH_ReadRepoContents|GH_WriteRepoContents|GH_WriteRepoPullRequests|GH_ManageWebhooks|GH_ManageDeployKeys|GH_PushProtectedBranch|GH_DeleteAlertsCodeScanning|GH_ViewSecretScanningAlerts|GH_RunOrgMigration|GH_BypassBranchProtection|GH_EditRepoProtections]->(:GH_Repository {node_id:'$($repo.node_id)'}) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repo.node_id -Kind 'GH_Repository' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Owns' -StartId $repo.owner.node_id -EndId $repo.node_id -Properties @{ traversable = $true }))

        # --- Default Repository Role Nodes ---

        # Read Role
        $repoReadId = "$($repo.node_id)_read"
        $repoReadProps = [pscustomobject]@{
            # Common Properties
            name                   = Normalize-Null "$($repo.full_name)/read"
            node_id                = Normalize-Null $repoReadId
            # Relational Properties
            environment_name       = Normalize-Null $Organization.properties.login
            environmentid         = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'read'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoReadId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoReadId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {node_id:'$($repoReadId)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) OPTIONAL MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {node_id:'$($repoReadId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoReadId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoReadProps))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoMetadata' -StartId $repoReadId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoContents' -StartId $repoReadId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoPullRequests' -StartId $repoReadId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoReadId -EndId $repoReadId -Properties @{traversable=$true}))
        # Organization members can read internal repositories by default, so add a GH_HasRole edge from org members role to repo read role for internal repos
        if($repo.visibility -eq 'internal')
        {
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasRole' -StartId $orgMembersId -EndId $repoReadId -Properties @{traversable=$true}))
        }

        # Write Role
        $repoWriteId = "$($repo.node_id)_write"
        $repoWriteProps = [pscustomobject]@{
            # Common Properties
            name                   = Normalize-Null "$($repo.full_name)/write"
            node_id                = Normalize-Null $repoWriteId
            # Relational Properties
            environment_name       = Normalize-Null $Organization.properties.login
            environmentid         = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'write'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoWriteId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoWriteId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {node_id:'$($repoWriteId)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) OPTIONAL MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {node_id:'$($repoWriteId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoWriteId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoWriteProps))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoMetadata' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoContents' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteRepoContents' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddLabel' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveLabel' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseIssue' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenIssue' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoPullRequests' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteRepoPullRequests' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ClosePullRequest' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenPullRequest' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddAssignee' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetIssueType' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveAssignee' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RequestPrReview' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MarkAsDuplicate' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetMilestone' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadCodeScanning' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteCodeScanning' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionAnswer' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionCommentMinimize' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDiscussionSpotlights' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionCategory' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionCategory' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ConvertIssuesToDiscussions' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditCategoryOnDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionComment' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionComment' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewDependabotAlerts' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ResolveDependabotAlerts' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDiscussionBadges' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoWriteId -EndId $repoWriteId -Properties @{traversable=$true}))

        # Admin Role
        $repoAdminId = "$($repo.node_id)_admin"
        $repoAdminProps = [pscustomobject]@{
            # Common Properties
            name                   = Normalize-Null "$($repo.full_name)/admin"
            node_id                = Normalize-Null $repoAdminId
            # Relational Properties
            environment_name       = Normalize-Null $Organization.properties.login
            environmentid         = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'admin'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoAdminId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoAdminId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {node_id:'$($repoAdminId)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) OPTIONAL MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {node_id:'$($repoAdminId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoAdminId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoAdminProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AdminTo' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoMetadata' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoContents' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteRepoContents' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddLabel' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveLabel' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseIssue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenIssue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadRepoPullRequests' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteRepoPullRequests' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ClosePullRequest' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenPullRequest' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddAssignee' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteIssue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveAssignee' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RequestPrReview' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MarkAsDuplicate' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetMilestone' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetIssueType' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageTopics' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsDiscussions' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsWiki' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsProjects' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsMergeTypes' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsPages' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageWebhooks' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDeployKeys' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoMetadata' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetInteractionLimits' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetSocialPreview' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_PushProtectedBranch' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadCodeScanning' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteCodeScanning' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteAlertsCodeScanning' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewSecretScanningAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ResolveSecretScanningAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RunOrgMigration' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionAnnouncement' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionCategory' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionCategory' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionCategory' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDiscussionSpotlights' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionAnswer' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionCommentMinimize' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ConvertIssuesToDiscussions' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateTag' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteTag' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewDependabotAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ResolveDependabotAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_BypassBranchProtection' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSecurityProducts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageRepoSecurityProducts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoProtections' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoAnnouncementBanners' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditCategoryOnDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDiscussionBadges' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionComment' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionComment' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_JumpMergeQueue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateSoloMergeQueueEntry' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoCustomPropertiesValues' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoAdminId -EndId $repoAdminId -Properties @{traversable=$true}))

        # Triage Role
        $repoTriageId = "$($repo.node_id)_triage"
        $repoTriageProps = [pscustomobject]@{
            # Common Properties
            name                   = Normalize-Null "$($repo.full_name)/triage"
            node_id                = Normalize-Null $repoTriageId
            # Relational Properties
            environment_name       = Normalize-Null $Organization.properties.login
            environmentid         = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'triage'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoTriageId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoTriageId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {node_id:'$($repoTriageId)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) OPTIONAL MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {node_id:'$($repoTriageId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoTriageId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoTriageProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddLabel' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveLabel' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseIssue' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenIssue' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ClosePullRequest' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenPullRequest' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddAssignee' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveAssignee' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RequestPrReview' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MarkAsDuplicate' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetMilestone' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetIssueType' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionAnswer' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionCommentMinimize' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionCategory' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionCategory' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ConvertIssuesToDiscussions' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditCategoryOnDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionComment' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionComment' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $repoTriageId -EndId $repoReadId -Properties @{traversable=$true}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoTriageId -EndId $repoTriageId -Properties @{traversable=$true}))

        # Maintain Role
        $repoMaintainId = "$($repo.node_id)_maintain"
        $repoMaintainProps = [pscustomobject]@{
            # Common Properties
            name                   = Normalize-Null "$($repo.full_name)/maintain"
            node_id                = Normalize-Null $repoMaintainId
            # Relational Properties
            environment_name       = Normalize-Null $Organization.properties.login
            environmentid         = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'maintain'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoMaintainId)'}) RETURN p"
            query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($repoMaintainId)'}) RETURN p"
            query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {node_id:'$($repoMaintainId)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) OPTIONAL MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
            query_repository_permissions = "MATCH p=(:GH_RepoRole {node_id:'$($repoMaintainId)'})-[*1..]->(:GH_Repository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoMaintainId -Kind 'GH_RepoRole', 'GH_Role' -Properties $repoMaintainProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageTopics' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsWiki' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsProjects' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsMergeTypes' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsPages' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoMetadata' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetInteractionLimits' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetSocialPreview' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_PushProtectedBranch' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateTag' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoAnnouncementBanners' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionAnnouncement' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionCategory' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsDiscussion' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $repoMaintainId -EndId $repoWriteId -Properties @{traversable=$true}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $orgAllRepoMaintainId -EndId $repoMaintainId -Properties @{traversable=$true}))

        # --- Custom Repository Roles ---
        foreach($customRepoRole in $customRepoRoles)
        {
            $customRepoRoleId = "$($repo.node_id)_$($customRepoRole.name)"
            $customRepoRoleProps = [pscustomobject]@{
                # Common Properties
                name                   = Normalize-Null "$($repo.full_name)/$($customRepoRole.name)"
                node_id                = Normalize-Null $customRepoRoleId
                # Relational Properties
                environment_name       = Normalize-Null $Organization.properties.login
                environmentid         = Normalize-Null $Organization.properties.node_id
                repository_name        = Normalize-Null $repo.name
                repository_id          = Normalize-Null $repo.node_id
                # Node Specific Properties
                short_name             = Normalize-Null $customRepoRole.name
                type                   = Normalize-Null 'custom'
                # Accordion Panel Queries
                query_explicit_users         = "MATCH p=(:GH_User)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($customRepoRoleId)'}) RETURN p"
                query_explicit_teams         = "MATCH p=(:GH_Team)-[:GH_HasRole]->(:GH_RepoRole {node_id:'$($customRepoRoleId)'}) RETURN p"
                query_unrolled_members       = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ReadRepoContents*1..]->(reporole:GH_RepoRole {node_id:'$($customRepoRoleId)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) OPTIONAL MATCH p2=(reporole)<-[:GH_HasRole]-(:GH_User) RETURN p,p1,p2"
                query_repository_permissions = "MATCH p=(:GH_RepoRole {node_id:'$($customRepoRoleId)'})-[*1..]->(:GH_Repository) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $customRepoRoleId -Kind 'GH_RepoRole', 'GH_Role' -Properties $customRepoRoleProps))

            if($null -ne $customRepoRole.base_role)
            {
                $targetBaseRoleId = "$($repo.node_id)_$($customRepoRole.base_role)"
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasBaseRole' -StartId $customRepoRoleId -EndId $targetBaseRoleId -Properties @{traversable=$true}))
            }

            foreach($permission in $customRepoRole.permissions)
            {
                switch($permission)
                {
                    # Issues & Pull Requests
                    'add_label' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddLabel' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'remove_label' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveLabel' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'close_issue' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseIssue' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'reopen_issue' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenIssue' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'close_pull_request' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ClosePullRequest' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'reopen_pull_request' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenPullRequest' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'add_assignee' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_AddAssignee' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'delete_issue' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteIssue' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'remove_assignee' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RemoveAssignee' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'request_pr_review' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_RequestPrReview' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'mark_as_duplicate' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_MarkAsDuplicate' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'set_milestone' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetMilestone' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'set_issue_type' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetIssueType' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    # Repository Settings
                    'manage_topics' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageTopics' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'manage_settings_wiki' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsWiki' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'manage_settings_projects' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsProjects' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'manage_settings_merge_types' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsMergeTypes' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'manage_settings_pages' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageSettingsPages' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'manage_webhooks' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageWebhooks' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'manage_deploy_keys' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDeployKeys' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'edit_repo_metadata' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoMetadata' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'set_interaction_limits' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetInteractionLimits' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'set_social_preview' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_SetSocialPreview' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'edit_repo_announcement_banners' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoAnnouncementBanners' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    # Branch & Tag Operations
                    'push_protected_branch' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_PushProtectedBranch' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'bypass_branch_protection' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_BypassBranchProtection' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'edit_repo_protections' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoProtections' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'create_tag' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateTag' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'delete_tag' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteTag' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    # Code Scanning & Security
                    'read_code_scanning' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReadCodeScanning' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'write_code_scanning' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_WriteCodeScanning' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'delete_alerts_code_scanning' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteAlertsCodeScanning' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'view_secret_scanning_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewSecretScanningAlerts' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'resolve_secret_scanning_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ResolveSecretScanningAlerts' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    # Dependabot
                    'view_dependabot_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ViewDependabotAlerts' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'resolve_dependabot_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ResolveDependabotAlerts' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    # Discussions
                    'delete_discussion' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussion' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'toggle_discussion_answer' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionAnswer' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'toggle_discussion_comment_minimize' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ToggleDiscussionCommentMinimize' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'edit_discussion_category' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionCategory' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'create_discussion_category' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateDiscussionCategory' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'convert_issues_to_discussions' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ConvertIssuesToDiscussions' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'close_discussion' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CloseDiscussion' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'reopen_discussion' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ReopenDiscussion' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'edit_category_on_discussion' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditCategoryOnDiscussion' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'manage_discussion_badges' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ManageDiscussionBadges' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'edit_discussion_comment' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditDiscussionComment' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'delete_discussion_comment' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_DeleteDiscussionComment' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    # Merge Queue & Custom Properties
                    'jump_merge_queue' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_JumpMergeQueue' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'create_solo_merge_queue_entry' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CreateSoloMergeQueueEntry' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                    'edit_repo_custom_properties_values' { $null = $edges.Add((New-GitHoundEdge -Kind 'GH_EditRepoCustomPropertiesValues' -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false})) }
                }
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
                $repoReadId     = "$($repo.properties.node_id)_read"
                $repoWriteId    = "$($repo.properties.node_id)_write"
                $repoAdminId    = "$($repo.properties.node_id)_admin"
                $repoTriageId   = "$($repo.properties.node_id)_triage"
                $repoMaintainId = "$($repo.properties.node_id)_maintain"

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
                        default    { $repoRoleId = "$($repo.properties.node_id)_$($collaborator.role_name)" }
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
                        default    { $repoRoleId = "$($repo.properties.node_id)_$($team.permission)" }
                    }
                    $teamMatchers = Get-GitHoundOrganizationTeamPropertyMatchers -OrganizationId $repo.properties.environmentid -TeamSlug $team.slug
                    if($teamMatchers)
                    {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasRole' -StartKind 'GH_Team' -StartPropertyMatchers $teamMatchers -EndId $repoRoleId -Properties @{traversable=$true}))
                    }
                    else
                    {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasRole' -StartId $team.node_id -EndId $repoRoleId -Properties @{traversable=$true}))
                    }
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
    # Map: branchProtectionRule ID → { name, id } of its parent repository (for Phase 3)
    $ruleToRepo = @{}

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

                # Track rule-to-branch and rule-to-repo mappings for Phase 3
                if ($rule) {
                    if (-not $ruleToBranches.ContainsKey($rule.id)) {
                        $ruleToBranches[$rule.id] = New-Object System.Collections.ArrayList
                        $ruleToRepo[$rule.id] = @{ name = $repo.name; id = $repo.id }
                    }
                    $null = $ruleToBranches[$rule.id].Add($branchId)
                }

                $props = [pscustomobject]@{
                    # Common Properties
                    name               = Normalize-Null "$($repo.name)\$($ref.name)"
                    node_id            = Normalize-Null $branchId
                    # Relational Properties
                    environment_name   = Normalize-Null $orgLogin
                    environmentid     = Normalize-Null $orgNodeId
                    repository_name    = Normalize-Null $repo.name
                    repository_id      = Normalize-Null $repo.id
                    # Node Specific Properties
                    short_name         = Normalize-Null $ref.name
                    commit_hash        = Normalize-Null $ref.target.oid
                    protected          = Normalize-Null ($null -ne $rule)
                    # Accordion Panel Queries
                    query_branch_write = "MATCH p=(:GH_User)-[:GH_CanWriteBranch|GH_CanEditAndWriteBranch]->(:GH_Branch {objectid:'$($branchId)'}) RETURN p"
                }

                $null = $nodes.Add((New-GitHoundNode -Id $branchId -Kind GH_Branch -Properties $props))
                $null = $edges.Add((New-GitHoundEdge -Kind GH_HasBranch -StartId $repo.id -EndId $branchId -Properties @{ traversable = $false }))
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

                # Track rule-to-branch and rule-to-repo mappings for Phase 3
                if ($rule) {
                    if (-not $ruleToBranches.ContainsKey($rule.id)) {
                        $ruleToBranches[$rule.id] = New-Object System.Collections.ArrayList
                        $ruleToRepo[$rule.id] = @{ name = $overflowRepo.name; id = $overflowRepo.nodeId }
                    }
                    $null = $ruleToBranches[$rule.id].Add($branchId)
                }

                $props = [pscustomobject]@{
                    # Common Properties
                    name               = Normalize-Null "$($overflowRepo.name)\$($ref.name)"
                    node_id            = Normalize-Null $branchId
                    # Relational Properties
                    environment_name   = Normalize-Null $orgLogin
                    environmentid     = Normalize-Null $orgNodeId
                    repository_name    = Normalize-Null $overflowRepo.name
                    repository_id      = Normalize-Null $overflowRepo.nodeId
                    # Node Specific Properties
                    short_name         = Normalize-Null $ref.name
                    commit_hash        = Normalize-Null $ref.target.oid
                    protected          = Normalize-Null ($null -ne $rule)
                    # Accordion Panel Queries
                    query_repo         = "MATCH p=(:GH_Repository)-[:GH_HasBranch]->(:GH_Branch {objectid:'$($branchId)'}) RETURN p"
                    query_protection   = "MATCH p=(:GH_BranchProtectionRule)-[:GH_ProtectedBy]->(:GH_Branch {objectid:'$($branchId)'}) RETURN p"
                    query_branch_write = "MATCH p=(:GH_User)-[:GH_CanWriteBranch|GH_CanEditAndWriteBranch]->(:GH_Branch {objectid:'$($branchId)'}) RETURN p"
                }

                $null = $nodes.Add((New-GitHoundNode -Id $branchId -Kind GH_Branch -Properties $props))
                $null = $edges.Add((New-GitHoundEdge -Kind GH_HasBranch -StartId $overflowRepo.nodeId -EndId $branchId -Properties @{ traversable = $false }))
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
            blocksCreations
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
                $ruleRepo = $ruleToRepo[$ruleId]

                # Create GH_BranchProtectionRule node
                $props = [pscustomobject]@{
                    # Common Properties
                    name                            = Normalize-Null $rule.pattern
                    node_id                         = Normalize-Null $ruleId
                    # Relational Properties
                    environment_name                = Normalize-Null $orgLogin
                    environmentid                  = Normalize-Null $orgNodeId
                    repository_name                 = Normalize-Null $ruleRepo.name
                    repository_id                   = Normalize-Null $ruleRepo.id
                    # Node Specific Properties
                    pattern                         = Normalize-Null $rule.pattern
                    enforce_admins                  = Normalize-Null $rule.isAdminEnforced
                    lock_branch                     = Normalize-Null $rule.lockBranch
                    blocks_creations                = Normalize-Null $rule.blocksCreations
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
                    query_user_exceptions           = "MATCH p=(:GH_User)-[]->(:GH_BranchProtectionRule {node_id:'$($rule.id)'}) RETURN p"
                    query_branches                  = "MATCH p=(:GH_BranchProtectionRule {node_id:'$($rule.id)'})-[:GH_ProtectedBy]->(:GH_Branch) RETURN p"
                }

                $null = $nodes.Add((New-GitHoundNode -Id $ruleId -Kind GH_BranchProtectionRule -Properties $props))
                $null = $edges.Add((New-GitHoundEdge -Kind GH_Contains -StartId $ruleRepo.id -EndId $ruleId -Properties @{ traversable = $false }))

                # Create GH_ProtectedBy edges from this rule to its branches
                foreach ($branchId in $ruleToBranches[$ruleId]) {
                    $null = $edges.Add((New-GitHoundEdge -Kind GH_ProtectedBy -StartId $ruleId -EndId $branchId -Properties @{ traversable = $false }))
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

function Compute-GitHoundBranchAccess
{
    <#
    .SYNOPSIS
        Computes effective branch access edges from accumulated collection data.

    .DESCRIPTION
        This function evaluates effective push access by cross-referencing role permissions
        with branch protection rule (BPR) settings and per-rule allowances. It produces
        traversable computed edges that represent the final evaluated access:

        - GH_CanCreateBranch (User/Team -> Repository): Actor can create new branches
        - GH_CanWriteBranch  (User/Team -> Branch or Repository): Actor can push to branch(es)
        - GH_CanEditProtection (RepoRole -> Branch): Role can modify/remove protections governing this branch

        The computation evaluates two independent gates per branch:

        Merge gate (PR reviews, lock branch):
          Bypassed by: bypass_branch_protection (suppressed by enforce_admins),
                       bypassPullRequestAllowances (PR reviews only, suppressed by enforce_admins)

        Push gate (push restrictions, blocks creations):
          Bypassed by: admin, push_protected_branch, pushAllowances
          NOT affected by enforce_admins

        This function makes no API calls — it is a pure in-memory computation over
        previously collected nodes and edges.

    .PARAMETER Nodes
        ArrayList of all accumulated nodes from prior collection steps.

    .PARAMETER Edges
        ArrayList of all accumulated edges from prior collection steps.

    .OUTPUTS
        PSCustomObject with Nodes (empty) and Edges (computed edges).

    .EXAMPLE
        $result = Compute-GitHoundBranchAccess -Nodes $nodes -Edges $edges
    #>
    Param(
        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]
        $Nodes,

        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]
        $Edges
    )

    $computedEdges = New-Object System.Collections.ArrayList
    $emittedEdges = @{} # Deduplication: "actorId|targetId|edgeKind" -> $true

    # ── Phase 1: Build indexes ─────────────────────────────────────────────

    Write-Host "[*]   Phase 1: Building indexes from $($Nodes.Count) nodes and $($Edges.Count) edges..."

    # Node lookup by ID
    $nodeById = @{}
    foreach ($node in $Nodes) {
        if ($node.id) {
            $nodeById[$node.id] = $node
        }
    }

    function Test-GitHoundNodeMatchesPropertyMatchers {
        param(
            [Parameter(Mandatory = $true)]
            $Node,

            [Parameter(Mandatory = $true)]
            [array]$PropertyMatchers
        )

        foreach ($matcher in $PropertyMatchers) {
            if ($matcher.operator -ne 'equals') { return $false }

            $nodeValue = $null
            if ($Node.properties -and $null -ne $Node.properties.PSObject.Properties[$matcher.key]) {
                $nodeValue = $Node.properties.$($matcher.key)
            }

            if ($null -eq $nodeValue -and $null -eq $matcher.value) { continue }
            if ([string]$nodeValue -ne [string]$matcher.value) { return $false }
        }

        return $true
    }

    function Resolve-GitHoundEdgeEndpointIds {
        param(
            [Parameter(Mandatory = $true)]
            $Endpoint
        )

        if ($Endpoint.match_by -eq 'property' -and $Endpoint.property_matchers) {
            $matches = New-Object System.Collections.ArrayList
            foreach ($node in $Nodes) {
                if ($Endpoint.kind -and ($node.kinds -notcontains $Endpoint.kind)) { continue }
                if (Test-GitHoundNodeMatchesPropertyMatchers -Node $node -PropertyMatchers $Endpoint.property_matchers) {
                    $null = $matches.Add($node.id)
                }
            }
            return @($matches | Where-Object { $_ })
        }

        if ($Endpoint.value) {
            return @($Endpoint.value)
        }

        return @()
    }

    $resolvedEdges = New-Object System.Collections.ArrayList
    foreach ($edge in $Edges) {
        $resolvedStartIds = Resolve-GitHoundEdgeEndpointIds -Endpoint $edge.start
        $resolvedEndIds = Resolve-GitHoundEdgeEndpointIds -Endpoint $edge.end

        foreach ($startId in $resolvedStartIds) {
            foreach ($endId in $resolvedEndIds) {
                if ([string]::IsNullOrWhiteSpace([string]$startId) -or [string]::IsNullOrWhiteSpace([string]$endId)) { continue }
                $null = $resolvedEdges.Add([PSCustomObject]@{
                    kind = $edge.kind
                    start = [PSCustomObject]@{ value = $startId }
                    end = [PSCustomObject]@{ value = $endId }
                    properties = $edge.properties
                })
            }
        }
    }

    # Edge direction indexes: outbound["kind|startId"] -> [endIds], inbound["kind|endId"] -> [startIds]
    $outbound = @{}
    $inbound = @{}
    foreach ($edge in $resolvedEdges) {
        $startId = $edge.start.value
        $endId = $edge.end.value
        $kind = $edge.kind

        $outKey = "$kind|$startId"
        if (-not $outbound.ContainsKey($outKey)) {
            $outbound[$outKey] = New-Object System.Collections.ArrayList
        }
        $null = $outbound[$outKey].Add($endId)

        $inKey = "$kind|$endId"
        if (-not $inbound.ContainsKey($inKey)) {
            $inbound[$inKey] = New-Object System.Collections.ArrayList
        }
        $null = $inbound[$inKey].Add($startId)
    }

    # Repo -> Branches mapping (from GH_HasBranch edges)
    $repoBranches = @{}
    foreach ($edge in $resolvedEdges) {
        if ($edge.kind -eq 'GH_HasBranch') {
            $repoId = $edge.start.value
            if (-not $repoBranches.ContainsKey($repoId)) {
                $repoBranches[$repoId] = New-Object System.Collections.ArrayList
            }
            $null = $repoBranches[$repoId].Add($edge.end.value)
        }
    }

    # Branch -> BPR mapping (from GH_ProtectedBy edges: BPR -> Branch)
    $branchToBPR = @{}
    foreach ($edge in $resolvedEdges) {
        if ($edge.kind -eq 'GH_ProtectedBy') {
            $branchToBPR[$edge.end.value] = $edge.start.value
        }
    }

    # BPR -> Repo mapping (derived: BPR -> ProtectedBy -> Branch -> HasBranch -> Repo)
    $bprToRepo = @{}
    foreach ($branchId in $branchToBPR.Keys) {
        $bprId = $branchToBPR[$branchId]
        if (-not $bprToRepo.ContainsKey($bprId)) {
            # Find which repo this branch belongs to via inbound GH_HasBranch
            $hasBranchKey = "GH_HasBranch|$branchId"
            if ($inbound.ContainsKey($hasBranchKey)) {
                $bprToRepo[$bprId] = $inbound[$hasBranchKey][0]
            }
        }
    }

    # Role -> Permissions mapping (from permission edges: Role -> Repo)
    $rolePermissions = @{}
    $roleToRepo = @{}
    $permissionEdgeKinds = @('GH_WriteRepoContents', 'GH_AdminTo', 'GH_PushProtectedBranch',
                              'GH_BypassBranchProtection', 'GH_EditRepoProtections')
    foreach ($edge in $resolvedEdges) {
        if ($edge.kind -in $permissionEdgeKinds) {
            $roleId = $edge.start.value
            if (-not $rolePermissions.ContainsKey($roleId)) {
                $rolePermissions[$roleId] = New-Object System.Collections.Generic.HashSet[string]
            }
            $null = $rolePermissions[$roleId].Add($edge.kind)
            $roleToRepo[$roleId] = $edge.end.value
        }
    }

    # Per-rule allowance actors (from GH_RestrictionsCanPush and GH_BypassPullRequestAllowances edges)
    $pushAllowanceActors = @{}
    $bypassPRActors = @{}
    foreach ($edge in $resolvedEdges) {
        if ($edge.kind -eq 'GH_RestrictionsCanPush') {
            $bprId = $edge.end.value
            if (-not $pushAllowanceActors.ContainsKey($bprId)) {
                $pushAllowanceActors[$bprId] = New-Object System.Collections.Generic.HashSet[string]
            }
            $null = $pushAllowanceActors[$bprId].Add($edge.start.value)
        }
        elseif ($edge.kind -eq 'GH_BypassPullRequestAllowances') {
            $bprId = $edge.end.value
            if (-not $bypassPRActors.ContainsKey($bprId)) {
                $bypassPRActors[$bprId] = New-Object System.Collections.Generic.HashSet[string]
            }
            $null = $bypassPRActors[$bprId].Add($edge.start.value)
        }
    }

    # Collect all repos (nodes with GH_Repository kind)
    $repoIds = New-Object System.Collections.ArrayList
    foreach ($node in $Nodes) {
        if ($node.kinds -contains 'GH_Repository') {
            $null = $repoIds.Add($node.id)
        }
    }

    # Collect all BPR nodes per repo
    $repoBPRs = @{}
    foreach ($node in $Nodes) {
        if ($node.kinds -contains 'GH_BranchProtectionRule') {
            $bprId = $node.id
            if ($bprToRepo.ContainsKey($bprId)) {
                $repoId = $bprToRepo[$bprId]
                if (-not $repoBPRs.ContainsKey($repoId)) {
                    $repoBPRs[$repoId] = New-Object System.Collections.ArrayList
                }
                $null = $repoBPRs[$repoId].Add($bprId)
            }
        }
    }

    Write-Host "[*]   Phase 1 complete. $($repoIds.Count) repos, $($repoBranches.Count) repos with branches, $($branchToBPR.Count) protected branches."

    # ── Phase 2: Build role full permission sets ─────────────────────────

    Write-Host "[*]   Phase 2: Resolving role permissions..."

    # Helper: Get all roles that inherit from a given role (reverse-transitive closure of GH_HasBaseRole)
    # GH_HasBaseRole goes from child -> parent (child inherits from parent)
    # We want: given a parent role, find all child roles that inherit from it
    function Get-InheritingRoles {
        param([string]$RoleId, [hashtable]$VisitedRoles)
        if ($VisitedRoles.ContainsKey($RoleId)) { return @() }
        $VisitedRoles[$RoleId] = $true

        $result = @($RoleId)
        $inKey = "GH_HasBaseRole|$RoleId"
        if ($inbound.ContainsKey($inKey)) {
            foreach ($childRoleId in $inbound[$inKey]) {
                $result += Get-InheritingRoles -RoleId $childRoleId -VisitedRoles $VisitedRoles
            }
        }
        return $result
    }

    # Helper: Collect full permission set for a role by following outbound GH_HasBaseRole (forward traversal)
    # A role inherits all permissions from its base roles
    function Get-BaseRolePerms {
        param([string]$RoleId, [hashtable]$Visited)
        if ($Visited.ContainsKey($RoleId)) { return @() }
        $Visited[$RoleId] = $true

        $perms = @()
        if ($rolePermissions.ContainsKey($RoleId)) {
            $perms = @($rolePermissions[$RoleId])
        }

        # Follow outbound GH_HasBaseRole to collect inherited perms
        $outKey = "GH_HasBaseRole|$RoleId"
        if ($outbound.ContainsKey($outKey)) {
            foreach ($baseRoleId in $outbound[$outKey]) {
                $perms += Get-BaseRolePerms -RoleId $baseRoleId -Visited $Visited
            }
        }
        return $perms
    }

    # Build: $roleFullPerms[roleId] = HashSet of ALL permission edge kinds (direct + inherited)
    # Build: $repoWriteRoles[repoId] = list of roleIds with write access
    $roleFullPerms = @{}
    $repoWriteRoles = @{}

    # Collect all roles that have any direct permission edges
    $allPermRoleIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($roleId in $rolePermissions.Keys) {
        $null = $allPermRoleIds.Add($roleId)
    }

    # Also find roles that inherit from permissioned roles (they might have their own perms too)
    # We need all RepoRole nodes that map to a repo
    foreach ($node in $Nodes) {
        if ($node.kinds -contains 'GH_RepoRole') {
            $null = $allPermRoleIds.Add($node.id)
        }
    }

    foreach ($roleId in $allPermRoleIds) {
        if ($roleFullPerms.ContainsKey($roleId)) { continue }

        $perms = Get-BaseRolePerms -RoleId $roleId -Visited @{}
        $permSet = New-Object System.Collections.Generic.HashSet[string]
        foreach ($p in $perms) { $null = $permSet.Add($p) }
        $roleFullPerms[$roleId] = $permSet

        # Determine which repo this role grants access to
        $repoId = $roleToRepo[$roleId]
        if (-not $repoId) {
            # This role might not have direct perm edges but inherits from one that does
            # Follow HasBaseRole forward to find the repo
            $outKey = "GH_HasBaseRole|$roleId"
            if ($outbound.ContainsKey($outKey)) {
                foreach ($baseId in $outbound[$outKey]) {
                    if ($roleToRepo.ContainsKey($baseId)) {
                        $repoId = $roleToRepo[$baseId]
                        break
                    }
                }
            }
        }
        if (-not $repoId) { continue }

        $hasWrite = $permSet.Contains('GH_WriteRepoContents') -or $permSet.Contains('GH_AdminTo')
        if ($hasWrite) {
            if (-not $repoWriteRoles.ContainsKey($repoId)) {
                $repoWriteRoles[$repoId] = New-Object System.Collections.ArrayList
            }
            $null = $repoWriteRoles[$repoId].Add($roleId)
        }
    }

    # Build: $actorRepoRoles[repoId][actorId] = [leaf roleIds the actor reaches on this repo]
    # Needed for Phase 3b to compute delta for per-actor allowance edges
    $actorRepoRoles = @{}

    foreach ($roleId in $rolePermissions.Keys) {
        $repoId = $roleToRepo[$roleId]
        if (-not $repoId) { continue }

        # Find all roles that eventually inherit from this role
        $allRoles = Get-InheritingRoles -RoleId $roleId -VisitedRoles @{}

        foreach ($roleInChain in $allRoles) {
            # Find actors (Users/Teams) with GH_HasRole to this role
            $hasRoleKey = "GH_HasRole|$roleInChain"
            if (-not $inbound.ContainsKey($hasRoleKey)) { continue }

            foreach ($actorId in $inbound[$hasRoleKey]) {
                if ([string]::IsNullOrWhiteSpace([string]$actorId)) { continue }
                if (-not $nodeById.ContainsKey($actorId)) { continue }

                $actorNode = $nodeById[$actorId]
                if (-not $actorNode) { continue }
                if ($actorNode.kinds -notcontains 'GH_User' -and $actorNode.kinds -notcontains 'GH_Team') { continue }

                if (-not $actorRepoRoles.ContainsKey($repoId)) {
                    $actorRepoRoles[$repoId] = @{}
                }
                if (-not $actorRepoRoles[$repoId].ContainsKey($actorId)) {
                    $actorRepoRoles[$repoId][$actorId] = New-Object System.Collections.Generic.HashSet[string]
                }
                # Map actor to the leaf role (the one with direct permission edges)
                $null = $actorRepoRoles[$repoId][$actorId].Add($roleId)
            }
        }
    }

    $totalRoleRepoPairs = 0
    foreach ($repoId in $repoWriteRoles.Keys) {
        $totalRoleRepoPairs += $repoWriteRoles[$repoId].Count
    }
    Write-Host "[*]   Phase 2 complete. $totalRoleRepoPairs role-repo write pairs resolved."

    # ── Phase 3a: Role-level computed edges ────────────────────────────────

    Write-Host "[*]   Phase 3a: Computing role-level access edges..."

    # Helper: Check if a BPR boolean property is true (handles both boolean and string after Normalize-Null)
    function Test-BPRProperty {
        param($Value)
        if ($Value -is [bool]) { return $Value }
        if ($Value -is [string]) { return $Value -eq 'True' }
        return $false
    }

    # Helper: Emit a computed edge with deduplication
    function Add-ComputedEdge {
        param(
            [string]$Kind,
            [string]$StartId,
            [string]$EndId,
            [hashtable]$Properties
        )
        $dedupKey = "$StartId|$EndId|$Kind"
        if ($emittedEdges.ContainsKey($dedupKey)) { return }
        $emittedEdges[$dedupKey] = $true
        $null = $computedEdges.Add((New-GitHoundEdge -Kind $Kind -StartId $StartId -EndId $EndId -Properties $Properties))
    }

    # Helper: Evaluate branch gates for a permission set (role-level, no per-actor allowances)
    # Returns: hashtable { accessible = [branchIds]; reasons = @{ branchId = reason } }
    function Invoke-RoleGateEvaluation {
        param(
            [System.Collections.Generic.HashSet[string]]$Perms,
            [System.Collections.ArrayList]$Branches,
            [hashtable]$BranchToBPR
        )

        $hasAdmin = $Perms.Contains('GH_AdminTo')
        $hasPushProtected = $Perms.Contains('GH_PushProtectedBranch')
        $hasBypassBranch = $Perms.Contains('GH_BypassBranchProtection')

        $accessible = New-Object System.Collections.ArrayList
        $reasons = @{}

        foreach ($branchId in $Branches) {
            $bprId = if ($BranchToBPR.ContainsKey($branchId)) { $BranchToBPR[$branchId] } else { $null }

            if (-not $bprId) {
                $null = $accessible.Add($branchId)
                $reasons[$branchId] = 'no_protection'
                continue
            }

            $bprNode = $nodeById[$bprId]
            if (-not $bprNode) {
                $null = $accessible.Add($branchId)
                $reasons[$branchId] = 'no_protection'
                continue
            }
            $bp = $bprNode.properties

            $enforceAdmins = Test-BPRProperty $bp.enforce_admins
            $hasPRReviews = Test-BPRProperty $bp.required_pull_request_reviews
            $hasLockBranch = Test-BPRProperty $bp.lock_branch
            $hasPushRestrictions = Test-BPRProperty $bp.push_restrictions

            # ── Evaluate merge gate ──
            $mergeGateBlocked = $hasPRReviews -or $hasLockBranch
            $passesMergeGate = $false
            $mergeReason = $null

            if (-not $mergeGateBlocked) {
                $passesMergeGate = $true
            }
            elseif ($hasAdmin -and -not $enforceAdmins) {
                $passesMergeGate = $true
                $mergeReason = 'admin'
            }
            elseif ($hasBypassBranch -and -not $enforceAdmins) {
                $passesMergeGate = $true
                $mergeReason = 'bypass_branch_protection'
            }
            # Note: bypassPRAllowances is per-actor, not evaluated here (handled in Phase 3b)

            # ── Evaluate push gate ──
            $pushGateBlocked = $hasPushRestrictions
            $passesPushGate = $false
            $pushReason = $null

            if (-not $pushGateBlocked) {
                $passesPushGate = $true
            }
            elseif ($hasAdmin) {
                $passesPushGate = $true
                $pushReason = 'admin'
            }
            elseif ($hasPushProtected) {
                $passesPushGate = $true
                $pushReason = 'push_protected_branch'
            }
            # Note: pushAllowances is per-actor, not evaluated here (handled in Phase 3b)

            # ── Combined result ──
            if ($passesMergeGate -and $passesPushGate) {
                $null = $accessible.Add($branchId)
                if ($mergeReason -and $pushReason) {
                    $reasons[$branchId] = $mergeReason
                }
                elseif ($mergeReason) {
                    $reasons[$branchId] = $mergeReason
                }
                elseif ($pushReason) {
                    $reasons[$branchId] = $pushReason
                }
                else {
                    $reasons[$branchId] = 'no_protection'
                }
            }
        }

        return @{ accessible = $accessible; reasons = $reasons }
    }

    # Track role-level accessible branches for Phase 3b delta computation
    $roleAccessibleBranches = @{}
    # Track whether each role got GH_CanCreateBranch for Phase 3b
    $roleCanCreate = @{}

    foreach ($repoId in $repoIds) {
        if (-not $repoWriteRoles.ContainsKey($repoId)) { continue }

        if ($repoBranches.ContainsKey($repoId)) { $branches = $repoBranches[$repoId] } else { $branches = @() }
        if ($repoBPRs.ContainsKey($repoId)) { $bprs = $repoBPRs[$repoId] } else { $bprs = @() }

        # Find the wildcard (*) BPR with push_restrictions + blocks_creations
        $wildcardBlockingBPR = $null
        foreach ($bprId in $bprs) {
            $bprNode = $nodeById[$bprId]
            if (-not $bprNode) { continue }
            $p = $bprNode.properties
            if ($p.pattern -eq '*' -and (Test-BPRProperty $p.push_restrictions) -and (Test-BPRProperty $p.blocks_creations)) {
                $wildcardBlockingBPR = $bprNode
                break
            }
        }

        foreach ($roleId in $repoWriteRoles[$repoId]) {
            $perms = $roleFullPerms[$roleId]
            $hasAdmin = $perms.Contains('GH_AdminTo')
            $hasPushProtected = $perms.Contains('GH_PushProtectedBranch')
            $hasBypassBranch = $perms.Contains('GH_BypassBranchProtection')
            $hasEditProtections = $perms.Contains('GH_EditRepoProtections')

            # ── GH_CanEditProtection (role -> repo and each protected branch) ──
            if ($hasEditProtections -or $hasAdmin) {
                $reason = if ($hasAdmin) { 'admin' } else { 'edit_repo_protections' }
                if ($bprs.Count -gt 0) {
                    Add-ComputedEdge -Kind 'GH_CanEditProtection' -StartId $roleId -EndId $repoId `
                        -Properties @{ traversable = $true; reason = $reason;
                            query_composition = "MATCH p=(:GH_RepoRole {objectid:'$($roleId.ToUpper())'})-[:GH_EditRepoProtections|GH_AdminTo]->(:GH_Repository {objectid:'$($repoId.ToUpper())'})-[:GH_HasBranch]->(:GH_Branch)<-[:GH_ProtectedBy]-(:GH_BranchProtectionRule) RETURN p" }
                }
                foreach ($branchId in $branches) {
                    if ($branchToBPR.ContainsKey($branchId)) {
                        Add-ComputedEdge -Kind 'GH_CanEditProtection' -StartId $roleId -EndId $branchId `
                            -Properties @{ traversable = $true; reason = $reason;
                                query_composition = "MATCH p=(:GH_RepoRole {objectid:'$($roleId.ToUpper())'})-[:GH_EditRepoProtections|GH_AdminTo]->(:GH_Repository)-[:GH_HasBranch]->(:GH_Branch {objectid:'$($branchId.ToUpper())'})<-[:GH_ProtectedBy]-(:GH_BranchProtectionRule) RETURN p" }
                    }
                }
            }

            # ── GH_CanCreateBranch (role -> repo) ──
            $roleCanCreate[$roleId] = $false
            if (-not $wildcardBlockingBPR) {
                Add-ComputedEdge -Kind 'GH_CanCreateBranch' -StartId $roleId -EndId $repoId `
                    -Properties @{ traversable = $true; reason = 'no_protection';
                        query_composition = "MATCH p=(:GH_RepoRole {objectid:'$($roleId.ToUpper())'})-[]->(:GH_Repository {objectid:'$($repoId.ToUpper())'}) RETURN p" }
                $roleCanCreate[$roleId] = $true
            }
            else {
                $wildcardBPRId = $wildcardBlockingBPR.properties.id
                if ($hasAdmin) {
                    Add-ComputedEdge -Kind 'GH_CanCreateBranch' -StartId $roleId -EndId $repoId `
                        -Properties @{ traversable = $true; reason = 'admin';
                            query_composition = "MATCH p1=(:GH_RepoRole {objectid:'$($roleId.ToUpper())'})-[]->(r:GH_Repository {objectid:'$($repoId.ToUpper())'}) OPTIONAL MATCH p2=(r)-[:GH_HasBranch]->(:GH_Branch)<-[:GH_ProtectedBy]-(:GH_BranchProtectionRule {pattern:'*'}) RETURN p1, p2" }
                    $roleCanCreate[$roleId] = $true
                }
                elseif ($hasPushProtected) {
                    Add-ComputedEdge -Kind 'GH_CanCreateBranch' -StartId $roleId -EndId $repoId `
                        -Properties @{ traversable = $true; reason = 'push_protected_branch';
                            query_composition = "MATCH p1=(:GH_RepoRole {objectid:'$($roleId.ToUpper())'})-[]->(r:GH_Repository {objectid:'$($repoId.ToUpper())'}) OPTIONAL MATCH p2=(r)-[:GH_HasBranch]->(:GH_Branch)<-[:GH_ProtectedBy]-(:GH_BranchProtectionRule {pattern:'*'}) RETURN p1, p2" }
                    $roleCanCreate[$roleId] = $true
                }
            }

            # ── GH_CanWriteBranch (role -> branch or repo) ──
            $gateResult = Invoke-RoleGateEvaluation -Perms $perms -Branches $branches -BranchToBPR $branchToBPR
            $accessibleBranches = $gateResult.accessible
            $branchReasons = $gateResult.reasons

            $roleAccessibleBranches[$roleId] = New-Object System.Collections.Generic.HashSet[string]
            foreach ($bid in $accessibleBranches) {
                $null = $roleAccessibleBranches[$roleId].Add($bid)
            }

            if ($accessibleBranches.Count -gt 0) {
                foreach ($branchId in $accessibleBranches) {
                    $reason = $branchReasons[$branchId]
                    $edgeTypes = switch ($reason) {
                        'no_protection'            { 'GH_HasBaseRole|GH_WriteRepoContents' }
                        'admin'                    { 'GH_HasBaseRole|GH_AdminTo' }
                        'bypass_branch_protection' { 'GH_HasBaseRole|GH_WriteRepoContents|GH_BypassBranchProtection' }
                        'push_protected_branch'    { 'GH_HasBaseRole|GH_WriteRepoContents|GH_PushProtectedBranch' }
                        default                    { 'GH_HasBaseRole|GH_WriteRepoContents|GH_BypassBranchProtection|GH_PushProtectedBranch' }
                    }
                    Add-ComputedEdge -Kind 'GH_CanWriteBranch' -StartId $roleId -EndId $branchId `
                        -Properties @{ traversable = $true; reason = $reason;
                            query_composition = "MATCH p1=(:GH_RepoRole {objectid:'$($roleId.ToUpper())'})-[:$($edgeTypes)*1..]->(:GH_Repository)-[:GH_HasBranch]->(b:GH_Branch {objectid:'$($branchId.ToUpper())'}) OPTIONAL MATCH p2=(b)<-[:GH_ProtectedBy]-(:GH_BranchProtectionRule) RETURN p1, p2" }
                }
            }
        }
    }

    Write-Host "[+]   Phase 3a complete. $($computedEdges.Count) role-level edges."

    # ── Phase 3b: Per-actor allowance edges (delta only) ───────────────────

    Write-Host "[*]   Phase 3b: Computing per-actor allowance edges..."

    $allowanceEdgesBefore = $computedEdges.Count

    foreach ($repoId in $repoIds) {
        if ($repoBranches.ContainsKey($repoId)) { $branches = $repoBranches[$repoId] } else { $branches = @() }
        if ($repoBPRs.ContainsKey($repoId)) { $bprs = $repoBPRs[$repoId] } else { $bprs = @() }
        if ($branches.Count -eq 0 -and $bprs.Count -eq 0) { continue }

        # Find the wildcard (*) BPR
        $wildcardBlockingBPR = $null
        foreach ($bprId in $bprs) {
            $bprNode = $nodeById[$bprId]
            if (-not $bprNode) { continue }
            $p = $bprNode.properties
            if ($p.pattern -eq '*' -and (Test-BPRProperty $p.push_restrictions) -and (Test-BPRProperty $p.blocks_creations)) {
                $wildcardBlockingBPR = $bprNode
                break
            }
        }

        # Collect all actors who appear in per-rule allowances for BPRs on this repo
        $allowanceActors = New-Object System.Collections.Generic.HashSet[string]
        foreach ($bprId in $bprs) {
            if ($pushAllowanceActors.ContainsKey($bprId)) {
                foreach ($aid in $pushAllowanceActors[$bprId]) { $null = $allowanceActors.Add($aid) }
            }
            if ($bypassPRActors.ContainsKey($bprId)) {
                foreach ($aid in $bypassPRActors[$bprId]) { $null = $allowanceActors.Add($aid) }
            }
        }

        foreach ($actorId in $allowanceActors) {
            # Find branches already covered by the actor's role-level edges
            $coveredBranches = New-Object System.Collections.Generic.HashSet[string]
            $actorRoleCanCreate = $false

            if ($actorRepoRoles.ContainsKey($repoId) -and $actorRepoRoles[$repoId].ContainsKey($actorId)) {
                foreach ($leafRoleId in $actorRepoRoles[$repoId][$actorId]) {
                    if ($roleAccessibleBranches.ContainsKey($leafRoleId)) {
                        foreach ($bid in $roleAccessibleBranches[$leafRoleId]) {
                            $null = $coveredBranches.Add($bid)
                        }
                    }
                    if ($roleCanCreate.ContainsKey($leafRoleId) -and $roleCanCreate[$leafRoleId]) {
                        $actorRoleCanCreate = $true
                    }
                }
            }

            # Check if actor has write access (needed as prerequisite)
            $actorHasWrite = $false
            if ($actorRepoRoles.ContainsKey($repoId) -and $actorRepoRoles[$repoId].ContainsKey($actorId)) {
                foreach ($leafRoleId in $actorRepoRoles[$repoId][$actorId]) {
                    if ($roleFullPerms.ContainsKey($leafRoleId)) {
                        $rp = $roleFullPerms[$leafRoleId]
                        if ($rp.Contains('GH_WriteRepoContents') -or $rp.Contains('GH_AdminTo')) {
                            $actorHasWrite = $true
                            break
                        }
                    }
                }
            }
            if (-not $actorHasWrite) { continue }

            # ── GH_CanCreateBranch: delta for pushAllowances on wildcard BPR ──
            if ($wildcardBlockingBPR -and -not $actorRoleCanCreate) {
                $wildcardBPRId = $wildcardBlockingBPR.properties.id
                $inPushAllowances = $pushAllowanceActors.ContainsKey($wildcardBPRId) -and $pushAllowanceActors[$wildcardBPRId].Contains($actorId)
                if ($inPushAllowances) {
                    Add-ComputedEdge -Kind 'GH_CanCreateBranch' -StartId $actorId -EndId $repoId `
                        -Properties @{ traversable = $true; reason = 'push_allowance';
                            query_composition = "MATCH p1=(a:GitHub {objectid:'$($actorId.ToUpper())'})-[:GH_RestrictionsCanPush]->(:GH_BranchProtectionRule {pattern:'*'})-[:GH_ProtectedBy]->(:GH_Branch)<-[:GH_HasBranch]-(r:GH_Repository {objectid:'$($repoId.ToUpper())'}) MATCH p2=(a)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_WriteRepoContents]->(r) RETURN p1, p2" }
                }
            }

            # ── GH_CanWriteBranch: delta for branches not covered by role-level edges ──
            $deltaAccessible = New-Object System.Collections.ArrayList
            $deltaReasons = @{}

            foreach ($branchId in $branches) {
                if ($coveredBranches.Contains($branchId)) { continue }

                $bprId = if ($branchToBPR.ContainsKey($branchId)) { $branchToBPR[$branchId] } else { $null }
                if (-not $bprId) { continue } # Unprotected branches are always covered at role level

                $bprNode = $nodeById[$bprId]
                if (-not $bprNode) { continue }
                $bp = $bprNode.properties

                $enforceAdmins = Test-BPRProperty $bp.enforce_admins
                $hasPRReviews = Test-BPRProperty $bp.required_pull_request_reviews
                $hasLockBranch = Test-BPRProperty $bp.lock_branch
                $hasPushRestrictions = Test-BPRProperty $bp.push_restrictions

                # Re-evaluate merge gate considering bypassPRAllowances
                $mergeGateBlocked = $hasPRReviews -or $hasLockBranch
                $passesMergeGate = $false
                $mergeReason = $null

                if (-not $mergeGateBlocked) {
                    $passesMergeGate = $true
                }
                elseif (-not $hasLockBranch -and -not $enforceAdmins) {
                    $inBypassPR = $bypassPRActors.ContainsKey($bprId) -and $bypassPRActors[$bprId].Contains($actorId)
                    if ($inBypassPR) {
                        $passesMergeGate = $true
                        $mergeReason = 'bypass_pr_allowance'
                    }
                }

                # Re-evaluate push gate considering pushAllowances
                $pushGateBlocked = $hasPushRestrictions
                $passesPushGate = $false
                $pushReason = $null

                if (-not $pushGateBlocked) {
                    $passesPushGate = $true
                }
                else {
                    $inPushAllow = $pushAllowanceActors.ContainsKey($bprId) -and $pushAllowanceActors[$bprId].Contains($actorId)
                    if ($inPushAllow) {
                        $passesPushGate = $true
                        $pushReason = 'push_allowance'
                    }
                }

                if ($passesMergeGate -and $passesPushGate) {
                    $null = $deltaAccessible.Add($branchId)
                    if ($mergeReason) { $deltaReasons[$branchId] = $mergeReason }
                    elseif ($pushReason) { $deltaReasons[$branchId] = $pushReason }
                    else { $deltaReasons[$branchId] = 'no_protection' }
                }
            }

            # Emit per-actor edges for the delta branches
            foreach ($branchId in $deltaAccessible) {
                $reason = $deltaReasons[$branchId]
                $qc = switch ($reason) {
                    'push_allowance' {
                        "MATCH p1=(a:GitHub {objectid:'$($actorId.ToUpper())'})-[:GH_RestrictionsCanPush]->(:GH_BranchProtectionRule)-[:GH_ProtectedBy]->(b:GH_Branch {objectid:'$($branchId.ToUpper())'}) MATCH p2=(:GitHub {objectid:'$($actorId.ToUpper())'})-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_WriteRepoContents]->(:GH_Repository)-[:GH_HasBranch]->(:GH_Branch {objectid:'$($branchId.ToUpper())'}) RETURN p1, p2"
                    }
                    default {
                        "MATCH p1=(a:GitHub {objectid:'$($actorId.ToUpper())'})-[:GH_RestrictionsCanPush|GH_BypassPullRequestAllowances]->(:GH_BranchProtectionRule)-[:GH_ProtectedBy]->(b:GH_Branch {objectid:'$($branchId.ToUpper())'}) MATCH p2=(:GitHub {objectid:'$($actorId.ToUpper())'})-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf*1..]->(:GH_RepoRole)-[:GH_WriteRepoContents]->(:GH_Repository)-[:GH_HasBranch]->(:GH_Branch {objectid:'$($branchId.ToUpper())'}) RETURN p1, p2"
                    }
                }
                Add-ComputedEdge -Kind 'GH_CanWriteBranch' -StartId $actorId -EndId $branchId `
                    -Properties @{ traversable = $true; reason = $reason; query_composition = $qc }
            }
        }
    }

    $allowanceEdges = $computedEdges.Count - $allowanceEdgesBefore
    Write-Host "[+]   Phase 3b complete. $allowanceEdges per-actor allowance edges."
    Write-Host "[+]   Total: $($computedEdges.Count) computed edges."

    $output = [PSCustomObject]@{
        Nodes = (New-Object System.Collections.ArrayList)
        Edges = $computedEdges
    }

    Write-Output $output
}

function Compute-GitHoundSecretScanningAccess
{
    <#
    .SYNOPSIS
        Computes effective secret scanning alert access edges from accumulated collection data.

    .DESCRIPTION
        This function evaluates which roles can read secret scanning alerts by cross-referencing
        GH_ViewSecretScanningAlerts permission edges with the structural edges that connect
        organizations and repositories to their alerts. It produces traversable computed edges
        that represent the ability to read alert details (including the leaked secret value):

        - GH_CanReadSecretScanningAlert (GH_OrgRole -> GH_SecretScanningAlert): Org role can read all alerts in the org
        - GH_CanReadSecretScanningAlert (GH_RepoRole -> GH_SecretScanningAlert): Repo role can read alerts in the repo

        This function makes no API calls — it is a pure in-memory computation over
        previously collected nodes and edges.

    .PARAMETER Nodes
        ArrayList of all accumulated nodes from prior collection steps.

    .PARAMETER Edges
        ArrayList of all accumulated edges from prior collection steps.

    .OUTPUTS
        PSCustomObject with Nodes (empty) and Edges (computed edges).

    .EXAMPLE
        $result = Compute-GitHoundSecretScanningAccess -Nodes $nodes -Edges $edges
    #>
    Param(
        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]
        $Nodes,

        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]
        $Edges
    )

    $computedEdges = New-Object System.Collections.ArrayList
    $emittedEdges = @{} # Deduplication: "startId|endId|kind" -> $true

    # Helper: Emit a computed edge with deduplication
    function Add-ComputedEdge {
        param(
            [string]$Kind,
            [string]$StartId,
            [string]$EndId,
            [hashtable]$Properties
        )
        $dedupKey = "$StartId|$EndId|$Kind"
        if ($emittedEdges.ContainsKey($dedupKey)) { return }
        $emittedEdges[$dedupKey] = $true
        $null = $computedEdges.Add((New-GitHoundEdge -Kind $Kind -StartId $StartId -EndId $EndId -Properties $Properties))
    }

    # ── Phase 1: Build indexes ─────────────────────────────────────────────

    Write-Host "[*]   Phase 1: Building indexes..."

    # Node lookup by ID (need kind to distinguish org vs repo targets)
    $nodeById = @{}
    foreach ($node in $Nodes) {
        if ($node.id) {
            $nodeById[$node.id] = $node
        }
    }

    # Collect alert node IDs for validation
    $alertNodeIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($node in $Nodes) {
        if ($node.kinds -contains 'GH_SecretScanningAlert') {
            $null = $alertNodeIds.Add($node.id)
        }
    }

    # Build org→alerts and repo→alerts maps from GH_Contains edges where target is a SecretScanningAlert
    $orgAlerts = @{}
    $repoAlerts = @{}

    foreach ($edge in $Edges) {
        if ($edge.kind -eq 'GH_Contains' -and $alertNodeIds.Contains($edge.end.value)) {
            $sourceNode = $nodeById[$edge.start.value]
            if ($sourceNode -and $sourceNode.kinds -contains 'GH_Organization') {
                $orgId = $edge.start.value
                if (-not $orgAlerts.ContainsKey($orgId)) {
                    $orgAlerts[$orgId] = New-Object System.Collections.ArrayList
                }
                $null = $orgAlerts[$orgId].Add($edge.end.value)
            }
            elseif ($sourceNode -and $sourceNode.kinds -contains 'GH_Repository') {
                $repoId = $edge.start.value
                if (-not $repoAlerts.ContainsKey($repoId)) {
                    $repoAlerts[$repoId] = New-Object System.Collections.ArrayList
                }
                $null = $repoAlerts[$repoId].Add($edge.end.value)
            }
        }
    }

    # Collect GH_ViewSecretScanningAlerts edges, partitioned by target kind
    $orgViewEdges = New-Object System.Collections.ArrayList  # source=OrgRole, target=Organization
    $repoViewEdges = New-Object System.Collections.ArrayList # source=RepoRole, target=Repository

    foreach ($edge in $Edges) {
        if ($edge.kind -eq 'GH_ViewSecretScanningAlerts') {
            $targetNode = $nodeById[$edge.end.value]
            if ($targetNode -and $targetNode.kinds -contains 'GH_Organization') {
                $null = $orgViewEdges.Add($edge)
            }
            elseif ($targetNode -and $targetNode.kinds -contains 'GH_Repository') {
                $null = $repoViewEdges.Add($edge)
            }
        }
    }

    Write-Host "[+]   Phase 1 complete. $($alertNodeIds.Count) alerts, $($orgViewEdges.Count) org-level and $($repoViewEdges.Count) repo-level view permission edges."

    # ── Phase 2: Org-level emission ────────────────────────────────────────

    Write-Host "[*]   Phase 2: Computing org-level GH_CanReadSecretScanningAlert edges..."

    foreach ($viewEdge in $orgViewEdges) {
        $roleId = $viewEdge.start.value
        $orgId = $viewEdge.end.value
        $alerts = $orgAlerts[$orgId]
        if (-not $alerts) { continue }

        foreach ($alertId in $alerts) {
            Add-ComputedEdge -Kind 'GH_CanReadSecretScanningAlert' -StartId $roleId -EndId $alertId -Properties @{
                traversable       = $true
                reason            = 'org_role_permission'
                query_composition = "MATCH p1=(:GH_OrgRole {objectid:'$roleId'})-[:GH_ViewSecretScanningAlerts]->(:GH_Organization)-[:GH_Contains]->(:GH_SecretScanningAlert {objectid:'$alertId'}) RETURN p1"
            }
        }
    }

    $orgEdgeCount = $computedEdges.Count
    Write-Host "[+]   Phase 2 complete. $orgEdgeCount org-level edges."

    # ── Phase 3: Repo-level emission ───────────────────────────────────────

    Write-Host "[*]   Phase 3: Computing repo-level GH_CanReadSecretScanningAlert edges..."

    foreach ($viewEdge in $repoViewEdges) {
        $roleId = $viewEdge.start.value
        $repoId = $viewEdge.end.value
        $alerts = $repoAlerts[$repoId]
        if (-not $alerts) { continue }

        foreach ($alertId in $alerts) {
            Add-ComputedEdge -Kind 'GH_CanReadSecretScanningAlert' -StartId $roleId -EndId $alertId -Properties @{
                traversable       = $true
                reason            = 'repo_role_permission'
                query_composition = "MATCH p1=(:GH_RepoRole {objectid:'$roleId'})-[:GH_ViewSecretScanningAlerts]->(:GH_Repository)-[:GH_Contains]->(:GH_SecretScanningAlert {objectid:'$alertId'}) RETURN p1"
            }
        }
    }

    $repoEdgeCount = $computedEdges.Count - $orgEdgeCount
    Write-Host "[+]   Phase 3 complete. $repoEdgeCount repo-level edges."
    Write-Host "[+]   Total: $($computedEdges.Count) computed secret scanning access edges."

    $output = [PSCustomObject]@{
        Nodes = (New-Object System.Collections.ArrayList)
        Edges = $computedEdges
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
        - Get repository content: https://docs.github.com/en/rest/repos/contents?apiVersion=2022-11-28#get-repository-content

        Fine Grained Permissions Reference:
        - "Actions" repository permissions (read)
        - "Contents" repository permissions (read)

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

    .PARAMETER WorkflowsAllBranches
        When set, falls back to enumerating all branches to find a workflow file if it is not present
        on the repository's default branch. By default, only the default branch is checked. Enabling
        this can significantly increase API calls and run time for repositories with many branches.

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the workflows and their relationships.

    .EXAMPLE
        $workflows = $repos | Git-HoundWorkflow -Session $Session

    .EXAMPLE
        $workflows = $repos | Git-HoundWorkflow -Session $Session -WorkflowsAllBranches
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
        $ChunkSize = 50,

        [Parameter()]
        [switch]
        $WorkflowsAllBranches
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
        $callsPerRepo = 10
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
                $allBranches = $using:WorkflowsAllBranches
                $functionBundle = $using:GitHoundFunctionBundle
                foreach($funcName in $functionBundle.Keys) {
                    Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
                }
                $repo = $_

                foreach($workflow in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/actions/workflows").workflows)
                {
                    $isStaticWorkflowFile = $workflow.path -match '^\.github/workflows/[^/]+\.(?:yml|yaml)$'

                    # Download workflow file contents from the repository
                    # Try the default branch first, then fall back to other branches if not found
                    $workflowContent = $null
                    $workflowBranch = $null
                    if ($isStaticWorkflowFile) {
                        $contentsBasePath = "repos/$($repo.properties.full_name)/contents/$($workflow.path)"
                        try {
                            $contentResponse = Invoke-GithubRestMethod -Session $Session -Path $contentsBasePath -ErrorAction Stop
                            if ($contentResponse.content) {
                                $workflowContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($contentResponse.content -replace '\s','')))
                                $workflowBranch = $repo.properties.default_branch
                            }
                        } catch {
                            if ($allBranches) {
                                # Workflow not on default branch — try other branches
                                try {
                                    $branches = Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/branches" -ErrorAction Stop
                                    foreach ($branch in $branches) {
                                        try {
                                            $contentResponse = Invoke-GithubRestMethod -Session $Session -Path "$contentsBasePath`?ref=$($branch.name)" -ErrorAction Stop
                                            if ($contentResponse.content) {
                                                $workflowContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($contentResponse.content -replace '\s','')))
                                                $workflowBranch = $branch.name
                                                break
                                            }
                                        } catch {
                                            continue
                                        }
                                    }
                                } catch {
                                    Write-Warning "Could not list branches for $($repo.properties.full_name): $_"
                                }
                                if (-not $workflowContent) {
                                    Write-Warning "Could not download workflow contents for $($repo.properties.full_name)/$($workflow.path) on any branch"
                                }
                            } else {
                                Write-Warning "Workflow $($repo.properties.full_name)/$($workflow.path) not found on default branch ($($repo.properties.default_branch)) — skipping (use -WorkflowsAllBranches to search other branches)"
                            }
                        }
                    } else {
                        Write-Verbose "Skipping content download for non-repo-backed or dynamic workflow '$($repo.properties.full_name)/$($workflow.path)'"
                    }

                    $props = [pscustomobject]@{
                        # Common Properties
                        name              = Normalize-Null "$($repo.properties.name)\$($workflow.name)"
                        #id                = Normalize-Null $workflow.id
                        node_id           = Normalize-Null $workflow.node_id
                        # Relational Properties
                        environment_name  = Normalize-Null $repo.properties.environment_name
                        environmentid    = Normalize-Null $repo.properties.environmentid
                        repository_name   = Normalize-Null $repo.name
                        repository_id     = Normalize-Null $repo.id
                        # Node Specific Properties
                        short_name        = Normalize-Null $workflow.name
                        path              = Normalize-Null $workflow.path
                        state             = Normalize-Null $workflow.state
                        url               = Normalize-Null $workflow.url
                        html_url          = Normalize-Null $workflow.html_url
                        branch            = Normalize-Null $workflowBranch
                        contents          = Normalize-Null $workflowContent
                        # Accordion Panel Queries
                        query_repository  = "MATCH p=(:GH_Repository)-[:GH_HasWorkflow]->(:GH_Workflow {node_id: '$($workflow.node_id)'}) RETURN p"
                        query_editors     = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_WriteRepoContents|GH_WriteRepoPullRequests*1..]->(r:GH_Repository)-[:GH_HasWorkflow]->(:GH_Workflow {node_id:'$($workflow.node_id)'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
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

function Git-HoundRunner
{
    <#
    .SYNOPSIS
        Fetches self-hosted runner groups and runners at the organization and repository scope.

    .DESCRIPTION
        This function models self-hosted runner access in two layers:
        - Organization runner groups and the runners assigned to them
        - Repository-level self-hosted runners registered directly to a repository

        It emits explicit GH_CanUseRunner edges from repositories to the runners they can
        dispatch jobs to, so access is represented directly in the graph without relying on
        implicit policy interpretation at query time.

        API Reference:
        - List self-hosted runner groups for an organization: https://docs.github.com/en/rest/actions/self-hosted-runner-groups?apiVersion=2022-11-28#list-self-hosted-runner-groups-for-an-organization
        - List repository access to a self-hosted runner group in an organization: https://docs.github.com/en/rest/actions/self-hosted-runner-groups?apiVersion=2022-11-28#list-repository-access-to-a-self-hosted-runner-group-in-an-organization
        - List self-hosted runners in a group for an organization: https://docs.github.com/en/rest/actions/self-hosted-runner-groups?apiVersion=2022-11-28#list-self-hosted-runners-in-a-group-for-an-organization
        - List self-hosted runners for a repository: https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#list-self-hosted-runners-for-a-repository

        Fine Grained Permissions Reference:
        - "Self-hosted runners" organization permissions (read)
        - "Administration" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Organization
        The GH_Organization node for the current collection.

    .PARAMETER Repository
        Repository output from Git-HoundRepository. Used to resolve repository access.
    #>
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true)]
        [psobject]
        $Organization,

        [Parameter(Position = 2, Mandatory = $true, ValueFromPipeline)]
        [psobject[]]
        $Repository
    )

    begin
    {
        $nodes = New-Object System.Collections.ArrayList
        $edges = New-Object System.Collections.ArrayList
        $repoNodes = New-Object System.Collections.ArrayList

        function Get-GitHoundRunnerApiErrorInfo {
            param(
                [Parameter(Mandatory = $true)]
                $ErrorRecord
            )

            $message = $null
            $status = $null

            try {
                $httpException = $ErrorRecord.ErrorDetails | ConvertFrom-Json
                $message = $httpException.message
                $status = $httpException.status
            }
            catch {
                $message = $ErrorRecord.Exception.Message
            }

            [PSCustomObject]@{
                Status = $status
                Message = $message
            }
        }
    }

    process
    {
        $Repository.nodes | Where-Object {$_.kinds -eq 'GH_Repository'} | ForEach-Object {
            $null = $repoNodes.Add($_)
        }
    }

    end
    {
        $orgLogin = $Session.OrganizationName
        $orgNodeId = $Organization.id

        $repoByNodeId = @{}
        $allRepoIds = New-Object System.Collections.ArrayList
        $privateRepoIds = New-Object System.Collections.ArrayList

        foreach ($repoNode in $repoNodes) {
            $repoByNodeId[$repoNode.properties.node_id] = $repoNode
            $null = $allRepoIds.Add($repoNode.id)
            if ($repoNode.properties.visibility -in @('private', 'internal')) {
                $null = $privateRepoIds.Add($repoNode.id)
            }
        }

        $seenRunnerNodeIds = @{}
        $seenUseEdges = @{}

        $runnerGroups = @()
        try {
            $runnerGroups = @((Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/actions/runner-groups").runner_groups)
        } catch {
            $errorInfo = Get-GitHoundRunnerApiErrorInfo -ErrorRecord $_
            if (($errorInfo.Status -eq "403" -and $errorInfo.Message -match "Resource not accessible by integration") -or $errorInfo.Status -eq "404") {
                Write-Warning "Skipping organization self-hosted runner groups for '${orgLogin}': $($errorInfo.Message)"
                Write-Host "[*] This usually means self-hosted runners are not enabled for the organization, or the GitHub App does not have access to that feature."
            } else {
                Write-Warning "Could not enumerate organization runner groups for ${orgLogin}: $_"
            }
        }

        foreach ($group in $runnerGroups) {
            $groupNodeId = "$orgNodeId`_runner_group_$($group.id)"
            $groupProperties = [pscustomobject]@{
                name                       = Normalize-Null "$orgLogin/$($group.name)"
                node_id                    = Normalize-Null $groupNodeId
                environment_name           = Normalize-Null $orgLogin
                environmentid              = Normalize-Null $Organization.properties.node_id
                group_id                   = Normalize-Null $group.id
                group_name                 = Normalize-Null $group.name
                visibility                 = Normalize-Null $group.visibility
                default                    = Normalize-Null $group.default
                inherited                  = Normalize-Null $group.inherited
                allows_public_repositories = Normalize-Null $group.allows_public_repositories
                restricted_to_workflows    = Normalize-Null $group.restricted_to_workflows
                selected_workflows         = Normalize-Null ($group.selected_workflows | ConvertTo-Json -Depth 10)
                runners_url                = Normalize-Null $group.runners_url
                query_runners              = "MATCH p=(:GH_RunnerGroup {node_id:'$groupNodeId'})-[:GH_Contains]->(:GH_OrgRunner) RETURN p"
                query_repositories         = "MATCH p=(:GH_Repository)-[:GH_CanUseRunner]->(:GH_OrgRunner)<-[:GH_Contains]-(:GH_RunnerGroup {node_id:'$groupNodeId'}) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $groupNodeId -Kind 'GH_RunnerGroup' -Properties $groupProperties))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNodeId -EndId $groupNodeId -Properties @{ traversable = $false }))

            $accessibleRepoIds = @()
            switch ($group.visibility) {
                'all' {
                    $accessibleRepoIds = @($allRepoIds)
                }
                'private' {
                    $accessibleRepoIds = @($privateRepoIds)
                }
                'selected' {
                    try {
                        $selectedRepos = @((Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/actions/runner-groups/$($group.id)/repositories").repositories)
                        $accessibleRepoIds = @($selectedRepos | Where-Object { $repoByNodeId.ContainsKey($_.node_id) } | ForEach-Object { $repoByNodeId[$_.node_id].id })
                    } catch {
                        $errorInfo = Get-GitHoundRunnerApiErrorInfo -ErrorRecord $_
                        if (($errorInfo.Status -eq "403" -and $errorInfo.Message -match "Resource not accessible by integration") -or $errorInfo.Status -eq "404") {
                            Write-Warning "Skipping selected repository access for runner group '$($group.name)' in '${orgLogin}': $($errorInfo.Message)"
                        } else {
                            Write-Warning "Could not enumerate selected repository access for runner group '$($group.name)' in ${orgLogin}: $_"
                        }
                    }
                }
                default {
                    $accessibleRepoIds = @()
                }
            }

            $groupRunners = @()
            try {
                $groupRunners = @((Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/actions/runner-groups/$($group.id)/runners").runners)
            } catch {
                $errorInfo = Get-GitHoundRunnerApiErrorInfo -ErrorRecord $_
                if (($errorInfo.Status -eq "403" -and $errorInfo.Message -match "Resource not accessible by integration") -or $errorInfo.Status -eq "404") {
                    Write-Warning "Skipping runners for runner group '$($group.name)' in '${orgLogin}': $($errorInfo.Message)"
                } else {
                    Write-Warning "Could not enumerate runners for runner group '$($group.name)' in ${orgLogin}: $_"
                }
            }

            foreach ($runner in $groupRunners) {
                $runnerNodeId = "$orgNodeId`_org_runner_$($runner.id)"
                if (-not $seenRunnerNodeIds.ContainsKey($runnerNodeId)) {
                    $runnerProperties = [pscustomobject]@{
                        name                 = Normalize-Null $runner.name
                        node_id              = Normalize-Null $runnerNodeId
                        environment_name     = Normalize-Null $orgLogin
                        environmentid        = Normalize-Null $Organization.properties.node_id
                        scope                = Normalize-Null 'organization'
                        runner_id            = Normalize-Null $runner.id
                        os                   = Normalize-Null $runner.os
                        status               = Normalize-Null $runner.status
                        busy                 = Normalize-Null $runner.busy
                        ephemeral            = Normalize-Null $runner.ephemeral
                        runner_group_id      = Normalize-Null $group.id
                        runner_group_name    = Normalize-Null $group.name
                        labels               = Normalize-Null ($runner.labels | ConvertTo-Json -Depth 10)
                    }
                    $null = $nodes.Add((New-GitHoundNode -Id $runnerNodeId -Kind @('GH_OrgRunner', 'GH_Runner') -Properties $runnerProperties))
                    $seenRunnerNodeIds[$runnerNodeId] = $true
                }

                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $groupNodeId -EndId $runnerNodeId -Properties @{ traversable = $false }))

                foreach ($repoId in $accessibleRepoIds) {
                    $edgeKey = "$repoId|$runnerNodeId"
                    if (-not $seenUseEdges.ContainsKey($edgeKey)) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanUseRunner' -StartId $repoId -EndId $runnerNodeId -Properties @{
                            traversable = $false
                            scope = 'organization'
                            via = 'runner_group'
                            runner_group_name = $group.name
                            runner_group_visibility = $group.visibility
                        }))
                        $seenUseEdges[$edgeKey] = $true
                    }
                }
            }
        }

        $repoRunnerCandidates = @($repoNodes | Where-Object { $_.properties.actions_enabled -and $_.properties.self_hosted_runners_enabled })
        foreach ($repoNode in $repoRunnerCandidates) {
            $repoRunners = @()
            try {
                $repoRunners = @((Invoke-GithubRestMethod -Session $Session -Path "repos/$($repoNode.properties.full_name)/actions/runners").runners)
            } catch {
                $errorInfo = Get-GitHoundRunnerApiErrorInfo -ErrorRecord $_
                if (($errorInfo.Status -eq "403" -and $errorInfo.Message -match "Resource not accessible by integration") -or $errorInfo.Status -eq "404") {
                    Write-Warning "Skipping repository runners for '$($repoNode.properties.full_name)': $($errorInfo.Message)"
                } else {
                    Write-Warning "Could not enumerate repository runners for $($repoNode.properties.full_name): $_"
                }
            }

            foreach ($runner in $repoRunners) {
                $runnerNodeId = "$($repoNode.id)`_repo_runner_$($runner.id)"
                if (-not $seenRunnerNodeIds.ContainsKey($runnerNodeId)) {
                    $runnerProperties = [pscustomobject]@{
                        name                 = Normalize-Null $runner.name
                        node_id              = Normalize-Null $runnerNodeId
                        environment_name     = Normalize-Null $orgLogin
                        environmentid        = Normalize-Null $Organization.properties.node_id
                        scope                = Normalize-Null 'repository'
                        runner_id            = Normalize-Null $runner.id
                        repository_name      = Normalize-Null $repoNode.properties.name
                        repository_id        = Normalize-Null $repoNode.properties.node_id
                        repository_full_name = Normalize-Null $repoNode.properties.full_name
                        os                   = Normalize-Null $runner.os
                        status               = Normalize-Null $runner.status
                        busy                 = Normalize-Null $runner.busy
                        ephemeral            = Normalize-Null $runner.ephemeral
                        labels               = Normalize-Null ($runner.labels | ConvertTo-Json -Depth 10)
                    }
                    $null = $nodes.Add((New-GitHoundNode -Id $runnerNodeId -Kind @('GH_RepoRunner', 'GH_Runner') -Properties $runnerProperties))
                    $seenRunnerNodeIds[$runnerNodeId] = $true
                }

                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $repoNode.id -EndId $runnerNodeId -Properties @{ traversable = $false }))

                $edgeKey = "$($repoNode.id)|$runnerNodeId"
                if (-not $seenUseEdges.ContainsKey($edgeKey)) {
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanUseRunner' -StartId $repoNode.id -EndId $runnerNodeId -Properties @{
                        traversable = $false
                        scope = 'repository'
                        via = 'repository'
                    }))
                    $seenUseEdges[$edgeKey] = $true
                }
            }
        }

        Write-Host "[+] Git-HoundRunner complete. $($nodes.Count) nodes, $($edges.Count) edges."
        [PSCustomObject]@{
            Nodes = $nodes
            Edges = $edges
        }
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
                    #id                = Normalize-Null $environment.id
                    node_id           = Normalize-Null $environment.node_id
                    # Relational Properties
                    environment_name  = Normalize-Null $repo.properties.environment_name
                    environmentid    = Normalize-Null $repo.properties.environmentid
                    repository_name   = Normalize-Null $repo.name
                    repository_id     = Normalize-Null $repo.id
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
                        $branchId = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$($repo.properties.environmentid)_$($repo.properties.full_name)_$($policy.name)"))).Replace('-', '')
                        $null = $edges.Add((New-GitHoundEdge -Kind GH_HasEnvironment -StartId $branchId -EndId $environment.node_id -Properties @{ traversable = $false }))
                    }
                }
                else 
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GH_HasEnvironment -StartId $repo.Properties.node_id -EndId $environment.node_id -Properties @{ traversable = $false }))
                }

                # List environment secrets
                # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-environment-secrets
                # "Environments" repository permissions (read)
                foreach($secret in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/environments/$($environment.name)/secrets").secrets)
                {
                    $secretId = "GH_EnvironmentSecret_$($environment.node_id)_$($secret.name)"
                    $properties = @{
                        # Common Properties
                        name                            = Normalize-Null $secret.name
                        node_id                         = Normalize-Null $secretId
                        # Relational Properties
                        environment_name                = Normalize-Null $repo.properties.environment_name
                        environmentid                  = Normalize-Null $repo.properties.environmentid
                        repository_name                 = Normalize-Null $repo.name
                        repository_id                   = Normalize-Null $repo.id
                        deployment_environment_name     = Normalize-Null $environment.name
                        deployment_environmentid       = Normalize-Null $environment.node_id
                        # Node Specific Properties
                        created_at                      = Normalize-Null $secret.created_at
                        updated_at                      = Normalize-Null $secret.updated_at
                        # Accordion Panel Queries
                    }

                    $null = $nodes.Add((New-GitHoundNode -Id $secretId -Kind 'GH_EnvironmentSecret', 'GH_Secret' -Properties $properties))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $environment.node_id -EndId $secretId -Properties @{ traversable = $false }))
                }

                # List environment variables
                # https://docs.github.com/en/rest/actions/variables?apiVersion=2022-11-28#list-environment-variables
                foreach($variable in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/environments/$($environment.name)/variables").variables)
                {
                    $variableId = "GH_EnvironmentVariable_$($environment.node_id)_$($variable.name)"
                    $varProperties = @{
                        # Common Properties
                        name                            = Normalize-Null $variable.name
                        node_id                         = Normalize-Null $variableId
                        # Relational Properties
                        environment_name                = Normalize-Null $repo.properties.environment_name
                        environmentid                  = Normalize-Null $repo.properties.environmentid
                        repository_name                 = Normalize-Null $repo.name
                        repository_id                   = Normalize-Null $repo.id
                        deployment_environment_name     = Normalize-Null $environment.name
                        deployment_environmentid       = Normalize-Null $environment.node_id
                        # Node Specific Properties
                        value                           = Normalize-Null $variable.value
                        created_at                      = Normalize-Null $variable.created_at
                        updated_at                      = Normalize-Null $variable.updated_at
                    }

                    $null = $nodes.Add((New-GitHoundNode -Id $variableId -Kind 'GH_EnvironmentVariable', 'GH_Variable' -Properties $varProperties))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $environment.node_id -EndId $variableId -Properties @{ traversable = $false }))
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
                name                 = Normalize-Null $secret.name
                node_id              = Normalize-Null $secretId
                # Relational Properties
                environment_name     = Normalize-Null $orgLogin
                environmentid       = Normalize-Null $orgNodeId
                # Node Specific Properties
                created_at           = Normalize-Null $secret.created_at
                updated_at           = Normalize-Null $secret.updated_at
                visibility           = Normalize-Null $secret.visibility
                # Accordion Panel Queries
                query_visible_repositories = "MATCH p=(:GH_OrgSecret {node_id:'$secretId'})<-[:GH_HasSecret]-(:GH_Repository) RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $secretId -Kind 'GH_OrgSecret', 'GH_Secret' -Properties $properties))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNodeId -EndId $secretId -Properties @{ traversable = $false }))

            # Resolve repository access based on visibility
            switch ($secret.visibility) {
                'all' {
                    foreach ($repoNodeId in $allRepoNodeIds) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecret' -StartId $repoNodeId -EndId $secretId -Properties @{ traversable = $true }))
                    }
                }
                'private' {
                    foreach ($repoNodeId in $privateRepoNodeIds) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecret' -StartId $repoNodeId -EndId $secretId -Properties @{ traversable = $true }))
                    }
                }
                'selected' {
                    $selectedProcessed++
                    Write-Host "[*]   Fetching selected repos for secret '$($secret.name)' ($selectedProcessed/$selectedCount)"
                    # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-selected-repositories-for-an-organization-secret
                    $selectedRepos = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/actions/secrets/$($secret.name)/repositories").repositories
                    foreach ($selectedRepo in $selectedRepos) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecret' -StartId $selectedRepo.node_id -EndId $secretId -Properties @{ traversable = $true }))
                    }
                }
            }
        }

        Write-Host "[+] Git-HoundOrganizationSecret: $($nodes.Count) secret nodes, $($edges.Count) secret edges."

        # ── Organization Variables ─────────────────────────────────────────
        # https://docs.github.com/en/rest/actions/variables?apiVersion=2022-11-28#list-organization-variables
        # Fine Grained Permissions: "Variables" organization permissions (read)
        $orgVariables = @((Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/actions/variables").variables | Where-Object { $_ })

        $varAllCount = 0
        $varPrivateCount = 0
        $varSelectedCount = 0

        foreach ($variable in $orgVariables) {
            switch ($variable.visibility) {
                'all'      { $varAllCount++ }
                'private'  { $varPrivateCount++ }
                'selected' { $varSelectedCount++ }
            }
        }

        Write-Host "[*] Git-HoundOrganizationVariable: Found $($orgVariables.Count) org variables (all: $varAllCount, private: $varPrivateCount, selected: $varSelectedCount) across $($repoNodes.Count) repos"

        $varSelectedProcessed = 0

        foreach ($variable in $orgVariables) {
            $variableId = "GH_OrgVariable_$($orgNodeId)_$($variable.name)"
            $properties = @{
                # Common Properties
                name                 = Normalize-Null $variable.name
                node_id              = Normalize-Null $variableId
                # Relational Properties
                environment_name     = Normalize-Null $orgLogin
                environmentid       = Normalize-Null $orgNodeId
                # Node Specific Properties
                value                = Normalize-Null $variable.value
                created_at           = Normalize-Null $variable.created_at
                updated_at           = Normalize-Null $variable.updated_at
                visibility           = Normalize-Null $variable.visibility
                # Accordion Panel Queries
                query_visible_repositories = "MATCH p=(:GH_OrgVariable {node_id:'$variableId'})<-[:GH_HasVariable]-(:GH_Repository) RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $variableId -Kind 'GH_OrgVariable', 'GH_Variable' -Properties $properties))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNodeId -EndId $variableId -Properties @{ traversable = $false }))

            # Resolve repository access based on visibility
            switch ($variable.visibility) {
                'all' {
                    foreach ($repoNodeId in $allRepoNodeIds) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasVariable' -StartId $repoNodeId -EndId $variableId -Properties @{ traversable = $true }))
                    }
                }
                'private' {
                    foreach ($repoNodeId in $privateRepoNodeIds) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasVariable' -StartId $repoNodeId -EndId $variableId -Properties @{ traversable = $true }))
                    }
                }
                'selected' {
                    $varSelectedProcessed++
                    Write-Host "[*]   Fetching selected repos for variable '$($variable.name)' ($varSelectedProcessed/$varSelectedCount)"
                    # https://docs.github.com/en/rest/actions/variables?apiVersion=2022-11-28#list-selected-repositories-for-an-organization-variable
                    $selectedRepos = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/actions/variables/$($variable.name)/repositories").repositories
                    foreach ($selectedRepo in $selectedRepos) {
                        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasVariable' -StartId $selectedRepo.node_id -EndId $variableId -Properties @{ traversable = $true }))
                    }
                }
            }
        }

        Write-Host "[+] Git-HoundOrganizationSecret complete. $($nodes.Count) nodes, $($edges.Count) edges (secrets + variables)."

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
                        name                 = Normalize-Null $secret.name
                        node_id              = Normalize-Null $secretId
                        # Relational Properties
                        environment_name     = Normalize-Null $repo.properties.environment_name
                        environmentid       = Normalize-Null $repo.properties.environmentid
                        repository_name      = Normalize-Null $repo.name
                        repository_id        = Normalize-Null $repo.id
                        # Node Specific Properties
                        created_at           = Normalize-Null $secret.created_at
                        updated_at           = Normalize-Null $secret.updated_at
                        visibility           = Normalize-Null $secret.visibility
                        # Accordion Panel Queries
                        query_visible_repositories = "MATCH p=(:GH_RepoSecret {node_id:'$secretId'})<-[:GH_HasSecret]-(:GH_Repository) RETURN p"
                        # There could be a query for workflows that use this secret
                        # There could be a query for users that can overwrite workflows to use this secret
                    }

                    $null = $nodes.Add((New-GitHoundNode -Id $secretId -Kind 'GH_RepoSecret', 'GH_Secret' -Properties $properties))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $repo.properties.node_id -EndId $secretId -Properties @{ traversable = $false }))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasSecret' -StartId $repo.properties.node_id -EndId $secretId -Properties @{ traversable = $true }))
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

function Git-HoundVariable
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub repository-level Actions variables.

    .DESCRIPTION
        This function retrieves repository-level Actions variables (not org variables — those are handled
        by Git-HoundOrganizationSecret). Uses chunked parallel execution with rate limit awareness
        and checkpoint files for crash recovery.

        API Reference:
        - List repository variables: https://docs.github.com/en/rest/actions/variables?apiVersion=2022-11-28#list-repository-variables

        Fine Grained Permissions Reference:
        - "Variables" repository permissions (read)

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
        A PSObject containing arrays of nodes and edges representing the repository variables and their relationships.

    .EXAMPLE
        $variables = $repos | Git-HoundVariable -Session $Session

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
            $existingChunks = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Variable_chunk_*.json" -ErrorAction SilentlyContinue | Sort-Object { [int]($_.Name -replace '.*chunk_(\d+)\.json','$1') })
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
                Write-Host "[*] Auto-resuming Git-HoundVariable from index $currentIndex ($($existingChunks.Count) chunks loaded, $($allNodes.Count) nodes, $($allEdges.Count) edges recovered)"
            }
        }

        if ($currentIndex -gt 0 -and $existingChunks.Count -eq 0) {
            Write-Host "[*] Resuming Git-HoundVariable from index $StartIndex of $totalRepos repos"
        } elseif ($currentIndex -eq 0) {
            Write-Host "[*] Git-HoundVariable: Enumerating repo-level variables for $totalRepos repos"
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

                # List repository variables
                # https://docs.github.com/en/rest/actions/variables?apiVersion=2022-11-28#list-repository-variables
                foreach($variable in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/actions/variables").variables)
                {
                    $variableId = "GH_Variable_$($repo.properties.node_id)_$($variable.name)"
                    $properties = @{
                        # Common Properties
                        name                 = Normalize-Null $variable.name
                        node_id              = Normalize-Null $variableId
                        # Relational Properties
                        environment_name     = Normalize-Null $repo.properties.environment_name
                        environmentid       = Normalize-Null $repo.properties.environmentid
                        repository_name      = Normalize-Null $repo.name
                        repository_id        = Normalize-Null $repo.id
                        # Node Specific Properties
                        value                = Normalize-Null $variable.value
                        created_at           = Normalize-Null $variable.created_at
                        updated_at           = Normalize-Null $variable.updated_at
                        # Accordion Panel Queries
                        query_visible_repositories = "MATCH p=(:GH_RepoVariable {node_id:'$variableId'})<-[:GH_HasVariable]-(:GH_Repository) RETURN p"
                    }

                    $null = $nodes.Add((New-GitHoundNode -Id $variableId -Kind 'GH_RepoVariable', 'GH_Variable' -Properties $properties))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $repo.properties.node_id -EndId $variableId -Properties @{ traversable = $false }))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_HasVariable' -StartId $repo.properties.node_id -EndId $variableId -Properties @{ traversable = $true }))
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
            $chunkFile = Join-Path $CheckpointPath "githound_Variable_chunk_$($currentIndex).json"
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
        $finalFile = Join-Path $CheckpointPath "githound_Variable_complete.json"
        $finalPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $finalFile

        # Clean up intermediate chunk files
        $intermediateFiles = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Variable_chunk_*.json" -ErrorAction SilentlyContinue)
        if ($intermediateFiles.Count -gt 0) {
            $intermediateFiles | Remove-Item -Force
            Write-Host "[+] Cleaned up $($intermediateFiles.Count) intermediate checkpoint files."
        }

        Write-Host "[+] Git-HoundVariable complete. Processed $totalRepos repos, collected $($allNodes.Count) nodes, $($allEdges.Count) edges. Final output: $finalFile"
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
# The GH_Contains edge is used to link the alert to both the organization and the repository
# However, that edge is not traversable because the GH_ViewSecretScanningAlerts permission is necessary to read the alerts
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
        A PSObject containing two properties: Nodes and Edges. Nodes is an array of GH_SecretScanningAlert nodes, and Edges is an array of GH_Contains edges.

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
        $alertId = "SSA_$($alert.repository.node_id)_$($alert.number)"
        $properties =[pscustomobject]@{
            # Common Properties
            name                     = Normalize-Null $alert.number
            node_id                  = Normalize-Null $alertId
            # Relational Properties
            environment_name         = Normalize-Null $alert.repository.owner.login
            environmentid           = Normalize-Null $alert.repository.owner.node_id
            repository_name          = Normalize-Null $alert.repository.name
            repository_id            = Normalize-Null $alert.repository.node_id
            repository_url           = Normalize-Null $alert.repository.html_url
            # Node Specific Properties
            # secret                   = Normalize-Null $alert.secret  # omitted from output; still used for GH_ValidToken edge generation
            secret_type              = Normalize-Null $alert.secret_type
            secret_type_display_name = Normalize-Null $alert.secret_type_display_name
            validity                 = Normalize-Null $alert.validity
            state                    = Normalize-Null $alert.state
            created_at               = Normalize-Null $alert.created_at
            updated_at               = Normalize-Null $alert.updated_at
            url                      = Normalize-Null $alert.html_url
            # Accordion Panel Queries
            query_repository         = "MATCH p=(r:GH_SecretScanningAlert {node_id:'$alertId'})<-[:GH_Contains]-(repo:GH_Repository) RETURN p"
            # This currently doesn't take into account that there is an organization-level permission that can allow users to view alerts without having any repository permissions, but it's a start. We can iterate on the queries in future releases.
            query_alert_viewers      = "MATCH p=(role:GH_Role)-[:GH_HasRole|GH_HasBaseRole|GH_MemberOf|GH_ViewSecretScanningAlerts*1..]->(:GH_Repository)-[:GH_Contains]->(:GH_SecretScanningAlert {node_id:'$alertId'}) MATCH p1=(role)<-[:GH_HasRole]-(:GH_User) RETURN p,p1"
        }

        $null = $nodes.Add((New-GitHoundNode -Id $alertId -Kind 'GH_SecretScanningAlert' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $alert.repository.owner.node_id -EndId $alertId -Properties @{ traversable = $false }))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $alert.repository.node_id -EndId $alertId -Properties @{ traversable = $false }))

        if($alert.state -eq 'open' -and $alert.secret_type -eq 'github_personal_access_token')
        {
            try
            {
                $user = Invoke-RestMethod -Uri https://api.github.com/user -Headers @{ Authorization = "Bearer $($alert.secret)" }
                $null = $edges.Add((New-GitHoundEdge -Kind 'GH_ValidToken' -StartId $alertId -EndId $user.node_id -Properties @{ traversable = $true }))
            }
            catch {
            
            }
        }
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
        Retrieves GitHub App installations and their parent App definitions for an organization.

    .DESCRIPTION
        This function fetches GitHub App installations for the specified organization and creates
        GH_AppInstallation nodes with edges linking them to the organization (GH_Contains) and
        to accessible repositories (GH_CanAccess).

        For installations with repository_selection "all", it uses the pre-collected repository
        nodes to create GH_CanAccess edges to every repository in the organization. For installations
        with repository_selection "selected", the specific repositories cannot be enumerated with a
        PAT (requires app-level authentication), so no repository edges are created.

        Additionally, for each unique app encountered, it calls the public GET /apps/{app_slug}
        endpoint to create GH_App nodes representing the app definition. GH_App nodes are linked
        to their installations via GH_InstalledAs edges.

        API Reference:
        - List app installations for an organization: https://docs.github.com/en/rest/orgs/orgs?apiVersion=2022-11-28#list-app-installations-for-an-organization
        - Get an app: https://docs.github.com/en/rest/apps/apps?apiVersion=2022-11-28#get-an-app

        Fine Grained Permissions Reference:
        - "Administration" organization permissions (read)

    .PARAMETER Session
        A GitHound session object used to authenticate and interact with the GitHub API.

    .PARAMETER Organization
        A PSObject representing the GitHub organization node.

    .PARAMETER Repository
        Repository output from Git-HoundRepository. Used to resolve repo access edges for
        installations with repository_selection "all".

    .OUTPUTS
        A PSObject containing two properties: Nodes and Edges. Nodes is an array of GH_App
        and GH_AppInstallation nodes. Edges is an array of GH_Contains, GH_InstalledAs, and
        GH_CanAccess edges.

    .EXAMPLE
        $appInstallations = $repos | Git-HoundAppInstallation -Session $session -Organization $org.nodes[0]
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

        $installations = @((Invoke-GithubRestMethod -Session $Session -Path "orgs/$orgLogin/installations").installations)

        Write-Host "[*] Git-HoundAppInstallation: Found $($installations.Count) app installations"

        # Track unique app slugs to avoid duplicate GH_App lookups
        $seenAppSlugs = @{}
        $appSlugInstallation = @{}   # Representative installation per slug (fallback for private apps)
        $allCount = 0
        $selectedCount = 0

        foreach ($app in $installations)
        {
            $installationNodeId = "GH_AppInstallation_$($app.id)"

            $properties = @{
                # Common Properties
                name                 = Normalize-Null $app.app_slug
                node_id              = Normalize-Null $installationNodeId
                # Relational Properties
                environment_name     = Normalize-Null $app.account.login
                environmentid       = Normalize-Null $app.account.node_id
                repositories_url     = Normalize-Null $app.repositories_url
                app_id               = Normalize-Null $app.id
                app_slug             = Normalize-Null $app.app_slug
                # Node Specific Properties
                client_id            = Normalize-Null $app.client_id
                repository_selection = Normalize-Null $app.repository_selection
                access_tokens_url    = Normalize-Null $app.access_tokens_url
                target_type          = Normalize-Null $app.target_type
                description          = Normalize-Null $app.description
                html_url             = Normalize-Null $app.html_url
                created_at           = Normalize-Null $app.created_at
                updated_at           = Normalize-Null $app.updated_at
                suspended_at         = Normalize-Null $app.suspended_at
                permissions          = Normalize-Null ($app.permissions | ConvertTo-Json -Depth 10)
                events               = Normalize-Null ($app.events | ConvertTo-Json -Depth 10)
                # Accordion Panel Queries
                query_repositories   = "MATCH p=(:GH_AppInstallation {node_id:'$installationNodeId'})-[:GH_CanAccess]->(:GH_Repository) RETURN p LIMIT 1000"
                query_app            = "MATCH p=(:GH_App)-[:GH_InstalledAs]->(:GH_AppInstallation {node_id:'$installationNodeId'}) RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $installationNodeId -Kind 'GH_AppInstallation' -Properties $properties))

            # Edge: Organization contains the installation
            $null = $edges.Add((New-GitHoundEdge -Kind 'GH_Contains' -StartId $orgNodeId -EndId $installationNodeId -Properties @{ traversable = $false }))

            # Repository access edges
            if ($app.repository_selection -eq 'all') {
                $allCount++
                foreach ($repoNodeId in $allRepoNodeIds) {
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_CanAccess' -StartId $installationNodeId -EndId $repoNodeId -Properties @{ traversable = $false }))
                }
            } else {
                $selectedCount++
                # Cannot enumerate selected repositories with a PAT — requires app installation token
            }

            # Collect unique app slugs for GH_App node creation
            if ($app.app_slug -and -not $seenAppSlugs.ContainsKey($app.app_slug)) {
                $seenAppSlugs[$app.app_slug] = New-Object System.Collections.ArrayList
                $appSlugInstallation[$app.app_slug] = $app
            }
            if ($app.app_slug) {
                $null = $seenAppSlugs[$app.app_slug].Add($installationNodeId)
            }
        }

        # Create GH_App nodes by looking up each unique app slug via the public API
        foreach ($slug in $seenAppSlugs.Keys) {
            try {
                Write-Host "[*]   Looking up app definition: $slug"
                $appDef = Invoke-GithubRestMethod -Session $Session -Path "apps/$slug" -ErrorAction Stop

                $appProperties = @{
                    # Common Properties
                    name                 = Normalize-Null $appDef.name
                    id                   = Normalize-Null $appDef.id
                    node_id              = Normalize-Null $appDef.node_id
                    # Node Specific Properties
                    slug                 = Normalize-Null $appDef.slug
                    client_id            = Normalize-Null $appDef.client_id
                    description          = Normalize-Null $appDef.description
                    external_url         = Normalize-Null $appDef.external_url
                    html_url             = Normalize-Null $appDef.html_url
                    owner_login          = Normalize-Null $appDef.owner.login
                    owner_node_id        = Normalize-Null $appDef.owner.node_id
                    owner_type           = Normalize-Null $appDef.owner.type
                    created_at           = Normalize-Null $appDef.created_at
                    updated_at           = Normalize-Null $appDef.updated_at
                    permissions          = Normalize-Null ($appDef.permissions | ConvertTo-Json -Depth 10)
                    events               = Normalize-Null ($appDef.events | ConvertTo-Json -Depth 10)
                    installations_count  = Normalize-Null $appDef.installations_count
                    # Accordion Panel Queries
                    query_installations  = "MATCH p=(:GH_App {slug: '$slug'})-[:GH_InstalledAs]->(:GH_AppInstallation) RETURN p"
                }

                $null = $nodes.Add((New-GitHoundNode -Id $appDef.node_id -Kind 'GH_App' -Properties $appProperties))

                # Edges: App -> each installation of this app
                foreach ($instId in $seenAppSlugs[$slug]) {
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GH_InstalledAs' -StartId $appDef.node_id -EndId $instId -Properties @{ traversable = $true }))
                }
            }
            catch {
                Write-Warning "Failed to look up app definition for '$slug' (likely private app). Creating node from installation data."
                $inst = $appSlugInstallation[$slug]
            }
        }

        Write-Host "[+] Git-HoundAppInstallation complete. $($nodes.Count) nodes, $($edges.Count) edges (all: $allCount, selected: $selectedCount)."

        Write-Output ([PSCustomObject]@{
            Nodes = $nodes
            Edges = $edges
        })
    }
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
                name                 = Normalize-Null $pat.token_name
                node_id              = Normalize-Null $patId
                # Relational Properties
                environment_name     = Normalize-Null $orgLogin
                environmentid       = Normalize-Null $orgNodeId
                owner_login          = Normalize-Null $pat.owner.login
                #owner_id             = Normalize-Null $pat.owner.id
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
                query_organization_permissions = "MATCH p=(:GH_PersonalAccessToken {node_id: '$($patId)'})-[:GH_CanAccess]->(:GH_Organization) RETURN p"
                query_user                     = "MATCH p=(:GH_User)-[:GH_HasPersonalAccessToken]->(:GH_PersonalAccessToken {node_id: '$($patId)'}) RETURN p"
                query_repositories             = "MATCH p=(:GH_PersonalAccessToken {node_id: '$($patId)'})-[:GH_CanAccess]->(:GH_Repository) RETURN p LIMIT 1000"
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
            name                 = Normalize-Null $request.token_name
            node_id              = Normalize-Null $requestId
            # Relational Properties
            environment_name     = Normalize-Null $orgLogin
            environmentid       = Normalize-Null $orgNodeId
            owner_login          = Normalize-Null $request.owner.login
            #owner_id             = Normalize-Null $request.owner.id
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
            query_organization_permissions = "MATCH p=(:GH_PersonalAccessTokenRequest {node_id: '$($requestId)'})-[:GH_CanAccess]->(:GH_Organization) RETURN p"
            query_user                     = "MATCH p=(:GH_User)-[:GH_HasPersonalAccessTokenRequest]->(:GH_PersonalAccessTokenRequest {node_id: '$($requestId)'}) RETURN p"
            query_repositories             = "MATCH p=(:GH_PersonalAccessTokenRequest {node_id: '$($requestId)'})-[:GH_CanAccess]->(:GH_Repository) RETURN p LIMIT 1000"
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
        $scimRequestError = $null
        $responseBytes = Invoke-GithubRestMethod `
            -Session $Session `
            -Path "scim/v2/organizations/$($Session.OrganizationName)/Users?startIndex=$($startIndex)" `
            -ErrorAction SilentlyContinue `
            -ErrorVariable scimRequestError

        if ($scimRequestError) {
            $errorRecord = $scimRequestError[0]
            $errorText = @(
                $errorRecord.ToString()
                $errorRecord.Exception.Message
                $errorRecord.ErrorDetails.Message
            ) -join " "

            if ($errorText -match "SCIM is not enabled for this organization" -and $errorText -match "configured on the enterprise account") {
                Write-Warning "Skipping organization SCIM for '$($Session.OrganizationName)': $errorText"
                Write-Host "[*] This usually means federated auth is configured at the enterprise level rather than directly on the organization."
                return [PSCustomObject]@{
                    Nodes = $nodes
                    Edges = $edges
                }
            }

            throw $errorRecord
        }

        if (-not $responseBytes) {
            Write-Warning "Skipping organization SCIM for '$($Session.OrganizationName)': GitHub returned an empty response."
            return [PSCustomObject]@{
                Nodes = $nodes
                Edges = $edges
            }
        }

        $result = [System.Text.Encoding]::ASCII.GetString($responseBytes) | ConvertFrom-Json
        foreach($scimIdentity in $result.Resources)
        {
            $props = [pscustomobject]@{
                # Common Properties
                name = Normalize-Null $scimIdentity.externalId
                id = Normalize-Null $scimIdentity.id
                # Relational Properties
                # Node Specific Properties
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
                # Accordion Panel Queries
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
        Parses GitHub OIDC subject claims from AZFederatedIdentityCredential nodes and creates GH_CanAssumeIdentity edges.

    .DESCRIPTION
        This function processes AZFederatedIdentityCredential nodes that have GitHub OIDC subject claims
        (subjects beginning with "repo:") and creates GH_CanAssumeIdentity edges from the appropriate GitHub
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
            -Kind 'GH_CanAssumeIdentity' `
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
        login
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
                    $ForeignUserNodeKind = 'Okta_User'
                    $ForeginEnvironmentNodeKind = 'Okta_Organization'
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
                environment_name         = $result.data.organization.login
                environmentid           = $result.data.organization.id
                foreign_environmentid   = $ForeignEnvironmentId
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
                    node_id                   = Normalize-Null $identity.id
                    name                      = Normalize-Null $identity.guid
                    guid                      = Normalize-Null $identity.guid
                    # Relational Properties
                    environmentid           = Normalize-Null $result.data.organization.id
                    environment_name         = Normalize-Null $result.data.organization.login
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
                
                $foreignUsername = if($identity.samlIdentity.username) { $identity.samlIdentity.username } elseif($identity.scimIdentity.username) { $identity.scimIdentity.username } else { $null }
                $foreignUserMatchers = Get-GitHoundForeignUserPropertyMatchers -ForeignUserNodeKind $ForeignUserNodeKind -Username $foreignUsername -ForeignEnvironmentId $ForeignEnvironmentId

                if($foreignUsername -and $ForeignUserNodeKind)
                {
                    if($foreignUserMatchers)
                    {
                        $null = $edges.Add((New-GitHoundEdge -Kind GH_MapsToUser -StartId $identity.id -EndKind $ForeignUserNodeKind -EndPropertyMatchers $foreignUserMatchers -Properties @{traversable=$false}))
                    }
                    else
                    {
                        $null = $edges.Add((New-GitHoundEdge -Kind GH_MapsToUser -StartId $identity.id -EndId $foreignUsername -EndKind $ForeignUserNodeKind -EndMatchBy name -Properties @{traversable=$false}))
                    }
                }

                if($identity.user -ne $null -and $identity.user.id -ne $null)
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GH_MapsToUser -StartId $identity.id -EndId $identity.user.id -Properties @{traversable=$false}))
                    
                    # Create GH_SyncedTo Edge from Foreign Identity to GH_User
                    # This might need to be something that happens during post-processing since we do not control whether the foreign user node already exists in the graph
                    if($ForeignUserNodeKind -and $foreignUsername)
                    {
                        if($foreignUserMatchers)
                        {
                            $null = $edges.Add((New-GitHoundEdge -Kind GH_SyncedTo -StartKind $ForeignUserNodeKind -StartPropertyMatchers $foreignUserMatchers -EndId $identity.user.id -Properties @{traversable=$true}))
                        }
                        else
                        {
                            $null = $edges.Add((New-GitHoundEdge -Kind GH_SyncedTo -StartId $foreignUsername -StartKind $ForeignUserNodeKind -StartMatchBy name -EndId $identity.user.id -Properties @{traversable=$true; composition="MATCH p=()<-[:GH_SyncedToEnvironment]-(:GH_SamlIdentityProvider)-[:GH_HasExternalIdentity]->(:GH_ExternalIdentity)-[:GH_MapsToUser]->(n) WHERE n.objectid = '$($identity.user.id.ToUpper())' OR n.name = '$($foreignUsername.ToUpper())' RETURN p"}))
                        }
                    }
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

    .PARAMETER WorkflowsAllBranches
        When set, falls back to enumerating all branches to find a workflow file if it is not present
        on the repository's default branch. By default, only the default branch is checked. Enabling
        this can significantly increase API calls and run time for repositories with many branches.
        Passed through to Git-HoundWorkflow.

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
        $CollectAll,

        [Parameter()]
        [switch]
        $WorkflowsAllBranches
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

    # ── Computed Edges: Branch Access ────────────────────────────────────────
    Write-Host "[*] Computing branch access edges (GH_CanWriteBranch, GH_CanCreateBranch, GH_CanEditProtection)"
    $branchAccess = Compute-GitHoundBranchAccess -Nodes $nodes -Edges $edges
    if($branchAccess.edges) { $edges.AddRange(@($branchAccess.edges)) }

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
            $workflowParams = @{
                Session        = $Session
                CheckpointPath = $CheckpointPath
            }
            if ($WorkflowsAllBranches) { $workflowParams['WorkflowsAllBranches'] = $true }
            $workflows = $repos | Git-HoundWorkflow @workflowParams
            Export-GitHoundStepOutput -StepResult $workflows -FilePath $stepFile
            Write-Host "[+] Saved: githound_Workflow_$orgId.json"
        }
        if($workflows.nodes) { $nodes.AddRange(@($workflows.nodes)) }
        if($workflows.edges) { $edges.AddRange(@($workflows.edges)) }
    } else {
        Write-Host "[*] Skipping Workflows (use -CollectAll to include)"
    }

    # ── Step 7.5: Self-Hosted Runners (requires -CollectAll) ──────────────
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_Runner_$orgId.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded Self-Hosted Runners from githound_Runner_$orgId.json"
            $runners = Import-GitHoundStepOutput -FilePath $stepFile
        } else {
            Write-Host "[*] Enumerating Self-Hosted Runners"
            $runners = $repos | Git-HoundRunner -Session $Session -Organization $org.nodes[0]
            Export-GitHoundStepOutput -StepResult $runners -FilePath $stepFile
            Write-Host "[+] Saved: githound_Runner_$orgId.json"
        }
        if($runners.nodes) { $nodes.AddRange(@($runners.nodes)) }
        if($runners.edges) { $edges.AddRange(@($runners.edges)) }
    } else {
        Write-Host "[*] Skipping Self-Hosted Runners (use -CollectAll to include)"
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

    # ── Step 10.5: Repository Variables (requires -CollectAll) ──────────
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_Variable_$orgId.json"
        $completeFile = Join-Path $CheckpointPath "githound_Variable_complete.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded Repository Variables from githound_Variable_$orgId.json"
            $variables = Import-GitHoundStepOutput -FilePath $stepFile
        } elseif ($Resume -and (Test-Path $completeFile)) {
            Write-Host "[*] Resuming: Found Variable complete file, converting to per-step output"
            $variables = Import-GitHoundStepOutput -FilePath $completeFile
            Export-GitHoundStepOutput -StepResult $variables -FilePath $stepFile
            Write-Host "[+] Saved: githound_Variable_$orgId.json"
        } else {
            Write-Host "[*] Enumerating Repository Variables"
            $variables = $repos | Git-HoundVariable -Session $Session -CheckpointPath $CheckpointPath
            Export-GitHoundStepOutput -StepResult $variables -FilePath $stepFile
            Write-Host "[+] Saved: githound_Variable_$orgId.json"
        }
        if($variables.nodes) { $nodes.AddRange(@($variables.nodes)) }
        if($variables.edges) { $edges.AddRange(@($variables.edges)) }
    } else {
        Write-Host "[*] Skipping Repository Variables (use -CollectAll to include)"
    }

    # ── Step 10.75: Workflow Analysis (requires -CollectAll) ─────────────
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_WorkflowAnalysis_$orgId.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded Workflow Analysis from githound_WorkflowAnalysis_$orgId.json"
            $workflowAnalysis = Import-GitHoundStepOutput -FilePath $stepFile
        } else {
            Write-Host "[*] Analyzing Workflows"
            $workflowGraphData = [PSCustomObject]@{
                graph = [PSCustomObject]@{
                    nodes = @($nodes | Where-Object { $_ -ne $null })
                    edges = @($edges | Where-Object { $_ -ne $null })
                }
            }
            $workflowAnalysis = Get-GitHoundWorkflowAnalysis -GraphData $workflowGraphData
            Export-GitHoundStepOutput -StepResult $workflowAnalysis -FilePath $stepFile
            Write-Host "[+] Saved: githound_WorkflowAnalysis_$orgId.json"
        }
        Merge-GitHoundWorkflowAnalysis -GraphNodes $nodes -GraphEdges $edges -AnalysisResult $workflowAnalysis
    } else {
        Write-Host "[*] Skipping Workflow Analysis (use -CollectAll to include)"
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

    # ── Computed Edges: Secret Scanning Access ────────────────────────────
    Write-Host "[*] Computing secret scanning access edges (GH_CanReadSecretScanningAlert)"
    $secretScanningAccess = Compute-GitHoundSecretScanningAccess -Nodes $nodes -Edges $edges
    if($secretScanningAccess.edges) { $edges.AddRange(@($secretScanningAccess.edges)) }

    # ── Step 12: App Installations (requires -CollectAll) ──────────────────
    if ($CollectAll) {
        $stepFile = Join-Path $CheckpointPath "githound_AppInstallation_$orgId.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded App Installations from githound_AppInstallation_$orgId.json"
            $appInstallations = Import-GitHoundStepOutput -FilePath $stepFile
        } else {
            Write-Host "[*] Enumerating App Installations"
            $appInstallations = $repos | Git-HoundAppInstallation -Session $Session -Organization $org.nodes[0]
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
            "githound_WorkflowAnalysis_$orgId.json",
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
        '$schema' = "https://raw.githubusercontent.com/MichaelGrafnetter/EntraAuthPolicyHound/refs/heads/main/bloodhound-opengraph.schema.json"
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
            '$schema' = "https://raw.githubusercontent.com/MichaelGrafnetter/EntraAuthPolicyHound/refs/heads/main/bloodhound-opengraph.schema.json"
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
                    '$schema' = "https://raw.githubusercontent.com/MichaelGrafnetter/EntraAuthPolicyHound/refs/heads/main/bloodhound-opengraph.schema.json"
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

function Invoke-GitHoundEnterprise
{
    <#
    .SYNOPSIS
        Orchestrates enterprise-first GitHound collection and then runs organization collection for related org installations.

    .DESCRIPTION
        This wrapper keeps enterprise collection intentionally thin. It collects the currently
        supported enterprise-scoped data, enumerates GitHub App installations, filters them
        down to active organization installations that belong to the enterprise, and then
        invokes the existing Invoke-GitHound organization workflow for each related org.

        Enterprise collection currently includes:
        - GH_Enterprise and org containment (Git-HoundEnterprise)
        - enterprise members (Git-HoundEnterpriseUser)
        - enterprise teams (Git-HoundEnterpriseTeam)
        - enterprise SAML provider and external identities (Git-HoundEnterpriseSamlProvider, when PAT-backed)

        Organization collection is delegated unchanged to Invoke-GitHound by creating a normal
        organization-scoped New-GitHubJwtSession for each related org installation.

    .PARAMETER Session
        A GitHound.Session with EnterpriseName set. JwtHeaders must be present so the wrapper
        can enumerate installations. PrivateKeyPath and ClientId must also be present so the
        wrapper can create organization-scoped New-GitHubJwtSession objects.

    .PARAMETER CheckpointPath
        Root directory for enterprise output and per-organization subdirectories.

    .PARAMETER Resume
        Reuses existing enterprise step files and passes the flag through to Invoke-GitHound.

    .PARAMETER CleanupIntermediates
        Cleans up enterprise step files after enterprise consolidation and passes the flag
        through to organization collection.

    .PARAMETER CollectAll
        Passed through to organization collection.

    .PARAMETER WorkflowsAllBranches
        Passed through to organization collection.
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
        $CollectAll,

        [Parameter()]
        [switch]
        $WorkflowsAllBranches
    )

    if (-not $Session.EnterpriseName) {
        throw "Invoke-GitHoundEnterprise requires Session.EnterpriseName to be set."
    }

    if (-not $Session.JwtHeaders) {
        throw "Invoke-GitHoundEnterprise requires a session with JwtHeaders so organization installations can be enumerated."
    }

    if (-not $Session.ClientId) {
        throw "Invoke-GitHoundEnterprise requires Session.ClientId to create organization-scoped sessions."
    }

    if (-not $Session.PrivateKeyPath) {
        throw "Invoke-GitHoundEnterprise requires Session.PrivateKeyPath to create organization-scoped sessions."
    }

    $enterpriseSlug = $Session.EnterpriseName
    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    Write-Host "[*] Starting GitHound enterprise wrapper for $enterpriseSlug"

    # ── Step 1: Enterprise ───────────────────────────────────────────────
    $entId = $null
    if ($Resume) {
        $enterpriseFiles = @(Get-ChildItem -Path $CheckpointPath -Filter "githound_Enterprise_*.json" -ErrorAction SilentlyContinue)
        if ($enterpriseFiles.Count -eq 1) {
            $enterprise = Import-GitHoundStepOutput -FilePath $enterpriseFiles[0].FullName
            if ($enterprise) {
                $entId = $enterprise.Nodes[0].id
                Write-Host "[*] Resuming: Loaded Enterprise from $($enterpriseFiles[0].Name)"
            }
        }
    }

    if (-not $entId) {
        Write-Host "[*] Enumerating Enterprise"
        $enterprise = Git-HoundEnterprise -Session $Session
        $entId = $enterprise.Nodes[0].id
        Export-GitHoundStepOutput -StepResult $enterprise -FilePath (Join-Path $CheckpointPath "githound_Enterprise_$entId.json")
        Write-Host "[+] Saved: githound_Enterprise_$entId.json"
    }
    if($enterprise.Nodes) { $nodes.AddRange(@($enterprise.Nodes)) }
    if($enterprise.Edges) { $edges.AddRange(@($enterprise.Edges)) }

    # ── Step 2: Enterprise Users ─────────────────────────────────────────
    $stepFile = Join-Path $CheckpointPath "githound_EnterpriseUser_$entId.json"
    if ($Resume -and (Test-Path $stepFile)) {
        Write-Host "[*] Resuming: Loaded Enterprise Users from githound_EnterpriseUser_$entId.json"
        $enterpriseUsers = Import-GitHoundStepOutput -FilePath $stepFile
    } else {
        Write-Host "[*] Enumerating Enterprise Users"
        $enterpriseUsers = Git-HoundEnterpriseUser -Session $Session -Enterprise $enterprise.Nodes[0]
        Export-GitHoundStepOutput -StepResult $enterpriseUsers -FilePath $stepFile
        Write-Host "[+] Saved: githound_EnterpriseUser_$entId.json"
    }
    if($enterpriseUsers.Nodes) { $nodes.AddRange(@($enterpriseUsers.Nodes)) }
    if($enterpriseUsers.Edges) { $edges.AddRange(@($enterpriseUsers.Edges)) }

    # ── Step 3: Enterprise Teams ─────────────────────────────────────────
    $stepFile = Join-Path $CheckpointPath "githound_EnterpriseTeam_$entId.json"
    if ($Resume -and (Test-Path $stepFile)) {
        Write-Host "[*] Resuming: Loaded Enterprise Teams from githound_EnterpriseTeam_$entId.json"
        $enterpriseTeams = Import-GitHoundStepOutput -FilePath $stepFile
    } else {
        Write-Host "[*] Enumerating Enterprise Teams"
        $enterpriseTeams = Git-HoundEnterpriseTeam -Session $Session -Enterprise $enterprise.Nodes[0]
        Export-GitHoundStepOutput -StepResult $enterpriseTeams -FilePath $stepFile
        Write-Host "[+] Saved: githound_EnterpriseTeam_$entId.json"
    }
    if($enterpriseTeams.Nodes) { $nodes.AddRange(@($enterpriseTeams.Nodes)) }
    if($enterpriseTeams.Edges) { $edges.AddRange(@($enterpriseTeams.Edges)) }

    # ── Step 4: Enterprise SAML (separate output) ────────────────────────
    if ($Session.HasPersonalAccessToken) {
        $stepFile = Join-Path $CheckpointPath "githound_EnterpriseSaml_$entId.json"
        if ($Resume -and (Test-Path $stepFile)) {
            Write-Host "[*] Resuming: Loaded Enterprise SAML from githound_EnterpriseSaml_$entId.json"
            $enterpriseSaml = Import-GitHoundStepOutput -FilePath $stepFile
        } else {
            Write-Host "[*] Enumerating Enterprise SAML"
            $enterpriseSaml = Git-HoundEnterpriseSamlProvider -Session $Session
            Export-GitHoundStepOutput -StepResult $enterpriseSaml -FilePath $stepFile
            Write-Host "[+] Saved: githound_EnterpriseSaml_$entId.json"
        }

        $enterpriseSamlPayload = [PSCustomObject]@{
            '$schema' = "https://raw.githubusercontent.com/MichaelGrafnetter/EntraAuthPolicyHound/refs/heads/main/bloodhound-opengraph.schema.json"
            graph = [PSCustomObject]@{
                nodes = @($enterpriseSaml.Nodes | Where-Object { $_ -ne $null })
                edges = @($enterpriseSaml.Edges | Where-Object { $_ -ne $null })
            }
        }
        $enterpriseSamlPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $CheckpointPath "githound_enterprise_saml_$entId.json")
    } else {
        Write-Host "[*] Skipping Enterprise SAML (session does not contain a PAT)"
    }

    # ── Enterprise Consolidation ─────────────────────────────────────────
    $filteredNodes = @($nodes | Where-Object { $_ -ne $null })
    $filteredEdges = @($edges | Where-Object { $_ -ne $null })

    $enterprisePayload = [PSCustomObject]@{
        '$schema' = "https://raw.githubusercontent.com/MichaelGrafnetter/EntraAuthPolicyHound/refs/heads/main/bloodhound-opengraph.schema.json"
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $filteredNodes
            edges = $filteredEdges
        }
    }
    $enterprisePayload | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $CheckpointPath "githound_enterprise_$entId.json")
    Write-Host "[+] Enterprise payload: githound_enterprise_$entId.json ($($filteredNodes.Count) nodes, $($filteredEdges.Count) edges)"

    # ── Related Org Installations ────────────────────────────────────────
    Write-Host "[*] Enumerating GitHub App installations"
    $allInstallations = @(Get-GitHubAppInstallation -Session $Session)
    $relatedOrgLogins = @(
        $enterprise.Nodes |
            Where-Object { $_.kinds -contains 'GH_Organization' } |
            ForEach-Object { $_.properties.login } |
            Where-Object { $_ }
    ) | Sort-Object -Unique

    $orgInstallations = @(
        $allInstallations |
            Where-Object {
                $_.TargetType -eq 'Organization' -and
                -not $_.SuspendedAt -and
                $_.Login -in $relatedOrgLogins
            }
    )

    Write-Host "[*] Found $($orgInstallations.Count) active related organization installation(s)"

    foreach ($installation in $orgInstallations) {
        $orgName = $installation.Login
        $orgCheckpointPath = Join-Path $CheckpointPath $orgName
        if (-not (Test-Path $orgCheckpointPath)) {
            $null = New-Item -ItemType Directory -Path $orgCheckpointPath -Force
        }

        Write-Host "[*] Running Invoke-GitHound for organization '$orgName'"
        $orgSession = New-GitHubJwtSession `
            -OrganizationName $orgName `
            -ClientId $Session.ClientId `
            -PrivateKeyPath $Session.PrivateKeyPath `
            -InstallationId $installation.InstallationId

        $invokeParams = @{
            Session               = $orgSession
            CheckpointPath        = $orgCheckpointPath
            Resume                = $Resume
            CleanupIntermediates  = $CleanupIntermediates
            CollectAll            = $CollectAll
            WorkflowsAllBranches  = $WorkflowsAllBranches
        }

        Invoke-GitHound @invokeParams
    }

    if ($CleanupIntermediates) {
        $enterpriseStepFiles = @(
            "githound_Enterprise_$entId.json",
            "githound_EnterpriseUser_$entId.json",
            "githound_EnterpriseTeam_$entId.json",
            "githound_EnterpriseSaml_$entId.json"
        )

        foreach ($fileName in $enterpriseStepFiles) {
            $filePath = Join-Path $CheckpointPath $fileName
            if (Test-Path $filePath) {
                Remove-Item $filePath -Force
            }
        }
    }

    Write-Host "[+] GitHound enterprise wrapper complete for $enterpriseSlug."
}
