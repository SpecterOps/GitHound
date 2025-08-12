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
function New-GithubAppSession {
    [OutputType('GitHound.Session')] 
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory = $true)]
        [string]
        $OrganizationName,

        [Parameter(Position=1, Mandatory = $true)]
        [string]
        $ClientId,

        [Parameter(Position=2, Mandatory = $false)]
        [string]
        $PrivateKeyPath = './priv.pem'
    )

    $header = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{
    alg = "RS256"
    typ = "JWT"
    }))).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    $payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{
    iat = [System.DateTimeOffset]::UtcNow.AddSeconds(-30).ToUnixTimeSeconds()
    exp = [System.DateTimeOffset]::UtcNow.AddMinutes(5).ToUnixTimeSeconds()
    iss = $ClientId 
    }))).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem((Get-Content $PrivateKeyPath -Raw))

    $signature = [Convert]::ToBase64String($rsa.SignData([System.Text.Encoding]::UTF8.GetBytes("$header.$payload"), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $jwt = "$header.$payload.$signature"

    $presession = New-GithubSession -OrganizationName $OrganizationName -Token $jwt 

    $Installation = Invoke-GithubRestMethod -Session $presession -Path "app/installations" 
    
    if ($null -eq $Installation -or $Installation.Count -eq 0) {
        throw "No installations found for the GitHub App in the organization '$OrganizationName'."
    } elseif ($Installation.Count -gt 1) {
        throw "Multiple installations found for the GitHub App in the organization '$OrganizationName'. Please specify a single installation."
    }

    $AccessToken = Invoke-GithubRestMethod -Session $presession -Path "app/installations/$($Installation.id)/access_tokens" -Method 'POST'

    New-GithubSession -OrganizationName $OrganizationName -Token $AccessToken.token 

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
            if($LinkHeader) {
                $Response = Invoke-WebRequest -Uri "$LinkHeader" -Headers $Session.Headers -Method $Method -ErrorAction Stop
            } else {
                Write-Verbose "https://api.github.com/$($Path)"
                $Response = Invoke-WebRequest -Uri "$($Session.Uri)$($Path)" -Headers $Session.Headers -Method $Method -ErrorAction Stop
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

    Invoke-RestMethod @fparams
}

function New-GitHoundNode
{
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [String]
        $Id,

        [Parameter(Position = 1, Mandatory = $true)]
        [String]
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
        $EndMatchBy = 'id'
    )

    $edge = @{
        kind = $Kind
        start = @{
            value = $StartId
        }
        end = @{
            value = $EndId
        }
        properties = @{}
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
    param($Value)
    if ($null -eq $Value) { return "" }
    return $Value
}

function Git-HoundOrganization
{
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session
    )

    $org = Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Session.OrganizationName)"

    $properties = [pscustomobject]@{
        login                                          = Normalize-Null $org.login
        id                                             = Normalize-Null $org.id
        node_id                                        = Normalize-Null $org.node_id
        name                                           = Normalize-Null $org.name
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
    }

    Write-Output (New-GitHoundNode -Id $org.node_id -Kind 'GHOrganization' -Properties $properties)
}

function Git-HoundTeam
{
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
            id                = Normalize-Null $team.id
            node_id           = Normalize-Null $team.node_id
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            name              = Normalize-Null $team.name
            slug              = Normalize-Null $team.slug
            description       = Normalize-Null $team.description
            privacy           = Normalize-Null $team.privacy
            permission        = Normalize-Null $team.permission
        }
        $null = $nodes.Add((New-GitHoundNode -Id $team.node_id -Kind 'GHTeam' -Properties $properties))
        
        if($null -ne $team.parent)
        {
            $null = $edges.Add((New-GitHoundEdge -Kind GHMemberOf -StartId $team.node_id -EndId $team.Parent.node_id))
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
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [PSTypeName('GitHound.Session')]
        $Session,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $Organization
    )

    $nodes = New-Object System.Collections.ArrayList

    $normalize_null = ${function:Normalize-Null}.ToString()
    $new_githoundnode = ${function:New-GitHoundNode}.ToString()
    $invoke_githubrestmethod = ${function:Invoke-GithubRestMethod}.ToString()

    Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/members" | ForEach-Object -Parallel {
        
        $nodes = $using:nodes
        $Session = $using:Session
        $Organization = $using:Organization
        ${function:Normalize-Null} = $using:normalize_null
        ${function:New-GitHoundNode} = $using:new_githoundnode
        ${function:Invoke-GithubRestMethod} = $using:invoke_githubrestmethod

        $user = $_
        Write-Verbose "Fetching user details for $($user.login)"
        try {
            $user_details = Invoke-GithubRestMethod -Session $Session -Path "user/$($user.id)"
        } catch {
            Write-Verbose "User $($user.login) could not be found via api"
            continue
        }

        $properties = @{
            id                  = Normalize-Null $user.id
            node_id             = Normalize-Null $user.node_id
            organization_name   = Normalize-Null $Organization.properties.login
            organization_id     = Normalize-Null $Organization.properties.node_id
            login               = Normalize-Null $user.login
            name                = Normalize-Null $user.login
            full_name           = Normalize-Null $user_details.name
            company             = Normalize-Null $user_details.company
            email               = Normalize-Null $user_details.email
            twitter_username    = Normalize-Null $user_details.twitter_username
            type                = Normalize-Null $user.type
            site_admin          = Normalize-Null $user.site_admin
        }
        
        $null = $nodes.Add((New-GitHoundNode -Id $user.node_id -Kind 'GHUser' -Properties $properties))
    } -ThrottleLimit 25

    Write-Output $nodes
}

