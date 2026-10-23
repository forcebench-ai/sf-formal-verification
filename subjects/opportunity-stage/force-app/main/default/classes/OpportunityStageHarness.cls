/**
 * Property harness for OpportunityStageHandler.beforeSave: the Apex counterpart of a fuzz entry
 * point. check() runs the handler on arbitrary inputs and asserts properties P1-P5. Any input
 * that makes it throw is a bug.
 *
 * The Lean statements in lean/Spec/ are authoritative. This class mirrors them so the same
 * properties can be exercised in a real org (Apex tests and difftest). It uses Apex semantics
 * throughout; for example, String == ignores case (docs/open-questions.md, Q1).
 *
 * Not part of the verified subject, so it may use constructs outside the modelled subset.
 */
public with sharing class OpportunityStageHarness {
    // The only fields beforeSave may change (P4).
    private static final Set<String> WRITABLE_FIELDS = new Set<String>{ 'Probability', 'CloseDate' };

    /**
     * Runs beforeSave(newList, oldMap, today) and asserts P1-P5. Mutates newList exactly as
     * beforeSave does. oldMap must be null (insert) or hold the previous version of every record
     * in newList (update).
     */
    public static void check(List<Opportunity> newList, Map<Id, Opportunity> oldMap, Date today) {
        List<Opportunity> before = copyAll(newList);
        List<Opportunity> sameRecords = new List<Opportunity>(newList);
        List<Opportunity> twice = copyAll(newList);

        Integer queries = Limits.getQueries();
        Integer dmlStatements = Limits.getDmlStatements();
        OpportunityStageHandler.beforeSave(newList, oldMap, today);

        // P1: reaching this line means no uncaught exception; no SOQL and no DML either.
        Assert.areEqual(queries, Limits.getQueries(), 'P1: beforeSave ran SOQL');
        Assert.areEqual(dmlStatements, Limits.getDmlStatements(), 'P1: beforeSave ran DML');

        // P4: the same records, in the same order.
        Assert.areEqual(before.size(), newList.size(), 'P4: list length changed');
        for (Integer i = 0; i < newList.size(); i++) {
            Assert.isTrue(newList[i] === sameRecords[i], 'P4: record ' + i + ' was replaced or moved');
        }

        for (Integer i = 0; i < newList.size(); i++) {
            Opportunity original = before[i];
            Opportunity result = newList[i];
            Opportunity old = oldMap == null ? null : oldMap.get(original.Id);
            Boolean insertedOrStageChanged = old == null || original.StageName != old.StageName;

            // P2: Probability follows the stage exactly when the record is new or its stage changed.
            Decimal expectedProbability = insertedOrStageChanged
                ? OpportunityStage.stageProbability(original.StageName)
                : original.Probability;
            Assert.areEqual(expectedProbability, result.Probability, 'P2: Probability of record ' + i);

            // P3: an error exactly when Closed Won with a null or negative Amount.
            Boolean expectError = original.StageName == 'Closed Won'
                && (original.Amount == null || original.Amount < 0);
            Assert.areEqual(expectError, result.hasErrors(), 'P3: errors on record ' + i);

            // P4: no field other than Probability and CloseDate changed.
            assertSameFields(original, result, WRITABLE_FIELDS, 'P4: record ' + i);
        }

        // P5: running twice gives the same records and errors as running once.
        OpportunityStageHandler.beforeSave(twice, oldMap, today);
        OpportunityStageHandler.beforeSave(twice, oldMap, today);
        for (Integer i = 0; i < newList.size(); i++) {
            assertSameFields(newList[i], twice[i], new Set<String>(), 'P5: record ' + i);
            Assert.areEqual(errorMessages(newList[i]), errorMessages(twice[i]), 'P5: errors on record ' + i);
        }
    }

    private static List<Opportunity> copyAll(List<Opportunity> records) {
        List<Opportunity> copies = new List<Opportunity>();
        for (Opportunity record : records) {
            copies.add(record.clone(true, true, false, false));
        }
        return copies;
    }

    private static void assertSameFields(SObject expected, SObject actual, Set<String> ignored, String context) {
        Map<String, Object> expectedFields = expected.getPopulatedFieldsAsMap();
        Map<String, Object> actualFields = actual.getPopulatedFieldsAsMap();
        Set<String> fields = new Set<String>(expectedFields.keySet());
        fields.addAll(actualFields.keySet());
        for (String field : fields) {
            if (!ignored.contains(field)) {
                Assert.areEqual(expectedFields.get(field), actualFields.get(field), context + ', field ' + field);
            }
        }
    }

    private static List<String> errorMessages(SObject record) {
        List<String> messages = new List<String>();
        for (Database.Error error : record.getErrors()) {
            messages.add(error.getMessage());
        }
        return messages;
    }
}
