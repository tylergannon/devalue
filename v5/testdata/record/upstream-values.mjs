// Native-port inputs from devalue v5.9.4/test/index.test.js common fixtures.
// Deferred features are listed in ephemeral/zig-upstream-test-coverage.md.
// This is fixture recording tooling, never run by native tests.
const primitive = [
  ['integer_positive',42], ['integer_negative',-5], ['decimal_positive',0.1],
  ['decimal_negative',-0.1], ['nan',NaN], ['infinity_positive',Infinity],
  ['infinity_negative',-Infinity], ['zero',0], ['negative_zero',-0],
  ['string','woo!!!'], ['boolean',true], ['bigint',1n],
  ['undefined',undefined], ['null',null],
];
const repeated = v => [v,v];
const danger = "</script><script src='https://evil.com/script.js'>alert('pwned')</script><script>";
const regex = () => /[</script><script>alert('xss')//]/;
class Foo { constructor(value) { this.value = value; } }
class Bar { constructor(value) { this.value = value; } }
class FunctionRef { constructor(fn) { this.fn = fn; } }
const nested = new Foo({bar:new Bar({answer:42})});
const fn = (x) => x * 2;
export const upstreamValues = [
  ...primitive.map(([name,v])=>['primitive_'+name,v]),
  ...primitive.slice(0,12).map(([name,v])=>['boxed_'+name,Object(name==='integer_negative'?-2:v)]),
  ['regexp',/regexp/gim], ['date',new Date(1e12)], ['array',['a','b','c']],
  ['array_zero',[0,-0]], ['array_empty',[]], ['array_sparse',[,'b',,]],
  ['array_very_sparse',Object.assign(Array(1000001),{1000000:'x'})],
  ['array_multi_sparse',Object.assign(Array(21),{10:'a',20:'b'})],
  ['object',{foo:'bar','x-y':'z'}], ['set',new Set([1,2,3])],
  ['map',new Map([['a','b']])], ['buffer',new Uint8Array([1,2,3]).buffer],
  ...[['newline','a\nb'],['quotes','"yar"'],['surrogate_pair','𝌆'],
      ['nul','\0'],['control','\u0001'],['control_extreme','\u001f'],
      ['backslash','\\']].map(([name,v])=>['string_'+name,v]),
  ['cycle_map',(()=>{const v=new Map();v.set('self',v);return v;})()],
  ['cycle_set',(()=>{const v=new Set();v.add(v);v.add(42);return v;})()],
  ['cycle_array',(()=>{const v=[];v[0]=v;return v;})()],
  ['cycle_object',(()=>{const v={};v.self=v;return v;})()],
  ['cycle_null_object',(()=>{const v=Object.create(null);v.self=v;return v;})()],
  ['cycle_class_equivalent',(()=>{const v={foo:'bar'};v.self=v;return v;})()],
  ['cycle_mutual',(()=>{const x={},y={};x.second=y;y.first=x;return [x,y];})()],
  ['repeat_string',repeated('a string')], ['repeat_null',repeated(null)],
  ['repeat_nan',repeated(NaN)], ['repeat_number_box',repeated(Object(42))],
  ['repeat_bigint_box',repeated(Object(1n))], ['repeat_nan_box',repeated(Object(NaN))],
  ['repeat_object',repeated({})], ['repeat_map',repeated(new Map())],
  ['repeat_set',repeated(new Set())], ['repeat_regexp',repeated(/regexp/)],
  ['repeat_date',repeated(new Date(1e12))],
  ['repeat_map_key',(()=>{const shared={id:1};return [shared,new Map([[shared,'v']])];})()],
  ['interlinked_map_keys',(()=>{const n=[{id:1},{id:2},{id:3}];return new Map(n.map((key,i)=>[key,new Map(n.filter((_,j)=>j!==i).map(k=>[k,1]))]));})()],
  ['xss_string',danger], ['xss_key',{'<svg onload=alert("xss_works")>':'bar'}],
  ['xss_regexp',regex()], ['xss_regexp_repeat',repeated(regex())],
  ['null_object_empty',Object.create(null)], ['plain_object_empty',{}],
  ['enumerable_object',{x:1}],
  ['null_object_keys',Object.assign(Object.create(null),{'':'empty',0:'numeric',constructor:'constructor',toString:'toString'})],
  ['custom_nested',[nested,nested],{Foo:x=>x instanceof Foo&&x.value,Bar:x=>x instanceof Bar&&x.value}],
  ['function_wrapped',new FunctionRef(fn),{FunctionRef:x=>x instanceof FunctionRef&&x.fn.toString()}],
  ['function_nested',{fn,nested:{data:42}},{FunctionRef:x=>typeof x==='function'&&x.toString()}],
  // Reproduce previously hand-written expectations through the pinned recorder.
  ['native_alias_cycle',(()=>{const a=['<hi>\n😀',undefined];const v={first:a,alias:a};v.self=v;return v;})()],
  ['native_boxed_variants',[Object(42),Object('hi'),Object(0n),Object(-0)]],
  ['native_builtins',(()=>{const o=Object.assign(Object.create(null),{x:1});const m=new Map([['k',o]]);m.set(m,m);const s=new Set([-0,0,NaN,NaN]);s.add(s);return [-123456789012345678901n,new Date(-1),/a\/b\n/my,new Uint8Array([0,255]).buffer,Object(false),o,m,s];})()],
];
