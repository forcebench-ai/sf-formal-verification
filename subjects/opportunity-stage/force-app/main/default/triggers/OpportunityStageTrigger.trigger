trigger OpportunityStageTrigger on Opportunity (before insert, before update) {
    OpportunityStageHandler.beforeSave(Trigger.new, Trigger.oldMap, Date.today());
}
