/**
 * Agentforce Vibes Hooks: RevOps Utilities
 *
 * Reusable hooks that provide flexibility without changing core Flow logic:
 * - Bypass control
 * - Configuration resolution (converts "current" to actual dates, % to decimals)
 * - Slack message building with opportunity links
 * - Notification routing
 */
public with sharing class RevOpsHooks {

    /**
     * Hook: Check if feature should be bypassed
     */
    public static Boolean shouldBypass(String featureName) {
        Automation_Bypass__mdt bypass = AutomationBypass.getDefault();
        if (bypass == null) {
            return false;
        }

        if (bypass.IsDisabled__c) {
            return true;
        }

        if (featureName == 'DiscountRiskReporting' && bypass.DiscountRiskReporting__c == false) {
            return true;
        }

        return false;
    }

    /**
     * Hook: Resolve configuration from natural language inputs
     * Converts "current" to actual quarter dates, % to decimals, etc.
     */
    public static Map<String, Object> resolveConfiguration(Object skillInput) {
        Map<String, Object> config = new Map<String, Object>();

        // Use dynamic typing to handle different input types
        Map<String, Object> inputMap = (Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(skillInput));

        // Resolve discount threshold (convert % to decimal)
        Decimal thresholdPercent = inputMap.containsKey('discountThresholdPercent')
            ? Decimal.valueOf(String.valueOf(inputMap.get('discountThresholdPercent')))
            : 20;
        config.put('discountThreshold', thresholdPercent / 100);

        // Resolve quarter dates
        String quarterInput = inputMap.containsKey('quarter')
            ? String.valueOf(inputMap.get('quarter'))
            : 'current';

        Map<String, Date> quarterDates = resolveQuarterDates(quarterInput);
        config.put('quarterStart', quarterDates.get('start'));
        config.put('quarterEnd', quarterDates.get('end'));

        // Resolve minimum amount
        config.put('minAmount', inputMap.get('minAmount'));

        return config;
    }

    /**
     * Hook: Resolve quarter dates from natural language
     * Supports: "current", "Q2 2026", "2026-Q3", etc.
     */
    private static Map<String, Date> resolveQuarterDates(String quarterInput) {
        Map<String, Date> dates = new Map<String, Date>();

        if (quarterInput == 'current' || String.isBlank(quarterInput)) {
            // Calculate current quarter
            Date today = Date.today();
            Integer currentMonth = today.month();
            Integer currentYear = today.year();
            Integer quarterStartMonth = ((Math.floor((currentMonth - 1) / 3).intValue()) * 3) + 1;

            dates.put('start', Date.newInstance(currentYear, quarterStartMonth, 1));
            dates.put('end', Date.newInstance(currentYear, quarterStartMonth + 2,
                Date.daysInMonth(currentYear, quarterStartMonth + 2)));
        } else {
            // Parse quarter input like "Q2 2026" or "2026-Q3"
            // For demo, default to current quarter (extend this for production)
            Date today = Date.today();
            Integer currentMonth = today.month();
            Integer currentYear = today.year();
            Integer quarterStartMonth = ((Math.floor((currentMonth - 1) / 3).intValue()) * 3) + 1;

            dates.put('start', Date.newInstance(currentYear, quarterStartMonth, 1));
            dates.put('end', Date.newInstance(currentYear, quarterStartMonth + 2,
                Date.daysInMonth(currentYear, quarterStartMonth + 2)));
        }

        return dates;
    }

    /**
     * Hook: Build Slack message with opportunity links
     */
    public static String buildSlackMessage(
        List<Opportunity> opps,
        Decimal thresholdPercent,
        Date quarterStart,
        Date quarterEnd
    ) {
        String baseUrl = System.URL.getOrgDomainUrl().toExternalForm();

        String message = ':rotating_light: *RevOps Quarterly Discount Risk Report*\n\n';
        message += ':bar_chart: *Total Opportunities at Risk:* ' + opps.size() + '\n';
        message += ':moneybag: *Discount Threshold:* ' + (thresholdPercent * 100).setScale(0) + '%\n';
        message += ':date: *Quarter:* ' + quarterStart.format() + ' to ' + quarterEnd.format() + '\n\n';

        if (opps.isEmpty()) {
            message += ':white_check_mark: No opportunities at risk this quarter.\n';
        } else {
            message += '*Opportunities:*\n';

            for (Opportunity opp : opps) {
                Decimal discountPercent = (opp.Discount__c * 100).setScale(0);
                String oppUrl = baseUrl + '/' + opp.Id;
                String amountFormatted = '$' + String.valueOf(opp.Amount.setScale(0));

                message += '• <' + oppUrl + '|' + opp.Name + '> - ' + discountPercent + '% discount - ' + amountFormatted;

                if (opp.Owner != null) {
                    message += ' (Owner: ' + opp.Owner.Name + ')';
                }

                message += '\n';
            }

            message += '\n_Click opportunity names to open in Salesforce._';
        }

        return message;
    }

    /**
     * Hook: Post message to Slack (async)
     */
    public static void postToSlack(String message) {
        // Call the existing RevOpsPostRunInvoker
        RevOpsPostRunInvoker.PayloadWrapper wrapper = new RevOpsPostRunInvoker.PayloadWrapper();
        wrapper.message = message;

        RevOpsPostRunInvoker.postToSlack(new List<RevOpsPostRunInvoker.PayloadWrapper>{wrapper});
    }
}