# vcpkg-port-node

Build the **Node.js source tree** (including V8) into a **linkable library**, delivered as
**vcpkg overlay ports** — so a C++ project can embed Node.js without vendoring Node.js
itself.

```cmake
find_package(unofficial-node CONFIG REQUIRED)
target_link_libraries(my_app PRIVATE unofficial::node::node)
```

## Status

Early development: there is no release yet, no tag, and no stable interface.

| | |
|---|---|
| Node.js | v26.11.1 (v26 line) |
| vcpkg | 2026.07.29 (pinned) |
| Build route | `configure.py` → `gyp -f ninja` → `ninja` |
| Delivery | static library + CMake config, as overlay ports |

## Why an overlay port

V8 is a Node.js-maintained fork and Node.js offers no externalize channel for it, so the
Node.js source tree always has to be built here. That alone rules out a submission to the
curated vcpkg registry, which is why consumption is through `overlay-ports`.

Everything Node.js *does* let us externalize (`--shared-*`, `--with-intl=system-icu`) is
meant to come from vcpkg instead of the vendored copy, so a consumer's dependency graph
holds one version of each library rather than two. The current verdict for every dependency
is written up under `docs/`.

## Using it

```jsonc
// vcpkg-configuration.json in your project
{
  "overlay-ports": ["path/to/vcpkg-port-node/ports"]
}
```

```jsonc
// vcpkg.json in your project
{
  "dependencies": [
    { "name": "node", "features": ["tools"] }
  ]
}
```

The `tools` feature installs a `node` executable together with `npm` and `npx`;
`test-suite` installs the official Node.js test suite so a consumer can run it against its
own embedder binary.

Both the working example and the validation harness live in `test/`: `cmake --preset …`
followed by `ctest`.

*(`ports/` and `test/` land with their first real content — a directory in this repository
always arrives with something in it.)*

## Repository layout

| Path | Purpose |
|---|---|
| `ports/` | The overlay ports: `node` plus any dependency that has to be pinned or patched |
| `test/` | Consumer-side example project and the validation harness (ctest) |
| `tools/` | Maintenance scripts, including the version-tree hasher |
| `versions/` | vcpkg version file for the `node` port |
| `docs/` | Design notes, dependency disposition, build and CI reference |
| `docs/decisions/` | Architecture decision records |

## Documentation

- `docs/` — reference material, English, versioned with the code.
- `docs/decisions/` — why things are the way they are.
- `AGENTS.md` — working rules for this repository (useful for humans too).
- A full usage guide arrives with the first release.

## License

MIT — see `LICENSE`. Vendored and patched third-party code keeps its own license; the
corresponding NOTICE files are preserved.
