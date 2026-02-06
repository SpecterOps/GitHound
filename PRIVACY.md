# GitHound Privacy Policy

**Last updated:** February 2025

## Overview

GitHound is an open-source, read-only data collector that maps GitHub organization structure and permissions into BloodHound-compatible graph data. This privacy policy describes how GitHound handles data when installed as a GitHub App or used with a Personal Access Token (PAT).

## Data Collection

GitHound collects the following data from your GitHub organization via the GitHub API:

- Organization metadata (name, settings, custom roles)
- User accounts and team memberships
- Repository metadata, roles, and branch protection rules
- GitHub Actions workflows, environments, and secrets metadata (names only, not secret values)
- Secret scanning alert metadata
- SAML/SSO identity provider configuration and external identity mappings
- GitHub App installation metadata

**GitHound does not collect:**

- Source code content (except GitHub Actions workflow YAML files for trigger/permission analysis)
- Secret values or credentials
- Issue or pull request content
- Commit history or diffs
- Personal user data beyond what GitHub exposes through its API (username, display name, email if public)

## Data Storage

- All collected data is stored **locally** on the machine running GitHound, in JSON files written to the working directory
- GitHound does **not** transmit collected data to any external service, server, or third party
- Data remains entirely under the control of the person or organization running the collector

## Data Processing

- GitHound processes GitHub API responses in memory during collection and writes the results to local JSON files
- Intermediate checkpoint files may be created during collection for crash recovery and are stored in the same local directory
- No data is cached, indexed, or stored beyond the output JSON files

## Third-Party Services

GitHound communicates exclusively with the **GitHub API** (`api.github.com`) using credentials you provide (PAT or App Installation token). It does not communicate with any other external service.

## Data Retention

GitHound does not manage data retention. Output files persist on your local filesystem until you delete them. You are responsible for securing and managing the collected data files according to your organization's data handling policies.

## Security

- GitHound requests only **read-only** permissions and never modifies your GitHub organization, repositories, or settings
- Authentication credentials (PATs or App tokens) are held in memory during collection and are not written to disk
- We recommend storing PATs in a password manager and rotating them after collection

## Changes to This Policy

Changes to this privacy policy will be reflected in this file within the GitHound repository. The "Last updated" date at the top of this document will be revised accordingly.

## Contact

For questions about this privacy policy or GitHound's data handling practices, please open an issue in the [GitHound repository](https://github.com/SpecterOps/GitHound/issues).
