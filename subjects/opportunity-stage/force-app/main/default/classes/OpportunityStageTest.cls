@IsTest
private class OpportunityStageTest {
    @IsTest
    static void stageProbabilityMatchesTheStandardSalesProcess() {
        Map<String, Decimal> expected = new Map<String, Decimal>{
            'Prospecting' => 10,
            'Qualification' => 10,
            'Needs Analysis' => 20,
            'Value Proposition' => 50,
            'Id. Decision Makers' => 60,
            'Perception Analysis' => 70,
            'Proposal/Price Quote' => 75,
            'Negotiation/Review' => 90,
            'Closed Won' => 100,
            'Closed Lost' => 0
        };
        for (String stage : expected.keySet()) {
            Assert.areEqual(expected.get(stage), OpportunityStage.stageProbability(stage), stage);
        }
    }

    @IsTest
    static void stageProbabilityIsNullForNullOrUnknownStages() {
        Assert.isNull(OpportunityStage.stageProbability(null));
        Assert.isNull(OpportunityStage.stageProbability(''));
        Assert.isNull(OpportunityStage.stageProbability('Not A Stage'));
        Assert.isNull(OpportunityStage.stageProbability('Closed  Won'));
    }

    @IsTest
    static void isClosedRecognisesOnlyTheClosedStages() {
        Assert.isTrue(OpportunityStage.isClosed('Closed Won'));
        Assert.isTrue(OpportunityStage.isClosed('Closed Lost'));
        Assert.isFalse(OpportunityStage.isClosed('Negotiation/Review'));
        Assert.isFalse(OpportunityStage.isClosed(null));
    }
}
