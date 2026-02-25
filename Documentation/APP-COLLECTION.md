# Collection via App Installation

While it creates a few extra steps, it may be advantageous to perform collection via a GitHub App Installation due to GitHub's increased rate limit threshold. App Installations receive **15,000 API requests per hour** compared to the **5,000 requests per hour** limit for Personal Access Tokens (PATs). This 3x increase makes App-based collection significantly faster for large organizations.

## Rate Limit Comparison

| Authentication Method   | Rate Limit  | Best For                                    |
|-------------------------|-------------|---------------------------------------------|
| Personal Access Token   | 5,000/hour  | Small to medium organizations (< 500 repos) |
| GitHub App Installation | 15,000/hour | Large organizations (500+ repos)            |

## Install the App

### Option 1: Install the SpecterOps GitHound App (Recommended)

The SpecterOps GitHound App is pre-configured with the minimum permissions required for collection.

1. Navigate to the GitHub App installation page (contact your SpecterOps representative for the link)
2. Select the GitHub Organization where you want to install the app
3. Review the requested permissions and click **Install**
4. On the confirmation page, select **All repositories** or choose specific repositories
5. Click **Install** to complete the installation

### Option 2: Create Your Own GitHub App

If you prefer to host your own GitHub App:

1. Navigate to your Organization Settings → Developer settings → GitHub Apps
2. Click **New GitHub App**
3. Configure the app with the following settings:
   - **GitHub App name**: Choose a unique name (e.g., `YourOrg-GitHound`)
   - **Homepage URL**: Your organization's URL
   - **Webhook**: Uncheck "Active" (webhooks are not needed for collection)

4. Set the required permissions:

   | Permission Category | Permission                     | Access Level |
   |---------------------|--------------------------------|--------------|
   | Repository          | Actions                        | Read-only    |
   | Repository          | Administration                 | Read-only    |
   | Repository          | Contents                       | Read-only    |
   | Repository          | Environments                   | Read-only    |
   | Repository          | Metadata                       | Read-only    |
   | Repository          | Secret scanning alerts         | Read-only    |
   | Repository          | Secrets                        | Read-only    |
   | Organization        | Administration                 | Read-only    |
   | Organization        | Custom organization roles      | Read-only    |
   | Organization        | Custom repository roles        | Read-only    |
   | Organization        | Members                        | Read-only    |
   | Organization        | Personal access tokens         | Read-only    |
   | Organization        | Personal access token requests | Read-only    |
   | Organization        | Secrets                        | Read-only    |

5. Under "Where can this GitHub App be installed?", select **Only on this account**
6. Click **Create GitHub App**
7. After creation, scroll down and click **Generate a private key**
8. Save the downloaded `.pem` file securely
9. Note the **App ID** and **Client ID** displayed on the app settings page
10. Install the app to your organization by clicking **Install App** in the left sidebar

## Get the App Installation Details

Go to settings, and make sure that you are in the context of your target GitHub Organization.

Find GitHub Apps in the menu under Third-party Access.

Locate the `GitHound - SpecterOps` App and select Configure.

This will take you to the following page. Notice the numeric value in the URL (`107643946` in the screenshot below). This is the Application Id that you will need in a subsequent step.

![App Installation Page](./images/app-installation-page.png)

Next, click on the `App settings` menu to get detailed information about the App as shown below:

![App Installation Details](./images/app-installation-details.png)

Keep track of the App Installation's `Client ID` value (`Iv23liPgjiu18oXLM2q7` in the screenshot above).

## Generate an installation access token

The step by step instructions for generating an installation access token can be found in [GitHub's documentation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app#generating-an-installation-access-token). The goal of this section is to demonstrate how this can be done in conjunction with the GitHound collector.

Use the `New-GitHubJwtSession` function to generate a JWT for the App Installation. This function requires both the Client ID, from the previous step, and the private key that you generated when you installed the App.

```powershell
$jwt = New-GitHubJwtSession -OrganizationName SpecterTst -ClientId Iv23liPgjiu18oXLM2q7 -PrivateKeyPath ~/Downloads/githound-specterops.2026-02-02.private-key.pem -AppId 107643946
```

You now have a GitHub Session that is ready to use with the rest of the application.

## Run the Collection

Once you have a valid JWT session, you can run the collection just like you would with a PAT-based session:

```powershell
# Run the full collection
Invoke-GitHound -Session $jwt
```

The output will be saved as `githound_<org_id>.json` in your current directory.

## Troubleshooting

### "Resource not accessible by integration"

This error indicates the GitHub App doesn't have the required permissions. Verify that:

- The app has all required permissions listed in the installation section
- The app is installed on the organization you're trying to collect from
- The app has access to all repositories (or the specific repositories you need)

### JWT Token Expired

GitHub App JWTs expire after 10 minutes. If you receive authentication errors during a long collection:

```powershell
# Regenerate the JWT session
$jwt = New-GitHubJwtSession -OrganizationName YourOrg -ClientId $clientId -PrivateKeyPath $keyPath -AppId $appId

# Resume collection with the new session
Invoke-GitHound -Session $jwt
```

### Private Key Issues

If you receive errors about the private key:

- Ensure the `.pem` file path is correct and accessible
- Verify the file contains the complete private key (begins with `-----BEGIN RSA PRIVATE KEY-----`)
- Check that the private key matches the GitHub App (regenerate if necessary)

## Security Considerations

- **Protect the private key**: Store the `.pem` file securely and never commit it to version control
- **Rotate keys periodically**: Generate new private keys and revoke old ones as part of your security practices
- **Limit app installation scope**: Only install the app on organizations that require collection
- **Review app permissions**: Periodically verify the app only has the minimum required permissions
