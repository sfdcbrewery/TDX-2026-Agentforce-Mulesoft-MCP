# RevOps Pipeline Risk Agent

Salesforce Agentforce agent that helps RevOps teams protect $50M+ quarterly pipelines by analyzing deal health, billing signals, contract status, and customer support tickets through dual MCP (Model Context Protocol) integration.

## Overview

This project demonstrates enterprise AI orchestration using:
- **Salesforce Agentforce**: AI agent framework with natural language understanding
- **MuleSoft MCP Server**: Salesforce data access (opportunities, billing, contracts) via Model Context Protocol
- **Elastic MCP Server**: Customer support ticket analysis from Elasticsearch
- **Concurrent Multi-Agent Orchestration**: Parallel execution of multiple risk assessment tools

## Architecture

```
User Query → Agentforce Bot (v2)
  → GenAi Planner (Orchestration)
    → GenAi Plugins (Topics)
      → GenAi Functions
        → Flows
          → Apex Actions (HTTP callouts)
            → Named Credentials
              → MuleSoft MCP | Elastic MCP
```

## Features

### Pipeline Risk Assessment
- **Deal Health Scoring**: Risk-scores opportunities by stage, activity, and amount
- **Billing Signal Detection**: Surfaces overdue invoices and payment gaps
- **Contract Status Tracking**: Identifies unsigned contracts and upcoming renewals
- **Support Ticket Analysis**: Analyzes customer support tickets from Elasticsearch

### Unified Account Health
Combines Salesforce deal data + Elastic support metrics into a single health score with AI-generated recommendations.

## Project Structure

```
tdx-2026/
├── .gitignore
├── README.md
├── sfdx-project.json
└── force-app/main/default/
    ├── bots/
    │   └── RevOpsPipelineRiskAgent/
    │       ├── RevOpsPipelineRiskAgent.bot-meta.xml
    │       └── v2.botVersion-meta.xml
    ├── genAiPlanners/
    │   └── RevOpsPipelineRiskAgent_v2.genAiPlanner-meta.xml
    ├── genAiPlugins/
    │   ├── Pipeline_Risk_Assessment.genAiPlugin-meta.xml
    │   └── AccountHealthTopic.genAiPlugin-meta.xml
    ├── genAiFunctions/
    │   ├── Assess_Deal_Health_MCP/
    │   ├── Check_Billing_Signals_MCP/
    │   ├── Check_Contract_Status_MCP/
    │   ├── SearchSupportTickets/
    │   └── GetAccountSupportHealth/
    ├── flows/
    │   ├── Assess_Deal_Health_MCP.flow-meta.xml
    │   ├── Check_Billing_Signals_MCP.flow-meta.xml
    │   ├── Check_Contract_Status_MCP.flow-meta.xml
    │   ├── Search_Support_Tickets_Flow.flow-meta.xml
    │   └── Get_Account_Support_Health.flow-meta.xml
    ├── classes/
    │   ├── AssessDealHealthAction.cls
    │   ├── CheckBillingSignalsAction.cls
    │   ├── CheckContractStatusAction.cls
    │   ├── SearchSupportTicketsAction.cls
    │   ├── GetAccountSupportHealthAction.cls
    │   ├── MuleSoftMcpClient.cls
    │   └── *Test.cls (6 test classes)
    ├── objects/
    │   ├── Billing_Record__c/
    │   └── Contract_Status__c/
    ├── namedCredentials/
    │   ├── MuleSoftMCP.namedCredential-meta.xml
    │   └── ElasticAgentMCPv2.namedCredential-meta.xml
    ├── remoteSiteSettings/
    │   ├── MuleSoftMCP.remoteSite-meta.xml
    │   └── ElasticAgentMCPv2.remoteSite-meta.xml
    └── permissionsets/
        └── MCP_Agent_Access.permissionset-meta.xml
```

## Prerequisites

- **Salesforce**: Developer or Enterprise org with Agentforce enabled
- **Salesforce CLI**: Latest version (`sf`)
- **MuleSoft MCP Server**: Deployed and accessible
- **Elastic MCP Server**: Deployed and accessible

## Setup

### 1. Clone Repository
```bash
git clone <repository-url>
cd tdx-2026
```

### 2. Authenticate to Salesforce
```bash
sf org login web --alias my-org --set-default
```

### 3. Deploy Salesforce Metadata
```bash
sf project deploy start --source-dir force-app/ --target-org my-org
```

