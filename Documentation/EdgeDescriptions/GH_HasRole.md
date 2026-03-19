# GH_HasRole

## Edge Schema

- Source: [GH_User](../NodeDescriptions/GH_User.md), [GH_Team](../NodeDescriptions/GH_Team.md), [GH_EnterpriseTeam](../NodeDescriptions/GH_EnterpriseTeam.md)
- Destination: [GH_OrgRole](../NodeDescriptions/GH_OrgRole.md), [GH_RepoRole](../NodeDescriptions/GH_RepoRole.md), [GH_TeamRole](../NodeDescriptions/GH_TeamRole.md), [GH_EnterpriseRole](../NodeDescriptions/GH_EnterpriseRole.md)

## General Information

The traversable [GH_HasRole](GH_HasRole.md) edge represents the assignment of a user, team, or enterprise team to a specific role within the organization, repository, team, or enterprise. This is the primary edge for connecting identities to their permissions and serves as the foundation of all access paths in the GitHub permission model. It is created by `Git-HoundUser` (for org roles), `Git-HoundRepositoryRole` (for repo roles), `Git-HoundTeam` (for team roles), and `Git-HoundEnterpriseTeam` (for enterprise-level role assignments). Because role assignment is the starting point for determining what a principal can do, this edge is traversable and critical for attack path analysis.

```mermaid
graph LR
    user1("GH_User alice")
    user2("GH_User bob")
    team1("GH_Team security-team")
    entTeam("GH_EnterpriseTeam Corp-Security")
    orgRole("GH_OrgRole SpecterOps\\Owners")
    repoRole("GH_RepoRole GitHound\\write")
    teamRole("GH_TeamRole security-team\\maintainer")
    entRole("GH_EnterpriseRole k-nexus-global\\owner")
    user1 -- GH_HasRole --> orgRole
    user2 -- GH_HasRole --> repoRole
    team1 -- GH_HasRole --> repoRole
    user1 -- GH_HasRole --> teamRole
    entTeam -- GH_HasRole --> entRole
```
