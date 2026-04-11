/**
 * Invocable action for Agentforce to check billing signals via MuleSoft MCP server.
 * Calls the check-billing-signals MCP tool on CloudHub 2.0.
 */
public with sharing class CheckBillingSignalsAction {

    private static final String WRAPPER_TOOL_NAME = 'post_v1_salesforce_check_billing_signals';
    private static final String BUSINESS_TOOL_NAME = 'check-billing-signals';

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

    private class BillingAnalysis {
        public String accountId;
        public String accountName;
        public Integer overdueCount = 0;
        public Decimal overdueAmount = 0;
        public Integer pendingCount = 0;
        public Decimal pendingAmount = 0;
        public String severity = 'Low';
        public List<String> overdueLines = new List<String>();

        public Boolean hasRiskSignals() {
            return overdueCount > 0 || pendingCount > 0;
        }
    }

    private static BillingAnalysis analyzeBillingData(String accountId, String fallbackAccountName) {
        BillingAnalysis analysis = new BillingAnalysis();
        analysis.accountId = accountId;

        List<Account> accounts = [SELECT Name FROM Account WHERE Id = :accountId LIMIT 1];
        analysis.accountName = accounts.isEmpty()
            ? (fallbackAccountName == null ? 'Account ' + accountId : fallbackAccountName)
            : accounts[0].Name;

        List<Billing_Record__c> records = [
            SELECT Name, Invoice_Amount__c, Due_Date__c, Payment_Status__c
            FROM Billing_Record__c
            WHERE Account__c = :accountId
            ORDER BY Due_Date__c DESC
            LIMIT 200
        ];

        for (Billing_Record__c rec : records) {
            String status = (rec.Payment_Status__c == null) ? '' : rec.Payment_Status__c.trim().toLowerCase();
            Decimal amount = (rec.Invoice_Amount__c == null) ? 0 : rec.Invoice_Amount__c;

            if (status == 'overdue') {
                analysis.overdueCount++;
                analysis.overdueAmount += amount;
                analysis.overdueLines.add('    - ' + rec.Name + ': $' + String.valueOf(amount) +
                    ' (Due: ' + String.valueOf(rec.Due_Date__c) + ')');
            } else if (status == 'pending') {
                analysis.pendingCount++;
                analysis.pendingAmount += amount;
            }
        }

        if (analysis.overdueCount > 3 || analysis.overdueAmount > 50000) {
            analysis.severity = 'Critical';
        } else if (analysis.overdueCount > 1 || analysis.overdueAmount > 20000) {
            analysis.severity = 'High';
        } else if (analysis.overdueCount > 0) {
            analysis.severity = 'Medium';
        }

        return analysis;
    }

    private static String buildSalesforceSummaryResponse(BillingAnalysis analysis, String upstreamBody) {
        String text =
            'Billing Signals Analysis:\n\n' +
            'Account: ' + analysis.accountName + '\n' +
            '  Severity: ' + analysis.severity + '\n' +
            '  Overdue Invoices: ' + String.valueOf(analysis.overdueCount) +
            ' ($' + String.valueOf(analysis.overdueAmount) + ')\n' +
            '  Pending Invoices: ' + String.valueOf(analysis.pendingCount) +
            ' ($' + String.valueOf(analysis.pendingAmount) + ')\n';

        if (!analysis.overdueLines.isEmpty()) {
            text += '\n  Overdue Invoices:\n' + String.join(analysis.overdueLines, '\n') + '\n';
        }

        Map<String, Object> payload = new Map<String, Object>{
            'content' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'text',
                    'text' => text
                }
            },
            'isError' => false,
            'authoritativeSource' => 'Salesforce',
            'fallback' => true,
            'upstreamBody' => upstreamBody
        };

        return JSON.serialize(payload);
    }

    @InvocableMethod(
        label='Check Billing Signals'
        description='Surfaces overdue invoices, payment gaps, and billing anomalies from the billing system for a given account or opportunity. Returns payment status and risk indicators.'
        callout=true
    )
    public static List<MCPResult> checkBillingSignals(List<CheckBillingSignalsRequest> requests) {
        List<MCPResult> results = new List<MCPResult>();

        for (CheckBillingSignalsRequest request : requests) {
            try {
                String safeAccountId   = sanitizeId(request.accountId);
                String safeAccountName = sanitizeName(request.accountName);

                if (safeAccountId == null && safeAccountName == null) {
                    throw new IllegalArgumentException('Either Account ID or Account Name is required');
                }

                MuleSoftMcpClient.AccountResolution resolution = MuleSoftMcpClient.resolveAccount(
                    safeAccountId,
                    safeAccountName,
                    null
                );
                safeAccountId = resolution.accountId;
                safeAccountName = resolution.accountName;
                if (safeAccountId == null) {
                    throw new IllegalArgumentException('No Account found with name: ' + request.accountName);
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
                    BillingAnalysis analysis = analyzeBillingData(safeAccountId, safeAccountName);
                    result.statusCode = toolResponse.statusCode;
                    result.response = analysis.hasRiskSignals()
                        ? buildSalesforceSummaryResponse(analysis, toolResponse.responseBody)
                        : toolResponse.responseBody;
                    result.success = true;
                } else {
                    BillingAnalysis analysis = analyzeBillingData(safeAccountId, safeAccountName);
                    result.statusCode = toolResponse.statusCode;
                    if (analysis.hasRiskSignals()) {
                        result.response = buildSalesforceSummaryResponse(analysis, toolResponse.responseBody);
                        result.success = true;
                    } else {
                        result.response = MuleSoftMcpClient.buildErrorPayload('Billing Signals', toolResponse);
                        result.success = false;
                    }
                }
                results.add(result);
            } catch (IllegalArgumentException e) {
                MCPResult result = new MCPResult();
                result.statusCode = 400;
                result.response = '{"error": "Invalid input: ' + e.getMessage().replace('"', '\'') + '"}';
                result.success = false;
                results.add(result);
            } catch (Exception e) {
                String safeAccountIdForFallback = sanitizeId(request.accountId);
                String safeAccountNameForFallback = sanitizeName(request.accountName);
                MCPResult result = new MCPResult();
                if (safeAccountIdForFallback != null) {
                    BillingAnalysis analysis = analyzeBillingData(safeAccountIdForFallback, safeAccountNameForFallback);
                    if (analysis.hasRiskSignals()) {
                        result.statusCode = 200;
                        result.response = buildSalesforceSummaryResponse(analysis, null);
                        result.success = true;
                        results.add(result);
                        continue;
                    }
                }

                result.statusCode = 503;
                result.response = JSON.serialize(new Map<String, Object>{
                    'error' => 'Billing Signals MCP callout failed.',
                    'content' => new List<Object>{
                        new Map<String, Object>{
                            'type' => 'text',
                            'text' => 'Billing Signals MCP callout failed before a response was returned. Check the named credential, endpoint, and MuleSoft application health.'
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

    public class CheckBillingSignalsRequest {
        @InvocableVariable(label='Account ID' description='Salesforce Account ID to check billing for' required=false)
        public String accountId;

        @InvocableVariable(label='Account Name' description='Account name to look up billing signals' required=false)
        public String accountName;
    }

    public class MCPResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='HTTP Status Code')
        public Integer statusCode;

        @InvocableVariable(label='Billing Signals Response' description='Full JSON response with billing signals and payment status')
        public String response;
    }
}