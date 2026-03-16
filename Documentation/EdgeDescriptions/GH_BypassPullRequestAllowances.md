# GH_BypassPullRequestAllowances

## Edge Schema

- Source: [GH_User](../NodeDescriptions/GH_User.md), [GH_Team](../NodeDescriptions/GH_Team.md)
- Destination: [GH_BranchProtectionRule](../NodeDescriptions/GH_BranchProtectionRule.md)

## General Information

The non-traversable [GH_BypassPullRequestAllowances](GH_BypassPullRequestAllowances.md) edge represents a per-actor allowance that bypasses the pull request review requirement on a branch protection rule. Created by `Git-HoundBranch` when collecting BPR bypass allowances, this edge identifies specific users or teams that can merge code without going through the normal PR review process. This is a significant security concern because these actors can push or merge changes directly, circumventing code review controls that protect branch integrity. Note that this bypass is suppressed when `enforce_admins` is enabled on the branch protection rule, meaning even listed actors must follow the PR review requirement.

```mermaid
graph LR
    user1("GH_User alice")
    team1("GH_Team release-managers")
    bpr1("GH_BranchProtectionRule main")
    user1 -- GH_BypassPullRequestAllowances --> bpr1
    team1 -- GH_BypassPullRequestAllowances --> bpr1
```
