/**
 * Invocable action for Agentforce to assess deal health via MuleSoft MCP server.
 * Calls the assess-deal-health MCP tool on CloudHub 2.0.
 */
public with sharing class AssessDealHealthAction {

    private static final String WRAPPER_TOOL_NAME = 'post_v1_salesforce_assess_deal_health';
    private static final String BUSINESS_TOOL_NAME = 'assess-deal-health';

    // Allowlist patterns: Salesforce IDs are 15 or 18 alphanumeric chars.
    // Opportunity names are limited to 120 chars and must not contain
    // control characters or HTML/JSON-breaking characters to prevent injection.
    private static final Pattern SF_ID_PATTERN = Pattern.compile('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$');
    private static final Integer MAX_NAME_LENGTH = 120;
    private static final Pattern SAFE_NAME_PATTERN = Pattern.compile('^[\\w\\s\\-\'&.,/()+@#:]+$');

    private static String sanitizeId(String id) {
        if (String.isBlank(id)) {
            return null;
        }
        String trimmed = id.trim();
        if (!SF_ID_PATTERN.matcher(trimmed).matches()) {
            throw new IllegalArgumentException('Invalid Salesforce ID format: ' + trimmed.abbreviate(20));
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

    private class OpportunityResolution {
        public String opportunityId;
        public String opportunityName;
        public String resolutionNote;
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

    private static OpportunityResolution resolveOpportunity(String opportunityId, String opportunityName) {
        OpportunityResolution resolution = new OpportunityResolution();
        resolution.opportunityId = opportunityId;
        resolution.opportunityName = opportunityName;

        if (String.isNotBlank(opportunityId) || String.isBlank(opportunityName)) {
            return resolution;
        }

        for (String searchTerm : buildSearchTerms(opportunityName)) {
            List<Opportunity> directMatches = [
                SELECT Id, Name, Account.Name, IsClosed, LastModifiedDate
                FROM Opportunity
                WHERE Name LIKE :('%' + searchTerm + '%')
                ORDER BY IsClosed ASC, LastModifiedDate DESC
                LIMIT 1
            ];
            if (!directMatches.isEmpty()) {
                resolution.opportunityId = directMatches[0].Id;
                resolution.opportunityName = directMatches[0].Name;
                if (opportunityName != directMatches[0].Name) {
                    resolution.resolutionNote = 'Resolved opportunity input "' + opportunityName + '" to opportunity "' + directMatches[0].Name + '".';
                }
                return resolution;
            }

            List<Opportunity> accountMatches = [
                SELECT Id, Name, Account.Name, IsClosed, LastModifiedDate
                FROM Opportunity
                WHERE Account.Name LIKE :('%' + searchTerm + '%')
                ORDER BY IsClosed ASC, LastModifiedDate DESC
                LIMIT 1
            ];
            if (!accountMatches.isEmpty()) {
                resolution.opportunityId = accountMatches[0].Id;
                resolution.opportunityName = accountMatches[0].Name;
                resolution.resolutionNote = 'Resolved account input "' + opportunityName + '" to opportunity "' + accountMatches[0].Name + '".';
                return resolution;
            }
        }

        return resolution;
    }

    private static void parseRiskFields(MCPResult result, String responseBody, String resolutionNote) {
        String textResponse = MuleSoftMcpClient.extractTextContent(responseBody);
        if (String.isBlank(textResponse)) {
            if (String.isNotBlank(resolutionNote)) {
                result.stageRiskFactors = resolutionNote;
            }
            return;
        }

        String[] lines = textResponse.split('\n');
        for (String line : lines) {
            String trimmedLine = line.trim();
            if (trimmedLine.startsWith('- ')) {
                trimmedLine = trimmedLine.substring(2).trim();
            }
            if (trimmedLine.startsWith('Risk Score: ')) {
                String scoreStr = trimmedLine.substring('Risk Score: '.length()).split('/')[0].trim();
                result.riskScore = Integer.valueOf(Decimal.valueOf(scoreStr).intValue());
            } else if (trimmedLine.startsWith('Risk Level: ')) {
                result.riskLevel = trimmedLine.substring('Risk Level: '.length()).trim();
            } else if (trimmedLine.startsWith('Note: ')) {
                result.stageRiskFactors = trimmedLine.substring('Note: '.length()).trim();
            } else if (trimmedLine.startsWith('Next Action: ')) {
                result.topNextAction = trimmedLine.substring('Next Action: '.length()).trim();
            }
        }

        if (String.isNotBlank(resolutionNote)) {
            result.stageRiskFactors = String.isBlank(result.stageRiskFactors)
                ? resolutionNote
                : resolutionNote + ' ' + result.stageRiskFactors;
        }
    }

    @InvocableMethod(
        label='Assess Deal Health'
        description='Scores Salesforce Opportunities by analyzing stage, days in current stage, last activity date, and deal amount to identify at-risk deals. Returns risk score (0-100) and risk level (Low/Medium/High/Critical).'
        callout=true
    )
    public static List<MCPResult> assessDealHealth(List<AssessDealHealthRequest> requests) {
        List<MCPResult> results = new List<MCPResult>();

        for (AssessDealHealthRequest request : requests) {
            try {
                String safeOppId   = sanitizeId(request.opportunityId);
                String safeOppName = sanitizeName(request.opportunityName);

                if (safeOppId == null && safeOppName == null) {
                    throw new IllegalArgumentException('Either Opportunity ID or Opportunity Name is required');
                }

                OpportunityResolution resolution = resolveOpportunity(safeOppId, safeOppName);
                Map<String, Object> arguments = new Map<String, Object>();
                if (String.isNotBlank(resolution.opportunityId)) {
                    arguments.put('opportunityId', resolution.opportunityId);
                } else {
                    arguments.put('opportunityName', resolution.opportunityName);
                }

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
                    parseRiskFields(result, toolResponse.responseBody, resolution.resolutionNote);
                } else {
                    result.statusCode = toolResponse.statusCode;
                    result.response = MuleSoftMcpClient.buildErrorPayload('Deal Health', toolResponse);
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
                    'error' => 'Deal Health MCP callout failed.',
                    'content' => new List<Object>{
                        new Map<String, Object>{
                            'type' => 'text',
                            'text' => 'Deal Health MCP callout failed before a response was returned. Check the named credential, endpoint, and MuleSoft application health.'
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

    public class AssessDealHealthRequest {
        @InvocableVariable(label='Opportunity ID' description='Salesforce Opportunity ID (15 or 18 char)' required=false)
        public String opportunityId;

        @InvocableVariable(label='Opportunity Name' description='Salesforce Opportunity Name to search by' required=false)
        public String opportunityName;
    }

    public class MCPResult {
        @InvocableVariable(label='Success' description='Whether the MCP call succeeded')
        public Boolean success;

        @InvocableVariable(label='HTTP Status Code')
        public Integer statusCode;

        @InvocableVariable(label='Risk Assessment Response' description='Full JSON response from the deal health assessment')
        public String response;
        
        @InvocableVariable(label='Risk Score')
        public Integer riskScore;
        
        @InvocableVariable(label='Risk Level')
        public String riskLevel;
        
        @InvocableVariable(label='Stage Risk Factors')
        public String stageRiskFactors;
        
        @InvocableVariable(label='Top Next Action')
        public String topNextAction;
    }
}