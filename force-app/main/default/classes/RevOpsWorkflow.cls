/**
 * Agentforce Vibes Workflow: RevOps Quarterly Risk
 *
 * Orchestrates the end-to-end execution:
 * 1. PreRunHook - Bypass checks, config loading
 * 2. Skill Execution - Core business logic
 * 3. PostRunHook - Notification routing
 *
 * This Workflow is what Agentforce Vibes calls when admin types natural language prompts.
 *
 * Example prompts handled by this workflow:
 * - "Run quarterly discount risk at 30%"
 * - "Show me high-discount deals this quarter and notify Slack"
 * - "Check pipeline hygiene for Q2 with 25% threshold"
 */
public with sharing class RevOpsWorkflow {

    @InvocableMethod(
        label='RevOps Workflow: Execute Quarterly Risk Analysis'
        description='Full workflow: bypass check → query opps → build report → notify Slack'
        category='Revenue Operations'
    )
    public static List<WorkflowResult> execute(List<WorkflowInput> inputs) {
        List<WorkflowResult> results = new List<WorkflowResult>();

        for (WorkflowInput input : inputs) {
            WorkflowResult result = new WorkflowResult();
            result.steps = new List<String>();

            try {
                // STEP 1: Pre-Run Hook - Log what we're doing
                result.steps.add('Starting RevOps Quarterly Risk Workflow...');
                result.steps.add('Threshold: ' + input.discountThresholdPercent + '%');
                result.steps.add('Quarter: ' + input.quarter);
                result.steps.add('Action: ' + input.actionPolicy);

                // STEP 2: Execute the Skill
                result.steps.add('Executing RevOps Quarterly Risk Skill...');

                RevOpsQuarterlyRiskSkill.SkillInput skillInput = new RevOpsQuarterlyRiskSkill.SkillInput();
                skillInput.quarter = input.quarter;
                skillInput.discountThresholdPercent = input.discountThresholdPercent;
                skillInput.minAmount = input.minAmount;
                skillInput.actionPolicy = input.actionPolicy;
                skillInput.notifyChannelLabel = input.notifyChannelLabel;

                List<RevOpsQuarterlyRiskSkill.SkillResult> skillResults =
                    RevOpsQuarterlyRiskSkill.executeSkill(new List<RevOpsQuarterlyRiskSkill.SkillInput>{skillInput});

                RevOpsQuarterlyRiskSkill.SkillResult skillResult = skillResults[0];

                // STEP 3: Process Skill Result
                if (skillResult.success) {
                    result.steps.add('✅ Skill executed successfully');
                    result.steps.add('Found ' + skillResult.totalAtRisk + ' opportunities at risk');
                    result.totalAtRisk = skillResult.totalAtRisk;
                    result.summary = skillResult.message;

                    if (skillResult.actionTaken != null) {
                        result.steps.add('Action: ' + skillResult.actionTaken);
                    }

                    result.success = true;
                } else {
                    result.steps.add('⚠️ Skill execution bypassed or failed');
                    result.steps.add(skillResult.message);
                    result.success = false;
                }

                // STEP 4: Post-Run Hook - Log completion
                result.steps.add('Workflow completed');

            } catch (Exception e) {
                result.success = false;
                result.steps.add('❌ Workflow failed: ' + e.getMessage());
                result.steps.add('Stack trace: ' + e.getStackTraceString());
            }

            results.add(result);
        }

        return results;
    }

    // Workflow Input - Mirrors Skill Input but can be extended
    public class WorkflowInput {
        @InvocableVariable(label='Quarter' description='current, Q2 2026, etc.' required=false)
        public String quarter = 'current';

        @InvocableVariable(label='Discount Threshold %' description='e.g., 20, 25, 30' required=false)
        public Decimal discountThresholdPercent = 20;

        @InvocableVariable(label='Minimum Amount' required=false)
        public Decimal minAmount;

        @InvocableVariable(label='Action Policy' description='ReportOnly or NotifySlack' required=false)
        public String actionPolicy = 'ReportOnly';

        @InvocableVariable(label='Notification Channel' required=false)
        public String notifyChannelLabel = 'RevOps_Notify_Channel';
    }

    // Workflow Result - Detailed execution log
    public class WorkflowResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Total At Risk')
        public Integer totalAtRisk;

        @InvocableVariable(label='Summary')
        public String summary;

        @InvocableVariable(label='Execution Steps')
        public List<String> steps;
    }
}