// Settles the behaviour docs/platform-model.md and docs/apex-subset.md mark "to be confirmed", so
// the semantics can be written to match. A probe, not difftest (see adderror.apex).
//
//   sf apex run -o sfv-dev -f tools/difftest/probes/semantics.apex | grep PROBE
//
// "->" is a value, "!!" is the type of an exception thrown. Non-ASCII characters are written as
// escapes so the file's encoding can't change what is tested.
//
// Observed: not yet run.

void p(String label, Object value) {
    System.debug('PROBE ' + label + ' -> ' + value);
}
void x(String label, Exception e) {
    System.debug('PROBE ' + label + ' !! ' + e.getTypeName());
}
void eqi(String a, String b) {
    System.debug('PROBE fold ' + a.escapeUnicode() + ' == ' + b.escapeUnicode() + ' -> ' + (a == b));
}

// Side effects, for evaluation order.
Decimal bump(Opportunity r, String label) {
    r.Description = (r.Description == null ? '' : r.Description) + label;
    return 1;
}
String bumpMsg(Opportunity r) {
    r.Description = 'evaluated';
    return 'message';
}
Decimal returnsInteger() {
    return 10;
}
Object identity(Decimal d) {
    return d;
}

Boolean nb = null;
Boolean nb2 = null;
Decimal nd = null;
Decimal nd2 = null;
Integer ni = null;
String ns = null;
String ns2 = null;
Date ndt = null;
Opportunity nr = null;
List<Opportunity> nl = null;
Map<Id, Opportunity> nm = null;

// --- Null in comparisons ---
try { p('dec null < 1', nd < 1); } catch (Exception e) { x('dec null < 1', e); }
try { p('dec null <= 1', nd <= 1); } catch (Exception e) { x('dec null <= 1', e); }
try { p('dec null > 1', nd > 1); } catch (Exception e) { x('dec null > 1', e); }
try { p('dec null >= 1', nd >= 1); } catch (Exception e) { x('dec null >= 1', e); }
try { p('1 < dec null', 1 < nd); } catch (Exception e) { x('1 < dec null', e); }
try { p('1 >= dec null', 1 >= nd); } catch (Exception e) { x('1 >= dec null', e); }
try { p('dec null < dec null', nd < nd2); } catch (Exception e) { x('dec null < dec null', e); }
try { p('dec null >= dec null', nd >= nd2); } catch (Exception e) { x('dec null >= dec null', e); }
try { p('int null < 1', ni < 1); } catch (Exception e) { x('int null < 1', e); }
try { p('int null >= 1', ni >= 1); } catch (Exception e) { x('int null >= 1', e); }
try { p('dec null == 1', nd == 1); } catch (Exception e) { x('dec null == 1', e); }
try { p('dec null != 1', nd != 1); } catch (Exception e) { x('dec null != 1', e); }
try { p('dec null == dec null', nd == nd2); } catch (Exception e) { x('dec null == dec null', e); }

// --- Null in Boolean operators ---
try { if (nb) { p('if null', 'then'); } else { p('if null', 'else'); } } catch (Exception e) { x('if null', e); }
try { p('!null', !nb); } catch (Exception e) { x('!null', e); }
try { p('null && true', nb && true); } catch (Exception e) { x('null && true', e); }
try { p('null && false', nb && false); } catch (Exception e) { x('null && false', e); }
try { p('true && null', true && nb); } catch (Exception e) { x('true && null', e); }
try { p('false && null', false && nb); } catch (Exception e) { x('false && null', e); }
try { p('null || true', nb || true); } catch (Exception e) { x('null || true', e); }
try { p('null || false', nb || false); } catch (Exception e) { x('null || false', e); }
try { p('true || null', true || nb); } catch (Exception e) { x('true || null', e); }
try { p('false || null', false || nb); } catch (Exception e) { x('false || null', e); }
try { p('null && null', nb && nb2); } catch (Exception e) { x('null && null', e); }
try { p('null == true', nb == true); } catch (Exception e) { x('null == true', e); }
try { p('null != true', nb != true); } catch (Exception e) { x('null != true', e); }
try { p('null == null (bool)', nb == nb2); } catch (Exception e) { x('null == null (bool)', e); }
try { Boolean r = false || nb; p('Boolean r = false || null', r); } catch (Exception e) { x('Boolean r = false || null', e); }

