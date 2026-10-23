// How addError accumulates on an in-memory sObject (docs/platform-model.md, Errors; open question Q4).
// A probe, not difftest: it records what the reference org does so the model can be designed to
// match. Difftest (milestone 2) replaces it with generated vectors run on both sides.
//
//   sf apex run -o sfv-dev -f tools/difftest/probes/adderror.apex | grep PROBE
//
// Observed on 2026-10-23, sfv-dev (Developer Edition, USA840), API 68.0:
//   PROBE record same,same -> 1 [same]
//   PROBE record one,two -> 1 [two]
//   PROBE record Same,same -> 1 [same]
//   PROBE record one,two,three -> 1 [three]
//   PROBE field x,x -> 1 [Name: x]
//   PROBE field x,y -> 1 [Name: y]
//   PROBE fields Name,Amount -> 2 [Amount: x, Name: x]
//   PROBE record,field -> 2 [same, Name: same]
// That is: one error per target (the record, or one field), and the last call wins. getErrors() is
// not in call order (Name's error was added first in the Name,Amount case).
//
// Not covered: addError inside a trigger during DML, which is what the subject does. Difftest must
// confirm the same behaviour there.

String show(SObject record) {
    List<String> parts = new List<String>();
    for (Database.Error e : record.getErrors()) {
        parts.add((e.getFields().isEmpty() ? '' : String.join(e.getFields(), ',') + ': ') + e.getMessage());
    }
    return record.getErrors().size() + ' [' + String.join(parts, ', ') + ']';
}

Opportunity a = new Opportunity();
a.addError('same');
a.addError('same');
System.debug('PROBE record same,same -> ' + show(a));

Opportunity b = new Opportunity();
b.addError('one');
b.addError('two');
System.debug('PROBE record one,two -> ' + show(b));

Opportunity c = new Opportunity();
c.addError('Same');
c.addError('same');
System.debug('PROBE record Same,same -> ' + show(c));

Opportunity d = new Opportunity();
d.addError('one');
d.addError('two');
d.addError('three');
System.debug('PROBE record one,two,three -> ' + show(d));

Opportunity e = new Opportunity();
e.Name.addError('x');
e.Name.addError('x');
System.debug('PROBE field x,x -> ' + show(e));

Opportunity f = new Opportunity();
f.Name.addError('x');
f.Name.addError('y');
System.debug('PROBE field x,y -> ' + show(f));

Opportunity g = new Opportunity();
g.Name.addError('x');
g.Amount.addError('x');
System.debug('PROBE fields Name,Amount -> ' + show(g));

Opportunity h = new Opportunity();
h.addError('same');
h.Name.addError('same');
System.debug('PROBE record,field -> ' + show(h));
