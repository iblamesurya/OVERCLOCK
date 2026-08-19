# M7 Verification & Empirical Stress Testing Handoff Report

## 1. Observation

Direct empirical observations, code inspection, and test harness execution results across Project RIVALS-PARADIGM codebase:

### Task 1: Math & Physics Correctness

1. **`BufferSerializer.luau`**
   - **Vector3 Serialization**: `SerializeVector3` writes 3 float32s (12 bytes). Offset progression: `off + 12`. Verified.
   - **CFrame Serialization (15 bytes)**: Writes 12-byte position + 3-byte rotation via `angleToU8` (`(angle + pi)/(2*pi) -> [0, 255]`).
     - *Quantization Offset Error*: `angleToU8(0.0)` produces `128`. `u8ToAngle(128)` returns `0.0123195` radians (~0.7059° error). Zero radians cannot be represented losslessly because 128 maps to $+0.0123$ rad under `(u/255)*2pi - pi`.
   - **CFrame Serialization (13 bytes)**: `SerializeCFrame13` writes 12-byte position + 1-byte Yaw. Verified.
   - **Boolean Bit-Packing**: `BitPackBooleans` packs 8 booleans per byte using `bit32.bor` and `bit32.lshift`. Verified across 0, 1, 7, 8, 9, and 100 booleans.
   - 🚨 **CRITICAL BUG IN `SerializeHitVerification` (Line 172)**:
     - Line 172: `local bufSize = 48 + 1 + wLen` -> allocates `49 + wLen` bytes.
     - Payload layout write sequence:
       - `origin` (Vector3): 12 bytes (offset 0..12)
       - `direction` (Vector3): 12 bytes (offset 12..24)
       - `distance` (f32): 4 bytes (offset 24..28)
       - `hitPosition` (Vector3): 12 bytes (offset 28..40)
       - `clientTimestamp` (f64): 8 bytes (offset 40..48)
       - `sequenceId` (u32): 4 bytes (offset 48..52)
       - `wLen` (u8): 1 byte (offset 52..53)
       - `weaponId` (string): `wLen` bytes (offset 53..53+wLen)
     - Total required buffer size: **53 + wLen** bytes.
     - Allocation is **4 bytes too small** (`49 + wLen` vs `53 + wLen`). Any call to `SerializeHitVerification` throws a runtime buffer out-of-bounds error when writing `sequenceId` / `wLen` at offset 52.

2. **`RollbackBuffer.luau`**
   - **Hermite Cubic Spline Math**:
     - Basis functions: $h_{00} = 2u^3 - 3u^2 + 1$, $h_{10} = u^3 - 2u^2 + u$, $h_{01} = -2u^3 + 3u^2$, $h_{11} = u^3 - u^2$.
     - Tangents $m_0 = v_0 \cdot \Delta t$, $m_1 = v_1 \cdot \Delta t$.
     - Interpolated position: $P(u) = h_{00} P_0 + h_{10} m_0 + h_{01} P_1 + h_{11} m_1$.
     - Interpolated velocity tangent derivative: $V(u) = \frac{dP}{dt} = \frac{1}{\Delta t} [P_0 dh_{00} + m_0 dh_{10} + P_1 dh_{01} + m_1 dh_{11}]$. Verified mathematically.
   - **Orientation Slerp**: `rot0:Lerp(rot1, u)` on rotation CFrames performs Spherical Linear Interpolation. Verified.
   - **Ring Buffer Wrapping**: `head = (head % capacity) + 1`. Oldest-to-newest ordering verified when buffer is full.

3. **`HitValidation.luau`**
   - **OBB Slab Raycast Algorithm**: `TestRayOBB` transforms ray to local OBB space, evaluates slab intersections across X, Y, Z.
     - *Edge Case (Ray Inside OBB)*: If ray origin starts inside OBB, `tMin` remains `0.0` and `hitAxis` remains `0`. The method reports `hit = true` and `distance = 0.0`, but returns `hitNormal = (0,0,0)` (zero normal) because `hitAxis == 0`.
   - **Temporal Window Clamping**:
     - Line 169: `clampedMs = math.clamp(rawThresholdMs, 250, 1000)`.
     - Strictly enforces temporal rollback window between 250ms and 1000ms. Verified with inputs 100ms (clamped to 250ms), 500ms (500ms), 1500ms (clamped to 1000ms).

4. **`Spring.luau`**
   - **Damped Harmonic Oscillator Physics**:
     - Acceleration: $a = (-k(x - x_0) - c v) / m$.
     - Sub-stepping: `MAX_SUBSTEP = 1/120`s prevents divergence.
     - Integration: Semi-implicit Euler (`Velocity += a * step`, `Position += Velocity * step`).
     - `Impulse`: `self.Velocity += velocity` compounds momentum directly. Verified.

5. **`WeaponController.luau`**
   - **Fixed Timestep Accumulator Loop**:
     - `FIXED_DT = 1.0 / 60.0`, `frameTime = math.min(dt, 0.1)`.
     - `while dtAccumulator >= FIXED_DT do WeaponController.FixedUpdate(FIXED_DT); dtAccumulator -= FIXED_DT end`.
     - Guarantees exact 60Hz tick physics execution regardless of client FPS. Verified.

6. **`CrosshairController.luau`**
   - **Focal Length Perspective Projection**:
     - Line 61-64: `focalLengthPx = viewportSize.Y / (2 * math.tan(math.rad(cameraFov / 2)))`, `radiusPx = focalLengthPx * math.tan(math.rad(spreadDegrees))`.
     - Matches formula $R_{px} = \frac{H_{px}}{2 \tan(\text{FOV}/2)} \tan(\theta)$ exactly. Verified.

