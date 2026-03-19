# GH_ViewEnterpriseActionsUsageMetrics

## Edge Schema

- Source: [GH_EnterpriseRole](../NodeDescriptions/GH_EnterpriseRole.md)
- Destination: [GH_Enterprise](../NodeDescriptions/GH_Enterprise.md)

## General Information

The non-traversable [GH_ViewEnterpriseActionsUsageMetrics](GH_ViewEnterpriseActionsUsageMetrics.md) edge represents that a custom enterprise role can view GitHub Actions usage metrics for the enterprise. This edge is dynamically generated from custom enterprise role permissions discovered by the collector.

```mermaid
graph LR
    node1("GH_EnterpriseRole k-nexus-global/Authentication-Admin")
    node2("GH_Enterprise k-nexus-global")
    node1 -- GH_ViewEnterpriseActionsUsageMetrics --> node2
```
