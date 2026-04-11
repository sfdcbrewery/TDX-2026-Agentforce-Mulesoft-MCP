public with sharing class MuleSoftMcpClient {

    private static final String NAMED_CREDENTIAL = 'MuleSoftMCP';

    public class ToolResponse {
        public Integer statusCode;
        public String responseBody;
        public Boolean success;
        public String errorMessage;
    }

    public class AccountResolution {
        public String accountId;
        public String accountName;
        public String resolutionNote;
    }

    public static ToolResponse callSalesforceTool(String wrapperToolName, String businessToolName, Map<String, Object> businessArguments) {
        Map<String, Object> rpcRequest = new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id' => Math.abs(Crypto.getRandomInteger()),
            'method' => 'tools/call',
            'params' => new Map<String, Object>{
                'name' => wrapperToolName,
                'arguments' => new Map<String, Object>{
                    'body' => new Map<String, Object>{
                        'name' => businessToolName,
                        'arguments' => businessArguments
                    }
                }
            }
        };

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + NAMED_CREDENTIAL + '/');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setBody(JSON.serialize(rpcRequest));
        request.setTimeout(30000);

        HttpResponse response = new Http().send(request);

        ToolResponse toolResponse = new ToolResponse();
        toolResponse.statusCode = response.getStatusCode();
        toolResponse.responseBody = response.getBody();
        toolResponse.success = isSuccessfulResponse(response.getStatusCode(), response.getBody());
        toolResponse.errorMessage = toolResponse.success ? null : extractErrorMessage(response.getBody());
        return toolResponse;
    }

    public static String extractTextContent(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }

        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            if (responseMap == null || !responseMap.containsKey('result')) {
                return null;
            }

            Map<String, Object> resultMap = (Map<String, Object>) responseMap.get('result');
            if (resultMap == null || !resultMap.containsKey('content')) {
                return null;
            }

            List<Object> contentList = (List<Object>) resultMap.get('content');
            if (contentList == null || contentList.isEmpty()) {
                return null;
            }

            for (Object item : contentList) {
                Map<String, Object> contentItem = (Map<String, Object>) item;
                if (contentItem != null && contentItem.containsKey('text')) {
                    String textValue = (String) contentItem.get('text');
                    return unwrapNestedText(textValue);
                }
            }
        } catch (Exception e) {
            return null;
        }

        return null;
    }

    public static String buildErrorPayload(String serviceLabel, ToolResponse toolResponse) {
        Integer statusCode = toolResponse == null ? 503 : toolResponse.statusCode;
        String upstreamBody = toolResponse == null ? null : toolResponse.responseBody;
        String userMessage = buildUserMessage(serviceLabel, statusCode, upstreamBody);

        return JSON.serialize(new Map<String, Object>{
            'error' => serviceLabel + ' MCP call failed.',
            'content' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'text',
                    'text' => userMessage
                }
            },
            'isError' => true,
            'fallback' => false,
            'upstreamStatusCode' => statusCode,
            'upstreamBody' => upstreamBody,
            'upstreamError' => toolResponse == null ? null : toolResponse.errorMessage
        });
    }

    public static AccountResolution resolveAccount(String accountId, String accountName, String opportunityId) {
        AccountResolution resolution = new AccountResolution();
        resolution.accountId = accountId;
        resolution.accountName = accountName;

        if (String.isNotBlank(accountId)) {
            return resolution;
        }

        if (String.isNotBlank(opportunityId)) {
            List<Opportunity> oppMatches = [
                SELECT AccountId, Account.Name
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];
            if (!oppMatches.isEmpty() && oppMatches[0].AccountId != null) {
                resolution.accountId = oppMatches[0].AccountId;
                resolution.accountName = oppMatches[0].Account == null ? accountName : oppMatches[0].Account.Name;
                return resolution;
            }
        }

        if (String.isBlank(accountName)) {
            return resolution;
        }

        List<String> searchTerms = buildSearchTerms(accountName);
        for (String searchTerm : searchTerms) {
            List<Account> accountMatches = [
                SELECT Id, Name
                FROM Account
                WHERE Name LIKE :('%' + searchTerm + '%')
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!accountMatches.isEmpty()) {
                resolution.accountId = accountMatches[0].Id;
                resolution.accountName = accountMatches[0].Name;
                if (accountName != accountMatches[0].Name) {
                    resolution.resolutionNote = 'Resolved account input "' + accountName + '" to account "' + accountMatches[0].Name + '".';
                }
                return resolution;
            }
        }

        for (String searchTerm : searchTerms) {
            List<Opportunity> opportunityMatches = [
                SELECT AccountId, Account.Name, Name
                FROM Opportunity
                WHERE Account.Name LIKE :('%' + searchTerm + '%') OR Name LIKE :('%' + searchTerm + '%')
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!opportunityMatches.isEmpty() && opportunityMatches[0].AccountId != null) {
                resolution.accountId = opportunityMatches[0].AccountId;
                resolution.accountName = opportunityMatches[0].Account == null ? accountName : opportunityMatches[0].Account.Name;
                resolution.resolutionNote = 'Resolved account input "' + accountName + '" using related opportunity "' + opportunityMatches[0].Name + '".';
                return resolution;
            }
        }

        return resolution;
    }

    private static Boolean isSuccessfulResponse(Integer statusCode, String responseBody) {
        if (statusCode == null || statusCode < 200 || statusCode >= 300 || String.isBlank(responseBody)) {
            return false;
        }

        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            return responseMap != null && responseMap.containsKey('result') && !responseMap.containsKey('error');
        } catch (Exception e) {
            return false;
        }
    }

    private static List<String> buildSearchTerms(String inputName) {
        List<String> searchTerms = new List<String>();
        if (String.isBlank(inputName)) {
            return searchTerms;
        }

        String trimmed = inputName.trim();
        searchTerms.add(trimmed);

        List<String> tokens = trimmed.split(' ');
        if (!tokens.isEmpty()) {
            String firstToken = tokens[0].trim();
            if (firstToken.length() >= 4 && !searchTerms.contains(firstToken)) {
                searchTerms.add(firstToken);
            }
        }

        return searchTerms;
    }

    private static String extractErrorMessage(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }

        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            if (responseMap == null) {
                return null;
            }

            if (responseMap.containsKey('error')) {
                Object errorValue = responseMap.get('error');
                if (errorValue instanceof String) {
                    return (String) errorValue;
                }

                Map<String, Object> errorMap = (Map<String, Object>) errorValue;
                if (errorMap != null && errorMap.containsKey('message')) {
                    return (String) errorMap.get('message');
                }
            }
        } catch (Exception e) {
            return null;
        }

        return null;
    }

    private static String unwrapNestedText(String rawText) {
        if (String.isBlank(rawText)) {
            return rawText;
        }

        String current = rawText;
        for (Integer i = 0; i < 3; i++) {
            String trimmed = current.trim();
            if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
                return current;
            }

            try {
                Map<String, Object> nestedMap = (Map<String, Object>) JSON.deserializeUntyped(trimmed);
                if (nestedMap == null || !nestedMap.containsKey('content')) {
                    return current;
                }

                List<Object> nestedContent = (List<Object>) nestedMap.get('content');
                if (nestedContent == null || nestedContent.isEmpty()) {
                    return current;
                }

                Map<String, Object> firstItem = (Map<String, Object>) nestedContent[0];
                if (firstItem == null || !firstItem.containsKey('text')) {
                    return current;
                }

                String nextValue = (String) firstItem.get('text');
                if (String.isBlank(nextValue) || nextValue == current) {
                    return current;
                }
                current = nextValue;
            } catch (Exception e) {
                return current;
            }
        }

        return current;
    }

    private static String buildUserMessage(String serviceLabel, Integer statusCode, String upstreamBody) {
        String normalizedBody = upstreamBody == null ? '' : upstreamBody.toLowerCase();
        if (statusCode == 401 || normalizedBody.contains('authentication attempt failed')) {
            return serviceLabel + ' MCP authentication failed. Configure the MuleSoftMCP named credential with Basic Authentication in Salesforce and store the username and password in the named principal.';
        }
        if (statusCode == 404) {
            return serviceLabel + ' MCP endpoint was not found. Verify that the named credential points to https://integrations-dev.elastic.dev/mulemcp and that the MuleSoft route is deployed.';
        }
        return serviceLabel + ' MCP service is temporarily unavailable. Verify the JSON-RPC endpoint, named credential authentication, and MuleSoft application health, then try again.';
    }
}