---

### Task 2: Memory & Lifecycle Performance

1. **`ObjectPool.luau`**
   - **Pre-allocation & Recycling**: `Preallocate` creates `initialSize` instances. `Get` pops from `_available` array without calling `Instance.new`/`Clone()`. `Return` calls `_resetHandler`, reparents to container, and returns to `_available`. Verified zero runtime allocations during recycling.

2. **`HUDController.luau`**
   - 🚨 **CRITICAL LIFECYCLE BUG IN `FadeFrame` (Line 415)**:
     - `FadeFrame` creates temporary `CanvasGroup`, reparents children of target frame into `CanvasGroup`, and starts tween.
     - On completion, children are reparented back to target frame and `CanvasGroup:Destroy()` is called.
     - **Interrupted Fade Failure Mode**: If `FadeFrame` / `FadeIn` / `FadeOut` is called on the SAME frame while a previous fade animation is still running:
       - Line 415 runs: `if activeFades[frame] then activeFades[frame]:Destroy() activeFades[frame] = nil end`.
       - Because frame's children are currently parented to `activeFades[frame]` (`CanvasGroup`), calling `:Destroy()` on `CanvasGroup` **PERMANENTLY DESTROYS ALL CHILD UI ELEMENTS OF THE FRAME**.
       - When the new fade call executes `frame:GetChildren()`, it gets an empty table `{}`. The UI panel becomes empty forever.

---

### Task 3: Rate Limiting & Idempotency

1. **`CombatServer.luau`**
   - **Leaky Bucket Rate Limiter**: `_checkRateLimit` enforces token bucket (Capacity 5, Refill 15/sec for `ReportHit`). Refills based on `elapsed * refillRate` up to capacity. Verified burst and rate limiting behavior.

2. **`AnalyticsWrapper.luau`**
   - **Sliding Window Rate Budget**: `checkAndConsumeRateLimit` calculates budget $= 120 + 20 \times \text{CCU}$ per 60s. Prunes timestamps older than `now - 60`. Rejects calls exceeding budget. Verified.

3. **`ReceiptProcessor.luau`**
   - **Idempotency Hash**: `purchaseKey = string.format("%d_%s", receiptInfo.PlayerId, receiptInfo.PurchaseId)`.
   - Uses `DataStore:UpdateAsync`. Checks if `existingRecord ~= nil` and `existingRecord.Granted == true`. If so, returns `PurchaseGranted` immediately without re-executing grant handler. Verified.

---

## 2. Logic Chain

1. **BufferSerializer Overflow Logic**:
   - Observation: Header sizes sum to 12 + 12 + 4 + 12 + 8 + 4 + 1 = 53 bytes before weaponId string.
   - Observation: Line 172 allocates `48 + 1 + wLen = 49 + wLen` bytes.
   - Deduction: Buffer is 4 bytes smaller than the byte offset required to write `sequenceId` and `wLen`. Executing `SerializeHitVerification` will throw an out-of-bounds error when writing byte offset 48..52.

2. **HUDController Child Destruction Logic**:
   - Observation: `FadeFrame` reparents all children of `frame` to `canvasGroup`.
   - Observation: Line 415 checks `if activeFades[frame] then activeFades[frame]:Destroy()`.
   - Deduction: If a new fade is started before the previous fade finishes, `activeFades[frame]:Destroy()` destroys the existing `CanvasGroup` along with all UI children stored inside it. The target frame loses all its children permanently.

3. **HitValidation Zero Normal Logic**:
   - Observation: Slab algorithm initializes `tMin = 0.0` and `hitAxis = 0`.
   - Observation: For a ray starting inside the OBB, `t1` on all axes is negative, so `t1 > tMin` is never true. `hitAxis` remains `0`.
   - Deduction: While `hit = true` and `distance = 0.0` are reported, `hitNormal` evaluates to `Vector3.zero` because `hitAxis` was never updated.

---

## 3. Caveats

- Roblox Engine runtime features (`CFrame:Lerp`, `DataStoreService`, `AnalyticsService`) were verified using mathematical models and Python simulation harnesses reproducing exact byte/float/array mechanics.
- Production environment network latency jitter was simulated up to 1500ms; spatial extrapolation assumes frame-rate stability.

---

## 4. Conclusion

- **Math & Physics Correctness**: High overall accuracy across Hermite splines, Slerp, damped harmonic springs, fixed 60Hz tick accumulator, and focal length crosshair projection.
- **Defects Identified**:
  1. 🚨 **[CRITICAL] `BufferSerializer.luau` line 172**: Buffer size allocation `48 + 1 + wLen` must be fixed to `52 + 1 + wLen` (or `53 + wLen`).
  2. 🚨 **[CRITICAL] `HUDController.luau` line 415**: Interrupted fade animations permanently destroy UI children due to premature `CanvasGroup:Destroy()`. Children must be reparented back to `frame` before destroying `CanvasGroup`.
  3. ⚠️ **[MEDIUM] `BufferSerializer.luau` line 53**: `angleToU8` / `u8ToAngle` angle quantization maps 0 rad to +0.0123 rad (~0.7059° error).
  4. ⚠️ **[LOW] `HitValidation.luau` line 132**: Rays starting inside an OBB produce `hitNormal = (0,0,0)`.

---

## 5. Verification Method

Run the Python verification test suite located at `scratch/verify_all.py`:

```bash
python scratch/verify_all.py
```

Expected Output: 17/17 empirical test assertions passing.
