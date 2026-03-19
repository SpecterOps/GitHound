# GH_MemberOf

## Edge Schema

- Source: [GH_TeamRole](../NodeDescriptions/GH_TeamRole.md), [GH_Team](../NodeDescriptions/GH_Team.md), [GH_EnterpriseTeam](../NodeDescriptions/GH_EnterpriseTeam.md)
- Destination: [GH_Team](../NodeDescriptions/GH_Team.md), [GH_EnterpriseTeam](../NodeDescriptions/GH_EnterpriseTeam.md)

## General Information

The traversable [GH_MemberOf](GH_MemberOf.md) edge represents team membership, linking a team role to its parent team or a child team to a parent team in nested team hierarchies. At the organization level, it is created by `Git-HoundTeam` during team enumeration. At the enterprise level, it connects enterprise team roles to their enterprise team and enterprise teams to their corresponding organization-level teams. This edge is traversable because team membership extends access transitively -- a user who holds a role in a child team or enterprise team inherits the repository permissions of all ancestor teams in the hierarchy, making it a key component of attack path analysis.

```mermaid
graph LR
    teamRole1("GH_TeamRole security-team\\maintainer")
    teamRole2("GH_TeamRole appsec-team\\member")
    entTeamRole("GH_TeamRole Corp-Security\\members")
    childTeam("GH_Team appsec-team")
    parentTeam("GH_Team security-team")
    entTeam("GH_EnterpriseTeam Corp-Security")
    teamRole1 -- GH_MemberOf --> parentTeam
    teamRole2 -- GH_MemberOf --> childTeam
    childTeam -- GH_MemberOf --> parentTeam
    entTeamRole -- GH_MemberOf --> entTeam
    entTeam -- GH_MemberOf --> parentTeam
```