// --- String == and case folding ---
p('a == A', 'a' == 'A');
p('a != A', 'a' != 'A');
p('null == a', ns == 'a');
p('a == null', 'a' == ns);
p('null != a', ns != 'a');
p('null == null (str)', ns == ns2);
p('empty == null', '' == ns);
p('a_space == a', 'a ' == 'a');
p('a.equals(A)', 'a'.equals('A'));
eqi('É', 'é');           // E acute, upper and lower
eqi('ß', 'SS');               // sharp s against its full uppercase
eqi('ß', 'ẞ');           // sharp s against capital sharp s
eqi('ſ', 's');                // long s folds onto ASCII?
eqi('ſ', 'S');
eqi('K', 'k');                // Kelvin sign folds onto ASCII?
eqi('K', 'K');
eqi('ı', 'I');                // dotless i
eqi('ı', 'i');
eqi('İ', 'i');                // dotted capital I
eqi('İ', 'I');
eqi('σ', 'ς');           // Greek sigma, medial and final
eqi('Σ', 'ς');
eqi('ǅ', 'ǆ');           // titlecase digraph
eqi('ﬁ', 'FI');               // fi ligature
eqi('𐐀', '𐐨'); // Deseret: code points or UTF-16 units?
eqi('Cloſed Won', 'Closed Won');
eqi('Іd. Decision Makers', 'Id. Decision Makers'); // Cyrillic I must not match
Map<String, Integer> byName = new Map<String, Integer>{ 'a' => 1 };
p('Map<String> get A', byName.get('A'));

// --- Decimal and Integer ---
p('1.0 == 1.00', 1.0 == 1.00);
p('1 == 1.0', 1 == 1.0);
p('0 == 0.00', 0 == 0.00);
Decimal d10 = 10;
p('Decimal d = 10', d10);
p('Decimal d = 10 is Decimal', ((Object) d10) instanceof Decimal);
p('Decimal d = 10 is Integer', ((Object) d10) instanceof Integer);
p('Decimal d = 10 scale', d10.scale());
p('1.10', 1.10);
p('1.10 scale', (1.10).scale());
p('return 10 as Decimal is Decimal', ((Object) returnsInteger()) instanceof Decimal);
p('return 10 as Decimal scale', returnsInteger().scale());
p('Integer arg to Decimal param is Decimal', identity(5) instanceof Decimal);
p('-0.01 < 0', -0.01 < 0);
p('0.00 < 0', 0.00 < 0);

// --- Dates and Ids ---
Date dt1 = Date.newInstance(2026, 1, 2);
Date dt2 = Date.newInstance(2026, 1, 2);
p('date == same date', dt1 == dt2);
p('date == null', dt1 == ndt);
p('null date == null', ndt == null);
Id id18 = '006000000000001AAA';
Id id15 = '006000000000001';
p('Id 18 == Id 15', id18 == id15);
p('Id 15 reads as', id15);
Id idUpper = '006000000000001AAA';
Id idOtherCase = '006000000000001aaa';
p('Id suffix case == ', idUpper == idOtherCase);

// --- sObject fields ---
Opportunity r1 = new Opportunity();
p('unset field', r1.StageName);
p('unset populated size', r1.getPopulatedFieldsAsMap().size());
r1.StageName = null;
p('explicit null reads', r1.StageName);
p('explicit null populated size', r1.getPopulatedFieldsAsMap().size());
p('explicit null populated', r1.getPopulatedFieldsAsMap());
Opportunity r2 = new Opportunity();
r2.StageName = '  spaced  ';
p('string field not trimmed', '[' + r2.StageName + ']');
r2.StageName = '';
p('empty string field', r2.StageName == null ? 'became null' : 'stayed empty');
r2.Amount = 1.23456;
p('Amount scale in memory', r2.Amount);
r2.Probability = 10;
p('Probability = 10', r2.Probability);
p('Probability = 10 is Decimal', ((Object) r2.Probability) instanceof Decimal);
r2.Probability = 33.333;
p('Probability scale in memory', r2.Probability);
r2.STAGENAME = 'upper';
p('field name case', r2.stagename);
Opportunity alias = r2;
alias.Name = 'through alias';
p('aliasing', r2.Name);
try { p('read field of null', nr.StageName); } catch (Exception e) { x('read field of null', e); }
try { nr.StageName = 'x'; p('write field of null', 'no exception'); } catch (Exception e) { x('write field of null', e); }

