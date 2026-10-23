/**
 * Default win probability for each stage of the standard Salesforce sales process.
 *
 * Verification subject: property P0 in lean/Spec/ states what stageProbability must return.
 * Keep this class inside the modelled Apex subset (docs/apex-subset.md). A change here is a
 * subject patch and must be logged in BUGS.md.
 */
public with sharing class OpportunityStage {
    /**
     * Returns the default probability (0-100) for a standard stage name, or null when the stage
     * name is null or not one of the standard stages.
     */
    public static Decimal stageProbability(String stageName) {
        if (stageName == null) {
            return null;
        }
        if (stageName == 'Prospecting') {
            return 10;
        }
        if (stageName == 'Qualification') {
            return 10;
        }
        if (stageName == 'Needs Analysis') {
            return 20;
        }
        if (stageName == 'Value Proposition') {
            return 50;
        }
        if (stageName == 'Id. Decision Makers') {
            return 60;
        }
        if (stageName == 'Perception Analysis') {
            return 70;
        }
        if (stageName == 'Proposal/Price Quote') {
            return 75;
        }
        if (stageName == 'Negotiation/Review') {
            return 90;
        }
        if (stageName == 'Closed Won') {
            return 100;
        }
        if (stageName == 'Closed Lost') {
            return 0;
        }
        return null;
    }

    /**
     * True when the stage name is one of the two closed stages.
     */
    public static Boolean isClosed(String stageName) {
        return stageName == 'Closed Won' || stageName == 'Closed Lost';
    }
}
