// Maps every generated value through the pinned devalue package and writes the
// golden. Run after `go run ./devalue/testdata/record`; see README.md.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { stringify, uneval } from "devalue";

import { values } from "./values.mjs";
import { zigValues } from "./zig-values.mjs";
import { upstreamValues } from "./upstream-values.mjs";
import { binaryValues, binaryExpressionValues, fileInput, browserWire } from "./binary-values.mjs";

const here = dirname(fileURLToPath(import.meta.url));

// The golden is only evidence of parity with the pinned release, so refuse to
// record from any other installed version.
const pinned = JSON.parse(readFileSync(join(here, "..", "..", "package.json"), "utf8"))
  .devDependencies.devalue;
const installed = installedVersion();
if (installed !== pinned) {
  throw new Error(`installed devalue ${installed} is not the pinned ${pinned}; run pnpm install in this module`);
}

const seen = new Set();
const cases = values.map(([name, value]) => {
  if (seen.has(name)) throw new Error(`duplicate case name ${name}`);
  seen.add(name);
  return { name, devalue: stringify(value), uneval: uneval(value) };
});
writeFileSync(
  join(here, "..", "golden.json"),
  JSON.stringify({ devalue: installed, cases }, null, 2) + "\n",
);
process.stdout.write(`wrote ${cases.length} cases from devalue ${installed}\n`);


// Every module regenerates its binary expectations from its own installed pin.
const moduleBinaryCases = binaryValues.map(([name,value,reducers]) =>
  ({name,devalue:stringify(value,reducers)}));
moduleBinaryCases.push({name:'browser_uint8',devalue:browserWire});
writeFileSync(join(here,'..','binary-golden.json'),
  JSON.stringify({devalue:installed,cases:moduleBinaryCases},null,2)+'\n');
const expressionCases = binaryExpressionValues.map(([name,value]) => {
  try { return {name,uneval:uneval(value)}; }
  catch(error) { return {name,error:error.message}; }
});
writeFileSync(join(here,'..','binary-uneval-golden.json'),
  JSON.stringify({devalue:installed,cases:expressionCases},null,2)+'\n');
writeFileSync(join(here,'..','binary-file-input.txt'),fileInput);
process.stdout.write(`wrote ${moduleBinaryCases.length} binary and ${expressionCases.length} binary expression cases from devalue ${installed}\n`);

const zigCases = zigValues.map(([name, value, reducers]) => ({ name, devalue: stringify(value, reducers) }));
writeFileSync(join(here, "..", "..", "..", "zig", "testdata", "flat-golden.json"),
  JSON.stringify({ devalue: installed, cases: zigCases }, null, 2) + "\n");
process.stdout.write(`wrote ${zigCases.length} Zig profile cases from devalue ${installed}\n`);

const upstreamCases = upstreamValues.map(([name, value, reducers]) => ({ name, devalue: stringify(value, reducers) }));
writeFileSync(join(here, "..", "..", "..", "zig", "testdata", "upstream-flat-golden.json"),
  JSON.stringify({ devalue: installed, cases: upstreamCases }, null, 2) + "\n");
process.stdout.write(`wrote ${upstreamCases.length} upstream-native cases from devalue ${installed}\n`);

const binaryCases = binaryValues.map(([name, value, reducers]) => ({ name, devalue: stringify(value, reducers) }));
binaryCases.push({name: "browser_uint8", devalue: browserWire});
writeFileSync(join(here, "..", "..", "..", "zig", "testdata", "binary-golden.json"),
  JSON.stringify({ devalue: installed, cases: binaryCases }, null, 2) + "\n");
writeFileSync(join(here, "..", "..", "..", "zig", "tests", "binary-file-input.txt"), fileInput);
process.stdout.write(`wrote ${binaryCases.length} binary cases from devalue ${installed}\n`);

// installedVersion reads the version of the devalue package that the import
// above resolved to. Its exports map hides package.json, so walk up from the
// resolved entry point.
function installedVersion() {
  let dir = dirname(fileURLToPath(import.meta.resolve("devalue")));
  for (;;) {
    const file = join(dir, "package.json");
    if (existsSync(file)) {
      const pkg = JSON.parse(readFileSync(file, "utf8"));
      if (pkg.name === "devalue") return pkg.version;
    }
    const parent = dirname(dir);
    if (parent === dir) throw new Error("cannot find the installed devalue package.json");
    dir = parent;
  }
}
