@IsTest
private class OpportunityStageHandlerTest {
    private static final Date TODAY = Date.newInstance(2026, 10, 23);
    private static final String AMOUNT_ERROR = 'A Closed Won opportunity needs an Amount of zero or more.';

    // ---------------------------------------------------------------- examples: insert

    @IsTest
    static void insertSetsProbabilityFromStage() {
        Opportunity opp = new Opportunity(StageName = 'Value Proposition', Probability = 3);
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, null, TODAY);
        Assert.areEqual(50, opp.Probability);
    }

    @IsTest
    static void insertWithUnknownStageClearsProbability() {
        Opportunity opp = new Opportunity(StageName = 'Not A Stage', Probability = 40);
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, null, TODAY);
        Assert.isNull(opp.Probability);
    }

    @IsTest
    static void emptyListIsANoOp() {
        List<Opportunity> records = new List<Opportunity>();
        OpportunityStageHandler.beforeSave(records, null, TODAY);
        Assert.areEqual(0, records.size());
    }

    // ---------------------------------------------------------------- examples: update

    @IsTest
    static void stageChangeSetsProbability() {
        Opportunity old = new Opportunity(Id = fakeId(1), StageName = 'Prospecting', Probability = 10);
        Opportunity opp = new Opportunity(Id = fakeId(1), StageName = 'Negotiation/Review', Probability = 10);
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, new Map<Id, Opportunity>{ old.Id => old }, TODAY);
        Assert.areEqual(90, opp.Probability);
    }

    @IsTest
    static void unchangedStageKeepsAManualProbability() {
        Opportunity old = new Opportunity(Id = fakeId(1), StageName = 'Prospecting', Probability = 10);
        Opportunity opp = new Opportunity(Id = fakeId(1), StageName = 'Prospecting', Probability = 35);
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, new Map<Id, Opportunity>{ old.Id => old }, TODAY);
        Assert.areEqual(35, opp.Probability);
    }

    // ---------------------------------------------------------------- examples: Closed Won amount

    @IsTest
    static void closedWonWithoutAmountGetsAnError() {
        Opportunity opp = new Opportunity(StageName = 'Closed Won', CloseDate = TODAY);
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, null, TODAY);
        Assert.isTrue(opp.hasErrors());
        Assert.areEqual(AMOUNT_ERROR, opp.getErrors()[0].getMessage());
    }

    @IsTest
    static void closedWonWithNegativeAmountGetsAnError() {
        Opportunity opp = new Opportunity(StageName = 'Closed Won', Amount = -0.01, CloseDate = TODAY);
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, null, TODAY);
        Assert.isTrue(opp.hasErrors());
    }

    @IsTest
    static void closedWonWithZeroAmountIsAccepted() {
        Opportunity opp = new Opportunity(StageName = 'Closed Won', Amount = 0, CloseDate = TODAY);
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, null, TODAY);
        Assert.isFalse(opp.hasErrors());
    }

    @IsTest
    static void closedLostWithoutAmountIsAccepted() {
        Opportunity opp = new Opportunity(StageName = 'Closed Lost', CloseDate = TODAY);
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, null, TODAY);
        Assert.isFalse(opp.hasErrors());
    }

    // ---------------------------------------------------------------- examples: CloseDate

    @IsTest
    static void closingWithoutCloseDateStampsToday() {
        Opportunity old = new Opportunity(Id = fakeId(1), StageName = 'Negotiation/Review');
        Opportunity opp = new Opportunity(Id = fakeId(1), StageName = 'Closed Lost');
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, new Map<Id, Opportunity>{ old.Id => old }, TODAY);
        Assert.areEqual(TODAY, opp.CloseDate);
    }

    @IsTest
    static void closingKeepsAnExistingCloseDate() {
        Date agreed = Date.newInstance(2026, 9, 30);
        Opportunity opp = new Opportunity(StageName = 'Closed Won', Amount = 100, CloseDate = agreed);
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, null, TODAY);
        Assert.areEqual(agreed, opp.CloseDate);
    }

    @IsTest
    static void openStageLeavesCloseDateAlone() {
        Opportunity opp = new Opportunity(StageName = 'Qualification');
        OpportunityStageHandler.beforeSave(new List<Opportunity>{ opp }, null, TODAY);
        Assert.isNull(opp.CloseDate);
    }

    // ---------------------------------------------------------------- the real trigger (DML)

    @IsTest
    static void triggerRejectsClosedWonWithoutAmount() {
        Opportunity opp = new Opportunity(Name = 'No amount', StageName = 'Closed Won', CloseDate = TODAY);
        Database.SaveResult result = Database.insert(opp, false);
        Assert.isFalse(result.isSuccess());
        Assert.areEqual(AMOUNT_ERROR, result.getErrors()[0].getMessage());
    }

    @IsTest
    static void triggerStampsCloseDateWhenInsertedClosed() {
        // CloseDate is required, so this insert only succeeds because the trigger fills it in.
        Opportunity opp = new Opportunity(Name = 'Closed on insert', StageName = 'Closed Lost');
        insert opp;
        Opportunity saved = [SELECT CloseDate, Probability FROM Opportunity WHERE Id = :opp.Id];
        Assert.areEqual(Date.today(), saved.CloseDate);
        Assert.areEqual(0, saved.Probability);
    }

    // ---------------------------------------------------------------- the property harness

    @IsTest
    static void harnessAcceptsHandWrittenCases() {
        // Insert: every interesting stage, amount and close date at least once.
        OpportunityStageHarness.check(new List<Opportunity>{
            new Opportunity(StageName = 'Closed Won'),
            new Opportunity(StageName = 'Closed Won', Amount = -1),
            new Opportunity(StageName = 'Closed Won', Amount = 0, CloseDate = TODAY.addDays(-3)),
            new Opportunity(StageName = 'Closed Lost'),
            new Opportunity(StageName = 'closed won'),
            new Opportunity(StageName = null, Probability = 20),
            new Opportunity(Description = 'only a description')
        }, null, TODAY);

        // Update: stage unchanged, unchanged up to case, changed, and changed into a closed stage.
        List<Opportunity> olds = new List<Opportunity>{
            new Opportunity(Id = fakeId(1), StageName = 'Prospecting'),
            new Opportunity(Id = fakeId(2), StageName = 'Prospecting'),
            new Opportunity(Id = fakeId(3), StageName = 'Prospecting'),
            new Opportunity(Id = fakeId(4), StageName = 'Negotiation/Review')
        };
        List<Opportunity> news = new List<Opportunity>{
            new Opportunity(Id = fakeId(1), StageName = 'Prospecting', Probability = 33),
            new Opportunity(Id = fakeId(2), StageName = 'PROSPECTING', Probability = 33),
            new Opportunity(Id = fakeId(3), StageName = 'Qualification', Probability = 33),
            new Opportunity(Id = fakeId(4), StageName = 'Closed Won', Amount = 5)
        };
        OpportunityStageHarness.check(news, new Map<Id, Opportunity>(olds), TODAY);
    }

    @IsTest
    static void harnessAcceptsRandomInserts() {
        Rng rng = new Rng(20261023);
        for (Integer batch = 0; batch < 40; batch++) {
            OpportunityStageHarness.check(randomRecords(rng, rng.next(21), false), null, TODAY);
        }
    }

    @IsTest
    static void harnessAcceptsRandomUpdates() {
        Rng rng = new Rng(42);
        for (Integer batch = 0; batch < 40; batch++) {
            List<Opportunity> records = randomRecords(rng, rng.next(21), true);
            OpportunityStageHarness.check(records, randomOldMap(rng, records), TODAY);
        }
    }

    @IsTest
    static void harnessAcceptsFull200RecordChunks() {
        Rng rng = new Rng(200);
        OpportunityStageHarness.check(randomRecords(rng, 200, false), null, TODAY);
        List<Opportunity> records = randomRecords(rng, 200, true);
        OpportunityStageHarness.check(records, randomOldMap(rng, records), TODAY);
    }

    // ---------------------------------------------------------------- random inputs

    // Standard stages, case variants, near misses, empty and null.
    private static final List<String> STAGES = new List<String>{
        null, '', 'Prospecting', 'Qualification', 'Needs Analysis', 'Value Proposition',
        'Id. Decision Makers', 'Perception Analysis', 'Proposal/Price Quote', 'Negotiation/Review',
        'Closed Won', 'Closed Lost', 'closed won', 'CLOSED LOST', 'prospecting', 'Closed  Won', 'Not A Stage'
    };
    private static final List<Decimal> AMOUNTS = new List<Decimal>{ null, -1000000, -0.01, 0, 0.01, 1, 2500.50 };
    private static final List<Decimal> PROBABILITIES = new List<Decimal>{ null, 0, 10, 37, 100 };
    private static final List<Date> CLOSE_DATES = new List<Date>{ null, Date.newInstance(2020, 1, 1), TODAY.addDays(30) };

    /** Deterministic linear congruential generator, so a failing seed reproduces exactly. */
    private class Rng {
        private Long state;

        Rng(Long seed) {
            state = seed;
        }

        Integer next(Integer bound) {
            state = Math.mod(state * 1103515245L + 12345L, 2147483648L);
            return (Integer) Math.mod(state / 65536L, (Long) bound);
        }
    }

    private static List<Opportunity> randomRecords(Rng rng, Integer count, Boolean withIds) {
        List<Opportunity> records = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            records.add(randomOpportunity(rng, withIds ? fakeId(i + 1) : null));
        }
        return records;
    }

    /** An oldMap consistent with records: same Ids, separate records, stage often unchanged. */
    private static Map<Id, Opportunity> randomOldMap(Rng rng, List<Opportunity> records) {
        Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>();
        for (Opportunity record : records) {
            Opportunity old = randomOpportunity(rng, record.Id);
            if (rng.next(2) == 0) {
                old.StageName = record.StageName;
            }
            oldMap.put(record.Id, old);
        }
        return oldMap;
    }

    private static Opportunity randomOpportunity(Rng rng, Id recordId) {
        Opportunity opp = recordId == null ? new Opportunity() : new Opportunity(Id = recordId);
        if (rng.next(4) != 0) {
            opp.StageName = STAGES[rng.next(STAGES.size())];
        }
        if (rng.next(4) != 0) {
            opp.Amount = AMOUNTS[rng.next(AMOUNTS.size())];
        }
        if (rng.next(4) != 0) {
            opp.Probability = PROBABILITIES[rng.next(PROBABILITIES.size())];
        }
        if (rng.next(4) != 0) {
            opp.CloseDate = CLOSE_DATES[rng.next(CLOSE_DATES.size())];
        }
        if (rng.next(2) == 0) {
            opp.Name = 'Fuzz ' + rng.next(1000);
            opp.Description = 'must not change';
        }
        return opp;
    }

    private static Id fakeId(Integer n) {
        return (Id) ('006' + String.valueOf(n).leftPad(12, '0'));
    }
}
