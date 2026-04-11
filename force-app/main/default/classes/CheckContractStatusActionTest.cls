/**
 * @description Test class for CheckContractStatusAction
 */
@IsTest
private class CheckContractStatusActionTest {

    @IsTest
    static void testSuccessfulContractCheck() {
        Test.setMock(HttpCalloutMock.class, new MockMuleSoftSuccess());

        CheckContractStatusAction.CheckContractStatusRequest req = new CheckContractStatusAction.CheckContractStatusRequest();
        req.accountId = '001000000000000';

        Test.startTest();
        List<CheckContractStatusAction.MCPResult> results =
            CheckContractStatusAction.checkContractStatus(new List<CheckContractStatusAction.CheckContractStatusRequest>{req});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertNotEquals(null, results[0].response);
    }

    @IsTest
    static void testHttpError() {
        Test.setMock(HttpCalloutMock.class, new MockMuleSoftError());

        CheckContractStatusAction.CheckContractStatusRequest req = new CheckContractStatusAction.CheckContractStatusRequest();
        req.accountId = '001000000000000';

        Test.startTest();
        List<CheckContractStatusAction.MCPResult> results =
            CheckContractStatusAction.checkContractStatus(new List<CheckContractStatusAction.CheckContractStatusRequest>{req});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
    }

    private class MockMuleSoftSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"All contracts signed"}]}}');
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