function Git-HoundRepository
{
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

    foreach($repo in (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/repos"))
    {
        $properties = @{
            id                          = Normalize-Null $repo.id
            node_id                     = Normalize-Null $repo.node_id
            organization_name           = Normalize-Null $Organization.properties.login
            organization_id             = Normalize-Null $Organization.properties.node_id
            name                        = Normalize-Null $repo.name
            full_name                   = Normalize-Null $repo.full_name
            private                     = Normalize-Null $repo.private
            owner_id                    = Normalize-Null $repo.owner.id
            owner_node_id               = Normalize-Null $repo.owner.node_id
            owner_name                  = Normalize-Null $repo.owner.login
            html_url                    = Normalize-Null $repo.html_url
            description                 = Normalize-Null $description
            created_at                  = Normalize-Null $repo.created_at
            updated_at                  = Normalize-Null $repo.updated_at
            pushed_at                   = Normalize-Null $repo.pushed_at
            archived                    = Normalize-Null $repo.archived
            disabled                    = Normalize-Null $repo.disabled
            open_issues_count           = Normalize-Null $repo.open_issues_count
            allow_forking               = Normalize-Null $repo.allow_forking
            web_commit_signoff_required = Normalize-Null $repo.web_commit_signoff_required
            visibility                  = Normalize-Null $repo.visibility
            forks                       = Normalize-Null $repo.forks
            open_issues                 = Normalize-Null $repo.open_issues
            watchers                    = Normalize-Null $repo.watchers
            default_branch              = Normalize-Null $repo.default_branch
            secret_scanning             = Normalize-Null $repo.security_and_analysis.secret_scanning.status
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repo.node_id -Kind 'GHRepository' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHOwns' -StartId $repo.owner.node_id -EndId $repo.node_id))
    }

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

# I still don't like the way branch protections are handled here, but we sped up the collection
function Git-HoundBranch
{
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

        $normalize_null = ${function:Normalize-Null}.ToString()
        $new_githoundnode = ${function:New-GitHoundNode}.ToString()
        $new_githoundedge = ${function:New-GitHoundEdge}.ToString()
        $invoke_githubrestmethod = ${function:Invoke-GithubRestMethod}.ToString()
    }

    process
    {
        $Repository.nodes | ForEach-Object -Parallel {
            $nodes = $using:nodes
            $edges = $using:edges
            $Session = $using:Session
            ${function:Normalize-Null} = $using:normalize_null
            ${function:New-GitHoundNode} = $using:new_githoundnode
            ${function:New-GitHoundEdge} = $using:new_githoundedge
            ${function:Invoke-GithubRestMethod} = $using:invoke_githubrestmethod
            $repo = $_

            Write-Verbose "Fetching branches for $($repo.properties.full_name)"
            foreach($branch in (Invoke-GithubRestMethod -Session $Session -Path "repos/$($repo.properties.full_name)/branches"))
            {    
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
                            $null = $edges.Add((New-GitHoundEdge -Kind GHBypassPullRequestAllowances -StartId $user.node_id -EndId $branch.commit.sha))
                        }

                        # We need an edge here
                        foreach($team in $Protections.required_pull_request_reviews.bypass_pull_request_allowances.teams) {
                            $null = $edges.Add((New-GitHoundEdge -Kind GHBypassPullRequestAllowances -StartId $team.node_id -EndId $branch.commit.sha))
                        }

                        # TODO: handle apps?
                        foreach($app in $Protections.required_pull_request_reviews.bypass_pull_request_allowances.apps) {
                            #$null = $edges.Add((New-GitHoundEdge -Kind GHBypassPullRequestAllowances -StartId $app.node_id -EndId $branch.commit.sha))
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
                            $null = $edges.Add((New-GitHoundEdge -Kind GHRestrictionsCanPush -StartId $user.node_id -EndId $branch.commit.sha))
                        }

                        foreach($team in $Protections.restrictions.team) {
                            $null = $edges.Add((New-GitHoundEdge -Kind GHRestrictionsCanPush -StartId $team.node_id -EndId $branch.commit.sha))
                        }

                        # TODO: handle apps?
                        foreach($app in $Protections.restrictions.apps) {
                            #$null = $edges.Add((New-GitHoundEdge -Kind GHRestrictionsCanPush -StartId $app.node_id -EndId $branch.commit.sha))
                        }

                        # Same question as BypassPrincipals
                        # Do we still need this value or is it implied by the edges?
                        <#
                        if ($RestrictionPrincipals) {
                            $protection_push_restrictions = $RestrictionPrincipals.Count
                        }
                        #>
                    }
                    else {
                        $protection_push_restrictions = 0
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
                    #$protection_bypass_pull_request_allowances = 0
                    #$protection_push_restrictions = 0
                }


                $branchId = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$($repo.properties.organization_id)_$($repo.properties.full_name)_$($branch.name)"))).Replace('-', '')

                $props = [pscustomobject]@{
                    organization                               = Normalize-Null $repo.properties.organization_name
                    organization_id                            = Normalize-Null $repo.properties.organization_id
                    short_name                                 = Normalize-Null $branch.name
                    name                                       = Normalize-Null "$($repo.properties.name)\$($branch.name)"
                    id                                         = Normalize-Null $branchId
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
                    #protection_push_restrictions               = Normalize-Null $protection_push_restrictions
                }

                foreach ($BranchProtectionProperty in $BranchProtectionProperties.GetEnumerator()) {
                    $props | Add-Member -MemberType NoteProperty -Name $BranchProtectionProperty.Key -Value $BranchProtectionProperty.Value
                }

                $null = $nodes.Add((New-GitHoundNode -Id $branchId -Kind GHBranch -Properties $props))
                $null = $edges.Add((New-GitHoundEdge -Kind GHHasBranch -StartId $repo.id -EndId $branchId))
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

# This is a second order data type after GHOrganization
function Git-HoundOrganizationRole
{
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

    $new_githoundedge = ${function:New-GitHoundEdge}.ToString()
    $invoke_githubrestmethod = ${function:Invoke-GithubRestMethod}.ToString()

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
            id                = Normalize-Null $customRoleId
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            name              = Normalize-Null "$($Organization.Properties.login)/$($customrole.name)"
            short_name        = Normalize-Null $customrole.name
            type              = Normalize-Null 'organization'
        }
        $null = $nodes.Add((New-GitHoundNode -Id $customRoleId -Kind 'GHOrgRole' -Properties $customRoleProps))

        foreach($team in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($Organization.Properties.login)/organization-roles/$($customRole.id)/teams"))
        {
            $null = $edges.Add((New-GitHoundEdge -Kind GHHasRole -StartId $team.node_id -EndId $customRoleId))
        }

        foreach($user in (Invoke-GithubRestMethod -Session $session -Path "orgs/$($Organization.Properties.login)/organization-roles/$($customRole.id)/users"))
        {
            $null = $edges.Add((New-GitHoundEdge -Kind GHHasRole -StartId $user.node_id -EndId $customRoleId))
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
            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $customRoleId -EndId $baseId))
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
                'manage_organization_webhooks' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageOrganizationWebhooks' -StartId $customRoleId -EndId $Organization.id)) }
                'org_bypass_code_scanning_dismissal_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHOrgBypassCodeScanningDismissalRequests' -StartId $customRoleId -EndId $Organization.id)) }
                'org_bypass_secret_scanning_closure_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHOrgBypassSecretScanningClosureRequests' -StartId $customRoleId -EndId $Organization.id)) }
                'org_review_and_manage_secret_scanning_bypass_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHOrgReviewAndManageSecretScanningBypassRequests' -StartId $customRoleId -EndId $Organization.id)) }
                'org_review_and_manage_secret_scanning_closure_requests' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHOrgReviewAndManageSecretScanningClosureRequests' -StartId $customRoleId -EndId $Organization.id)) }
                #'read_audit_logs' {$kind = 'GHReadAuditLogs'}
                #'read_code_quality' {$kind = 'GHReadCodeQuality'}
                #'read_code_scanning' {$kind = 'GHReadCodeScanning'}
                'read_organization_actions_usage_metrics' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadOrganizationActionsUsageMetrics' -StartId $customRoleId -EndId $Organization.id)) }
                'read_organization_custom_org_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadOrganizationCustomOrgRole' -StartId $customRoleId -EndId $Organization.id)) }
                'read_organization_custom_repo_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadOrganizationCustomRepoRole' -StartId $customRoleId -EndId $Organization.id)) }
                #'resolve_dependabot_alerts' {$kind = 'GHResolveDependabotAlerts'}
                'resolve_secret_scanning_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHResolveSecretScanningAlerts' -StartId $customRoleId -EndId $Organization.id)) }
                #'review_org_code_scanning_dismissal_requests' {$kind = 'GHReviewOrgCodeScanningDismissalRequests'}
                #'view_dependabot_alerts' {$kind = 'GHViewDependabotAlerts'}
                #'view_org_code_scanning_dismissal_requests' {$kind = 'GHViewOrgCodeScanningDismissalRequests'}
                'view_secret_scanning_alerts' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHViewSecretScanningAlerts' -StartId $customRoleId -EndId $Organization.id)) }
                'write_organization_actions_secrets' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationActionsSecrets' -StartId $customRoleId -EndId $Organization.id)) }
                'write_organization_actions_settings' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationActionsSettings' -StartId $customRoleId -EndId $Organization.id)) }
                #'write_organization_actions_variables' {$kind = 'GHWriteOrganizationActionsVariables'}
                #'write_code_quality' {$kind = 'GHWriteCodeQuality'}
                #'write_code_scanning' {$kind = 'GHWriteCodeScanning'}
                'write_organization_custom_org_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationCustomOrgRole' -StartId $customRoleId -EndId $Organization.id)) }
                'write_organization_custom_repo_role' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationCustomRepoRole' -StartId $customRoleId -EndId $Organization.id)) }
                'write_organization_network_configurations' { $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteOrganizationNetworkConfigurations' -StartId $customRoleId -EndId $Organization.id)) }
                #'write_organization_runner_custom_images' {$kind = 'GHWriteOrganizationRunnerCustomImages'}
                #'write_organization_runners_and_runner_groups' {$kind = 'GHWriteOrganizationRunnersAndRunnerGroups'}
            }
        }
    }

    $orgOwnersId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($organization.id)_owners"))
    $ownersProps = [pscustomobject]@{
        id                = Normalize-Null $orgOwnersId
        organization_name = Normalize-Null $Organization.properties.login
        organization_id   = Normalize-Null $Organization.properties.node_id
        name              = Normalize-Null "$($Organization.Properties.login)/owners"
        short_name        = Normalize-Null 'owners'
        type              = Normalize-Null 'organization'
    }
    $null = $nodes.Add((New-GitHoundNode -Id $orgOwnersId -Kind 'GHOrgRole' -Properties $ownersProps))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateRepository' -StartId $orgOwnersId -EndId $Organization.id))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHInviteMember' -StartId $orgOwnersId -EndId $Organization.id))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHAddCollaborator' -StartId $orgOwnersId -EndId $Organization.id))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateTeam' -StartId $orgOwnersId -EndId $Organization.id))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHTransferRepository' -StartId $orgOwnersId -EndId $Organization.id))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgOwnersId -EndId $orgAllRepoAdminId))

    $orgMembersId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($organization.id)_members"))
    $membersProps = [pscustomobject]@{
        id                = Normalize-Null $orgMembersId
        organization_name = Normalize-Null $Organization.properties.login
        organization_id   = Normalize-Null $Organization.properties.node_id
        name              = Normalize-Null "$($Organization.Properties.login)/members"
        short_name        = Normalize-Null 'members'
        type              = Normalize-Null 'organization'
    }
    $null = $nodes.Add((New-GitHoundNode -Id $orgMembersId -Kind 'GHOrgRole' -Properties $membersProps))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateRepository' -StartId $orgMembersId -EndId $Organization.id))
    $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateTeam' -StartId $orgMembersId -EndId $Organization.id))

    if($Organization.Properties.default_repository_permission -ne 'none')
    {
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgMembersId -EndId ([Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Organization.id)_all_repo_$($Organization.properties.default_repository_permission)")))))
    }

    # Need to add custom role membership here
    # This is a great place to parallelize, because we must enumerate users and then check their memberships individually
    Invoke-GithubRestMethod -Session $Session -Path "orgs/$($organization.Properties.login)/members" | ForEach-Object -Parallel {
        
        $edges = $using:edges
        $Session = $using:Session
        $Organization = $using:Organization
        $orgOwnersId = $using:orgOwnersId
        $orgMembersId = $using:orgMembersId
        ${function:New-GitHoundEdge} = $using:new_githoundedge
        ${function:Invoke-GithubRestMethod} = $using:invoke_githubrestmethod
        $user = $_
        
        switch((Invoke-GithubRestMethod -Session $Session -Path "orgs/$($organization.Properties.login)/memberships/$($user.login)").role)
        {
            'admin' { $destId = $orgOwnersId}
            'member' { $destId = $orgMembersId }
            #'moderator' { $orgmoderatorsList.Add($m) }
            #'security admin' { $orgsecurityList.Add($m) }
        }
        $null = $edges.Add($(New-GitHoundEdge -Kind 'GHHasRole' -StartId $user.node_id -EndId $destId))
    } -ThrottleLimit 25

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

# This is a third order data type after GHOrganization and GHTeam
function Git-HoundTeamRole
{
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

    $normalize_null = ${function:Normalize-Null}.ToString()
    $new_githoundnode = ${function:New-GitHoundNode}.ToString()
    $new_githoundedge = ${function:New-GitHoundEdge}.ToString()
    $invoke_githubrestmethod = ${function:Invoke-GithubRestMethod}.ToString()

    Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/teams" | ForEach-Object -Parallel {
        
        $nodes = $using:nodes
        $edges = $using:edges
        $Session = $using:Session
        $Organization = $using:Organization
        ${function:Normalize-Null} = $using:normalize_null
        ${function:New-GitHoundNode} = $using:new_githoundnode
        ${function:New-GitHoundEdge} = $using:new_githoundedge
        ${function:Invoke-GithubRestMethod} = $using:invoke_githubrestmethod

        $memberId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($_.node_id)_members"))
        $memberProps = [pscustomobject]@{
            id                = Normalize-Null $memberId
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            name              = Normalize-Null "$($Organization.Properties.login)/$($_.slug)/members"
            short_name        = Normalize-Null 'members'
            type              = Normalize-Null 'team'
        }
        $null = $nodes.Add((New-GitHoundNode -Id $memberId -Kind 'GHTeamRole' -Properties $memberProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHMemberOf' -StartId $memberId -EndId $_.node_id))

        $maintainerId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($_.node_id)_maintainers"))
        $maintainerProps = [pscustomobject]@{
            id                = Normalize-Null $maintainerId
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            name              = Normalize-Null "$($Organization.Properties.login)/$($_.slug)/maintainers"
            short_name        = Normalize-Null 'maintainers'
            type              = Normalize-Null 'team'
        }
        $null = $nodes.Add((New-GitHoundNode -Id $maintainerId -Kind 'GHTeamRole' -Properties $maintainerProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHMemberOf' -StartId $maintainerId -EndId $_.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHAddMember' -StartId $maintainerId -EndId $_.node_id))

        foreach($member in (Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/teams/$($_.slug)/members"))
        {
            switch((Invoke-GithubRestMethod -Session $Session -Path "orgs/$($Organization.Properties.login)/teams/$($_.slug)/memberships/$($member.login)").role)
            {
                'member' { $targetId = $memberId }
                'maintainer' { $targetId = $maintainerId }
            }
            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasRole' -StartId $member.node_id -EndId $targetId))
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

    $normalize_null = ${function:Normalize-Null}.ToString()
    $new_githoundnode = ${function:New-GitHoundNode}.ToString()
    $new_githoundedge = ${function:New-GitHoundEdge}.ToString()
    $invoke_githubrestmethod = ${function:Invoke-GithubRestMethod}.ToString()

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
        ${function:Normalize-Null} = $using:normalize_null
        ${function:New-GitHoundNode} = $using:new_githoundnode
        ${function:New-GitHoundEdge} = $using:new_githoundedge
        ${function:Invoke-GithubRestMethod} = $using:invoke_githubrestmethod
        $repo = $_

        # Create $repo Read Role
        $repoReadId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_read"))
        $repoReadProps = [pscustomobject]@{
            id                = Normalize-Null $repoReadId
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            name              = Normalize-Null "$($repo.full_name)/read"
            short_name        = Normalize-Null 'read'
            type              = Normalize-Null 'repository'
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoReadId -Kind 'GHRepoRole' -Properties $repoReadProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHCanPull' -StartId $repoReadId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoContents' -StartId $repoReadId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoReadId -EndId $repoReadId))

        # Create $repo Write Role
        $repoWriteId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_write"))
        $repoWriteProps = [pscustomobject]@{
            id                = Normalize-Null $repoWriteId
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            name              = Normalize-Null "$($repo.full_name)/write"
            short_name        = Normalize-Null 'write'
            type              = Normalize-Null 'repository'
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoWriteId -Kind 'GHRepoRole' -Properties $repoWriteProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHCanPush' -StartId $repoWriteId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHCanPull' -StartId $repoWriteId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoContents' -StartId $repoWriteId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteRepoContents' -StartId $repoWriteId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteRepoPullRequests' -StartId $repoWriteId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoWriteId -EndId $repoWriteId))

        # Create $repo Admin Role
        $repoAdminId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_admin"))
        $repoAdminProps = [pscustomobject]@{
            id                = Normalize-Null $repoAdminId
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            name              = Normalize-Null "$($repo.full_name)/admin"
            short_name        = Normalize-Null 'admin'
            type              = Normalize-Null 'repository'
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoAdminId -Kind 'GHRepoRole' -Properties $repoAdminProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHAdminTo' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHCanPush' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHCanPull' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHReadRepoContents' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteRepoContents' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHWriteRepoPullRequests' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageWebhooks' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageDeployKeys' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHPushProtectedBranch' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHDeleteAlertsCodeScanning' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHViewSecretScanningAlerts' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHRunOrgMigration' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHBypassProtections' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageSecurityProducts' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHManageRepoSecurityProducts' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHEditProtections' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHJumpMergeQueue' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHCreateSoloMergeQueueEntry' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHEditRepoCustomPropertiesValues' -StartId $repoAdminId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoAdminId -EndId $repoAdminId))

        # Create $repo Triage Role
        $repoTriageId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_triage"))
        $repoTriageProps = [pscustomobject]@{
            id                = Normalize-Null $repoTriageId
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            name              = Normalize-Null "$($repo.full_name)/triage"
            short_name        = Normalize-Null 'triage'
            type              = Normalize-Null 'repository'
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoTriageId -Kind 'GHRepoRole' -Properties $repoTriageProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $repoTriageId -EndId $repoReadId))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoTriageId -EndId $repoTriageId))

        # Create $repo Maintain Role
        $repoMaintainId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_maintain"))
        $repoMaintainProps = [pscustomobject]@{
            id                = Normalize-Null $repoMaintainId
            organization_name = Normalize-Null $Organization.properties.login
            organization_id   = Normalize-Null $Organization.properties.node_id
            name              = Normalize-Null "$($repo.full_name)/maintain"
            short_name        = Normalize-Null 'maintain'
            type              = Normalize-Null 'repository'
        }
        $null = $nodes.Add((New-GitHoundNode -Id $repoMaintainId -Kind 'GHRepoRole' -Properties $repoMaintainProps))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHPushProtectedBranch' -StartId $repoMaintainId -EndId $repo.node_id))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $repoMaintainId -EndId $repoWriteId))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $orgAllRepoMaintainId -EndId $repoMaintainId))

        # Custom Repository Roles
        foreach($customRepoRole in $customRepoRoles)
        {
            $customRepoRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_$($customRepoRole.name)"))
            $customRepoRoleProps = [pscustomobject]@{
                id                = Normalize-Null $customRepoRoleId
                organization_name = Normalize-Null $Organization.properties.login
                organization_id   = Normalize-Null $Organization.properties.node_id
                name              = Normalize-Null "$($repo.full_name)/$($customRepoRole.name)"
                short_name        = Normalize-Null $customRepoRole.name
                type              = Normalize-Null 'repository'
            }
            $null = $nodes.Add((New-GitHoundNode -Id $customRepoRoleId -Kind 'GHRepoRole' -Properties $customRepoRoleProps))
            
            if($null -ne $customRepoRole.base_role)
            {
                $targetBaseRoleId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($repo.node_id)_$($customRepoRole.base_role)"))
                $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasBaseRole' -StartId $customRepoRoleId -EndId $targetBaseRoleId))
            }
            
            foreach($permission in $customRepoRole.permissions)
            {
                switch($permission)
                {
                    'manage_webhooks' {$null = $edges.Add((New-GitHoundEdge -Kind GHManageWebhooks -StartId $customRepoRoleId -EndId $repo.node_id))}
                    'manage_deploy_keys' {$null = $edges.Add((New-GitHoundEdge -Kind GHManageDeployKeys -StartId $customRepoRoleId -EndId $repo.node_id))}
                    'push_protected_branch' {$null = $edges.Add((New-GitHoundEdge -Kind GHPushProtectedBranch -StartId $customRepoRoleId -EndId $repo.node_id))}
                    'delete_alerts_code_scanning' {$null = $edges.Add((New-GitHoundEdge -Kind GHDeleteAlertsCodeScanning -StartId $customRepoRoleId -EndId $repo.node_id))}
                    'view_secret_scanning_alerts' {$null = $edges.Add((New-GitHoundEdge -Kind GHViewSecretScanningAlerts -StartId $customRepoRoleId -EndId $repo.node_id))}
                    'bypass_branch_protection' {$null = $edges.Add((New-GitHoundEdge -Kind GHBypassProtections -StartId $customRepoRoleId -EndId $repo.node_id))}
                    'edit_repo_protections' {$null = $edges.Add((New-GitHoundEdge -Kind GHEditProtections -StartId $customRepoRoleId -EndId $repo.node_id))}
                    'jump_merge_queue' {$null = $edges.Add((New-GitHoundEdge -Kind GHJumpMergeQueue -StartId $customRepoRoleId -EndId $repo.node_id))}
                    'create_solo_merge_queue_entry' {$null = $edges.Add((New-GitHoundEdge -Kind GHCreateSoloMergeQueueEntry -StartId $customRepoRoleId -EndId $repo.node_id))}
                    'edit_repo_custom_properties_values' {$null = $edges.Add((New-GitHoundEdge -Kind GHEditRepoCustomPropertiesValues -StartId $customRepoRoleId -EndId $repo.node_id))}
                }
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
            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasRole' -StartId $collaborator.node_id -EndId $repoRoleId))
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
            $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasRole' -StartId $team.node_id -EndId $repoRoleId))
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
        $properties = @{
            id                       = Normalize-Null $alertId
            name                     = Normalize-Null $alert.number
            repository_name          = Normalize-Null $alert.repository.name
            repository_id            = Normalize-Null $alert.repository.node_id
            repository_url           = Normalize-Null $alert.repository.html_url
            secret_type              = Normalize-Null $alert.secret_type
            secret_type_display_name = Normalize-Null $alert.secret_type_display_name
            validity                 = Normalize-Null $alert.validity
            state                    = Normalize-Null $alert.state
            created_at               = Normalize-Null $alert.created_at
            updated_at               = Normalize-Null $alert.updated_at
            url                      = Normalize-Null $alert.html_url
        }

        $null = $nodes.Add((New-GitHoundNode -Id $alertId -Kind 'GHSecretScanningAlert' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHHasSecretScanningAlert' -StartId $alert.repository.node_id -EndId $alertId))
    }

    $output = [PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    }

    Write-Output $output
}

function Git-HoundAppInstallation
{
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
            id                   = Normalize-Null $app.client_id
            name                 = Normalize-Null $app.app_slug
            repository_selection = Normalize-Null $app.repository_selection
            access_tokens_url    = Normalize-Null $app.access_tokens_url
            repositories_url     = Normalize-Null $app.repositories_url
            description          = Normalize-Null $app.description
            html_url             = Normalize-Null $app.html_url
            created_at           = Normalize-Null $app.created_at
            updated_at           = Normalize-Null $app.updated_at
            organization_name    = Normalize-Null $app.account.login
            organization_id      = Normalize-Null $app.account.node_id
            #permissions          = Normalize-Null ($app.permissions | ConvertTo-Json -Depth 10)
            #events               = Normalize-Null ($app.events | ConvertTo-Json -Depth 10)
        }

        $null = $nodes.Add((New-GitHoundNode -Id $app.client_id -Kind 'GHAppInstallation' -Properties $properties))
        $null = $edges.Add((New-GitHoundEdge -Kind 'GHContains' -StartId $app.account.node_id -EndId $app.client_id))
    }

    Write-Output ([PSCustomObject]@{
        Nodes = $nodes
        Edges = $edges
    })
}

# This is a second order data type after GHOrganization
function Git-HoundGraphQlSamlProvider
{
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
    
    $edges = New-Object System.Collections.ArrayList

    do{
        $result = Invoke-GitHubGraphQL -Headers $Session.Headers -Query $Query -Variables $Variables

        # One issue with this approach is in cases where the IdP has changed and old external identities are still present, the issuer may not match the current IdP
        switch -Wildcard ($result.data.organization.samlIdentityProvider.issuer)
        {
            'https://auth.pingone.com/*' {
                foreach($identity in $result.data.organization.samlIdentityProvider.externalIdentities.nodes)
                {
                    foreach($attribute in $identity.samlIdentity.attributes)
                    {
                        if($attribute.name -eq 'NameID')
                        {
                            $null = $edges.Add((New-GitHoundEdge -Kind SyncedToGHUser -StartId $attribute.value -StartKind PingOneUser -StartMatchBy name -EndId $identity.user.id -EndKind GHUser))
                        }
                    }
                }
            }
            'https://login.microsoftonline.com/*' {
                # This is to catch the Entra SSO cases, I just currently don't have an example of the issuer string
                foreach($identity in $result.data.organization.samlIdentityProvider.externalIdentities.nodes)
                {
                    foreach($attribute in $identity.samlIdentity.attributes)
                    {
                        if($attribute.name -eq 'http://schemas.microsoft.com/identity/claims/objectidentifier')
                        {
                            $null = $edges.Add((New-GitHoundEdge -Kind SyncedToGHUser -StartId $attribute.value -StartKind AZUser -EndId $identity.user.id -EndKind GHUser))
                        }
                    }
                }
            }
            default { Write-Verbose "Issuer: $($_)" }
        }

        $Variables['after'] = $result.data.organization.samlIdentityProvider.externalIdentities.pageInfo.endCursor
    }
    while($result.data.organization.samlIdentityProvider.externalIdentities.pageInfo.hasNextPage)

    Write-Output $edges
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

    Write-Host "[*] Starting Git-Hound for $($Session.OrganizationName)"
    $org = Git-HoundOrganization -Session $Session
    $nodes.Add($org) | Out-Null

    Write-Host "[*] Enumerating Organization Users"
    $users = $org | Git-HoundUser -Session $Session
    if($users) { $nodes.AddRange(@($users)) }

    Write-Host "[*] Enumerating Organization Teams"
    $teams = $org | Git-HoundTeam -Session $Session
    if($teams.nodes) { $nodes.AddRange(@($teams.nodes)) }
    if($teams.edges) { $edges.AddRange(@($teams.edges)) }

    Write-Host "[*] Enumerating Organization Repositories"
    $repos = $org | Git-HoundRepository -Session $Session
    if($repos.nodes) { $nodes.AddRange(@($repos.nodes)) }
    if($repos.edges) { $edges.AddRange(@($repos.edges)) }

    Write-Host "[*] Enumerating Organization Branches"
    $branches = $repos | Git-HoundBranch -Session $Session
    if($branches.nodes) { $nodes.AddRange(@($branches.nodes)) }
    if($branches.edges) { $edges.AddRange(@($branches.edges)) }

    Write-Host "[*] Enumerating Team Roles"
    $teamroles = $org | Git-HoundTeamRole -Session $Session
    if($teamroles.nodes) { $nodes.AddRange(@($teamroles.nodes)) }
    if($teamroles.edges) { $edges.AddRange(@($teamroles.edges)) }

    Write-Host "[*] Enumerating Organization Roles"
    $orgroles = $org | Git-HoundOrganizationRole -Session $Session
    if($orgroles.nodes) { $nodes.AddRange(@($orgroles.nodes)) }
    if($orgroles.edges) { $edges.AddRange(@($orgroles.edges)) }

    Write-Host "[*] Enumerating Repository Roles"
    $reporoles = $org | Git-HoundRepositoryRole -Session $Session
    if($reporoles.nodes) { $nodes.AddRange(@($reporoles.nodes)) }
    if($reporoles.edges) { $edges.AddRange(@($reporoles.edges)) }
    
    Write-Host "[*] Enumerating Secret Scanning Alerts"
    $secretalerts = $org | Git-HoundSecretScanningAlert -Session $Session
    if($secretalerts.nodes) { $nodes.AddRange(@($secretalerts.nodes)) }
    if($secretalerts.edges) { $edges.AddRange(@($secretalerts.edges)) }

    #Write-Host "[*] Enumerating App Installations"
    #$appInstallations = $org | Git-HoundAppInstallation -Session $Session
    #if($appInstallations.nodes) { $nodes.AddRange(@($appInstallations.nodes)) }
    #if($appInstallations.edges) { $edges.AddRange(@($appInstallations.edges)) }

    Write-Host "[*] Converting to OpenGraph JSON Payload"
    $payload = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            source_kind = "GHBase"
        }
        graph = [PSCustomObject]@{
            nodes = $nodes.ToArray()
            edges = $edges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_$($org.id).json"

    Write-Host "[*] Enumerating SAML Identity Provider"
    $samlEdges = New-Object System.Collections.ArrayList
    $saml = Git-HoundGraphQlSamlProvider -Session $Session
    if($saml) { $samlEdges.AddRange(@($saml)) }

    $payload = [PSCustomObject]@{
        graph = [PSCustomObject]@{
            nodes = @()
            edges = $samlEdges.ToArray()
        }
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath "./githound_saml_$($org.id).json"

    #$payload | BHDataUploadJSON
}
