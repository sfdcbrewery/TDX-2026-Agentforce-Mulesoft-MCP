/**
 * @description Test class for GetAccountSupportHealthAction
 */
@IsTest
private class GetAccountSupportHealthActionTest {

    @IsTest
    static void testSuccessfulHealthCheck() {
        // Set up mock responses for both MuleSoft and Elastic callouts
        Test.setMock(HttpCalloutMock.class, new MockMultiCalloutSuccess());

        // Create test request
        GetAccountSupportHealthAction.HealthRequest req = new GetAccountSupportHealthAction.HealthRequest();
        req.accountName = 'Pinnacle Financial';
        req.opportunityName = 'Test Opportunity';

        // Execute
        Test.startTest();
        List<GetAccountSupportHealthAction.HealthResult> results =
            GetAccountSupportHealthAction.execute(new List<GetAccountSupportHealthAction.HealthRequest>{req});
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        GetAccountSupportHealthAction.HealthResult result = results[0];
        System.assertEquals(true, result.success, 'Call should succeed');
        System.assertNotEquals(null, result.overallHealthScore, 'Should have overall health score');
    }

    @IsTest
    static void testMissingAccountName() {
        // Set up mock response
        Test.setMock(HttpCalloutMock.class, new MockMultiCalloutSuccess());

        // Create test request without account name
        GetAccountSupportHealthAction.HealthRequest req = new GetAccountSupportHealthAction.HealthRequest();

        // Execute
        Test.startTest();
        List<GetAccountSupportHealthAction.HealthResult> results =
            GetAccountSupportHealthAction.execute(new List<GetAccountSupportHealthAction.HealthRequest>{req});
        Test.stopTest();

        // Assert - action completes but with no account context
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Should complete even without account name');
    }

    // Mock HTTP Response that handles multiple callouts
    private class MockMultiCalloutSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            // Return appropriate response based on endpoint
            if (req.getEndpoint().contains('mulemcp')) {
                res.setBody('{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"{\\"riskScore\\":45,\\"riskLevel\\":\\"Medium\\"}"}]}}');
            } else {
                res.setBody('{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"{\\"results\\":[{\\"data\\":{\\"resources\\":[]}}]}"}]}}');
            }
            return res;
        }
    }
}