# Troubleshooting

This guide covers common issues encountered when running GitHound and how to resolve them.

## Rate Limiting

### Symptoms

- Collection pauses with messages about waiting for rate limit renewal
- `403 Forbidden` errors with `X-RateLimit-Remaining: 0` header
- Very slow collection times

### Solutions

**For small to medium environments (< 500 repos):**

The built-in rate limit handling will automatically pause and resume. Allow the collection to complete.

**For large environments (500+ repos):**

1. Use the [App Installation method](./APP-COLLECTION.md) for 3x higher rate limits (15,000/hour vs 5,000/hour)
2. Use the step-by-step manual collection process in [COLLECTION.md](./COLLECTION.md#alternative-collection-for-large-environments)
3. Run collection during off-peak hours when rate limits refresh

### Checking Current Rate Limit Status

```powershell
# Check rate limit status
Invoke-GitHubRestMethod -Session $session -Uri "https://api.github.com/rate_limit" | ConvertTo-Json
```

## Authentication Errors

### "Bad credentials" or 401 Unauthorized

**Causes:**

- Personal Access Token has expired
- Token was revoked or regenerated
- Token doesn't have the required permissions

**Solutions:**

1. Generate a new Fine-grained Personal Access Token following the [COLLECTION guide](./COLLECTION.md)
2. Verify the token has all required repository and organization permissions
3. Ensure the token is scoped to "All repositories"

### "Resource not accessible by integration"

**Causes:**

- The authenticated user doesn't have access to the requested resource
- The PAT permissions are insufficient
- SSO authorization is required but not completed

**Solutions:**

1. Verify you're using an organization administrator account
2. Check that the PAT has all required permissions
3. For organizations with SAML SSO: Authorize the PAT for SSO access in GitHub settings

### "Must have admin rights to Repository"

**Causes:**

- Attempting to collect admin-only data without admin permissions
- Some repository functions require elevated access

**Solutions:**

1. Use a PAT created by an organization owner
2. Ensure the PAT has "Administration" read permission on repositories

## Collection Errors

### Null Values in Output

**Symptoms:**

- JSON output contains null entries in nodes or edges arrays
- Warnings about filtering null values during collection

**Causes:**

This was a known issue in environments with many repositories (40k+) due to thread-safety in parallel collection. It has been fixed in recent versions.

**Solutions:**

1. Update to the latest version of GitHound
2. If still occurring, the collector automatically filters null values and logs a warning

### "Cannot index into a null array"

**Causes:**

- A collection function returned no data
- Network interruption during collection
- Permission issues preventing data retrieval

**Solutions:**

1. Run the specific collection function individually to identify the issue:

   ```powershell
   $org = Git-HoundOrganization -Session $session
   $org  # Check if data was returned
   ```

2. Verify network connectivity to GitHub API
3. Check for any error messages in the console output

### Empty or Partial Collection

**Symptoms:**

- Some node types are missing from the output
- Fewer nodes than expected

**Causes:**

- PAT missing specific permissions
- Some collection functions failed silently
- Rate limiting caused early termination

**Solutions:**

1. Use the step-by-step collection process to identify which function is failing
2. Verify all required PAT permissions are configured
3. Check that GitHub Actions is enabled for workflow/environment collection

## Crash Recovery

### PowerShell Crashed or Terminal Closed Mid-Collection

**Symptoms:**

- PowerShell window closed unexpectedly during collection
- System crashed or lost power during a long-running collection
- Terminal session timed out

**Solutions:**

`Invoke-GitHound` writes a per-step output file after each collection function completes. To resume from where you left off:

```powershell
Invoke-GitHound -Session $session -Resume
```

The `-Resume` flag detects existing per-step files on disk and skips those steps. Collection resumes from the first incomplete step.

**What gets preserved:**

- Any step that fully completed has its output file on disk (e.g. `githound_Organization_*.json`, `githound_User_*.json`, etc.)
- Functions with internal checkpointing (RepositoryRole, Workflow, Secret) also save intermediate chunk files, so they can resume mid-function rather than starting over
- Git-HoundBranch saves per-page checkpoint files during execution; however, if interrupted mid-function it will re-run from scratch on resume (the 3-phase design requires in-memory state that isn't serialized to checkpoints)

**To start completely fresh** (ignoring any existing files):

```powershell
Invoke-GitHound -Session $session
```

Without the `-Resume` flag, all steps are re-collected and existing files are overwritten.

### Corrupt or Truncated Output Files

**Symptoms:**

- `ConvertFrom-Json` errors when loading a collection file
- Resume skips a step but the data appears incomplete

**Solutions:**

1. Delete the corrupt per-step file and re-run with `-Resume`:

   ```powershell
   Remove-Item ./githound_Repository_*.json
   Invoke-GitHound -Session $session -Resume
   ```

2. GitHound automatically detects corrupt checkpoint files and re-collects the affected step

## Large Environment Issues

### Collection Takes Too Long

For organizations with thousands of repositories, a full collection can take several hours.

**Recommendations:**

1. Use the [App Installation method](./APP-COLLECTION.md) for higher rate limits
2. Run collection during off-peak hours
3. Use `-Resume` to pick up where you left off if collection is interrupted
4. Use the [manual step-by-step collection](./COLLECTION.md#alternative-collection-for-large-environments) for maximum control

### Memory Issues

**Symptoms:**

- PowerShell becomes unresponsive
- Out of memory errors

**Solutions:**

1. Use a 64-bit PowerShell session
2. Close unnecessary applications to free memory
3. Use the step-by-step collection to process in smaller batches

## GitHub Actions / Workflows Not Collected

**Symptoms:**

- No GHWorkflow nodes in output
- No GHEnvironment nodes

**Causes:**

- GitHub Actions is disabled for the organization or repositories
- PAT missing "Actions" read permission

**Solutions:**

1. Verify GitHub Actions is enabled in organization settings
2. Check that the PAT has "Actions" read permission on repositories
3. Note: Repositories with Actions disabled are intentionally skipped

## SAML/SSO Identity Collection Issues

### No GHExternalIdentity Nodes

**Causes:**

- SAML SSO is not configured for the organization
- PAT user doesn't have access to SAML identity data
- GraphQL endpoint permissions

**Solutions:**

1. Verify SAML SSO is configured in organization settings
2. Ensure the PAT user is an organization owner
3. Check that the organization has a GitHub Enterprise license (required for SAML)

## BloodHound Import Issues

### "Invalid JSON" Error

**Causes:**

- JSON file is corrupted or truncated
- Collection was interrupted before completion

**Solutions:**

1. Validate the JSON file:

   ```powershell
   Get-Content ./githound_*.json | ConvertFrom-Json
   ```

2. If validation fails, re-run the collection
3. Use the step-by-step collection to save progress

### Nodes/Edges Not Appearing in Graph

**Causes:**

- BloodHound version doesn't support the node/edge types
- Import process failed silently

**Solutions:**

1. Ensure you're using a BloodHound version that supports OpenGraph/Custom schemas
2. Check BloodHound logs for import errors
3. Verify the JSON structure matches the expected format

## Getting Help

If you encounter issues not covered in this guide:

1. Check the [GitHub Issues](https://github.com/SpecterOps/GitHound/issues) for similar problems
2. Open a new issue with:
   - PowerShell version (`$PSVersionTable`)
   - GitHound version or commit hash
   - Full error message and stack trace
   - Approximate environment size (number of repos, users, teams)
   - Steps to reproduce the issue
