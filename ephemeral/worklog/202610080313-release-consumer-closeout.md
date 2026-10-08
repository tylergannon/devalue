# Release and consumer status closeout

doc_bug: The main AGENTS.md still says v5 is untagged after v5.0.0 was published and proxy-verified. Update release and consumer state from live publication evidence so later sessions start at skgo migration rather than repeat completed work.
friction: Restoring the prior archived release worktree returned archive-cleanup-pending -> created a separate managed closeout worktree from origin/main; no old checkout content was discarded.

friction: A fresh no-replace consumer was queried before its new module checksums were populated; implicit go mod download added only the module-file sum -> explicitly download the pinned polytype and devalue versions before generation. Both unsuccessful setup attempts and the passing run are retained; no assertions were weakened.
decision: Polytype PR #163 merged at 3e5e40c and the release workflow published v1.5.0. Public proxy origins match that commit and devalue v5.0.0 at f4c94b9. The fresh consumer regenerates, verifies exact wire and typed decoding with no replaces, and installs the published CLI; its source/result is retained here and attached to the polytype release. Production skgo migration and v6 parity remain next work.
