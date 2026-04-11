/**
 * @description Test class for CheckBillingSignalsAction
 */
@IsTest
private class CheckBillingSignalsActionTest {

    @IsTest
    static void testSuccessfulBillingCheck() {
        Test.setMock(HttpCalloutMock.class, new MockMuleSoftSuccess());

        CheckBillingSignalsAction.CheckBillingSignalsRequest req = new CheckBillingSignalsAction.CheckBillingSignalsRequest();
        req.accountId = '001000000000000';

        Test.startTest();
        List<CheckBillingSignalsAction.MCPResult> results =
            CheckBillingSignalsAction.checkBillingSignals(new List<CheckBillingSignalsAction.CheckBillingSignalsRequest>{req});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertNotEquals(null, results[0].response);
    }

    @IsTest
    static void testHttpError() {
        Test.setMock(HttpCalloutMock.class, new MockMuleSoftError());

        CheckBillingSignalsAction.CheckBillingSignalsRequest req = new CheckBillingSignalsAction.CheckBillingSignalsRequest();
        req.accountId = '001000000000000';

        Test.startTest();
        List<CheckBillingSignalsAction.MCPResult> results =
            CheckBillingSignalsAction.checkBillingSignals(new List<CheckBillingSignalsAction.CheckBillingSignalsRequest>{req});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
    }

    private class MockMuleSoftSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"No overdue invoices"}]}}');
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