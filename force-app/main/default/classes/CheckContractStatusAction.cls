/**
 * Invocable action for Agentforce to check contract status via MuleSoft MCP server.
 * Calls the check-contract-status MCP tool on CloudHub 2.0.
 */
public with sharing class CheckContractStatusAction {

    private static final String WRAPPER_TOOL_NAME = 'post_v1_salesforce_check_contract_status';
    private static final String BUSINESS_TOOL_NAME = 'check-contract-status';

    private static final Pattern SF_ID_PATTERN = Pattern.compile('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$');
    private static final Integer MAX_NAME_LENGTH = 255;
    private static final Pattern SAFE_NAME_PATTERN = Pattern.compile('^[\\w\\s\\-\'&.,/()+@#:]+$');

    private static String sanitizeId(String id) {
        if (String.isBlank(id)) {
            return null;
        }
        String trimmed = id.trim();
        if (!SF_ID_PATTERN.matcher(trimmed).matches()) {
            throw new IllegalArgumentException('Invalid Salesforce ID format');
        }
        return trimmed;
    }

    private static String sanitizeName(String name) {
        if (String.isBlank(name)) {
            return null;
        }
        String trimmed = name.trim();
        if (trimmed.length() > MAX_NAME_LENGTH) {
            throw new IllegalArgumentException('Name exceeds maximum allowed length');
        }
        if (!SAFE_NAME_PATTERN.matcher(trimmed).matches()) {
            throw new IllegalArgumentException('Name contains disallowed characters');
        }
        return trimmed;
    }

    @InvocableMethod(
        label='Check Contract Status'
        description='Returns unsigned contracts, upcoming renewals, and contract risk indicators from the contract platform for a given account or opportunity. Identifies contracts at risk.'
        callout=true
    )
    public static List<MCPResult> checkContractStatus(List<CheckContractStatusRequest> requests) {
        List<MCPResult> results = new List<MCPResult>();

        for (CheckContractStatusRequest request : requests) {
            try {
                String safeAccountId   = sanitizeId(request.accountId);
                String safeAccountName = sanitizeName(request.accountName);
                String safeOppId       = sanitizeId(request.opportunityId);

                if (safeAccountId == null && safeAccountName == null && safeOppId == null) {
                    throw new IllegalArgumentException('At least one of Account ID, Account Name, or Opportunity ID is required');
                }

                MuleSoftMcpClient.AccountResolution resolution = MuleSoftMcpClient.resolveAccount(
                    safeAccountId,
                    safeAccountName,
                    safeOppId
                );
                safeAccountId = resolution.accountId;
                safeAccountName = resolution.accountName;
                if (safeAccountId == null) {
                    throw new IllegalArgumentException('No Account found for the provided identifier');
                }

                Map<String, Object> arguments = new Map<String, Object>();
                arguments.put('accountId', safeAccountId);

                MuleSoftMcpClient.ToolResponse toolResponse = MuleSoftMcpClient.callSalesforceTool(
                    WRAPPER_TOOL_NAME,
                    BUSINESS_TOOL_NAME,
                    arguments
                );

                MCPResult result = new MCPResult();
                if (toolResponse.success) {
                    result.statusCode = toolResponse.statusCode;
                    result.response = toolResponse.responseBody;
                    result.success = true;
                } else {
                    result.statusCode = toolResponse.statusCode;
                    result.response = MuleSoftMcpClient.buildErrorPayload('Contract Status', toolResponse);
                    result.success = false;
                }
                results.add(result);
            } catch (IllegalArgumentException e) {
                MCPResult result = new MCPResult();
                result.statusCode = 400;
                result.response = '{"error": "Invalid input: ' + e.getMessage().replace('"', '\'') + '"}';
                result.success = false;
                results.add(result);
            } catch (Exception e) {
                MCPResult result = new MCPResult();
                result.statusCode = 503;
                result.response = JSON.serialize(new Map<String, Object>{
                    'error' => 'Contract Status MCP callout failed.',
                    'content' => new List<Object>{
                        new Map<String, Object>{
                            'type' => 'text',
                            'text' => 'Contract Status MCP callout failed before a response was returned. Check the named credential, endpoint, and MuleSoft application health.'
                        }
                    },
                    'isError' => true,
                    'fallback' => true,
                    'exceptionType' => e.getTypeName(),
                    'exceptionMessage' => e.getMessage()
                });
                result.success = false;
                results.add(result);
            }
        }
        return results;
    }

    public class CheckContractStatusRequest {
        @InvocableVariable(label='Account ID' description='Salesforce Account ID' required=false)
        public String accountId;

        @InvocableVariable(label='Account Name' description='Account name to search contracts for' required=false)
        public String accountName;

        @InvocableVariable(label='Opportunity ID' description='Salesforce Opportunity ID to check associated contracts' required=false)
        public String opportunityId;
    }

    public class MCPResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='HTTP Status Code')
        public Integer statusCode;

        @InvocableVariable(label='Contract Status Response' description='Full JSON response with contract status and renewal information')
        public String response;
    }
}