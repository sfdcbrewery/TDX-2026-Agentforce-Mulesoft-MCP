public with sharing class RevOpsPostRunInvoker {

    private static final String SLACK_CHANNEL_ID = 'C0AR2J8KBN0';

    @InvocableMethod(label='RevOps Post Run Invoker' description='Posts summary to Slack channel')
    public static void postToSlack(List<PayloadWrapper> requests) {
        // Check bypass first
        Automation_Bypass__mdt bypass = AutomationBypass.getDefault();
        if (bypass != null && bypass.IsDisabled__c) {
            System.debug('RevOps automation is bypassed');
            return;
        }

        List<String> messages = new List<String>();
        for (PayloadWrapper req : requests) {
            String message;

            // If opportunity data is provided, build formatted message
            if (req.opportunities != null && !req.opportunities.isEmpty()) {
                message = buildFormattedMessage(req);
            } else {
                // Otherwise use the provided message
                message = req.message;
            }

            if (String.isNotBlank(message)) {
                messages.add(message);
            }
        }

        if (!messages.isEmpty()) {
            postMessagesToSlackAsync(messages);
        }
    }

    private static String buildFormattedMessage(PayloadWrapper req) {
        String instanceUrl = URL.getOrgDomainUrl().toExternalForm();

        // Get owner names for all opportunities
        Set<Id> ownerIds = new Set<Id>();
        for (Opportunity opp : req.opportunities) {
            if (opp.OwnerId != null) {
                ownerIds.add(opp.OwnerId);
            }
        }

        Map<Id, String> ownerNames = new Map<Id, String>();
        if (!ownerIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds]) {
                ownerNames.put(u.Id, u.Name);
            }
        }

        List<String> lines = new List<String>();
        lines.add(':rotating_light: *RevOps Quarterly Discount Risk Report*\n');
        lines.add(':bar_chart: *Total Opportunities at Risk:* ' + req.opportunities.size());
        lines.add(':moneybag: *Discount Threshold:* ' + req.discountThreshold.setScale(0) + '%');
        lines.add(':date: *Quarter:* ' + req.quarterStartDate.format() + ' to ' + req.quarterEndDate.format());
        lines.add('\n*Opportunities:*');

        for (Opportunity opp : req.opportunities) {
            Decimal discountPercent = (opp.Discount__c != null) ? opp.Discount__c * 100 : 0;
            String amount = (opp.Amount != null) ? '$' + String.valueOf(opp.Amount.setScale(0).format()) : '$0';
            String ownerName = ownerNames.containsKey(opp.OwnerId) ? ownerNames.get(opp.OwnerId) : 'Unknown';
            String oppUrl = instanceUrl + '/' + opp.Id;

            String line = '• <' + oppUrl + '|' + opp.Name + '> - ' +
                         discountPercent.setScale(0) + '% discount - ' +
                         amount + ' (Owner: ' + ownerName + ')';
            lines.add(line);
        }

        lines.add('\n_Click opportunity names to open in Salesforce._');

        return String.join(lines, '\n');
    }

    @future(callout=true)
    private static void postMessagesToSlackAsync(List<String> messages) {
        for (String message : messages) {
            try {
                postMessageToSlackWebhook(message);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Failed to post to Slack: ' + e.getMessage());
                System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            }
        }
    }

    private static void postMessageToSlackWebhook(String messageText) {
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'POSTING TO SLACK (Channel: ' + SLACK_CHANNEL_ID + ')');
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, messageText);
        System.debug(LoggingLevel.INFO, '========================================');

        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();

            // Use Named Credential for Slack webhook
            req.setEndpoint('callout:Slack_Webhook');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');

            // Slack webhook expects simple JSON payload
            Map<String, Object> payload = new Map<String, Object>{
                'text' => messageText,
                'channel' => SLACK_CHANNEL_ID,
                'username' => 'RevOps Agent',
                'icon_emoji' => ':chart_with_upwards_trend:',
                'mrkdwn' => true
            };

            req.setBody(JSON.serialize(payload));

            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200 && res.getBody() == 'ok') {
                System.debug(LoggingLevel.INFO, '✅ Successfully posted to Slack!');
            } else {
                System.debug(LoggingLevel.WARN, '⚠️ Slack webhook returned: ' + res.getStatusCode());
                System.debug(LoggingLevel.WARN, 'Response: ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '❌ Slack callout failed: ' + e.getMessage());
            throw e;
        }
    }

    public class PayloadWrapper {
        @InvocableVariable(label='Message' description='Message to post to Slack' required=false)
        public String message;

        @InvocableVariable(label='Discount Threshold' description='Discount threshold percentage' required=false)
        public Decimal discountThreshold;

        @InvocableVariable(label='Quarter Start Date' description='Quarter start date' required=false)
        public Date quarterStartDate;

        @InvocableVariable(label='Quarter End Date' description='Quarter end date' required=false)
        public Date quarterEndDate;

        @InvocableVariable(label='Opportunities' description='List of opportunities at risk' required=false)
        public List<Opportunity> opportunities;
    }
}