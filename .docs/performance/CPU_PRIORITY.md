# CPU priority — desktop over dev workloads

> Companion to [VIDEO_PLAYBACK.md](./VIDEO_PLAYBACK.md) (frame drops) and
> [MEMORY_PRESSURE.md](./MEMORY_PRESSURE.md) (the RAM equivalent of the same problem).

## The problem

Background agents running tests inside VS Code — vitest workers at ~100% CPU each on a
16-core/22-thread 155H — pushed browser video from 7/900 dropped frames (0.78%) into double
digits while a video was playing.

**The decoder is never the victim.** Video decode runs on the GPU video engine and is
untouched by CPU load; `drm-engine-video` keeps climbing normally throughout. What starves is
the CPU-side work that *feeds* the compositor — Gecko's render thread and the 120 Hz composite
— against an **8.3 ms per-frame budget**. Frames then arrive late and YouTube counts them as
dropped, which reads as a decode problem and is not one.

## What lives where

Verified via `/proc/<pid>/cgroup`. The useful fact: **everything VS Code spawns stays in its
scope** — extension host, Claude Code extension, integrated-terminal shells, npm/npx, and
vitest workers all resolve to `app-code-<pid>.scope`. One weight covers the entire dev
workload class without naming individual tools, and keeps working for whatever runs next.

```
user@1000.service
├── app.slice                       100
│   ├── app-code-<pid>.scope         20   VS Code + extension host + vitest + dev servers
│   ├── app-zen-<pid>.scope         100   Zen, when launched normally
│   └── app-dbus-*.slice            100   idle daemons
├── session.slice                   300
│   ├── wayland-wm@hyprland.service 300   Hyprland + apps it spawns directly
│   ├── kitty-<pid>-0.scope         100   terminals
│   └── pipewire / portals / dbus   100
└── background.slice                 30
```

## The trap: weights only compare siblings

Setting `app-code-*.scope` to `CPUWeight=20` **on its own does almost nothing.** cgroup weights
are proportional *between siblings only*, and `app.slice`'s other members are idle dbus
daemons — so under contention `app.slice` still won its full top-level share and VS Code
consumed nearly all of it.

The decision has to be made one level up, between `app.slice` and `session.slice`. That is what
the `session.slice` weight is for: at 300 vs 100 the session takes ~75% under contention
instead of ~50%.

The layered result:

| Comparison | Ratio | Protects |
|---|---|---|
| `session.slice` vs `app.slice` | 300 : 100 | compositor's frame budget |
| Zen vs VS Code, inside `app.slice` | 100 : 20 | entertainment over dev work |
| compositor vs terminals, inside `session.slice` | 300 : 100 | compositing over shell |

## Files

| Drop-in | Setting |
|---|---|
| `systemd/user/app-code-.scope.d/50-cpuweight.conf` | `CPUWeight=20`, `IOWeight=50` |
| `systemd/user/session.slice.d/50-cpuweight.conf` | `CPUWeight=300` |
| `systemd/user/wayland-wm@.service.d/50-cpuweight.conf` | `CPUWeight=300` |

`app-code-.scope.d` matches every transient `app-code-<pid>.scope` — systemd resolves drop-ins
by the truncated prefix. The same directory already carries `MemoryHigh=9G`.

## Weights, not caps

`CPUWeight` binds **only under contention**. Dev work still gets the entire machine when
nothing else wants it; interactive VS Code use is unaffected on an idle box. This is
deliberately not `CPUQuota`, which is a hard ceiling and would slow builds for no benefit when
there is nothing to protect.

## Applying and verifying

Drop-ins take effect for units started afterwards. For an already-running unit:

```sh
systemctl --user daemon-reload
systemctl --user set-property --runtime app-code-<pid>.scope CPUWeight=20 IOWeight=50
systemctl --user set-property --runtime session.slice CPUWeight=300
systemctl --user set-property --runtime wayland-wm@hyprland.desktop.service CPUWeight=300
```

`--runtime` avoids writing a second copy of the config into `~/.config/systemd/user.control/`,
which would then shadow the tracked drop-ins.

**Verify against the kernel, never against the unit file** — read `cpu.weight` directly:

```sh
B=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service
cat "$B/session.slice/cpu.weight" "$B/app.slice/cpu.weight" \
    "$B/app.slice/app-code-"*".scope/cpu.weight"
```

Find which cgroup any process is actually in:

```sh
cat /proc/<pid>/cgroup | grep '^0::' | cut -d: -f3
```

## Interaction with sched_ext

`scx_lavd` (latency-aware virtual deadline) is the active scheduler via `scx_loader`, and
already biases toward interactive tasks — which is why this only became visible under
saturation. The cgroup weights are a coarser, explicit backstop for the case lavd cannot
resolve alone: many CPU-bound workers all demanding cores simultaneously.

## Gotcha: launch method decides the cgroup

A process inherits the cgroup of whoever spawned it. Launching Zen from a terminal (or from an
agent shell) puts it in that `kitty-<pid>-0.scope` rather than its own `app-zen-*.scope`, so it
silently gets terminal priority instead of app priority. Launch GUI apps via their `.desktop`
entry or `uwsm app` to land in `app.slice`. Check with the `/proc/<pid>/cgroup` command above
before concluding a weight "isn't working".
