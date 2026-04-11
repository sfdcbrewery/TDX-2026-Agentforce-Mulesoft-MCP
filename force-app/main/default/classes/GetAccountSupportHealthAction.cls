/**
 * @description Unified action that combines Salesforce deal health + Elastic support ticket analysis
 * @author TDX 2026
 */
public with sharing class GetAccountSupportHealthAction {

    @InvocableMethod(
        label='Get Account Support Health (Unified MCP)'
        description='Analyze account health using both Salesforce MCP and Elastic MCP data'
        category='Agent Actions'
        callout=true
    )
    public static List<HealthResult> execute(List<HealthRequest> requests) {
        List<HealthResult> results = new List<HealthResult>();

        for (HealthRequest req : requests) {
            HealthResult result = analyzeAccountHealth(req);
            results.add(result);
        }

        return results;
    }

    private static HealthResult analyzeAccountHealth(HealthRequest req) {
        HealthResult result = new HealthResult();
        result.accountName = req.accountName;

        try {
            // Step 1: Get Salesforce deal health from MuleSoft MCP
            DealHealthData dealHealth = assessDealHealth(req.opportunityName);

            // Step 2: Get support ticket data from Elastic MCP
            SupportTicketData supportData = getSupportTickets(req.accountName);

            // Step 3: Combine insights
            result.success = true;
            result.dealHealthScore = dealHealth.riskScore;
            result.dealHealthSummary = dealHealth.summary;
            result.openSupportTickets = supportData.totalTickets;
            result.criticalTickets = supportData.criticalCount;
            result.highTickets = supportData.highCount;
            result.averageSentiment = supportData.avgSentiment;
            result.topIssues = supportData.topIssues;

            // Calculate overall health score
            result.overallHealthScore = calculateOverallHealth(dealHealth, supportData);
            result.recommendation = generateRecommendation(dealHealth, supportData);

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    private static DealHealthData assessDealHealth(String oppName) {
        DealHealthData data = new DealHealthData();

        try {
            MuleSoftMcpClient.ToolResponse toolResponse = MuleSoftMcpClient.callSalesforceTool(
                'post_v1_salesforce_assess_deal_health',
                'assess-deal-health',
                new Map<String, Object>{
                    'opportunityName' => oppName
                }
            );

            if (toolResponse.success) {
                String textResponse = MuleSoftMcpClient.extractTextContent(toolResponse.responseBody);
                data.riskScore = parseRiskScore(textResponse);
                data.summary = String.isBlank(textResponse) ? 'Deal health response received from Salesforce MCP.' : textResponse;
            } else {
                data.riskScore = 0;
                data.summary = MuleSoftMcpClient.buildErrorPayload('Deal Health', toolResponse);
            }

        } catch (Exception e) {
            data.riskScore = 0;
            data.summary = 'Error: ' + e.getMessage();
        }

        return data;
    }

    private static SupportTicketData getSupportTickets(String accountName) {
        SupportTicketData data = new SupportTicketData();

        try {
            // Call Elastic MCP server
            Map<String, Object> mcpRequest = new Map<String, Object>{
                'jsonrpc' => '2.0',
                'id' => Math.abs(Crypto.getRandomInteger()),
                'method' => 'tools/call',
                'params' => new Map<String, Object>{
                    'name' => 'platform_core_search',
                    'arguments' => new Map<String, Object>{
                        'query' => 'account_name:"' + accountName + '" | stats count by priority, avg sentiment_score',
                        'index' => 'support-tickets'
                    }
                }
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:ElasticAgentMCPv2');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setHeader('Authorization', 'Basic dGR4MjAyNjpTaG93dGltZSFAMw==');
            req.setBody(JSON.serialize(mcpRequest));
            req.setTimeout(120000);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                // Parse response
                data.totalTickets = 10; // TODO: Parse from actual response
                data.criticalCount = 2;
                data.highCount = 3;
                data.avgSentiment = -0.65;
                data.topIssues = 'Billing issues, Data sync failures';
            }

        } catch (Exception e) {
            data.totalTickets = 0;
            data.topIssues = 'Error retrieving tickets: ' + e.getMessage();
        }

        return data;
    }

    private static Decimal calculateOverallHealth(DealHealthData dealHealth, SupportTicketData supportData) {
        // Weighted scoring: 60% deal health, 40% support health
        Decimal dealWeight = 0.6;
        Decimal supportWeight = 0.4;

        // Convert support data to health score (0-100)
        Decimal supportScore = 100;
        if (supportData.criticalCount > 0) {
            supportScore -= (supportData.criticalCount * 15);
        }
        if (supportData.highCount > 0) {
            supportScore -= (supportData.highCount * 5);
        }
        if (supportData.avgSentiment < -0.5) {
            supportScore -= 10;
        }

        return (dealHealth.riskScore * dealWeight) + (supportScore * supportWeight);
    }

    private static String generateRecommendation(DealHealthData dealHealth, SupportTicketData supportData) {
        if (supportData.criticalCount > 2) {
            return 'URGENT: Multiple critical support tickets require immediate attention. Schedule executive escalation call.';
        } else if (supportData.avgSentiment < -0.7) {
            return 'WARNING: Negative customer sentiment detected. Recommend CSM intervention.';
        } else if (dealHealth.riskScore < 50) {
            return 'Deal health at risk. Review pipeline stage and recent activities.';
        } else {
            return 'Account health is stable. Continue monitoring support ticket trends.';
        }
    }

    private static Decimal parseRiskScore(String textResponse) {
        if (String.isBlank(textResponse)) {
            return 0;
        }

        for (String line : textResponse.split('\n')) {
            String trimmedLine = line.trim();
            if (trimmedLine.startsWith('- ')) {
                trimmedLine = trimmedLine.substring(2).trim();
            }
            if (trimmedLine.startsWith('Risk Score: ')) {
                String scoreText = trimmedLine.substring('Risk Score: '.length()).split('/')[0].trim();
                return Decimal.valueOf(scoreText);
            }
        }

        return 0;
    }

    // Input wrapper
    public class HealthRequest {
        @InvocableVariable(required=true label='Account Name')
        public String accountName;

        @InvocableVariable(required=false label='Opportunity Name')
        public String opportunityName;
    }

    // Output wrapper
    public class HealthResult {
        @InvocableVariable
        public Boolean success = false;

        @InvocableVariable
        public String accountName;

        @InvocableVariable(label='Deal Health Score')
        public Decimal dealHealthScore;

        @InvocableVariable(label='Deal Health Summary')
        public String dealHealthSummary;

        @InvocableVariable(label='Open Support Tickets')
        public Integer openSupportTickets;

        @InvocableVariable(label='Critical Tickets')
        public Integer criticalTickets;

        @InvocableVariable(label='High Priority Tickets')
        public Integer highTickets;

        @InvocableVariable(label='Average Sentiment Score')
        public Decimal averageSentiment;

        @InvocableVariable(label='Top Issues')
        public String topIssues;

        @InvocableVariable(label='Overall Health Score')
        public Decimal overallHealthScore;

        @InvocableVariable(label='Recommendation')
        public String recommendation;

        @InvocableVariable
        public String errorMessage;
    }

    // Helper classes
    private class DealHealthData {
        public Decimal riskScore;
        public String summary;
    }

    private class SupportTicketData {
        public Integer totalTickets = 0;
        public Integer criticalCount = 0;
        public Integer highCount = 0;
        public Decimal avgSentiment = 0;
        public String topIssues;
    }
}