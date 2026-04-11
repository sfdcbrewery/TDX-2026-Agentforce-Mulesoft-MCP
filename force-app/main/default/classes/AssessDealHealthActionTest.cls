/**
 * @description Test class for AssessDealHealthAction
 */
@IsTest
private class AssessDealHealthActionTest {

    @IsTest
    static void testSuccessfulDealHealthAssessment() {
        Test.setMock(HttpCalloutMock.class, new MockMuleSoftSuccess());

        AssessDealHealthAction.AssessDealHealthRequest req = new AssessDealHealthAction.AssessDealHealthRequest();
        req.opportunityName = 'Test Opportunity';

        Test.startTest();
        List<AssessDealHealthAction.MCPResult> results =
            AssessDealHealthAction.assessDealHealth(new List<AssessDealHealthAction.AssessDealHealthRequest>{req});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertNotEquals(null, results[0].response);
    }

    @IsTest
    static void testHttpError() {
        Test.setMock(HttpCalloutMock.class, new MockMuleSoftError());

        AssessDealHealthAction.AssessDealHealthRequest req = new AssessDealHealthAction.AssessDealHealthRequest();
        req.opportunityName = 'Test Opportunity';

        Test.startTest();
        List<AssessDealHealthAction.MCPResult> results =
            AssessDealHealthAction.assessDealHealth(new List<AssessDealHealthAction.AssessDealHealthRequest>{req});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
    }

    private class MockMuleSoftSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Risk Score: 45/100"}]}}');
            return res;
        }
    }

    private class MockMuleSoftError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            return res;
        }
    }
}