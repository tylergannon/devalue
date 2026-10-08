// Manually authored native-port inputs from devalue v5.9.4/test/{index,buffer}.test.js.
// All expected wire bytes are recorded by the pinned upstream package.
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { execFileSync } from 'node:child_process';
if (typeof globalThis.Float16Array !== 'function') {
  throw new Error('binary recording requires Node with Float16Array (use Node 26+); no cases may be skipped');
}
const constructors = [Int8Array, Uint8Array, Uint8ClampedArray, Int16Array,
  Uint16Array, Float16Array, Int32Array, Uint32Array, Float32Array, Float64Array,
  BigInt64Array, BigUint64Array, DataView];
const bytes = () => Uint8Array.from({length: 32}, (_, i) => i).buffer;
const view = (C, b, off, n) => new C(b, off, n);
const repeated = v => [v, v];
export const binaryValues = constructors.flatMap(C => {
  const w = C.BYTES_PER_ELEMENT ?? 1;
  return [
    [C.name+'_full', view(C, bytes(), 0, 32 / w)],
    [C.name+'_sub', view(C, bytes(), w, 2)],
    [C.name+'_empty_end', view(C, bytes(), 32, 0)],
    [C.name+'_empty_buffer', view(C, new ArrayBuffer(0), 0, 0)],
    [C.name+'_identity', (() => {
      const buffer = bytes(), v = view(C, buffer, w, 2);
      const root = {view:v, again:v, distinct:view(C, buffer, w, 2), buffer};
      root.self = root; return root;
    })()],
    [C.name+'_odd_explicit', view(C, Uint8Array.from({length: 33}, (_, i)=>i).buffer, 0, 1)],
  ];
});
binaryValues.push(
  ['uint8', new Uint8Array([1,2,3])],
  ['node_alloc', Buffer.alloc(4,65)],
  ['float64_negative_zero', new Float64Array([-0,1.5])],
  ['bigint64', new BigInt64Array([1n,-2n,3n])],
  ['biguint64', new BigUint64Array([1n,2n,3n])],
  ['dataview', new DataView(new Uint8Array([1,2,3]).buffer)],
  ['dataview_sub', new DataView(Uint8Array.from({length:10},(_,i)=>i).buffer,2,4)],
  ['uint16_sub', new Uint16Array([10,20,30,40]).subarray(1,3)],
  ['buffer_repeat_views', (()=>{const a=Uint8Array.from({length:10},(_,i)=>i);return [a,new Uint16Array(a.buffer)];})()],
  ['typed_repeat', repeated(Uint8Array.from({length:10},(_,i)=>i))],
  ['buffer_typed_repeat', (()=>{const a=Uint8Array.from({length:10},(_,i)=>i);return [a,a,new Uint16Array(a.buffer)];})()],
  ['data_repeat', repeated(new DataView(Uint8Array.from({length:10},(_,i)=>i).buffer))],
  ['buffer_data_repeat', (()=>{const b=Uint8Array.from({length:10},(_,i)=>i).buffer,v=new DataView(b);return [v,v,b];})()],
  ['data_sub_repeat', repeated(new DataView(Uint8Array.from({length:10},(_,i)=>i).buffer,2,4))],
  ['bigint_repeat', repeated(new BigInt64Array([1n,2n,3n]))],
  ['ordinary_shared', (()=>{const buffer=new Uint8Array([0,1,2,3,4,5]).buffer,view=new Uint8Array(buffer,1,3);return {buffer,view,again:view,data:new DataView(buffer,2,2)};})()],
  ['raw_float_bits', new Float64Array(new Uint8Array([1,0,0,0,0,0,248,127,0,0,0,0,0,0,0,128]).buffer)],
  ['empty_copy', Buffer.from('SECRET').subarray(3,3)],
  ['isolated_copies', (()=>{const allocation=Buffer.allocUnsafe(128).fill(255), first=allocation.subarray(8,11),second=allocation.subarray(24,26);first.set([1,2,3]);second.set([4,5]);const v={first,again:first,second};v.self=v;return v;})()],
  ['source_from', Buffer.from([1,2,3])],
  ['source_unsafe', (()=>{const b=Buffer.allocUnsafe(3);b.set([1,2,3]);return b;})()],
  ['source_concat', Buffer.concat([Buffer.from([1]),Buffer.from([2,3])])],
  ['source_slice', Buffer.from([255,1,2,3,255]).slice(1,4)],
  ['source_subarray', Buffer.from([255,1,2,3,255]).subarray(1,4)],
  ['source_unpooled', (()=>{const b=Buffer.alloc(32,255);b.set([1,2,3],8);return b.subarray(8,11);})()],
  ['source_arraybuffer', Buffer.from(new Uint8Array([255,1,2,3,255]).buffer,1,3)],
  ['source_vm', runInNewContext('Buffer.from([1,2,3])',{Buffer})],
);
// Native test reads the checked-in byte input rather than depending on Node.
export const fileInput = readFileSync(new URL('../../node_modules/devalue/package.json', import.meta.url));
binaryValues.push(['file_contents', {file:fileInput}]);
binaryValues.push(
  ['reduced_view', new Uint8Array([1,2,3]), {View:x=>x instanceof Uint8Array && 'payload'}],
  ['reduced_buffer', new Uint8Array([1,2,3]), {Raw:x=>x instanceof ArrayBuffer && 'payload'}],
);
// buffer.test.js fresh-process browser-path invariant. This is recording
// evidence only; native tests never start Node or supply browser globals.
export const browserWire = execFileSync(process.execPath, ['--input-type=module','--eval', `
  globalThis.Buffer = undefined;
  globalThis.process = undefined;
  const { stringify } = await import(${JSON.stringify(import.meta.resolve('devalue'))});
  console.log(stringify(new Uint8Array([1,2,3])));
`], {encoding:'utf8'}).trim();

// Shared empty storage must remain shared; an independent empty buffer must not.
binaryValues.push(['empty_shared', (() => {
  const buffer = new ArrayBuffer(0), view = new Uint8Array(buffer);
  const root = {buffer,view,again:view,distinct:new Uint8Array(buffer),
    data:new DataView(buffer),separate:new ArrayBuffer(0)};
  root.self=root; return root;
})()]);
binaryValues.push(['float16_values', new Float16Array(new Uint16Array([
  0,0x8000,0x3c00,0x0001,0x03ff,0x0400,0x7bff,0x7c00,0xfc00,0x7e01
]).buffer)]);
export const binaryExpressionValues = binaryValues.filter(([name]) =>
  name === 'empty_shared' || name === 'float16_values' ||
  name.startsWith('Float16Array_') && !name.endsWith('odd_explicit'));
// Preserve the 5.9.4 expression quirk; the corrected spelling is upstream 6.x.
const oddBuffer = new ArrayBuffer(3), oddView = new Uint16Array(oddBuffer,0,1);
binaryExpressionValues.push(['odd_alone', oddView], ['odd_shared', [oddView,oddBuffer]]);