// --- sObject == ---
Opportunity same1 = new Opportunity(Name = 'x');
Opportunity same2 = new Opportunity(Name = 'x');
Opportunity diff = new Opportunity(Name = 'y');
p('sObject == equal fields', same1 == same2);
p('sObject == different fields', same1 == diff);
p('sObject == null', same1 == nr);
p('null sObject == null', nr == null);

// --- Maps ---
Map<Id, Opportunity> m = new Map<Id, Opportunity>{ id18 => same1 };
p('map get hit', m.get(id18) === same1);
p('map get 15 char', m.get(id15) === same1);
p('map get other case', m.get(idOtherCase) === same1);
Id otherId = '006000000000002AAA';
p('map get missing', m.get(otherId));
Id nullId = null;
try { p('map get null key', m.get(nullId)); } catch (Exception e) { x('map get null key', e); }
try { p('null map get', nm.get(id18)); } catch (Exception e) { x('null map get', e); }

// --- Lists and loops ---
try { for (Opportunity o : nl) { p('null list', 'iterated'); } p('null list', 'no exception'); } catch (Exception e) { x('null list', e); }
List<Opportunity> withNull = new List<Opportunity>{ null, new Opportunity() };
try {
    Integer seen = 0;
    for (Opportunity o : withNull) {
        seen++;
        p('null element ' + seen, o);
    }
} catch (Exception e) { x('null element', e); }
List<Opportunity> two = new List<Opportunity>{ new Opportunity(), new Opportunity() };
Integer iteration = 0;
for (Opportunity o : two) {
    iteration++;
    Decimal scoped;
    p('redeclared local, iteration ' + iteration, scoped);
    scoped = 5;
}

// --- Evaluation order ---
Opportunity log = new Opportunity();
try { nr.Amount = bump(log, 'rhs'); } catch (Exception e) { x('null.F = f()', e); }
p('null.F = f() evaluated f', log.Description);
log = new Opportunity();
try { nr.addError(bumpMsg(log)); } catch (Exception e) { x('null.addError(f())', e); }
p('null.addError(f()) evaluated f', log.Description);
log = new Opportunity();
try { p('f() < null', bump(log, 'l') < nd); } catch (Exception e) { x('f() < null', e); }
p('f() < null evaluated f', log.Description);
log = new Opportunity();
try { p('null < f()', nd < bump(log, 'r')); } catch (Exception e) { x('null < f()', e); }
p('null < f() evaluated f', log.Description);
log = new Opportunity();
p('left to right', (bump(log, 'a') < bump(log, 'b')) + ' ' + log.Description);

// --- addError ---
String nullMsg = null;
try { Opportunity r = new Opportunity(); r.addError(nullMsg); p('addError(null) hasErrors', r.hasErrors()); p('addError(null) errors', r.getErrors()); } catch (Exception e) { x('addError(null)', e); }
try { nr.addError('m'); p('null.addError', 'no exception'); } catch (Exception e) { x('null.addError', e); }
Opportunity withError = new Opportunity();
withError.addError('m');
withError.Name = 'after';
p('field write after addError', withError.Name + ' ' + withError.hasErrors());
p('errors have fields', withError.getErrors()[0].getFields());

// --- addError during DML, through the deployed trigger (rolled back) ---
Savepoint sp = Database.setSavepoint();
Database.SaveResult bad = Database.insert(
    new Opportunity(Name = 'probe', StageName = 'Closed Won', CloseDate = Date.today()), false);
p('DML closed won no amount success', bad.isSuccess());
p('DML closed won no amount errors', bad.getErrors().size());
Database.rollback(sp);
