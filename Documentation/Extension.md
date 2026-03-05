---
name: "GitHound"
version: "1.0.0"
namespace: "GH"
environment_kind: "GH_Organization"
source_kind: "GH_Base"
principal_kinds:
  - "GH_User"
  - "GH_Team"
---

# GitHound

GitHound is a BloodHound OpenGraph extension that collects GitHub organization data and maps it into an attack graph. It enumerates organizations, users, teams, repositories, roles, branches, branch protection rules, workflows, environments, secrets, variables, apps, personal access tokens, SAML/SCIM identity providers, and secret scanning alerts. The collector also computes effective branch push access by analyzing the interaction of role permissions, branch protection rules, and per-actor allowances.

GitHound supports hybrid edges connecting GitHub entities to Azure (Entra ID), AWS, Okta, and PingOne identity systems.
