# horizon-shader

Sources of **Petalveil**, a shader pack for [Horizon](https://github.com/horizon-rust/horizon) (WGSL, shader API 0.1).

- `pack/` — the pack itself (`horizon-shaders.toml` + `.wgsl`), the folder Horizon loads.
- `.opencode/NOTES.md` — notes for agents working here (tooling, API gotchas, local loop).

## Check and package

The checker is Horizon's own tool; it is not installed system-wide, build it once:

```sh
git clone --filter=blob:none https://github.com/horizon-rust/horizon.git /tmp/opencode/horizon
cd /tmp/opencode/horizon && cargo build -p horizon-shader-api --bin horizon-shader
```

Then, from this folder:

```sh
/tmp/opencode/horizon/target/debug/horizon-shader check pack
/tmp/opencode/horizon/target/debug/horizon-shader pack pack --out petalveil-0.1.0.hshader
```

## Live in the game

`pack/` is symlinked into the instance's `shaderpacks/`, and Horizon reloads a pack within half a second of every
save: edit, save, look. Pick it on **Options > Horizon Settings > Shader Packs**.

```sh
ln -sfn "$PWD/pack" ~/.local/share/horizon/shaderpacks/petalveil
horizon-launcher packs on --kind shader "Petalveil"
```
