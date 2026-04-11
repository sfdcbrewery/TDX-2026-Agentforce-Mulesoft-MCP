/**
 * @description Apex Invocable Action for searching support tickets via Elastic MCP
 * @author TDX 2026
 */
public with sharing class SearchSupportTicketsAction {

    @InvocableMethod(
        label='Search Support Tickets (MCP)'
        description='Search support tickets in Elasticsearch via MCP server'
        category='Agent Actions'
        callout=true
    )
    public static List<SearchResult> execute(List<SearchRequest> requests) {
        List<SearchResult> results = new List<SearchResult>();

        for (SearchRequest req : requests) {
            SearchResult result = searchTickets(req);
            results.add(result);
        }

        return results;
    }

    private static SearchResult searchTickets(SearchRequest req) {
        SearchResult result = new SearchResult();

        try {
            // Build MCP request payload via MuleSoft wrapper
            Map<String, Object> mcpRequest = new Map<String, Object>{
                'jsonrpc' => '2.0',
                'id' => generateRequestId(),
                'method' => 'tools/call',
                'params' => new Map<String, Object>{
                    'name' => 'post_v1_elastic',
                    'arguments' => new Map<String, Object>{
                        'body' => new Map<String, Object>{
                            'method' => 'tools/call',
                            'name' => 'platform_core_search',
                            'arguments' => new Map<String, Object>{
                                'query' => req.searchQuery,
                                'index' => String.isNotBlank(req.indexName) ? req.indexName.replace('_', '-') : 'support-tickets'
                            }
                        }
                    }
                }
            };

            // Make callout to MuleSoft Elastic MCP wrapper
            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint('callout:ElasticAgentMCPv2');
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setHeader('Accept', 'application/json');
            httpReq.setHeader('Authorization', 'Basic dGR4MjAyNjpTaG93dGltZSFAMw==');
            httpReq.setBody(JSON.serialize(mcpRequest));
            httpReq.setTimeout(120000);

            Http http = new Http();
            HttpResponse httpRes = http.send(httpReq);

            if (httpRes.getStatusCode() == 200) {
                Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
                result.success = true;
                result.rawResponse = JSON.serializePretty(response);

                // Parse MCP response
                if (response.containsKey('result')) {
                    Map<String, Object> mcpResult = (Map<String, Object>) response.get('result');
                    if (mcpResult.containsKey('content')) {
                        List<Object> contentList = (List<Object>) mcpResult.get('content');
                        if (!contentList.isEmpty()) {
                            Map<String, Object> contentItem = (Map<String, Object>) contentList[0];
                            if (contentItem.containsKey('text')) {
                                String textContent = (String) contentItem.get('text');
                                result.searchResults = textContent;
                                result.summary = extractSearchSummary(textContent);
                            }
                        }
                    }
                }
            } else {
                result.success = false;
                result.errorMessage = 'HTTP ' + httpRes.getStatusCode() + ': ' + httpRes.getStatus();
                result.rawResponse = httpRes.getBody();
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
            result.stackTrace = e.getStackTraceString();
        }

        return result;
    }

    private static String extractSearchSummary(String jsonText) {
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonText);
            if (parsed.containsKey('results')) {
                List<Object> results = (List<Object>) parsed.get('results');
                return 'Found ' + results.size() + ' result(s)';
            }
        } catch (Exception e) {
            return 'Results available';
        }
        return 'Search completed';
    }

    private static Integer generateRequestId() {
        return Math.abs(Crypto.getRandomInteger());
    }

    // Input wrapper
    public class SearchRequest {
        @InvocableVariable(required=true label='Search Query' description='Natural language search query')
        public String searchQuery;

        @InvocableVariable(required=false label='Index Name' description='Elasticsearch index name (default: support-tickets)')
        public String indexName;
    }

    // Output wrapper
    public class SearchResult {
        @InvocableVariable(label='Success')
        public Boolean success = false;

        @InvocableVariable(label='Search Results')
        public String searchResults;

        @InvocableVariable(label='Summary')
        public String summary;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Raw Response')
        public String rawResponse;

        @InvocableVariable(label='Stack Trace')
        public String stackTrace;
    }
}