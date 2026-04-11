@IsTest
private class AutomationBypassTest {

    @IsTest
    static void testGetDefault() {
        // Test when bypass metadata exists
        Automation_Bypass__mdt mockBypass = new Automation_Bypass__mdt(
            DeveloperName = 'Default',
            IsDisabled__c = false,
            DiscountRiskReporting__c = true
        );
        AutomationBypass.mockBypass = mockBypass;

        Automation_Bypass__mdt result = AutomationBypass.getDefault();

        System.assertNotEquals(null, result, 'Should return bypass metadata');
        System.assertEquals(false, result.IsDisabled__c, 'IsDisabled should be false');
        System.assertEquals(true, result.DiscountRiskReporting__c, 'DiscountRiskReporting should be true');
    }

    @IsTest
    static void testIsDisabled_GlobalBypass() {
        Automation_Bypass__mdt mockBypass = new Automation_Bypass__mdt(
            DeveloperName = 'Default',
            IsDisabled__c = true,
            DiscountRiskReporting__c = true
        );
        AutomationBypass.mockBypass = mockBypass;

        List<Boolean> results = AutomationBypass.isDisabled(new List<String>{'DiscountRiskReporting'});

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0], 'Global bypass should disable all features');
    }

    @IsTest
    static void testIsDisabled_FeatureSpecific() {
        Automation_Bypass__mdt mockBypass = new Automation_Bypass__mdt(
            DeveloperName = 'Default',
            IsDisabled__c = false,
            DiscountRiskReporting__c = false
        );
        AutomationBypass.mockBypass = mockBypass;

        List<Boolean> results = AutomationBypass.isDisabled(new List<String>{'DiscountRiskReporting'});

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0], 'DiscountRiskReporting should be disabled');
    }

    @IsTest
    static void testIsDisabled_Enabled() {
        Automation_Bypass__mdt mockBypass = new Automation_Bypass__mdt(
            DeveloperName = 'Default',
            IsDisabled__c = false,
            DiscountRiskReporting__c = true
        );
        AutomationBypass.mockBypass = mockBypass;

        List<Boolean> results = AutomationBypass.isDisabled(new List<String>{'DiscountRiskReporting'});

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0], 'DiscountRiskReporting should be enabled');
    }

    @IsTest
    static void testIsDisabled_NoBypassMetadata() {
        AutomationBypass.mockBypass = null;

        List<Boolean> results = AutomationBypass.isDisabled(new List<String>{'DiscountRiskReporting'});

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0], 'Should default to enabled when no bypass metadata');
    }
}