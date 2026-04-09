BeforeAll {
    . "$PSScriptRoot/../githound.ps1"
}

Describe 'Test-GitHubSessionTokenNeedsRefresh' {
    It 'Returns $false for PAT sessions (no JwtClientId)' {
        $session = New-GithubSession -OrganizationName 'TestOrg' -Token 'ghp_faketoken'
        Test-GitHubSessionTokenNeedsRefresh -Session $session | Should -Be $false
    }

    It 'Returns $false when token has more than 10 minutes remaining' {
        $session = New-GithubSession -OrganizationName 'TestOrg' -Token 'ghs_faketoken'
        $session | Add-Member -NotePropertyName 'JwtClientId' -NotePropertyValue 'Iv1.abc123'
        $session | Add-Member -NotePropertyName 'JwtPrivateKeyPath' -NotePropertyValue '/tmp/fake.pem'
        $session | Add-Member -NotePropertyName 'JwtAppId' -NotePropertyValue '12345'
        $session | Add-Member -NotePropertyName 'TokenExpiresAt' -NotePropertyValue ([System.DateTimeOffset]::UtcNow.AddMinutes(30))

        Test-GitHubSessionTokenNeedsRefresh -Session $session | Should -Be $false
    }

    It 'Returns $true when token expires within 10 minutes' {
        $session = New-GithubSession -OrganizationName 'TestOrg' -Token 'ghs_faketoken'
        $session | Add-Member -NotePropertyName 'JwtClientId' -NotePropertyValue 'Iv1.abc123'
        $session | Add-Member -NotePropertyName 'JwtPrivateKeyPath' -NotePropertyValue '/tmp/fake.pem'
        $session | Add-Member -NotePropertyName 'JwtAppId' -NotePropertyValue '12345'
        $session | Add-Member -NotePropertyName 'TokenExpiresAt' -NotePropertyValue ([System.DateTimeOffset]::UtcNow.AddMinutes(5))

        Test-GitHubSessionTokenNeedsRefresh -Session $session | Should -Be $true
    }

    It 'Returns $true when token is already expired' {
        $session = New-GithubSession -OrganizationName 'TestOrg' -Token 'ghs_faketoken'
        $session | Add-Member -NotePropertyName 'JwtClientId' -NotePropertyValue 'Iv1.abc123'
        $session | Add-Member -NotePropertyName 'JwtPrivateKeyPath' -NotePropertyValue '/tmp/fake.pem'
        $session | Add-Member -NotePropertyName 'JwtAppId' -NotePropertyValue '12345'
        $session | Add-Member -NotePropertyName 'TokenExpiresAt' -NotePropertyValue ([System.DateTimeOffset]::UtcNow.AddMinutes(-5))

        Test-GitHubSessionTokenNeedsRefresh -Session $session | Should -Be $true
    }
}

Describe 'Update-GitHubSessionToken' {
    It 'Throws when called on a PAT session' {
        $session = New-GithubSession -OrganizationName 'TestOrg' -Token 'ghp_faketoken'
        { Update-GitHubSessionToken -Session $session } | Should -Throw '*not created with GitHub App JWT credentials*'
    }
}

Describe 'New-GitHubJwtSession session properties' {
    It 'Stores JWT credentials on the session object when mocked' {
        # Mock the REST call that exchanges JWT for installation token
        Mock Invoke-GithubRestMethod {
            return [PSCustomObject]@{
                token      = 'ghs_mockinstallationtoken'
                expires_at = ([System.DateTimeOffset]::UtcNow.AddHours(1)).ToString('o')
            }
        }

        # Mock Get-Content to return a valid PEM (we won't actually sign since REST is mocked)
        # We need to mock the RSA signing path, so instead mock the whole JWT exchange
        # Since New-GitHubJwtSession does RSA signing before the REST call, we need a real key
        # Generate a throwaway RSA key for testing
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $pem = $rsa.ExportRSAPrivateKeyPem()
        $tempPem = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tempPem -Value $pem -NoNewline

        try {
            $session = New-GitHubJwtSession -OrganizationName 'TestOrg' -ClientId 'Iv1.testclient' -PrivateKeyPath $tempPem -AppId '99999'

            $session.JwtClientId | Should -Be 'Iv1.testclient'
            $session.JwtPrivateKeyPath | Should -Be $tempPem
            $session.JwtAppId | Should -Be '99999'
            $session.TokenExpiresAt | Should -Not -BeNullOrEmpty
            $session.Headers['Authorization'] | Should -Be 'Bearer ghs_mockinstallationtoken'
        }
        finally {
            Remove-Item $tempPem -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Invoke-GithubRestMethod 401 handling' {
    It 'Does not attempt token refresh on 401 for PAT sessions' {
        Mock Invoke-WebRequest {
            $errorDetails = @{ status = "401"; message = "Bad credentials" } | ConvertTo-Json
            $exception = [System.Net.Http.HttpRequestException]::new("401 Unauthorized")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'HttpError', 'ConnectionError', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([System.Management.Automation.ErrorDetails]::new($errorDetails)) -Force
            throw $errorRecord
        }

        Mock Update-GitHubSessionToken { }

        $session = New-GithubSession -OrganizationName 'TestOrg' -Token 'ghp_faketoken'

        # Should error (401 with no JWT credentials = unrecoverable)
        Invoke-GithubRestMethod -Session $session -Path 'test' -ErrorVariable restErrors 2>$null

        Should -Invoke Update-GitHubSessionToken -Times 0
    }
}
