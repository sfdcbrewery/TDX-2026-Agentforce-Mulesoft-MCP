/**
 * @description Test class for SearchSupportTicketsAction
 */
@IsTest
private class SearchSupportTicketsActionTest {

    @IsTest
    static void testSuccessfulSearch() {
        // Set up mock response
        Test.setMock(HttpCalloutMock.class, new MockElasticMCPSuccess());

        // Create test request
        SearchSupportTicketsAction.SearchRequest req = new SearchSupportTicketsAction.SearchRequest();
        req.searchQuery = 'Pinnacle Financial';
        req.indexName = 'support-tickets';

        // Execute
        Test.startTest();
        List<SearchSupportTicketsAction.SearchResult> results =
            SearchSupportTicketsAction.execute(new List<SearchSupportTicketsAction.SearchRequest>{req});
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        SearchSupportTicketsAction.SearchResult result = results[0];
        System.assertEquals(true, result.success, 'Call should succeed');
        System.assertNotEquals(null, result.searchResults, 'Should have search results');
    }

    @IsTest
    static void testHttpError() {
        // Set up mock error response
        Test.setMock(HttpCalloutMock.class, new MockElasticMCPError());

        // Create test request
        SearchSupportTicketsAction.SearchRequest req = new SearchSupportTicketsAction.SearchRequest();
        req.searchQuery = 'Test';
        req.indexName = 'support-tickets';

        // Execute
        Test.startTest();
        List<SearchSupportTicketsAction.SearchResult> results =
            SearchSupportTicketsAction.execute(new List<SearchSupportTicketsAction.SearchRequest>{req});
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        SearchSupportTicketsAction.SearchResult result = results[0];
        System.assertEquals(false, result.success, 'Call should fail');
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
    }

    @IsTest
    static void testDefaultIndexName() {
        // Set up mock response
        Test.setMock(HttpCalloutMock.class, new MockElasticMCPSuccess());

        // Create test request without index name
        SearchSupportTicketsAction.SearchRequest req = new SearchSupportTicketsAction.SearchRequest();
        req.searchQuery = 'Test Query';

        // Execute
        Test.startTest();
        List<SearchSupportTicketsAction.SearchResult> results =
            SearchSupportTicketsAction.execute(new List<SearchSupportTicketsAction.SearchRequest>{req});
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Should use default index name');
    }

    // Mock HTTP Success Response
    private class MockElasticMCPSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"{\\"results\\":[{\\"type\\":\\"resource_list\\",\\"data\\":{\\"resources\\":[{\\"reference\\":{\\"id\\":\\"CASE-001\\",\\"index\\":\\"support-tickets\\"}}]}}]}"}]}}');
            return res;
        }
    }

    // Mock HTTP Error Response
    private class MockElasticMCPError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }
}