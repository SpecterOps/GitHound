BeforeAll {
    . "$PSScriptRoot/../githound.ps1"

    # Test-RefNameMatch is defined inside Git-HoundBranch (nested scope), so replicate for testing.
    function Test-RefNameMatch {
        param(
            [string]$BranchName,
            [string[]]$Include,
            [string[]]$Exclude,
            [string]$DefaultBranch
        )

        $matched = $false
        foreach ($pattern in $Include) {
            if ($pattern -eq '~ALL') {
                $matched = $true
                break
            }
            if ($pattern -eq '~DEFAULT_BRANCH') {
                if ($BranchName -eq $DefaultBranch) {
                    $matched = $true
                    break
                }
                continue
            }
            $branchPattern = $pattern -replace '^refs/heads/', ''
            if ($BranchName -like $branchPattern) {
                $matched = $true
                break
            }
        }

        if (-not $matched) { return $false }

        foreach ($pattern in $Exclude) {
            if ($pattern -eq '~ALL') { return $false }
            if ($pattern -eq '~DEFAULT_BRANCH') {
                if ($BranchName -eq $DefaultBranch) { return $false }
                continue
            }
            $branchPattern = $pattern -replace '^refs/heads/', ''
            if ($BranchName -like $branchPattern) { return $false }
        }

        return $true
    }

    # Helpers for building minimal graph objects
    function Make-Node {
        param([string]$Id, [string]$Kind, [hashtable]$Props)
        return [pscustomobject]@{
            id         = $Id
            kinds      = @($Kind)
            properties = [pscustomobject]$Props
        }
    }

    function Make-Edge {
        param([string]$Kind, [string]$StartId, [string]$EndId)
        return [pscustomobject]@{
            kind  = $Kind
            start = [pscustomobject]@{ value = $StartId }
            end   = [pscustomobject]@{ value = $EndId }
            properties = [pscustomobject]@{ traversable = $false }
        }
    }
}

Describe 'Test-RefNameMatch' {
    Context '~ALL pattern' {
        It 'Matches any branch when include contains ~ALL' {
            Test-RefNameMatch -BranchName 'main' -Include @('~ALL') -Exclude @() -DefaultBranch 'main' | Should -Be $true
            Test-RefNameMatch -BranchName 'feature/foo' -Include @('~ALL') -Exclude @() -DefaultBranch 'main' | Should -Be $true
        }

        It 'Excludes branch when exclude contains ~ALL' {
            Test-RefNameMatch -BranchName 'main' -Include @('~ALL') -Exclude @('~ALL') -DefaultBranch 'main' | Should -Be $false
        }
    }

    Context '~DEFAULT_BRANCH pattern' {
        It 'Matches the default branch' {
            Test-RefNameMatch -BranchName 'main' -Include @('~DEFAULT_BRANCH') -Exclude @() -DefaultBranch 'main' | Should -Be $true
        }

        It 'Does not match non-default branches' {
            Test-RefNameMatch -BranchName 'develop' -Include @('~DEFAULT_BRANCH') -Exclude @() -DefaultBranch 'main' | Should -Be $false
        }

        It 'Excludes the default branch when in exclude list' {
            Test-RefNameMatch -BranchName 'main' -Include @('~ALL') -Exclude @('~DEFAULT_BRANCH') -DefaultBranch 'main' | Should -Be $false
        }
    }

    Context 'refs/heads/ prefix patterns' {
        It 'Strips refs/heads/ prefix and matches exact branch' {
            Test-RefNameMatch -BranchName 'main' -Include @('refs/heads/main') -Exclude @() -DefaultBranch 'main' | Should -Be $true
        }

        It 'Does not match different branch' {
            Test-RefNameMatch -BranchName 'develop' -Include @('refs/heads/main') -Exclude @() -DefaultBranch 'main' | Should -Be $false
        }

        It 'Matches wildcard patterns' {
            Test-RefNameMatch -BranchName 'release/1.0' -Include @('refs/heads/release/*') -Exclude @() -DefaultBranch 'main' | Should -Be $true
            Test-RefNameMatch -BranchName 'feature/foo' -Include @('refs/heads/release/*') -Exclude @() -DefaultBranch 'main' | Should -Be $false
        }

        It 'Matches refs/heads/* as wildcard for all branches' {
            Test-RefNameMatch -BranchName 'anything' -Include @('refs/heads/*') -Exclude @() -DefaultBranch 'main' | Should -Be $true
        }
    }

    Context 'Include and exclude combinations' {
        It 'Include all but exclude release branches' {
            Test-RefNameMatch -BranchName 'main' -Include @('~ALL') -Exclude @('refs/heads/release/*') -DefaultBranch 'main' | Should -Be $true
            Test-RefNameMatch -BranchName 'release/2.0' -Include @('~ALL') -Exclude @('refs/heads/release/*') -DefaultBranch 'main' | Should -Be $false
        }

        It 'Multiple include patterns' {
            Test-RefNameMatch -BranchName 'main' -Include @('refs/heads/main', 'refs/heads/develop') -Exclude @() -DefaultBranch 'main' | Should -Be $true
            Test-RefNameMatch -BranchName 'develop' -Include @('refs/heads/main', 'refs/heads/develop') -Exclude @() -DefaultBranch 'main' | Should -Be $true
            Test-RefNameMatch -BranchName 'feature/x' -Include @('refs/heads/main', 'refs/heads/develop') -Exclude @() -DefaultBranch 'main' | Should -Be $false
        }
    }

    Context 'Empty patterns' {
        It 'Returns false with empty include' {
            Test-RefNameMatch -BranchName 'main' -Include @() -Exclude @() -DefaultBranch 'main' | Should -Be $false
        }
    }
}

