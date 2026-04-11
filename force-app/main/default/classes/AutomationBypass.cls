public with sharing class AutomationBypass {

    @TestVisible
    private static Automation_Bypass__mdt mockBypass;

    /**
     * Returns the default Automation_Bypass__mdt record
     */
    public static Automation_Bypass__mdt getDefault() {
        if (Test.isRunningTest() && mockBypass != null) {
            return mockBypass;
        }

        List<Automation_Bypass__mdt> bypasses = [
            SELECT IsDisabled__c, DiscountRiskReporting__c
            FROM Automation_Bypass__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        return bypasses.isEmpty() ? null : bypasses[0];
    }

    /**
     * Checks if a specific feature is disabled via bypass metadata
     */
    @InvocableMethod(label='Check Automation Bypass' description='Returns true if automation is bypassed')
    public static List<Boolean> isDisabled(List<String> featureNames) {
        List<Boolean> results = new List<Boolean>();
        Automation_Bypass__mdt bypass = getDefault();

        for (String featureName : featureNames) {
            if (bypass == null) {
                results.add(false);
                continue;
            }

            Boolean disabled = false;
            if (bypass.IsDisabled__c) {
                disabled = true;
            } else if (featureName == 'DiscountRiskReporting' && bypass.DiscountRiskReporting__c == false) {
                disabled = true;
            }
            results.add(disabled);
        }

        return results;
    }
}