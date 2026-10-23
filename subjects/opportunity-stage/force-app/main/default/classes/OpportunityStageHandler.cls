/**
 * Before-insert and before-update logic for Opportunity. No SOQL, no DML.
 *
 * Verification subject: properties P1-P5 in lean/Spec/ state what beforeSave must do. Keep this
 * class inside the modelled Apex subset (docs/apex-subset.md). A change here is a subject patch
 * and must be logged in BUGS.md.
 */
public with sharing class OpportunityStageHandler {
    /**
     * @param newList the records being saved (Trigger.new)
     * @param oldMap  the previous versions by Id (Trigger.oldMap); null on insert
     * @param today   the date to stamp on CloseDate, passed in so the method has no hidden inputs
     */
    public static void beforeSave(List<Opportunity> newList, Map<Id, Opportunity> oldMap, Date today) {
        for (Opportunity opp : newList) {
            Opportunity old = null;
            if (oldMap != null) {
                old = oldMap.get(opp.Id);
            }
            Boolean stageChanged = old == null || opp.StageName != old.StageName;

            if (stageChanged) {
                opp.Probability = OpportunityStage.stageProbability(opp.StageName);
                if (OpportunityStage.isClosed(opp.StageName) && opp.CloseDate == null) {
                    opp.CloseDate = today;
                }
            }

            if (opp.StageName == 'Closed Won' && (opp.Amount == null || opp.Amount < 0)) {
                opp.addError('A Closed Won opportunity needs an Amount of zero or more.');
            }
        }
    }
}
