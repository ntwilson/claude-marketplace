# Example Output: `.claude/pr-123-walkthrough.md`

This is what the skill writes for PR #123. It illustrates the plan list, chunk sizing (substantial logic one function at a time, trivia grouped across files), the deep-linked file reference on each chunk, inline concerns, an attached review comment, and the wrap-up. Examples of follow-up Q&A and comment posting follow the document.

Each chunk's file reference links to its exact line as `#diff-<sha256(path)>R<line>`, where the `R` number is the chunk's anchor line counted out of the hunk header. The 64-character hashes are elided to `…` below for readability; real output carries them in full.

---

# Walkthrough — PR #123 — Add weather distribution caching

Caches weather probability distributions in memory so repeated forecast-point analyses stop re-querying Hub. Adds cache key/entry types, a thread-safe cache module, a read-through path in the data assembly layer, and startup wiring with periodic eviction.

## Plan

1. **#1** — `CacheKey` and `CacheEntry` types — `OneInN/DataStructures.fs`
2. **#2** — `createCache` — `OneInN/CacheManager.fs`
3. **#3** — `tryGet` — `OneInN/CacheManager.fs`
4. **#4** — `set` — `OneInN/CacheManager.fs`
5. **#5** — `evictExpired` — `OneInN/CacheManager.fs`
6. **#6** — `retrieveDistribution` read-through path — `OneInN/DataAssembly.fs`
7. **#7** — Startup wiring — `OneInN/Program.fs`
8. **#8** — Cache behavior tests — `OneInN/CacheManagerSpec.fs`
9. **#9** — Project file and `open` additions — 3 files

---

## #1 — `CacheKey` and `CacheEntry` types