### 4. Configure Named Credentials
1. Navigate to **Setup → Named Credentials**
2. Update endpoints for:
   - **MuleSoftMCP**: Your MuleSoft MCP server URL
   - **ElasticAgentMCPv2**: Your Elastic MCP server URL

### 5. Configure Remote Site Settings
Both remote sites point to `https://integrations-dev.elastic.dev` - update if your endpoints differ.

### 6. Assign Permission Set
```bash
sf org assign permset --name MCP_Agent_Access --target-org my-org
```

### 7. Activate Agent
1. Navigate to **Setup → Agents**
2. Find **RevOps Pipeline Risk Agent**
3. Click **Activate**

## Usage

### Example Queries

**Deal Health Assessment**
```
What's the health of the Pinnacle Financial opportunity?
```

**Billing Signal Check**
```
Are there any billing issues with Edge Communications?
```

**Contract Status**
```
Check contract status for Grand Hotels
```

**Support Ticket Analysis**
```
What support cases does Pinnacle Financial have?
```

**Unified Account Health**
```
What's the overall health of Pinnacle Financial account?
```

## Agent Components

### GenAi Planner
`RevOpsPipelineRiskAgent_v2` - Orchestrates agent using `ConcurrentMultiAgentOrchestration` to run multiple tools in parallel.

### GenAi Plugins (Topics)

1. **Pipeline_Risk_Assessment** - Main topic with 4 functions:
   - Assess_Deal_Health_MCP
   - Check_Billing_Signals_MCP
   - Check_Contract_Status_MCP
   - SearchSupportTickets

2. **AccountHealthTopic** - Unified health analysis with 2 functions:
   - GetAccountSupportHealth
   - SearchSupportTickets

### MCP Tools

| Function | Flow | Apex Action | Purpose |
|----------|------|-------------|---------|
| Assess_Deal_Health_MCP | Assess_Deal_Health_MCP | AssessDealHealthAction | Risk-score opportunities |
| Check_Billing_Signals_MCP | Check_Billing_Signals_MCP | CheckBillingSignalsAction | Detect overdue invoices |
| Check_Contract_Status_MCP | Check_Contract_Status_MCP | CheckContractStatusAction | Find unsigned contracts |
| SearchSupportTickets | Search_Support_Tickets_Flow | SearchSupportTicketsAction | Query Elasticsearch |
| GetAccountSupportHealth | Get_Account_Support_Health | GetAccountSupportHealthAction | Unified health score |

## Testing

### Run Apex Tests
```bash
sf apex run test --test-level RunLocalTests --target-org my-org --code-coverage --result-format human
```

### Test Classes
- `AssessDealHealthActionTest`
- `CheckBillingSignalsActionTest`
- `CheckContractStatusActionTest`
- `SearchSupportTicketsActionTest`
- `GetAccountSupportHealthActionTest`
- `MuleSoftMcpClientTest`

## Key Implementation Details

### MCP Request Format
All MCP tools use JSON-RPC 2.0:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "tool-name",
    "arguments": { "param": "value" }
  }
}
```

### Named Credentials
Apex uses `callout:NamedCredential` syntax:
```apex
req.setEndpoint('callout:MuleSoftMCP');
```

### Authentication
- **MuleSoftMCP**: Basic Auth header in Apex
- **ElasticAgentMCPv2**: Basic Auth header in Apex
- Update credentials in Apex classes as needed

### Flow to Apex Integration
- Flows are autolaunched
- Apex actions use `callout=true` annotation
- Agent script references Flows via `invocationTarget`

## Custom Objects

### Billing_Record__c
Stores billing/invoice data for billing signal analysis.

**Fields:**
- Invoice_Amount__c (Currency)
- Due_Date__c (Date)
- Payment_Status__c (Text)

### Contract_Status__c
Stores contract data for contract status tracking.

**Fields:**
- Contract_Signed__c (Checkbox)
- Renewal_Date__c (Date)
- Contract_Value__c (Currency)

## Troubleshooting

### "Inappropriate Content" Guardrail Triggers
The GenAi Plugin instructions explicitly authorize support ticket searches as legitimate internal business operations. If still blocked, review plugin scope and instructions.

### Flow Not Executing
- Verify Flow status is "Active"
- Check Flow variable types match Apex outputs
- Review Debug Logs

### MCP Connection Failures
- Test endpoints with curl
- Verify Named Credential URLs
- Check authentication headers in Apex

## License

MIT License - see LICENSE file for details.

## Acknowledgments

Built for TrailheadDX 2026 demonstration of Salesforce Agentforce with dual MCP integration (MuleSoft + Elastic).
