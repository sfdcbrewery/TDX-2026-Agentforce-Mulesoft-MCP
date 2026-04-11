/**
 * Agentforce Vibes Skill: RevOps Quarterly Discount Risk
 *
 * This is a parameterized Skill that wraps the core Flow execution.
 * Admins can change threshold, quarter, action policy via natural language prompts.
 *
 * Example prompts:
 * - "Run RevOps quarterly risk at 30% threshold and notify Slack"
 * - "Show me discount risk for Q2 2026 at 25%"
 * - "Run quarterly hygiene check with 15% discount threshold"
 */
public with sharing class RevOpsQuarterlyRiskSkill {

    @InvocableMethod(
        label='RevOps: Quarterly Discount Risk'
        description='Analyzes opportunities with high discounts and notifies teams. Flexible threshold and actions.'
        category='Revenue Operations'
    )
    public static List<SkillResult> executeSkill(List<SkillInput> inputs) {
        List<SkillResult> results = new List<SkillResult>();

        for (SkillInput input : inputs) {
            SkillResult result = new SkillResult();

            try {
                // Step 1: Pre-Run Hook - Check bypass and load config
                if (RevOpsHooks.shouldBypass('DiscountRiskReporting')) {
                    result.success = false;
                    result.message = '⚠️ RevOps reporting is currently bypassed via Automation_Bypass__mdt';
                    result.totalAtRisk = 0;
                    results.add(result);
                    continue;
                }

                // Step 2: Resolve configuration via Hook
                Map<String, Object> config = RevOpsHooks.resolveConfiguration(input);

                // Step 3: Execute core logic - Query opportunities
                List<Opportunity> atRiskOpps = queryAtRiskOpportunities(
                    (Decimal)config.get('discountThreshold'),
                    (Date)config.get('quarterStart'),
                    (Date)config.get('quarterEnd'),
                    (Decimal)config.get('minAmount')
                );

                result.totalAtRisk = atRiskOpps.size();
                result.opportunities = atRiskOpps;

                // Step 4: Build summary message via Hook
                result.message = RevOpsHooks.buildSlackMessage(
                    atRiskOpps,
                    (Decimal)config.get('discountThreshold'),
                    (Date)config.get('quarterStart'),
                    (Date)config.get('quarterEnd')
                );

                // Step 5: Post-Run Hook - Route notification based on action policy
                if (input.actionPolicy == 'NotifyChannel' || input.actionPolicy == 'NotifySlack') {
                    RevOpsHooks.postToSlack(result.message);
                    result.actionTaken = 'Posted to Slack channel C0AR2J8KBN0';
                } else {
                    result.actionTaken = 'Report only - no notification sent';
                }

                result.success = true;

            } catch (Exception e) {
                result.success = false;
                result.message = '❌ Error: ' + e.getMessage();
                result.totalAtRisk = 0;
            }

            results.add(result);
        }

        return results;
    }

    private static List<Opportunity> queryAtRiskOpportunities(
        Decimal thresholdDecimal,
        Date quarterStart,
        Date quarterEnd,
        Decimal minAmount
    ) {
        String query = 'SELECT Id, Name, Amount, Discount__c, CloseDate, Owner.Name ' +
                      'FROM Opportunity ' +
                      'WHERE Discount__c > :thresholdDecimal ' +
                      'AND CloseDate >= :quarterStart ' +
                      'AND CloseDate <= :quarterEnd ' +
                      'AND IsClosed = false ';

        if (minAmount != null && minAmount > 0) {
            query += 'AND Amount >= :minAmount ';
        }

        query += 'ORDER BY Discount__c DESC LIMIT 100';

        return Database.query(query);
    }

    // Input wrapper for the Skill
    public class SkillInput {
        @InvocableVariable(label='Quarter' description='Which quarter: "current", "Q2 2026", etc.' required=false)
        public String quarter = 'current';

        @InvocableVariable(label='Discount Threshold %' description='Discount percentage threshold (e.g., 20 for 20%)' required=false)
        public Decimal discountThresholdPercent = 20;

        @InvocableVariable(label='Minimum Amount' description='Minimum opportunity amount to include' required=false)
        public Decimal minAmount;

        @InvocableVariable(label='Action Policy' description='ReportOnly, NotifySlack, NotifyChannel' required=false)
        public String actionPolicy = 'ReportOnly';

        @InvocableVariable(label='Notification Channel' description='Slack channel for notifications' required=false)
        public String notifyChannelLabel = 'RevOps_Notify_Channel';
    }

    // Output wrapper for the Skill
    public class SkillResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Total Opportunities at Risk')
        public Integer totalAtRisk;

        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='Action Taken')
        public String actionTaken;

        @InvocableVariable(label='Opportunities')
        public List<Opportunity> opportunities;
    }
}