[`OneInN/DataStructures.fs:47`](https://github.com/mea/OneInN/pull/123/files#diff-4c1f…a9e0R47)

```diff
+type CacheKey =
+  | ForecastPointKey of ForecastPointId
+  | WeatherStationKey of WeatherStationId
+
+type CacheEntry<'T> = {
+  Value: 'T
+  CachedAt: Instant
+  ExpiresAt: Instant
+}
```

Everything downstream keys off these, so they come first: a DU so the two lookup kinds can't be confused for one another, and a generic entry carrying its own expiry rather than relying on a module-wide TTL.

---

## #2 — `createCache`

[`OneInN/CacheManager.fs:12`](https://github.com/mea/OneInN/pull/123/files#diff-8b73…16dcR12)

```diff
+let createCache () =
+  ConcurrentDictionary<CacheKey, CacheEntry<Distribution>>()
```

`ConcurrentDictionary` rather than a `Map` behind a lock, because reads dominate and the eviction pass is the only writer that touches many keys at once.

---

## #3 — `tryGet`

[`OneInN/CacheManager.fs:18`](https://github.com/mea/OneInN/pull/123/files#diff-8b73…16dcR18)

```diff
+let tryGet key (cache: Cache<'K,'V>) =
+  match cache.TryGetValue(key) with
+  | true, entry when entry.ExpiresAt > now() -> Some entry
+  | _ -> None
```

Treats an expired entry as a miss so callers never check freshness themselves — expiry stays entirely the cache's business.

⚠️ `now()` is called outside `io { }`, making `tryGet` non-deterministic and awkward to test. Taking the instant as a parameter, or returning `io<Option<'V>>`, would keep it honest.

**@alice** on line 20:
> Should this be taking the clock as a parameter?

---

## #4 — `set`

[`OneInN/CacheManager.fs:25`](https://github.com/mea/OneInN/pull/123/files#diff-8b73…16dcR25)

```diff
+let set key value ttl (cache: Cache<'K,'V>) =
+  let entry = { Value = value; CachedAt = now(); ExpiresAt = now() + ttl }
+  cache.[key] <- entry
```

Takes the TTL per call rather than fixing it in the module, so different lookup kinds can age out at different rates.

⚠️ `now()` is evaluated twice, so `CachedAt` and `ExpiresAt - ttl` can differ by a tick — harmless today, but it makes `CachedAt` an unreliable audit field.

---

## #5 — `evictExpired`

[`OneInN/CacheManager.fs:31`](https://github.com/mea/OneInN/pull/123/files#diff-8b73…16dcR31)

```diff
+let evictExpired (cache: Cache<'K, CacheEntry<'V>>) =
+  for kvp in cache do
+    if kvp.Value.ExpiresAt <= now() then
+      cache.TryRemove(kvp.Key) |> ignore
```

Bounds memory growth, since `tryGet` treating expired entries as misses doesn't actually remove them.

⚠️ Enumerating a `ConcurrentDictionary` while removing from it won't throw, but it can skip entries added during the pass. Acceptable for eviction — missed entries are caught next cycle — though snapshotting `cache.Keys` first would make it predictable.

---

## #6 — `retrieveDistribution` read-through path

[`OneInN/DataAssembly.fs:88`](https://github.com/mea/OneInN/pull/123/files#diff-2e50…7f31R88)

```diff
 let retrieveDistribution key (ctx: HubContext) = io {
-  return! queryDistribution key ctx
+  match CacheManager.tryGet key cache with
+  | Some entry -> return Ok entry.Value
+  | None ->
+    let! result = queryDistribution key ctx
+    result |> Result.iter (fun d -> CacheManager.set key d oneHour cache)
+    return result
 }
```

The single read-through point: this was the only place that queried Hub for distributions, so wrapping it here covers every caller without touching any of them.

⚠️ Only successful results are cached, which is right, but nothing bounds the cache size — a long-running process touching many forecast points grows without limit. An LRU cap or max-entry count would close that.

---

## #7 — Startup wiring

[`OneInN/Program.fs:23`](https://github.com/mea/OneInN/pull/123/files#diff-9a04…b5ffR23)

```diff
+let initializeCache () =
+  let cache = CacheManager.createCache()
+  let timer = new Timer(fun _ -> CacheManager.evictExpired cache)
+  timer.Change(TimeSpan.Zero, TimeSpan.FromMinutes(10.0)) |> ignore
+  cache
+
 let main argv =
+  let cache = initializeCache()
   ...
```

Creates the one process-wide cache and starts the eviction timer at 10 minutes — well under the 1-hour TTL, so expired entries never linger long.

⚠️ The `Timer` is never disposed and is rooted only by this local, so it can be collected mid-run and silently stop evicting.

---

## #8 — Cache behavior tests

[`OneInN/CacheManagerSpec.fs:9`](https://github.com/mea/OneInN/pull/123/files#diff-d7c8…3a12R9)

```diff
+let ``tryGet returns None for an expired entry`` () =
+  let cache = createCache()
+  set (ForecastPointKey id) dist (TimeSpan.FromTicks 1L) cache
+  test <@ tryGet (ForecastPointKey id) cache = None @>
+
+let ``tryGet returns the value before expiry`` () = ...
+let ``evictExpired removes only expired entries`` () = ...
```

Covers the three behaviors that would silently regress: expiry-as-miss, hit before expiry, and selective eviction.

⚠️ Expiry is tested with a 1-tick TTL rather than a controllable clock, which is the practical consequence of the `now()` coupling in **#3** — a stale-entry test can't be written without sleeping.

---

## #9 — Project file and `open` additions

[`OneInN/OneInN.fsproj:14`](https://github.com/mea/OneInN/pull/123/files#diff-fb61…08c7R14), [`OneInN/DataAssembly.fs:6`](https://github.com/mea/OneInN/pull/123/files#diff-2e50…7f31R6), [`OneInN/Program.fs:4`](https://github.com/mea/OneInN/pull/123/files#diff-9a04…b5ffR4)

```diff
+    <Compile Include="CacheManager.fs" />
+    <Compile Include="CacheManagerSpec.fs" />
```

```diff
+open System.Collections.Concurrent
+open OneInN.CacheManager
```

Mechanical: registers the new files in compilation order (after `DataStructures.fs`, before `DataAssembly.fs`) and adds the two `open`s the new call sites need.

---

## Wrap-up

That's the whole change — 9 chunks across 6 files.

Worth a second look before merging: the unbounded cache size (**#6**) and the uncollected timer (**#7**) are the two that could bite in a long-running process. The `now()` coupling in **#3**/**#4** is style rather than a bug, but it is what forces the tick-based expiry test in **#8**.

---

# Example follow-up Q&A

> User: "#3 does the expiry check use UTC?"

`now()` here is `MEA.Core.Time.now`, which returns a NodaTime `Instant` — always UTC, no local-time conversion. `ExpiresAt` is produced by `set` (**#4**) from the same function, so both sides of the comparison are UTC instants and there's no timezone hazard in the comparison itself. The testability concern on **#3** still stands.

> User: "#6 what happens on an error result?"

`Result.iter` only runs on `Ok`, so a failed Hub query caches nothing and the next call retries. That's the intended behavior — the gap is that there's no negative caching, so a persistently failing key re-queries Hub on every request.

> User: "compare #5 and #7 — is the eviction interval actually safe?"

`evictExpired` (**#5**) is only ever called by the timer in **#7**, at 10-minute intervals against a 1-hour TTL, so an expired entry lives at most ~10 extra minutes. Memory-wise that's fine. The real risk is the timer being collected (**#7**), after which nothing calls **#5** at all and expired entries accumulate for the life of the process — invisible, because `tryGet` keeps returning correct results the whole time.

---

# Example comment posting

> User: "#7 comment: this timer can be GC'd — nothing roots it but the local. Please hold it in a field or return it alongside the cache."

Queued on **#7** → `OneInN/Program.fs:26` (RIGHT). 1 comment in the queue.

> User: "#6 comment too: can we cap this? unbounded growth worries me for the Planner run"

Queued on **#6** → `OneInN/DataAssembly.fs:88–95` (RIGHT, multi-line). 2 comments in the queue.

---

# Example suggested change

The user describes the fix; the skill writes the code and shows it for approval before it enters the queue.

> User: "#7 suggest: hold the timer so it can't be collected"

Read the exact lines at the reviewed commit first:

```
pwsh -File ../../shared/scripts/show-lines.ps1 -Sha 4f2a1c9 -Path OneInN/Program.fs -Start 24 -End 27
```

```
    24    let cache = CacheManager.createCache()
    25    let timer = new Timer(fun _ -> CacheManager.evictExpired cache)
    26    timer.Change(TimeSpan.Zero, TimeSpan.FromMinutes(10.0)) |> ignore
    27    cache
```

Then present it — **not queued yet**:

````markdown
**Pending suggestion on #7** — `OneInN/Program.fs:24–27` (RIGHT) — *not queued yet*

Replacing lines 24–27, currently:

```fsharp
    let cache = CacheManager.createCache()
    let timer = new Timer(fun _ -> CacheManager.evictExpired cache)
    timer.Change(TimeSpan.Zero, TimeSpan.FromMinutes(10.0)) |> ignore
    cache
```

The comment body that would be posted:

> The `Timer` is rooted only by this local, so it can be collected mid-run and silently
> stop evicting. Returning it alongside the cache keeps it alive for the process lifetime.

```suggestion
    let cache = CacheManager.createCache()
    let timer = new Timer(fun _ -> CacheManager.evictExpired cache)
    timer.Change(TimeSpan.Zero, TimeSpan.FromMinutes(10.0)) |> ignore
    { Cache = cache; EvictionTimer = timer }
```

Say **queue it** to add this to the review, or tell me what to change.
````

The range is 24–27 rather than the whole chunk: only these four lines are being replaced, and all four appear in the block — the three unchanged ones included, since anything omitted from the range would be deleted on apply. Indentation matches the file exactly (four spaces), because GitHub applies leading whitespace literally.

> User: "make it a `use` binding so it gets disposed"

Reworked — still not queued:

````markdown
**Pending suggestion on #7** — `OneInN/Program.fs:24–27` (RIGHT) — *not queued yet*

```suggestion
    let cache = CacheManager.createCache()
    use timer = new Timer(fun _ -> CacheManager.evictExpired cache)
    timer.Change(TimeSpan.Zero, TimeSpan.FromMinutes(10.0)) |> ignore
    { Cache = cache; EvictionTimer = timer }
```

⚠️ Worth noting before you queue this: `use` disposes the timer when `initializeCache`
returns, which stops eviction immediately rather than at process exit. A field on a
long-lived record, or `main` holding it, is closer to what you described.

Say **queue it** to add this as-is, or tell me what to change.
````

> User: "good point, go with the record version"

Queued on **#7** → `OneInN/Program.fs:24–27` (RIGHT, suggestion). 3 comments in the queue.

---

# Example submission

> User: "submit the review"

Dry run — 3 comments to post as one review:

```
OneInN/Program.fs        L26     RIGHT
OneInN/DataAssembly.fs   L88-95  RIGHT
OneInN/Program.fs        L24-27  RIGHT  (suggestion)
```

Head SHA still `4f2a1c9`, matching the walkthrough. Submit?

> User: "yes"

Submitted review 4821866707 with 3 comments: `https://github.com/mea/OneInN/pull/123#pullrequestreview-4821866707`

Queue cleared.
