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

function Get-Headers
{
    param(
        [Parameter (Mandatory = $TRUE)]
        $GitHubPat
    )

    $headers = @{'Authorization' = "Bearer $($GitHubPat)" }
    return $headers
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
    
    while (-not $requestSuccessful -and $retryCount -lt 3) {
        try {
            $result = Invoke-RestMethod @fparams
            $requestSuccessful = $true
        }
        catch {
            $httpException = $_.ErrorDetails | ConvertFrom-Json
            if (($httpException.status -eq "403" -and $httpException.message -match "rate limit") -or $httpException.status -eq "429") {
                Write-Warning "Rate limit hit when doing GraphQL call. Retry $($retryCount + 1)/3"
                Write-Debug $_
                Wait-GithubGraphQlRateLimit -Session $Session
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
        $node = New-GitHoundNode -Id 'node123' -Kind @('GHUser', 'GHAdmin') -Properties @{ name = 'John Doe'; email = 'john.doe@example.com' }

        This example creates a new node with the identifier 'node123', of kinds 'GHUser' and 'GHAdmin', and includes additional properties for name and email.
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

        $edge = New-GitHoundEdge -Kind 'GHOwns' -StartId 'user123' -EndId 'repo456' -StartKind 'GHUser' -EndKind 'GHRepository' -Properties @{ traversable = $true }

        This example creates a new edge of kind 'GHOwns' from a user node to a repository node with additional properties.
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
        Fetches and processes GitHub Organizations.

    .DESCRIPTION
        This function retrieves organization details for the organization specified in the GitHound.Session object. It creates a node representing the organization.

        API Reference: 
        - Get an organization: https://docs.github.com/en/rest/orgs/orgs?apiVersion=2022-11-28#get-an-organization
        - Get GitHub Actions permissions for an organization: https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#get-github-actions-permissions-for-an-organization

        Fine Grained Permissions Reference:
        - "Administration" organization permissions (read)

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
        id                                             = Normalize-Null $org.id
        node_id                                        = Normalize-Null $org.node_id
        name                                           = Normalize-Null $org.name
        # Relational Properties
        # Node Specific Properties
        login                                          = Normalize-Null $org.login
        blog                                           = Normalize-Null $org.blog
        is_verified                                    = Normalize-Null $org.is_verified
        public_repos                                   = Normalize-Null $org.public_repos
        followers                                      = Normalize-Null $org.followers
        html_url                                       = Normalize-Null $org.html_url
        created_at                                     = Normalize-Null $org.created_at
        updated_at                                     = Normalize-Null $org.updated_at
        total_private_repos                            = Normalize-Null $org.total_private_repos
        owned_private_repos                            = Normalize-Null $org.owned_private_repos
        collaborators                                  = Normalize-Null $org.collaborators
        default_repository_permission                  = Normalize-Null $org.default_repository_permission
        two_factor_requirement_enabled                 = Normalize-Null $org.two_factor_requirement_enabled
        advanced_security_enabled_for_new_repositories = Normalize-Null $org.advanced_security_enabled_for_new_repositories
        actions_enabled_repositories                   = Normalize-Null $actions.enabled_repositories
        actions_allowed_actions                        = Normalize-Null $actions.allowed_actions
        actions_sha_pinning_required                   = Normalize-Null $actions.sha_pinning_required
        # Accordion Panel Queries
        query_users                                    = "MATCH (n:GHUser {organization_id:'$($org.node_id)}) RETURN n"
        query_teams                                    = "MATCH (n:GHTeam {organization_id:'$($org.node_id)}) RETURN n"
        query_repositories                             = "MATCH (n:GHRepository {organization_id:'$($org.node_id)}) RETURN n"
    }

    $null = $nodes.Add((New-GitHoundNode -Id $org.node_id -Kind 'GHOrganization' -Properties $properties))

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
        Fetches and processes GitHub Teams for an organization.

    .DESCRIPTION
        This function retrieves teams for each organization provided in the pipeline. It creates nodes representing the teams and their relationships to the organization.

        API Reference: 
        - List teams: https://docs.github.com/en/rest/teams/teams?apiVersion=2022-11-28#list-teams

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

    foreach($team in (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Session.OrganizationName)/teams"))
    {
        $properties = [pscustomobject]@{
            # Common Properties
            id                = Normalize-Null $team.id
            node_id           = Normalize-Null $team.node_id
            name              = Normalize-Null $team.name
            # Relational Properties
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            # Node Specific Properties
            slug              = Normalize-Null $team.slug
            description       = Normalize-Null $team.description
            privacy           = Normalize-Null $team.privacy
            permission        = Normalize-Null $team.permission
            # Accordion Panel Queries
            query_first_degree_members = "MATCH p=(:GHUser)-[:GHHasRole]->(t:GHTeamRole)-[:GHMemberOf]->(:GHTeam {node_id:'$($team.node_id)'}) RETURN p"
            query_unrolled_members     = "MATCH p=(t:GHTeamRole)-[:GHMemberOf*1..]->(:GHTeam {node_id:'$($team.node_id)'}) MATCH p1 = (t)<-[:GHHasRole]-(:GHUser) RETURN p,p1"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $team.node_id -Kind 'GHTeam' -Properties $properties))
        
        if($null -ne $team.parent)
        {
            $null = $edges.Add((New-GitHoundEdge -Kind GHMemberOf -StartId $team.node_id -EndId $team.Parent.node_id -Properties @{ traversable = $true }))
        }
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
        Fetches and processes GitHub Users for an organization.

    .DESCRIPTION
        This function retrieves users for each organization provided in the pipeline. It creates nodes representing the users and their relationships to the organization.

        API Reference: 
        - List organization members: https://docs.github.com/en/rest/orgs/members?apiVersion=2022-11-28#list-organization-members
        - Get a user: https://docs.github.com/en/rest/users/users?apiVersion=2022-11-28#get-a-user

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


    Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/members" | ForEach-Object -Parallel {
        
        $nodes = $using:nodes
        $Session = $using:Session
        $Organization = $using:Organization
        $functionBundle = $using:GitHoundFunctionBundle
        foreach($funcName in $functionBundle.Keys) {
            Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
        }
        

        $user = $_
        <#
        Write-Verbose "Fetching user details for $($user.login)"
        try {
            $user_details = Invoke-GithubRestMethod -Session $Session -Path "user/$($user.id)"
        } catch {
            Write-Verbose "User $($user.login) could not be found via api"
            continue
        }
        #>

        $properties = @{
            # Common Properties
            id                  = Normalize-Null $user.id
            node_id             = Normalize-Null $user.node_id
            name                = Normalize-Null $user.login
            # Relational Properties
            organization_name   = Normalize-Null $Organization.properties.login
            organization_id     = Normalize-Null $Organization.properties.node_id
            # Node Specific Properties
            login               = Normalize-Null $user.login
            #full_name           = Normalize-Null $user_details.name
            #company             = Normalize-Null $user_details.company
            #email               = Normalize-Null $user_details.email
            #twitter_username    = Normalize-Null $user_details.twitter_username
            type                = Normalize-Null $user.type
            site_admin          = Normalize-Null $user.site_admin
            # Accordion Panel Queries
            query_roles         = "MATCH p=(t:GHUser {node_id:'$($user.node_id)'})-[:GHHasRole|GHMemberOf*1..4]->(:GitHub) RETURN p"
            query_teams         = "MATCH p=(:GHUser {node_id:'$($user.node_id)'})-[:GHHasRole]->(t:GHTeamRole)-[:GHMemberOf*1..4]->(:GHTeam) RETURN p"
            query_repositories  = "MATCH p=(t:GHUser {node_id:'$($user.node_id)'})-[:GHHasRole]->(:GHRepoRole)-[:GHReadRepoContents|GHWriteRepoContents|GHWriteRepoPullRequests|GHManageWebhooks|GHManageDeployKeys|GHPushProtectedBranch|GHDeleteAlertsCodeScanning|GHViewSecretScanningAlerts|GHRunOrgMigration|GHBypassBranchProtection|GHEditRepoProtections]->(:GHRepository) RETURN p"
            query_branches      = ""
        }
        
        $null = $nodes.Add((New-GitHoundNode -Id $user.node_id -Kind 'GHUser' -Properties $properties))
    } -ThrottleLimit 25

    Write-Output $nodes
}

function Git-HoundRepository
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Repositories for an organization. 

    .DESCRIPTION
        This function retrieves repositories for each organization provided in the pipeline. It creates nodes and edges representing the repositories and their relationships to the organization.

        API Reference: 
        - Get GitHub Actions permissions for an organization: https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#get-github-actions-permissions-for-an-organization
        - List selected repositories enabled for GitHub Actions in an organization: https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#list-github-actions-enabled-repositories-for-an-organization
        - List organization repositories: https://docs.github.com/en/rest/repos/repos?apiVersion=2022-11-28#list-organization-repositories

        Fine Grained Permissions Reference:
        - "Administration" organization permissions (read)
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

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $actions = Invoke-GithubRestMethod -Session $session -Path "orgs/$($Organization.Properties.login)/actions/permissions"

    if($actions.enabled_repositories -ne 'all')
    {
        $enabledRepos = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/actions/permissions/repositories").repositories.node_id
    }

    foreach($repo in (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/repos"))
    {
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
            organization_name            = Normalize-Null $Organization.properties.login
            organization_id              = Normalize-Null $Organization.properties.node_id
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
            query_branches               = "MATCH p=(:GHRepository {node_id: '$($repo.node_id)'})-[:GHHasBranch]->(:GHBranch) RETURN p"
            query_roles                  = "MATCH p=(:GHRepoRole)-[]->(:GHRepository {node_id: '$($repo.node_id)'}) RETURN p"
            query_teams                  = "MATCH p=(:GHTeam)-[:GHMemberOf|GHHasRole]->(:GHRepoRole)-[]->(:GHRepository {node_id: '$($repo.node_id)'}) RETURN p"
            query_workflows              = "MATCH p=(:GHRepository {node_id:'R_kgDOQKVZEw'})-[:GHHasWorkflow]->(w:GHWorkflow) RETURN p"
            query_user_permissions       = "MATCH p=(:GHUser)-[:GHHasRole]->()-[:GHHasBaseRole|GHHasRole|GHOwns|GHAddMember|GHMemberOf]->(:GHRepoRole)-[]->(:GHRepository {node_id: '$($repo.node_id)'}) RETURN p"
            query_explicit_readers       = "MATCH p=(role:GitHub)-[:GHHasBaseRole|GHReadRepoContents*1..]->(r:GHRepository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GHHasRole]-(:GHUser) RETURN p,p1"
            query_unrolled_readers       = "MATCH p=(:GitHub)-[:GHMemberOf|GHHasRole|GHHasBaseRole|GHReadRepoContents*1..]->(r:GHRepository {node_id:'$($repo.node_id)'}) RETURN p"
            query_explicit_writers       = "MATCH p=(role:GitHub)-[:GHHasBaseRole|GHWriteRepoContents|GHWriteRepoPullRequests*1..]->(r:GHRepository {node_id:'$($repo.node_id)'}) MATCH p1=(role)<-[:GHHasRole]-(:GHUser) RETURN p,p1"
            query_unrolled_writers       = "MATCH p=(:GitHub)-[:GHMemberOf|GHHasRole|GHHasBaseRole|GHWriteRepoContents|GHWriteRepoPullRequests*1..]->(r:GHRepository {node_id:'$($repo.node_id)'}) RETURN p"
            #query_first_degree_object_control  = "MATCH p=(t:GHUser)-[:GHHasRole]->(:GHRepoRole)-[:GHReadRepoContents|GHWriteRepoContents|GHWriteRepoPullRequests|GHManageWebhooks|GHManageDeployKeys|GHPushProtectedBranch|GHDeleteAlertsCodeScanning|GHViewSecretScanningAlerts|GHRunOrgMigration|GHBypassBranchProtection|GHEditRepoProtections]->(:GHRepository {node_id:'$($repo.node_id)'}) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repo.node_id -Kind 'GHRepository' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHOwns' -StartId $repo.owner.node_id -EndId $repo.node_id -Properties @{ traversable = $true }))
    }

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Git-HoundBranch
{
    <#
    .SYNOPSIS
        Retrieves branches for GitHub repositories and creates nodes and edges representing branch protections.
    
    .DESCRIPTION
        This function processes GitHub repositories to fetch their branches and associated protection settings. It creates nodes for each branch and edges to represent relationships such as bypass permissions and push restrictions.

        API Reference:
        - Get a branch: https://docs.github.com/en/rest/branches/branches?apiVersion=2022-11-28#get-a-branch
        - Get branch protection: https://docs.github.com/en/rest/branches/branch-protection?apiVersion=2022-11-28#get-branch-protection

        Fine Grained Permissions Reference:
        - "Contents" repository permissions (read)
        - "Administration" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Repository
        A GitHound.Repository object representing the repository for which branches are to be fetched.

    .EXAMPLE
        $branches = Git-HoundRepository | Git-HoundBranch
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
    }

    process
    {
        $Repository.nodes | Where-Object {$_.kinds -eq 'GHRepository'} | ForEach-Object -Parallel {
            $nodes = $using:nodes
            $edges = $using:edges
            $Session = $using:Session
            $functionBundle = $using:GitHoundFunctionBundle
            foreach($funcName in $functionBundle.Keys) {
                Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
            }
            $repo = $_

            Write-Verbose "Fetching branches for $($repo.properties.full_name)"
            foreach($branch in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/branches"))
            {    
                $branchId = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$($repo.properties.organization_id)_$($repo.properties.full_name)_$($branch.name)"))).Replace('-', '')

                #$BranchProtections = [pscustomobject]@{}
                $BranchProtectionProperties = [ordered]@{}
                
                if ($branch.protection.enabled -and $branch.protection_url) 
                {
                    $Protections = Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.Properties.full_name)/branches/$($branch.name)/protection"

                    $protection_enforce_admins = $Protections.enforce_admins.enabled
                    $protection_lock_branch = $Protections.lock_branch.enabled

                    # Check for Pull Request Reviews
                    # pull requests are required before merging
                    if ($Protections.required_pull_request_reviews) {
                        
                        $protection_required_pull_request_reviews = $False
                        
                        $protection_required_approving_review_count = $Protections.required_pull_request_reviews.required_approving_review_count
                        if ($Protections.required_pull_request_reviews.required_approving_review_count) {
                            $protection_required_pull_request_reviews = $True
                        }

                        $protection_require_code_owner_reviews = $Protections.required_pull_request_reviews.require_code_owner_reviews
                        if ($Protections.required_pull_request_reviews.require_code_owner_reviews) {
                            $protection_required_pull_request_reviews = $True
                        }

                        $protection_require_last_push_approval = $Protections.required_pull_request_reviews.require_last_push_approval
                        if ($Protections.required_pull_request_reviews.require_last_push_approval) {
                            $protection_required_pull_request_reviews = $True
                        }

                        # We need an edge here
                        foreach($user in $Protections.required_pull_request_reviews.bypass_pull_request_allowances.users) {
                            $null = $edges.Add((New-GitHoundEdge -Kind GHBypassRequiredPullRequest -StartId $user.node_id -EndId $branchId -Properties @{ traversable = $false }))
                        }

                        # We need an edge here
                        foreach($team in $Protections.required_pull_request_reviews.bypass_pull_request_allowances.teams) {
                            $null = $edges.Add((New-GitHoundEdge -Kind GHBypassRequiredPullRequest -StartId $team.node_id -EndId $branchId -Properties @{ traversable = $false }))
                        }

                        # TODO: handle apps?
                        foreach($app in $Protections.required_pull_request_reviews.bypass_pull_request_allowances.apps) {
                            #$null = $edges.Add((New-GitHoundEdge -Kind GHBypassRequiredPullRequest -StartId $app.node_id -EndId $branchId -Properties @{ traversable = $false }))
                        }

                        # We replaced BypassPrincipals with the above edges
                        # Do we still need this value or is it implied by the edges?
                        <#
                        if ($BypassPrincipals) {
                            $protection_bypass_pull_request_allowances = $BypassPrincipals.Count
                        }
                        else {
                            $protection_bypass_pull_request_allowances = 0
                        }
                        #>
                    }
                    else {
                        $protection_required_pull_request_reviews = $false
                    }

                    # Check for restrictions
                    if ($Protections.restrictions) {
                        foreach($user in $Protections.restrictions.users) {
                            $null = $edges.Add((New-GitHoundEdge -Kind GHRestrictionsCanPush -StartId $user.node_id -EndId $branchId -Properties @{ traversable = $false }))
                        }

                        foreach($team in $Protections.restrictions.teams) {
                            $null = $edges.Add((New-GitHoundEdge -Kind GHRestrictionsCanPush -StartId $team.node_id -EndId $branchId -Properties @{ traversable = $false }))
                        }

                        # TODO: handle apps?
                        #foreach($app in $Protections.restrictions.apps) {
                        #   $null = $edges.Add((New-GitHoundEdge -Kind GHRestrictionsCanPush -StartId $app.node_id -EndId $branchId -Properties @{ traversable = $false }))
                        #}

                        $protection_push_restrictions = $true
                    }
                    else {
                        $protection_push_restrictions = $false
                    }
                }
                else 
                {
                    # Here we just set all of the protection properties to false
                    $protection_enforce_admins = $false
                    $protection_lock_branch = $false
                    $protection_required_pull_request_reviews = $false
                    $protection_required_approving_review_count = 0
                    $protection_require_code_owner_reviews = $false
                    $protection_require_last_push_approval = $false
                    #$protection_bypass_pull_request_allowances = $false
                    $protection_push_restrictions = $false
                }

                $props = [pscustomobject]@{
                    # Common Properties
                    name                                       = Normalize-Null "$($repo.properties.name)\$($branch.name)"
                    id                                         = Normalize-Null $branchId
                    # Relational Properties
                    organization                               = Normalize-Null $repo.properties.organization_name
                    organization_id                            = Normalize-Null $repo.properties.organization_id
                    # Node Specific Properties
                    short_name                                 = Normalize-Null $branch.name
                    commit_hash                                = Normalize-Null $branch.commit.sha
                    commit_url                                 = Normalize-Null $branch.commit.url
                    protected                                  = Normalize-Null $branch.protected
                    protection_enforce_admins                  = Normalize-Null $protection_enforce_admins
                    protection_lock_branch                     = Normalize-Null $protection_lock_branch
                    protection_required_pull_request_reviews   = Normalize-Null $protection_required_pull_request_reviews
                    protection_required_approving_review_count = Normalize-Null $protection_required_approving_review_count
                    protection_require_code_owner_reviews      = Normalize-Null $protection_require_code_owner_reviews
                    protection_require_last_push_approval      = Normalize-Null $protection_require_last_push_approval
                    #protection_bypass_pull_request_allowances  = Normalize-Null $protection_bypass_pull_request_allowances
                    protection_push_restrictions               = Normalize-Null $protection_push_restrictions
                    # Accordion Panel Queries
                    query_branch_write                         = "MATCH p=(:GHUser)-[:GHCanWriteBranch|GHCanEditAndWriteBranch]->(:GHBranch {objectid:'$($branchId)'}) RETURN p"
                }

                foreach ($BranchProtectionProperty in $BranchProtectionProperties.GetEnumerator()) {
                    $props | Add-Member -MemberType NoteProperty -Name $BranchProtectionProperty.Key -Value $BranchProtectionProperty.Value
                }

                $null = $nodes.Add((New-GitHoundNode -Id $branchId -Kind GHBranch -Properties $props))
                $null = $edges.Add((New-GitHoundEdge -Kind GHHasBranch -StartId $repo.id -EndId $branchId -Properties @{ traversable = $true }))
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

function Git-HoundWorkflow
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Workflows (Actions) for repositories.
    
    .DESCRIPTION
        This function retrieves workflows for each repository provided in the pipeline. It creates nodes and edges representing the workflows and their relationships to repositories.

        API Reference: 
        - List repository workflows: https://docs.github.com/en/rest/actions/workflows?apiVersion=2022-11-28#list-repository-workflows

        Fine Grained Permissions Reference: 
        - "Actions" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Repository
        An array of repository objects to process.

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the workflows and their relationships.

    .EXAMPLE
        $workflows = Git-HoundRepository | Git-HoundWorkflow
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
    }

    process
    {
        $Repository.nodes | Where-Object {$_.kinds -eq 'GHRepository'} | ForEach-Object -Parallel {
            $nodes = $using:nodes
            $edges = $using:edges
            $Session = $using:Session
            $functionBundle = $using:GitHoundFunctionBundle
            foreach($funcName in $functionBundle.Keys) {
                Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
            }
            $repo = $_

            Write-Verbose "Fetching workflows for $($repo.properties.full_name)"
            foreach($workflow in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/actions/workflows").workflows)
            {
                #$workflowconfig = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/contents/$($workflow.path)").content)) | ConvertFrom-Yaml

                $props = [pscustomobject]@{
                    # Common Properties
                    name              = Normalize-Null "$($repo.properties.name)\$($workflow.name)"
                    id                = Normalize-Null $workflow.id
                    node_id           = Normalize-Null $workflow.node_id
                    # Relational Properties
                    organization_name = Normalize-Null $repo.properties.organization_name
                    organization_id   = Normalize-Null $repo.properties.organization_id
                    repository_name   = Normalize-Null $repo.properties.full_name
                    repository_id     = Normalize-Null $repo.properties.node_id
                    # Node Specific Properties
                    short_name        = Normalize-Null $workflow.name
                    path              = Normalize-Null $workflow.path
                    state             = Normalize-Null $workflow.state
                    url               = Normalize-Null $workflow.url
                    # Accordion Panel Queries
                }

                $null = $nodes.Add((New-GitHoundNode -Id $workflow.node_id -Kind GHWorkflow -Properties $props))
                $null = $edges.Add((New-GitHoundEdge -Kind GHHasWorkflow -StartId $repo.properties.node_id -EndId $workflow.node_id -Properties @{ traversable = $false }))
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
        $nodes = New-Object System.Collections.ArrayList
        $edges = New-Object System.Collections.ArrayList
    }

    process
    {
        $Repository.nodes | Where-Object {$_.kinds -eq 'GHRepository'} | ForEach-Object -Parallel {
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
                    organization      = Normalize-Null $repo.properties.organization_name
                    organization_id   = Normalize-Null $repo.properties.organization_id
                    repository_name   = Normalize-Null $repo.properties.full_name
                    repository_id     = Normalize-Null $repo.properties.id
                    # Node Specific Properties
                    short_name        = Normalize-Null $environment.name
                    can_admins_bypass = Normalize-Null $environment.can_admins_bypass
                    # Accordion Panel Queries
                }

                $null = $nodes.Add((New-GitHoundNode -Id $environment.node_id -Kind GHEnvironment -Properties $props))

                if($environment.deployment_branch_policy.custom_branch_policies -eq $true)
                {
                    foreach($policy in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/environments/$($environment.name)/deployment-branch-policies").branch_policies)
                    {
                        $branchId = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$($repo.properties.organization_id)_$($repo.properties.full_name)_$($policy.name)"))).Replace('-', '')
                        $null = $edges.Add((New-GitHoundEdge -Kind GHHasEnvironment -StartId $branchId -EndId $environment.node_id -Properties @{ traversable = $false }))
                    }
                }
                else 
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GHHasEnvironment -StartId $repo.Properties.node_id -EndId $environment.node_id -Properties @{ traversable = $true }))
                }

                # List environment secrets
                # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-environment-secrets
                # "Environments" repository permissions (read)
                foreach($secret in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/environments/$($environment.name)/secrets").secrets)
                {
                    $secretId = "GHEnvironmentSecret_$($environment.node_id)_$($secret.name)"
                    $properties = @{
                        # Common Properties
                        id                   = Normalize-Null $secretId
                        name                 = Normalize-Null $secret.name
                        # Relational Properties
                        organization_name    = Normalize-Null $Organization.Properties.login
                        organization_id      = Normalize-Null $Organization.Properties.node_id
                        environment_name     = Normalize-Null $environment.name
                        environment_id       = Normalize-Null $environment.node_id
                        # Node Specific Properties
                        created_at           = Normalize-Null $secret.created_at
                        updated_at           = Normalize-Null $secret.updated_at
                        # Accordion Panel Queries
                    }

                    $null = $nodes.Add((New-GitHoundNode -Id $secretId -Kind 'GHEnvironmentSecret' -Properties $properties))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GHContains' -StartId $environment.node_id -EndId $secretId -Properties @{ traversable = $false }))
                    $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasSecret' -StartId $environment.node_id -EndId $secretId -Properties @{ traversable = $false }))
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

function Git-HoundSecret
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Secrets for organizations and repositories.

    .DESCRIPTION
        This function retrieves organization and repository secrets. It creates nodes and edges representing the secrets and their relationships to organizations and repositories.

        API Reference: 
        - List organization secrets: https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-organization-secrets
        - List repository organization secrets: https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-repository-organization-secrets
        - List repository secrets: https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-repository-secrets

        Fine Grained Permissions Reference: 
        - "Secrets" organization permissions (read)
        - "Secrets" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Repository
        An array of repository objects to process.

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the environments and their relationships.

    .EXAMPLE
        $secrets = Git-HoundRepository | Git-HoundSecret

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

        $org = Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Session.OrganizationName)"

        # List organization secrets
        # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-organization-secrets
        # "Secrets" organization permissions (read)
        foreach($secret in (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($org.login)/actions/secrets").secrets)
        {
            $secretId = "GHOrgSecret_$($org.node_id)_$($secret.name)"
            $properties = @{
                # Common Properties
                id                   = Normalize-Null $secretId
                name                 = Normalize-Null $secret.name
                # Relational Properties
                organization_name    = Normalize-Null $org.login
                organization_id      = Normalize-Null $org.node_id
                # Node Specific Properties
                created_at           = Normalize-Null $secret.created_at
                updated_at           = Normalize-Null $secret.updated_at
                visibility           = Normalize-Null $secret.visibility
                # Accordion Panel Queries
            }

            $null = $nodes.Add((New-GitHoundNode -Id $secretId -Kind 'GHOrgSecret' -Properties $properties))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GHContains' -StartId $org.node_id -EndId $secretId -Properties @{ traversable = $false }))
        }
    }

    process
    {
        $Repository.nodes | Where-Object {$_.kinds -eq 'GHRepository'} | ForEach-Object -Parallel {
            $nodes = $using:nodes
            $edges = $using:edges
            $Session = $using:Session
            $functionBundle = $using:GitHoundFunctionBundle
            foreach($funcName in $functionBundle.Keys) {
                Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
            }
            $repo = $_

            # List repository organization secrets
            # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-repository-organization-secrets
            # "Secrets" repository permissions (read)
            foreach($secret in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/actions/organization-secrets").secrets)
            {
                $secretId = "GHOrgSecret_$($orgId)_$($secret.name)"
                $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasSecret' -StartId $repo.properties.node_id -EndId $secretId -Properties @{ traversable = $false }))
            }

            # List repository secrets
            # https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#list-repository-secrets
            # "Secrets" repository permissions (read)
            foreach($secret in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/actions/secrets").secrets)
            {
                $secretId = "GHSecret_$($repo.properties.node_id)_$($secret.name)"
                $properties = @{
                    # Common Properties
                    id                   = Normalize-Null $secretId
                    name                 = Normalize-Null $secret.name
                    # Relational Properties
                    organization_name    = Normalize-Null $Organization.Properties.login
                    organization_id      = Normalize-Null $Organization.Properties.node_id
                    repository_name      = Normalize-Null $repo.properties.name
                    repository_id        = Normalize-Null $repo.properties.node_id
                    # Node Specific Properties
                    created_at           = Normalize-Null $secret.created_at
                    updated_at           = Normalize-Null $secret.updated_at
                    visibility           = Normalize-Null $secret.visibility
                    # Accordion Panel Queries
                }

                $null = $nodes.Add((New-GitHoundNode -Id $secretId -Kind 'GHRepoSecret' -Properties $properties))
                $null = $edges.Add((New-GitHoundEdge -Kind 'GHContains' -StartId $repo.properties.node_id -EndId $secretId -Properties @{ traversable = $false }))
                $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasSecret' -StartId $repo.properties.node_id -EndId $secretId -Properties @{ traversable = $false }))
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

function Git-HoundOrganizationRole
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Organization Roles for an organization.

    .DESCRIPTION
        This function retrieves custom organization roles for a given organization. It creates nodes and edges representing the roles and their relationships to users and teams.

        API Reference:
        - Get all organization roles for an organization: https://docs.github.com/en/rest/orgs/organization-roles?apiVersion=2022-11-28#get-all-organization-roles-for-an-organization
        - List teams that are assigned to an organization role: https://docs.github.com/en/rest/orgs/organization-roles?apiVersion=2022-11-28#list-teams-that-are-assigned-to-an-organization-role
        - List users that are assigned to an organization role: https://docs.github.com/en/rest/orgs/organization-roles?apiVersion=2022-11-28#list-users-that-are-assigned-to-an-organization-role
        - List organization members: https://docs.github.com/en/rest/orgs/members?apiVersion=2022-11-28#list-organization-members
        - Get organization membership for a user: https://docs.github.com/en/rest/orgs/members?apiVersion=2022-11-28#get-organization-membership-for-a-user

        Fine Grained Permissions Reference:
        - "Custom organization roles" organization permissions (read)
        - "Members" organization permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Organization
        An organization object to process.

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the organization roles and their relationships.

    .EXAMPLE
        $orgRoles = Git-HoundOrganization | Git-HoundOrganizationRole
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

    $orgAllRepoReadId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_read"))
    $orgAllRepoTriageId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_triage"))
    $orgAllRepoWriteId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_write"))
    $orgAllRepoMaintainId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_maintain"))
    $orgAllRepoAdminId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_admin"))

    # In general parallelizing this is a bad idea, because most organizations have a small number of custom roles
    foreach($customrole in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($Organization.Properties.login)/organization-roles").roles)
    {
        $customRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_$($customrole.name)"))
        $customRoleProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $customRoleId
            name                   = Normalize-Null "$($Organization.Properties.login)/$($customrole.name)"
            # Relational Properties
            organization_name      = Normalize-Null $Organization.properties.login
            organization_id        = Normalize-Null $Organization.properties.node_id
            # Node Specific Properties
            short_name             = Normalize-Null $customrole.name
            type                   = Normalize-Null 'custom'
            # Accordion Panel Queries
            query_explicit_members = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHOrgRole {id:'$($customRoleId)'}) RETURN p"
            query_unrolled_members = "MATCH p=(:GHUser)-[:GHHasRole|GHHasBaseRole|GHMemberOf*1..]->(:GHOrgRole {id:'$($customRoleId)'}) RETURN p"
            query_repositories     = "MATCH p=(:GHOrgRole {id:'$($customRoleId)'})-[*]->(:GHRepository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $customRoleId -Kind 'GHOrgRole', 'GHRole' -Properties $customRoleProps))

        foreach($team in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($Organization.Properties.login)/organization-roles/$($customRole.id)/teams"))
        {
            $null = $edges.Add((New-GitHoundEdge -Kind GHHasRole -StartId $team.node_id -EndId $customRoleId -Properties @{traversable=$true}))
        }

        foreach($user in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($Organization.Properties.login)/organization-roles/$($customRole.id)/users"))
        {
            $null = $edges.Add((New-GitHoundEdge -Kind GHHasRole -StartId $user.node_id -EndId $customRoleId -Properties @{traversable=$true}))
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

            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $customRoleId -EndId $baseId -Properties @{traversable=$true}))
        }

        # Need to add support for custom permissions here
        foreach($premission in $customrole.permissions)
        {
            switch($premission)
            {
                #'delete_alerts_code_scanning' {$kind = 'GHDeleteAlertCodeScanning'}
                #'edit_org_custom_properties_values' {$kind = 'GHEditOrgCustomPropertiesValues'}
                #'manage_org_custom_properties_definitions' {$kind = 'GHManageOrgCustomPropertiesDefinitions'}
                #'manage_organization_oauth_application_policy' {$kind = 'GHManageOrganizationOAuthApplicationPolicy'}
                #'manage_organization_ref_rules' {$kind = 'GHManageOrganizationRefRules'}
                'manage_organization_webhooks' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageOrganizationWebhooks' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'org_bypass_code_scanning_dismissal_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHOrgBypassCodeScanningDismissalRequests' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'org_bypass_secret_scanning_closure_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHOrgBypassSecretScanningClosureRequests' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'org_review_and_manage_secret_scanning_bypass_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHOrgReviewAndManageSecretScanningBypassRequests' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'org_review_and_manage_secret_scanning_closure_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHOrgReviewAndManageSecretScanningClosureRequests' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                #'read_audit_logs' {$kind = 'GHReadAuditLogs'}
                #'read_code_quality' {$kind = 'GHReadCodeQuality'}
                #'read_code_scanning' {$kind = 'GHReadCodeScanning'}
                'read_organization_actions_usage_metrics' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadOrganizationActionsUsageMetrics' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'read_organization_custom_org_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadOrganizationCustomOrgRole' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'read_organization_custom_repo_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadOrganizationCustomRepoRole' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                #'resolve_dependabot_alerts' {$kind = 'GHResolveDependabotAlerts'}
                'resolve_secret_scanning_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHResolveSecretScanningAlerts' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                #'review_org_code_scanning_dismissal_requests' {$kind = 'GHReviewOrgCodeScanningDismissalRequests'}
                #'view_dependabot_alerts' {$kind = 'GHViewDependabotAlerts'}
                #'view_org_code_scanning_dismissal_requests' {$kind = 'GHViewOrgCodeScanningDismissalRequests'}
                'view_secret_scanning_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHViewSecretScanningAlerts' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'write_organization_actions_secrets' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationActionsSecrets' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'write_organization_actions_settings' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationActionsSettings' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                #'write_organization_actions_variables' {$kind = 'GHWriteOrganizationActionsVariables'}
                #'write_code_quality' {$kind = 'GHWriteCodeQuality'}
                #'write_code_scanning' {$kind = 'GHWriteCodeScanning'}
                'write_organization_custom_org_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationCustomOrgRole' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'write_organization_custom_repo_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationCustomRepoRole' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                'write_organization_network_configurations' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationNetworkConfigurations' -StartId $customRoleId -EndId $Organization.id -Properties @{traversable=$false})) }
                #'write_organization_runner_custom_images' {$kind = 'GHWriteOrganizationRunnerCustomImages'}
                #'write_organization_runners_and_runner_groups' {$kind = 'GHWriteOrganizationRunnersAndRunnerGroups'}
            }
        }
    }

    $orgOwnersId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($organization.id)_owners"))
    $ownersProps = [pscustomobject]@{
        # Common Properties
        id                     = Normalize-Null $orgOwnersId
        name                   = Normalize-Null "$($Organization.Properties.login)/owners"
        # Relational Properties
        organization_name      = Normalize-Null $Organization.properties.login
        organization_id        = Normalize-Null $Organization.properties.node_id
        # Node Specific Properties
        short_name             = Normalize-Null 'owners'
        type                   = Normalize-Null 'default'
        # Accordion Panel Queries
        query_explicit_members = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHOrgRole {id:'$($orgOwnersId)'}) RETURN p"
        query_unrolled_members = "MATCH p=(:GHUser)-[:GHHasRole|GHHasBaseRole|GHMemberOf*1..]->(:GHOrgRole {id:'$($orgOwnersId)'}) RETURN p"
        query_repositories     = "MATCH p=(:GHOrgRole {id:'$($orgOwnersId)'})-[*]->(:GHRepository) RETURN p"
    }
    $null = $nodes.Add((New-GitHoundNode -Id $orgOwnersId -Kind 'GHOrgRole', 'GHRole' -Properties $ownersProps))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateRepository' -StartId $orgOwnersId -EndId $Organization.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHInviteMember' -StartId $orgOwnersId -EndId $Organization.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHAddCollaborator' -StartId $orgOwnersId -EndId $Organization.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateTeam' -StartId $orgOwnersId -EndId $Organization.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHTransferRepository' -StartId $orgOwnersId -EndId $Organization.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgOwnersId -EndId $orgAllRepoAdminId -Properties @{traversable=$true}))

    $orgMembersId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($organization.id)_members"))
    $membersProps = [pscustomobject]@{
        # Common Properties
        id                = Normalize-Null $orgMembersId
        name              = Normalize-Null "$($Organization.Properties.login)/members"
        # Relational Properties
        organization_name = Normalize-Null $Organization.properties.login
        organization_id   = Normalize-Null $Organization.properties.node_id
        # Node Specific Properties
        short_name        = Normalize-Null 'members'
        type              = Normalize-Null 'default'
        # Accordion Panel Queries
        query_explicit_members = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHOrgRole {id:'$($orgMembersId)'}) RETURN p"
        query_unrolled_members = "MATCH p=(:GHUser)-[:GHHasRole|GHHasBaseRole|GHMemberOf*1..]->(:GHOrgRole {id:'$($orgMembersId)'}) RETURN p"
        query_repositories     = "MATCH p=(:GHOrgRole {id:'$($orgMembersId)'})-[*]->(:GHRepository) RETURN p"
    }
    $null = $nodes.Add((New-GitHoundNode -Id $orgMembersId -Kind 'GHOrgRole', 'GHRole' -Properties $membersProps))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateRepository' -StartId $orgMembersId -EndId $Organization.id -Properties @{traversable=$false}))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateTeam' -StartId $orgMembersId -EndId $Organization.id -Properties @{traversable=$false}))

    if($Organization.Properties.default_repository_permission -ne 'none')
    {
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgMembersId -EndId ([Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_$($Organization.properties.default_repository_permission)"))) -Properties @{traversable=$true}))
    }

    # Need to add custom role membership here
    # This is a great place to parallelize, because we must enumerate users and then check their memberships individually
    Invoke-GithubRestMethod -Session $Session -Path "orgs/$($organization.Properties.login)/members" | ForEach-Object -Parallel {
        
        $edges = $using:edges
        $Session = $using:Session
        $Organization = $using:Organization
        $orgOwnersId = $using:orgOwnersId
        $orgMembersId = $using:orgMembersId
        $functionBundle = $using:GitHoundFunctionBundle
        foreach($funcName in $functionBundle.Keys) {
            Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
        }
        $user = $_
        
        switch((Invoke-GithubRestMethod -Session $Session -Path "orgs/$($organization.Properties.login)/memberships/$($user.login)").role)
        {
            'admin' { $destId = $orgOwnersId}
            'member' { $destId = $orgMembersId }
            #'moderator' { $orgmoderatorsList.Add($m) }
            #'security admin' { $orgsecurityList.Add($m) }
        }
        $null = $edges.Add($(New-GitHoundEdge -Kind 'GHHasRole' -StartId $user.node_id -EndId $destId -Properties @{traversable=$true}))
    } -ThrottleLimit 25

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

# This is a third order data type after GHOrganization and GHTeam
# I think this should work by passing in the GHTeam output from Git-HoundTeam
# The question is whether this hinders its standalone nature, of course we can evaluate whether the input is provided from the pipeline or not
function Git-HoundTeamRole
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Team Roles for a given organization.

    .DESCRIPTION
        This function retrieves team roles for a given organization. It creates nodes and edges representing the roles and their relationships to users and teams.

        API Reference: 
        - List teams: https://docs.github.com/en/rest/teams/teams?apiVersion=2022-11-28#list-teams
        - List team members: https://docs.github.com/en/rest/teams/members?apiVersion=2022-11-28#list-team-members
        - Get team membership for a user: https://docs.github.com/en/rest/teams/members?apiVersion=2022-11-28#get-team-membership-for-a-user

        Fine Grained Permissions Reference:
        - "Members" organization permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Organization
        An organization object to process.

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the team roles and their relationships.

    .EXAMPLE
        $teamRoles = Git-HoundOrganization | Git-HoundTeamRole
    #>
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]
        $Team
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList

    $Team.Nodes | ForEach-Object -Parallel {
        
        $nodes = $using:nodes
        $edges = $using:edges
        $Session = $using:Session

        $functionBundle = $using:GitHoundFunctionBundle
        foreach($funcName in $functionBundle.Keys) {
            Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
        }
        $team = $_

        $memberId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($team.id)_members"))
        $memberProps = [pscustomobject]@{
            # Common Properties
            id                 = Normalize-Null $memberId
            name               = Normalize-Null "$($team.properties.organization_name)/$($team.properties.slug)/members"
            # Relational Properties
            organization_name  = Normalize-Null $team.properties.organization_name
            organization_id    = Normalize-Null $team.properties.organization_id
            team_name          = Normalize-Null $team.properties.name
            team_id            = Normalize-Null $team.id
            # Node Specific Properties
            short_name         = Normalize-Null 'members'
            type               = Normalize-Null 'team'
            # Accordion Panel Queries
            query_members      = "MATCH p=(:GHUser)-[GHHasRole]->(:GHTeamRole {id:'$($memberId)'}) RETURN p"
            query_repositories = "MATCH p=(:GHTeamRole {id:'$($memberId)'})-[*]->(:GHRepository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $memberId -Kind 'GHTeamRole','GHRole' -Properties $memberProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHMemberOf' -StartId $memberId -EndId $team.id -Properties @{traversable=$true}))

        $maintainerId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($team.id)_maintainers"))
        $maintainerProps = [pscustomobject]@{
            # Common Properties
            id                 = Normalize-Null $maintainerId
            name               = Normalize-Null "$($team.properties.organization_name)/$($team.properties.slug)/maintainers"
            # Relational Properties
            organization_name  = Normalize-Null $team.properties.organization_name
            organization_id    = Normalize-Null $team.properties.organization_id
            team_name          = Normalize-Null $team.properties.name
            team_id            = Normalize-Null $team.id
            # Node Specific Properties
            short_name         = Normalize-Null 'maintainers'
            type               = Normalize-Null 'team'
            # Accordion Panel Queries
            query_members      = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHTeamRole {id:'$($maintainerId)'}) RETURN p"
            query_repositories = "MATCH p=(:GHTeamRole {id:'$($maintainerId)'})-[*]->(:GHRepository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $maintainerId -Kind 'GHTeamRole','GHRole' -Properties $maintainerProps))

        $null = $edges.Add((New-GitHoundEdge -Kind 'GHMemberOf' -StartId $maintainerId -EndId $team.id -Properties @{traversable=$true}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHAddMember' -StartId $maintainerId -EndId $team.id -Properties @{traversable=$true}))

        foreach($member in (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($team.properties.organization_name)/teams/$($team.properties.slug)/members?role=member"))
        {
            <#
            switch((Invoke-GithubRestMethod -Session $Session -Path "orgs/$($team.properties.organization_name)/teams/$($team.properties.slug)/memberships/$($member.login)").role)
            {
                'member' { $targetId = $memberId }
                'maintainer' { $targetId = $maintainerId }
            }
            #>

            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasRole' -StartId $member.node_id -EndId $memberId -Properties @{traversable=$true}))
        }

        foreach($maintainer in (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($team.properties.organization_name)/teams/$($team.properties.slug)/members?role=maintainer"))
        {
            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasRole' -StartId $maintainer.node_id -EndId $maintainerId -Properties @{traversable=$true}))
        }
    } -ThrottleLimit 25

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

# This is a third order data type after GHOrganization and GHRepository
function Git-HoundRepositoryRole
{
    <#
    .SYNOPSIS
        Fetches and processes GitHub Repository Roles for a given organization.

    .DESCRIPTION
        This function retrieves custom repository roles for a given organization. It creates nodes and edges representing the roles and their relationships to users and teams.

        API Reference:
        - List custom repository roles in an organization: https://docs.github.com/en/enterprise-cloud@latest/rest/orgs/custom-roles?apiVersion=2022-11-28#list-custom-repository-roles-in-an-organization
        - List organization repositories: https://docs.github.com/en/enterprise-cloud@latest/rest/repos/repos?apiVersion=2022-11-28#list-organization-repositories
        - List repository collaborators: https://docs.github.com/en/rest/collaborators/collaborators?apiVersion=2022-11-28#list-repository-collaborators
        - List repository teams: https://docs.github.com/en/enterprise-cloud@latest/rest/repos/repos?apiVersion=2022-11-28#list-repository-teams

        Fine Grained Permissions Reference:
        - "Custom repository roles" organization permissions (read)
        - "Administration" organization permissions (read)
        - "Metadata" repository permissions (read)
        - "Administration" repository permissions (read)

    .PARAMETER Session
        A GitHound.Session object used for authentication and API requests.

    .PARAMETER Organization
        An organization object to process.

    .OUTPUTS
        A PSObject containing arrays of nodes and edges representing the repository roles and their relationships.

    .EXAMPLE
        $repoRoles = Git-HoundOrganization | Git-HoundRepositoryRole
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

    $orgAllRepoReadId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_read"))
    $orgAllRepoTriageId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_triage"))
    $orgAllRepoWriteId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_write"))
    $orgAllRepoMaintainId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_maintain"))
    $orgAllRepoAdminId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_admin"))

    $customRepoRoles = (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/custom-repository-roles").custom_roles


    Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.properties.login)/repos" | ForEach-Object -Parallel{
        
        $nodes = $using:nodes
        $edges = $using:edges
        $Session = $using:Session
        $Organization = $using:Organization
        $orgAllRepoReadId = $using:orgAllRepoReadId
        $orgAllRepoTriageId = $using:orgAllRepoTriageId
        $orgAllRepoWriteId = $using:orgAllRepoWriteId
        $orgAllRepoMaintainId = $using:orgAllRepoMaintainId
        $orgAllRepoAdminId = $using:orgAllRepoAdminId
        $customRepoRoles = $using:customRepoRoles

        $functionBundle = $using:GitHoundFunctionBundle
        foreach($funcName in $functionBundle.Keys) {
            Set-Item -Path "function:$funcName" -Value ([scriptblock]::Create($functionBundle[$funcName]))
        }
        $repo = $_

        # Create $repo Read Role
        $repoReadId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_read"))
        $repoReadProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoReadId
            name                   = Normalize-Null "$($repo.full_name)/read"
            # Relational Properties
            organization_name      = Normalize-Null $Organization.properties.login
            organization_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'read'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_members = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHRepoRole {id:'$($repoReadId)'}) RETURN p"
            query_unrolled_members = "MATCH p=(:GHUser)-[:GHHasRole|GHHasBaseRole|GHMemberOf*1..]->(:GHRepoRole {id:'$($repoReadId)'}) RETURN p"
            query_repository       = "MATCH p=(:GHRepoRole {id:'$($repoReadId)'})-[*]->(:GHRepository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoReadId -Kind 'GHRepoRole', 'GHRole' -Properties $repoReadProps))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoMetadata' -StartId $repoReadId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoContents' -StartId $repoReadId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoPullRequests' -StartId $repoReadId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoReadId -EndId $repoReadId -Properties @{traversable=$true}))

        # Create $repo Write Role
        $repoWriteId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_write"))
        $repoWriteProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoWriteId
            name                   = Normalize-Null "$($repo.full_name)/write"
            # Relational Properties
            organization_name      = Normalize-Null $Organization.properties.login
            organization_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'write'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_members = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHRepoRole {id:'$($repoWriteId)'}) RETURN p"
            query_unrolled_members = "MATCH p=(:GHUser)-[:GHHasRole|GHHasBaseRole|GHMemberOf*1..]->(:GHRepoRole {id:'$($repoWriteId)'}) RETURN p"
            query_repository       = "MATCH p=(:GHRepoRole {id:'$($repoWriteId)'})-[*]->(:GHRepository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoWriteId -Kind 'GHRepoRole', 'GHRole' -Properties $repoWriteProps))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoMetadata' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoContents' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteRepoContents' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHAddLabel' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHRemoveLabel' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCloseIssue' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReopenIssue' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoPullRequests' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteRepoPullRequests' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHClosePullRequest' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReopenPullRequest' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHAddAssignee' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetIssueType' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHRemoveAssignee' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHRequestPrReview' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHMarkAsDuplicate' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetMilestone' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReadCodeScanning' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteCodeScanning' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHToggleDiscussionAnswer' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHToggleDiscussionCommentMinimize' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageDiscussionSpotlights' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateDiscussionCategory' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditDiscussionCategory' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHConvertIssuesToDiscussions' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCloseDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReopenDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditCategoryOnDiscussion' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditDiscussionComment' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteDiscussionComment' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHViewDependabotAlerts' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHResolveDependabotAlerts' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageDiscussionBadges' -StartId $repoWriteId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoWriteId -EndId $repoWriteId -Properties @{traversable=$true}))

        # Create $repo Admin Role
        $repoAdminId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_admin"))
        $repoAdminProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoAdminId
            name                   = Normalize-Null "$($repo.full_name)/admin"
            # Relational Properties
            organization_name      = Normalize-Null $Organization.properties.login
            organization_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'admin'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_members = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHRepoRole {id:'$($repoAdminId)'}) RETURN p"
            query_unrolled_members = "MATCH p=(:GHUser)-[:GHHasRole|GHHasBaseRole|GHMemberOf*1..]->(:GHRepoRole {id:'$($repoAdminId)'}) RETURN p"
            query_repository       = "MATCH p=(:GHRepoRole {id:'$($repoAdminId)'})-[*]->(:GHRepository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoAdminId -Kind 'GHRepoRole', 'GHRole' -Properties $repoAdminProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHAdminTo' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoMetadata' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoContents' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteRepoContents' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHAddLabel' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHRemoveLabel' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCloseIssue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReopenIssue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoPullRequests' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteRepoPullRequests' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHClosePullRequest' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReopenPullRequest' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHAddAssignee' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteIssue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHRemoveAssignee' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHRequestPrReview' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHMarkAsDuplicate' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetMilestone' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetIssueType' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageTopics' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsDiscussions' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsWiki' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsProjects' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsMergeTypes' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsPages' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageWebhooks' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageDeployKeys' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditRepoMetadata' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetInteractionLimits' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetSocialPreview' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHPushProtectedBranch' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReadCodeScanning' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteCodeScanning' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteAlertsCodeScanning' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHViewSecretScanningAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHResolveSecretScanningAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHRunOrgMigration' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateDiscussionAnnouncement' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateDiscussionCategory' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditDiscussionCategory' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteDiscussionCategory' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageDiscussionSpotlights' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHToggleDiscussionAnswer' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHToggleDiscussionCommentMinimize' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHConvertIssuesToDiscussions' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateTag' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteTag' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHViewDependabotAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHResolveDependabotAlerts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHBypassBranchProtection' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSecurityProducts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageRepoSecurityProducts' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHEditRepoProtections' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditRepoAnnouncementBanners' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCloseDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReopenDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditCategoryOnDiscussion' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageDiscussionBadges' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditDiscussionComment' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteDiscussionComment' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHJumpMergeQueue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateSoloMergeQueueEntry' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHEditRepoCustomPropertiesValue' -StartId $repoAdminId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoAdminId -EndId $repoAdminId -Properties @{traversable=$true}))

        # Create $repo Triage Role
        $repoTriageId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_triage"))
        $repoTriageProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoTriageId
            name                   = Normalize-Null "$($repo.full_name)/triage"
            # Relational Properties
            organization_name      = Normalize-Null $Organization.properties.login
            organization_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'triage'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_members = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHRepoRole {id:'$($repoTriageId)'}) RETURN p"
            query_unrolled_members = "MATCH p=(:GHUser)-[:GHHasRole|GHHasBaseRole|GHMemberOf*1..]->(:GHRepoRole {id:'$($repoTriageId)'}) RETURN p"
            query_repository       = "MATCH p=(:GHRepoRole {id:'$($repoTriageId)'})-[*]->(:GHRepository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoTriageId -Kind 'GHRepoRole', 'GHRole' -Properties $repoTriageProps))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHAddLabel' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHRemoveLabel' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCloseIssue' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReopenIssue' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHClosePullRequest' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReopenPullRequest' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHAddAssignee' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHRemoveAssignee' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHRequestPrReview' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHMarkAsDuplicate' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetMilestone' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetIssueType' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHToggleDiscussionAnswer' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHToggleDiscussionCommentMinimize' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditDiscussionCategory' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateDiscussionCategory' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHConvertIssuesToDiscussions' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCloseDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHReopenDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditCategoryOnDiscussion' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditDiscussionComment' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteDiscussionComment' -StartId $repoTriageId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $repoTriageId -EndId $repoReadId -Properties @{traversable=$true}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoTriageId -EndId $repoTriageId -Properties @{traversable=$true}))

        # Create $repo Maintain Role
        $repoMaintainId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_maintain"))
        $repoMaintainProps = [pscustomobject]@{
            # Common Properties
            id                     = Normalize-Null $repoMaintainId
            name                   = Normalize-Null "$($repo.full_name)/maintain"
            # Relational Properties
            organization_name      = Normalize-Null $Organization.properties.login
            organization_id        = Normalize-Null $Organization.properties.node_id
            repository_name        = Normalize-Null $repo.name
            repository_id          = Normalize-Null $repo.node_id
            # Node Specific Properties
            short_name             = Normalize-Null 'maintain'
            type                   = Normalize-Null 'default'
            # Accordion Panel Queries
            query_explicit_members = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHRepoRole {id:'$($repoMaintainId)'}) RETURN p"
            query_unrolled_members = "MATCH p=(:GHUser)-[:GHHasRole|GHHasBaseRole|GHMemberOf*1..]->(:GHRepoRole {id:'$($repoMaintainId)'}) RETURN p"
            query_repository       = "MATCH p=(:GHRepoRole {id:'$($repoMaintainId)'})-[*]->(:GHRepository) RETURN p"
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoMaintainId -Kind 'GHRepoRole', 'GHRole' -Properties $repoMaintainProps))

        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageTopics' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsWiki' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsProjects' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsMergeTypes' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsPages' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHEditRepoMetadata' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetInteractionLimits' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSetSocialPreview' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHPushProtectedBranch' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateDiscussionAnnouncement' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteDiscussionCategory' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSettingsDiscussion' -StartId $repoMaintainId -EndId $repo.node_id -Properties @{traversable=$false}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $repoMaintainId -EndId $repoWriteId -Properties @{traversable=$true}))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoMaintainId -EndId $repoMaintainId -Properties @{traversable=$true}))

        # Custom Repository Roles
        foreach($customRepoRole in $customRepoRoles)
        {
            $customRepoRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_$($customRepoRole.name)"))
            $customRepoRoleProps = [pscustomobject]@{
                # Common Properties
                id                     = Normalize-Null $customRepoRoleId
                name                   = Normalize-Null "$($repo.full_name)/$($customRepoRole.name)"
                # Relational Properties
                organization_name      = Normalize-Null $Organization.properties.login
                organization_id        = Normalize-Null $Organization.properties.node_id
                repository_name        = Normalize-Null $repo.name
                repository_id          = Normalize-Null $repo.node_id
                # Node Specific Properties
                short_name             = Normalize-Null $customRepoRole.name
                type                   = Normalize-Null 'custom'
                # Accordion Panel Queries
                query_explicit_members = "MATCH p=(:GHUser)-[:GHHasRole]->(:GHRepoRole {id:'$($customRepoRoleId)'}) RETURN p"
                query_unrolled_members = "MATCH p=(:GHUser)-[:GHHasRole|GHHasBaseRole|GHMemberOf*1..]->(:GHRepoRole {id:'$($customRepoRoleId)'}) RETURN p"
                query_repository       = "MATCH p=(:GHRepoRole {id:'$($customRepoRoleId)'})-[*]->(:GHRepository) RETURN p"
            }
            $null = $nodes.Add((New-GitHoundNode -Id $customRepoRoleId -Kind 'GHRepoRole', 'GHRole' -Properties $customRepoRoleProps))
            
            if($null -ne $customRepoRole.base_role)
            {
                $targetBaseRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_$($customRepoRole.base_role)"))
                $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $customRepoRoleId -EndId $targetBaseRoleId -Properties @{traversable=$true}))
            }
            
            foreach($permission in $customRepoRole.permissions)
            {
                $null = $edges.Add((New-GitHoundEdge -Kind "GH$(ConvertTo-PascalCase -String $permission)" -StartId $customRepoRoleId -EndId $repo.node_id -Properties @{traversable=$false}))
            }
        }

        # Finding Members...
        ## GHUser Members
        foreach($collaborator in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($Organization.Properties.login)/$($repo.name)/collaborators?affiliation=direct"))
        {
            switch($collaborator.role_name)
            {
                'admin' { $repoRoleId = $repoAdminId }
                'maintain' { $repoRoleId = $repoMaintainId }
                'write' { $repoRoleId = $repoWriteId }
                'triage' { $repoRoleId = $repoTriageId }
                'read' { $repoRoleId = $repoReadId }
                default { $repoRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_$($collaborator.role_name)"))}
            }
            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasRole' -StartId $collaborator.node_id -EndId $repoRoleId -Properties @{traversable=$true}))
        }

        ## GHTeam Members
        foreach($team in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($Organization.Properties.login)/$($repo.name)/teams"))
        {
            switch($team.permission)
            {
                'admin' { $repoRoleId =  $repoAdminId }
                'maintain' { $repoRoleId =  $repoMaintainId }
                'push' { $repoRoleId = $repoWriteId }
                'triage' { $repoRoleId = $repoTriageId }
                'pull' { $repoRoleId = $repoReadId }
                default { $repoRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_$($team.permission)")) }
            }
            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasRole' -StartId $team.node_id -EndId $repoRoleId -Properties @{traversable=$true}))
        }
    } -ThrottleLimit 25

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

# This is a second order data type after GHOrganization
# Inspired by https://github.com/SpecterOps/GitHound/issues/3
# The GHHasSecretScanningAlert edge is used to link the alert to the repository
# However, that edge is not traversable because the GHReadSecretScanningAlerts permission is necessary to read the alerts and the GHReadRepositoryContents permission is necessary to read the repository
function Git-HoundSecretScanningAlert
{
    <#
    .SYNOPSIS
        Retrieves secret scanning alerts for a given GitHub organization.

    .DESCRIPTION
        This function fetches secret scanning alerts for the specified organization using the provided GitHound session and constructs nodes and edges representing the alerts and their relationships to repositories.

        Requires the GitHub API permission: GHReadSecretScanningAlerts on the organization and GHReadRepositoryContents on the repository.

        API Reference: 
        - List secret scanning alerts for an organization: https://docs.github.com/en/rest/secret-scanning/secret-scanning?apiVersion=2022-11-28#list-secret-scanning-alerts-for-an-organization

        Fine Grained Permissions Reference:
        - "Secret scanning alerts" repository permissions (read)

    .PARAMETER Session
        A GitHound session object used to authenticate and interact with the GitHub API.

    .PARAMETER Organization
        A PSObject representing the GitHub organization for which to retrieve secret scanning alerts.

    .OUTPUTS
        A PSObject containing two properties: Nodes and Edges. Nodes is an array of GHSecretScanningAlert nodes, and Edges is an array of GHHasSecretScanningAlert edges.

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
        $alertId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("SSA_$($Organization.id)_$($alert.repository.node_id)_$($alert.number)"))
        $properties =[pscustomobject]@{
            # Common Properties
            id                       = Normalize-Null $alertId
            name                     = Normalize-Null $alert.number
            # Relational Properties
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
        }

        $null = $nodes.Add((New-GitHoundNode -Id $alertId -Kind 'GHSecretScanningAlert' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasSecretScanningAlert' -StartId $alert.repository.node_id -EndId $alertId -Properties @{ traversable = $false }))
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
        A PSObject containing two properties: Nodes and Edges. Nodes is an array of GHAppInstallation nodes, and Edges is an array of edges (currently empty).
    
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
            organization_name    = Normalize-Null $app.account.login
            organization_id      = Normalize-Null $app.account.node_id
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

        $null = $nodes.Add((New-GitHoundNode -Id $app.client_id -Kind 'GHAppInstallation' -Properties $properties))
        #$null = $edges.Add((New-GitHoundEdge -Kind 'GHContains' -StartId $app.account.node_id -EndId $app.client_id -Properties @{ traversable = $false }))
    }

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
                active = Normalize-Null $scimIdentity.active
                external_id = Normalize-Null $scimIdentity.externalId
                family_name = Normalize-Null $scimIdentity.name.familyName
                given_name = Normalize-Null $scimIdentity.name.givenName
                username = Normalize-Null $scimIdentity.username
                schemas = Normalize-Null $scimIdentity.schemas
                id = Normalize-Null $scimIdentity.id
                resource_type = Normalize-Null $scimIdentity.meta.resourceType
                #created_date = Normalize-Null $scimIdentity.meta.created
                #last_modified_date = Normalize-Null $scimIdentity.meta.lastModified
                scim_location = Normalize-Null $scimIdentity.meta.location
            }
            
            $null = $nodes.Add((New-GitHoundNode -Kind SCIMUser -Id $scimIdentity.externalId -Properties $props))
            $null = $edges.Add((New-GitHoundEdge -Kind SCIMProvisioned -StartId $scimIdentity.externalId -EndId $scimIdentity.id -Properties @{ traversable = $true }))
        }

        $startIndex = $result.startIndex + $result.itemsPerPage
    } while($startIndex -lt $result.totalResults)
    
    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

# This is a second order data type after GHOrganization
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
                    #$null = $edges.Add((New-GitHoundEdge -Kind 'GHSyncedToEnvironment' -StartId $result.data.organization.samlIdentityProvider.id -EndId $ForeignEnvironmentName -EndKind $ForeginEnvironmentNodeKind -EndMatchBy name -Properties @{traversable=$false}))
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
                organization_name         = $result.data.organization.name
                organization_id           = $result.data.organization.id
                foreign_environment_id   = $ForeignEnvironmentId
                # Node Specific Properties
                digest_method             = $result.data.organization.samlIdentityProvider.digestMethod
                idp_certificate           = $result.data.organization.samlIdentityProvider.idpCertificate
                issuer                    = $result.data.organization.samlIdentityProvider.issuer
                signature_method          = $result.data.organization.samlIdentityProvider.signatureMethod
                sso_url                   = $result.data.organization.samlIdentityProvider.ssoUrl
                # Accordion Panel Queries
                query_environments        = "MATCH p=(:GHSamlIdentityProvider {objectid: '$($result.data.organization.samlIdentityProvider.id.ToUpper())'})<-[:GHHasSamlIdentityProvider]->(:GHOrganization) RETURN p"
                query_external_identities = "MATCH p=(:GHSamlIdentityProvider {objectid: '$($result.data.organization.samlIdentityProvider.id.ToUpper())'})-[:GHHasExternalIdentity]->() RETURN p"
            }

            $null = $nodes.Add((New-GitHoundNode -Id $result.data.organization.samlIdentityProvider.id -Kind 'GHSamlIdentityProvider' -Properties $identityProviderProps))
            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasSamlIdentityProvider' -StartId $result.data.organization.id -EndId $result.data.organization.samlIdentityProvider.id -Properties @{traversable=$false}))

            # Iterate through each External Identity and create GHExternalIdentity Nodes and relevant Edges
            foreach($identity in $result.data.organization.samlIdentityProvider.externalIdentities.nodes)
            {
                # Create GHExternalIdentity Node and Connect it to GHSamlIdentityProvider Node via GHHasExternalIdentity Edge
                # We may discover in the future that we need to capture more properties from the external identity

                $EIprops = [pscustomobject]@{
                    # Common Properties
                    name                      = Normalize-Null $identity.id
                    guid                      = Normalize-Null $identity.guid
                    # Relational Properties
                    organization_id           = Normalize-Null $result.data.organization.id
                    organization_name         = Normalize-Null $result.data.organization.name
                    # Node Specific Properties
                    saml_identity_family_name = Normalize-Null $identity.samlIdentity.familyName
                    saml_identity_given_name  = Normalize-Null $identity.samlIdentity.givenName
                    saml_identity_name_id     = Normalize-Null $identity.samlIdentity.nameId
                    saml_identity_username    = Normalize-Null $identity.samlIdentity.username
                    scim_identity_family_name = Normalize-Null $identity.scimIdentity.familyName
                    scim_identity_given_name  = Normalize-Null $identity.scimIdentity.givenName
                    scim_identity_username    = Normalize-Null $identity.scimIdentity.username
                    github_username           = Normalize-Null $identity.user.login
                    github_user_id            = Normalize-Null $identity.user.id
                    # Accordion Panel Queries
                    query_mapped_users = "MATCH p=(:GHExternalIdentity {objectid: '$($identity.id.ToUpper())'})-[:GHMapsToUser]->() RETURN p"
                }

                $null = $nodes.Add((New-GitHoundNode -Id $identity.id -Kind 'GHExternalIdentity' -Properties $EIprops))
                $null = $edges.Add((New-GitHoundEdge -Kind GHHasExternalIdentity -StartId $result.data.organization.samlIdentityProvider.id -EndId $identity.id -Properties @{traversable=$false}))
                
                if($identity.samlIdentity.username -ne $null)
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GHMapsToUser -StartId $identity.id -EndId $identity.samlIdentity.username -EndKind $ForeignUserNodeKind -EndMatchBy name -Properties @{traversable=$false}))
                }
                elseif($identity.scimIdentity.username -ne $null)
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GHMapsToUser -StartId $identity.id -EndId $identity.scimIdentity.username -EndKind $ForeignUserNodeKind -EndMatchBy name -Properties @{traversable=$false}))
                }

                if($identity.user.id -ne $null)
                {
                    $null = $edges.Add((New-GitHoundEdge -Kind GHMapsToUser -StartId $identity.id -EndId $identity.user.id -Properties @{traversable=$false}))
                    
                    # Create SyncedToGHUser Edge from Foreign Identity to GHUser
                    # This might need to be something that happens during post-processing since we do not control whether the foreign user node already exists in the graph
                    $null = $edges.Add((New-GitHoundEdge -Kind SyncedToGHUser -StartId $identity.samlIdentity.username -StartKind $ForeignUserNodeKind -StartMatchBy name -EndId $identity.user.id -Properties @{traversable=$true; composition="MATCH p=()<-[:GHSyncedToEnvironment]-(:GHSamlIdentityProvider)-[:GHHasExternalIdentity]->(:GHExternalIdentity)-[:GHMapsToUser]->(n) WHERE n.objectid = '$($identity.user.id.ToUpper())' OR n.name = '$($identity.samlIdentity.username.ToUpper())' RETURN p"}))
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
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList
    
    $Global:GitHoundFunctionBundle = Get-GitHoundFunctionBundle

    Write-Host "[*] Starting GitHound for $($Session.OrganizationName)"
    $org = Git-HoundOrganization -Session $Session
    if($org.nodes) { $nodes.AddRange(@($org.nodes)) }
    if($org.edges) { $edges.AddRange(@($org.edges)) }

    Write-Host "[*] Enumerating Organization Users"
    $users = $org.nodes[0] | Git-HoundUser -Session $Session
    if($users) { $nodes.AddRange(@($users)) }

    Write-Host "[*] Enumerating Organization Teams"
    $teams = $org.nodes[0] | Git-HoundTeam -Session $Session
    if($teams.nodes) { $nodes.AddRange(@($teams.nodes)) }
    if($teams.edges) { $edges.AddRange(@($teams.edges)) }

    Write-Host "[*] Enumerating Organization Repositories"
    $repos = $org.nodes[0] | Git-HoundRepository -Session $Session
    if($repos.nodes) { $nodes.AddRange(@($repos.nodes)) }
    if($repos.edges) { $edges.AddRange(@($repos.edges)) }

    Write-Host "[*] Enumerating Organization Branches"
    $branches = $repos | Git-HoundBranch -Session $Session
    if($branches.nodes) { $nodes.AddRange(@($branches.nodes)) }
    if($branches.edges) { $edges.AddRange(@($branches.edges)) }

    Write-Host "[*] Enumerating Organization Workflows"
    $workflows = $repos | Git-HoundWorkflow -Session $Session
    if($workflows.nodes) { $nodes.AddRange(@($workflows.nodes)) }
    if($workflows.edges) { $edges.AddRange(@($workflows.edges)) }

    Write-Host "[*] Enumerating Organization Environments"
    $environments = $repos | Git-HoundEnvironment -Session $Session
    if($environments.nodes) { $nodes.AddRange(@($environments.nodes)) }
    if($environments.edges) { $edges.AddRange(@($environments.edges)) }

    Write-Host "[*] Enumerating Organization Secrets"
    $secrets = $repos | Git-HoundSecret -Session $Session
    if($secrets.nodes) { $nodes.AddRange(@($secrets.nodes)) }
    if($secrets.edges) { $edges.AddRange(@($secrets.edges)) }

    Write-Host "[*] Enumerating Team Roles"
    $teamroles = $org.nodes[0] | Git-HoundTeamRole -Session $Session
    if($teamroles.nodes) { $nodes.AddRange(@($teamroles.nodes)) }
    if($teamroles.edges) { $edges.AddRange(@($teamroles.edges)) }

    Write-Host "[*] Enumerating Organization Roles"
    $orgroles = $org.nodes[0] | Git-HoundOrganizationRole -Session $Session
    if($orgroles.nodes) { $nodes.AddRange(@($orgroles.nodes)) }
    if($orgroles.edges) { $edges.AddRange(@($orgroles.edges)) }

    Write-Host "[*] Enumerating Repository Roles"
    $reporoles = $org.nodes[0] | Git-HoundRepositoryRole -Session $Session
    if($reporoles.nodes) { $nodes.AddRange(@($reporoles.nodes)) }
    if($reporoles.edges) { $edges.AddRange(@($reporoles.edges)) }
    
    Write-Host "[*] Enumerating Secret Scanning Alerts"
    $secretalerts = $org.nodes[0] | Git-HoundSecretScanningAlert -Session $Session
    if($secretalerts.nodes) { $nodes.AddRange(@($secretalerts.nodes)) }
    if($secretalerts.edges) { $edges.AddRange(@($secretalerts.edges)) }

    Write-Host "[*] Enumerating App Installations"
    $appInstallations = $org.nodes[0] | Git-HoundAppInstallation -Session $Session
    if($appInstallations.nodes) { $nodes.AddRange(@($appInstallations.nodes)) }
    if($appInstallations.edges) { $edges.AddRange(@($appInstallations.edges)) }

    Write-Host "[*] Converting to OpenGraph JSON Payload"
    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $nodes.ToArray()
            edges = $edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_$($org.nodes[0].id).json"


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
}

function Invoke-GitHoundIndependent
{
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList
    
    $Global:GitHoundFunctionBundle = Get-GitHoundFunctionBundle

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

    #Write-Host "[*] Enumerating App Installations"
    #$appInstallations = $org.nodes[0] | Git-HoundAppInstallation -Session $Session
    #if($appInstallations.nodes) { $nodes.AddRange(@($appInstallations.nodes)) }
    #if($appInstallations.edges) { $edges.AddRange(@($appInstallations.edges)) }

    Write-Host "[*] Converting to OpenGraph JSON Payload"
    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GitHub"
        }
        graph = [PSCustomObject]@{
            nodes = $nodes.ToArray()
            edges = $edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_$($org.nodes[0].id).json"


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
}