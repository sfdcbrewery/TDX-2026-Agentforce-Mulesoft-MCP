/**
 * @description Test class for MuleSoftMcpClient
 */
@IsTest
private class MuleSoftMcpClientTest {

    @IsTest
    static void testSuccessfulToolCall() {
        Test.setMock(HttpCalloutMock.class, new MockMuleSoftSuccess());

        Test.startTest();
        MuleSoftMcpClient.ToolResponse response = MuleSoftMcpClient.callSalesforceTool(
            'post_v1_salesforce_assess_deal_health',
            'assess-deal-health',
            new Map<String, Object>{'opportunityName' => 'Test'}
        );
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertNotEquals(null, response.responseBody);
    }

    @IsTest
    static void testHttpError() {
        Test.setMock(HttpCalloutMock.class, new MockMuleSoftError());

        Test.startTest();
        MuleSoftMcpClient.ToolResponse response = MuleSoftMcpClient.callSalesforceTool(
            'post_v1_salesforce_assess_deal_health',
            'assess-deal-health',
            new Map<String, Object>{'opportunityName' => 'Test'}
        );
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertNotEquals(null, response.errorMessage);
    }

    @IsTest
    static void testExtractTextContent() {
        String validJson = '{"result":{"content":[{"type":"text","text":"Test content"}]}}';
        String extracted = MuleSoftMcpClient.extractTextContent(validJson);
        System.assertEquals('Test content', extracted);

        String invalidJson = '{"error":"test"}';
        String extractedEmpty = MuleSoftMcpClient.extractTextContent(invalidJson);
        System.assertEquals(null, extractedEmpty);
    }

    @IsTest
    static void testBuildErrorPayload() {
        MuleSoftMcpClient.ToolResponse errorResponse = new MuleSoftMcpClient.ToolResponse();
        errorResponse.success = false;
        errorResponse.errorMessage = 'Test error';
        errorResponse.statusCode = 500;

        String payload = MuleSoftMcpClient.buildErrorPayload('TestTool', errorResponse);
        System.assert(payload.contains('TestTool'));
        System.assert(payload.contains('Test error'));
    }

    private class MockMuleSoftSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Success"}]}}');
            return res;
        }
    }

    private class MockMuleSoftError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('{"error":"test error"}');
            return res;
        }
    }
}