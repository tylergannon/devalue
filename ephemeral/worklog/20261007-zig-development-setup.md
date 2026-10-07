# Zig development setup

decision: User scoped the first phase to current Zig tooling and coding-agent research; flat codec implementation follows later, in a separate zig/ package in this repository.
friction: Homebrew zig resolves to 0.16.0-dev.2915+065c6e794 while stable 0.17.0 is available -> pin mise and use mise exec so agents do not silently use the old binary.
decision: Two Luna researchers found no inspected standalone skill verified for stable Zig 0.17 -> create compact original repository-local guidance grounded in installed source; retain candidate links in ephemeral/zig-development-research.md.
friction: mise's first Zig download mirror failed transiently; its fallback mirror installed 0.17.0 -> wait for installation completion before launching a dependent mise exec, which otherwise overlaps installation.
friction: Repository mise pin is not selected by plain zig in this shell -> use mise exec -- zig explicitly; the pinned compiler passed native allocator/JSON and allocation-failure smoke tests. Global shell/tool configuration was not changed.
