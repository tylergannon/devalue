// Additional flat-profile inputs not all faithfully representable in Go.
// Expected bytes are recorded by the same pinned JS import as the shared corpus.
export const zigValues = [
  ["distinct_empty", [[], [], new ArrayBuffer(0), new ArrayBuffer(0)]],
  ["date_identities", (() => { const d = new Date(0); return [d, d, new Date(0)]; })()],
  ["regexp_identities", (() => { const r = /x/; return [r, r, /x/]; })()],
  ["date_min", new Date(-8640000000000000)],
  ["date_max", new Date(8640000000000000)],
  ["date_year_zero", new Date("0000-01-01T00:00:00.000Z")],
  ["date_year_negative", new Date("-000001-01-01T00:00:00.000Z")],
  ["date_year_expanded", new Date("+010000-01-01T00:00:00.000Z")],
  ["sparse_max", Object.assign(Array(4294967295), {0: undefined, 42: "x", 4294967294: null})],
  ["unicode_controls", "\u0000\u0001\b\f\n\r\t\"\\<\u2028\u2029雪😀"],
  ["key_boundaries", {z: 1, "01": 2, "4294967294": 3, "4294967295": 4, "-1": 5, "1.0": 6, "2": 7, "0": 8, "😀": 9}],
  ...[1e-6,1e-7,1e20,1e21,Number.MIN_VALUE,Number.MAX_VALUE,9007199254740991,9007199254740992,1.0000000000000001e-7,0.0000010000000000000002,999999999999999900000,1.0000000000000001e21,9.999999999999997e-7,9.999999999999998e-8,99999999999999980000,100000000000000020000].map((v,i) => ["number_"+i,v]),
  ...[3,4,5,6].map(n=>["sparse_boundary_"+n,Object.assign(Array(n),{0:"x"})]),
  ["custom_self", (()=>{const f={};f.value={name:"self",ref:f};return f;})(), {Foo:x=>x?.value}],
  ["custom_mutual", (()=>{const f={kind:"foo"}; const b={kind:"bar"};f.value={name:"outer",ref:b};b.value={name:"inner",ref:f};return f;})(), {Foo:x=>x?.kind==="foo"&&x.value,Bar:x=>x?.kind==="bar"&&x.value}],
  ["custom_primitive", 42, {Answer:x=>x===42&&"forty-two"}],
  ["custom_name", 42, {"Name<\u2028":x=>x===42&&"forty-two"}],
];