Describe 'Compute-GitHoundBranchAccess multi-rule evaluation' {
    Context 'Single BPR (backwards compatible)' {
        It 'Emits GH_CanWriteBranch for unprotected branches' {
            $nodes = New-Object System.Collections.ArrayList
            $edges = New-Object System.Collections.ArrayList

            $null = $nodes.Add((Make-Node -Id 'org1' -Kind 'GH_Organization' -Props @{ login = 'testorg'; node_id = 'org1' }))
            $null = $nodes.Add((Make-Node -Id 'repo1' -Kind 'GH_Repository' -Props @{ name = 'testrepo'; node_id = 'repo1' }))
            $null = $nodes.Add((Make-Node -Id 'branch1' -Kind 'GH_Branch' -Props @{ name = 'testrepo\main'; short_name = 'main'; repository_id = 'repo1'; node_id = 'branch1' }))
            $null = $nodes.Add((Make-Node -Id 'role1' -Kind 'GH_RepoRole' -Props @{ short_name = 'write'; repository_id = 'repo1' }))

            $null = $edges.Add((Make-Edge -Kind 'GH_Owns' -StartId 'org1' -EndId 'repo1'))
            $null = $edges.Add((Make-Edge -Kind 'GH_HasBranch' -StartId 'repo1' -EndId 'branch1'))
            $null = $edges.Add((Make-Edge -Kind 'GH_WriteRepoContents' -StartId 'role1' -EndId 'repo1'))

            $result = Compute-GitHoundBranchAccess -Nodes $nodes -Edges $edges

            $canWrite = $result.Edges | Where-Object { $_.kind -eq 'GH_CanWriteBranch' -and $_.start.value -eq 'role1' -and $_.end.value -eq 'branch1' }
            $canWrite | Should -Not -BeNullOrEmpty
            $canWrite.properties.reason | Should -Be 'no_protection'
        }
    }

    Context 'Multiple protection rules per branch' {
        It 'Blocks access when one rule blocks and actor cannot bypass it' {
            $nodes = New-Object System.Collections.ArrayList
            $edges = New-Object System.Collections.ArrayList

            $null = $nodes.Add((Make-Node -Id 'repo1' -Kind 'GH_Repository' -Props @{ name = 'testrepo'; node_id = 'repo1' }))
            $null = $nodes.Add((Make-Node -Id 'branch1' -Kind 'GH_Branch' -Props @{ name = 'testrepo\main'; short_name = 'main'; repository_id = 'repo1'; node_id = 'branch1' }))
            $null = $nodes.Add((Make-Node -Id 'role1' -Kind 'GH_RepoRole' -Props @{ short_name = 'write'; repository_id = 'repo1' }))

            # BPR: no blocking
            $null = $nodes.Add((Make-Node -Id 'bpr1' -Kind 'GH_BranchProtectionRule' -Props @{
                pattern = 'main'; enforce_admins = $true; lock_branch = $false;
                required_pull_request_reviews = $false; push_restrictions = $false;
                blocks_creations = $false; source_type = 'branch_protection_rule'
            }))

            # Ruleset: blocks via PR reviews, enforce_admins = true
            $null = $nodes.Add((Make-Node -Id 'rs1_repo1' -Kind 'GH_BranchProtectionRule' -Props @{
                pattern = 'main'; enforce_admins = $true; lock_branch = $false;
                required_pull_request_reviews = $true; push_restrictions = $false;
                blocks_creations = $false; source_type = 'ruleset'; enforcement = 'active'
            }))

            $null = $edges.Add((Make-Edge -Kind 'GH_HasBranch' -StartId 'repo1' -EndId 'branch1'))
            $null = $edges.Add((Make-Edge -Kind 'GH_WriteRepoContents' -StartId 'role1' -EndId 'repo1'))
            $null = $edges.Add((Make-Edge -Kind 'GH_ProtectedBy' -StartId 'bpr1' -EndId 'branch1'))
            $null = $edges.Add((Make-Edge -Kind 'GH_ProtectedBy' -StartId 'rs1_repo1' -EndId 'branch1'))

            $result = Compute-GitHoundBranchAccess -Nodes $nodes -Edges $edges

            $canWrite = $result.Edges | Where-Object { $_.kind -eq 'GH_CanWriteBranch' -and $_.start.value -eq 'role1' -and $_.end.value -eq 'branch1' }
            $canWrite | Should -BeNullOrEmpty
        }
    }

    Context 'Evaluate-mode rulesets skipped in gate evaluation' {
        It 'Allows access when blocking ruleset is in evaluate mode' {
            $nodes = New-Object System.Collections.ArrayList
            $edges = New-Object System.Collections.ArrayList

            $null = $nodes.Add((Make-Node -Id 'repo1' -Kind 'GH_Repository' -Props @{ name = 'testrepo'; node_id = 'repo1' }))
            $null = $nodes.Add((Make-Node -Id 'branch1' -Kind 'GH_Branch' -Props @{ name = 'testrepo\main'; short_name = 'main'; repository_id = 'repo1'; node_id = 'branch1' }))
            $null = $nodes.Add((Make-Node -Id 'role1' -Kind 'GH_RepoRole' -Props @{ short_name = 'write'; repository_id = 'repo1' }))

            # Ruleset: would block via PR reviews but is in evaluate mode
            $null = $nodes.Add((Make-Node -Id 'rs1_repo1' -Kind 'GH_BranchProtectionRule' -Props @{
                pattern = 'main'; enforce_admins = $true; lock_branch = $false;
                required_pull_request_reviews = $true; push_restrictions = $false;
                blocks_creations = $false; source_type = 'ruleset'; enforcement = 'evaluate'
            }))

            $null = $edges.Add((Make-Edge -Kind 'GH_HasBranch' -StartId 'repo1' -EndId 'branch1'))
            $null = $edges.Add((Make-Edge -Kind 'GH_WriteRepoContents' -StartId 'role1' -EndId 'repo1'))
            $null = $edges.Add((Make-Edge -Kind 'GH_ProtectedBy' -StartId 'rs1_repo1' -EndId 'branch1'))

            $result = Compute-GitHoundBranchAccess -Nodes $nodes -Edges $edges

            $canWrite = $result.Edges | Where-Object { $_.kind -eq 'GH_CanWriteBranch' -and $_.start.value -eq 'role1' -and $_.end.value -eq 'branch1' }
            $canWrite | Should -Not -BeNullOrEmpty
        }
    }
}
