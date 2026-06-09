# Learning Log — Week 3
## Register Renaming, the ROB, and First Verilog

## Theory: What I Actually Understood

### Tags Become Physical Registers

The first thing that clicked was realising that Tomasulo and modern register renaming are *the same algorithm with different labels*. In Tomasulo, a "tag" meant "reservation station #7 is computing this value." In modern processors, a "tag" means "physical register P#34 will hold this value." Both are just unique identifiers for an in-flight result. The dependency tracking works exactly the same way.

What changes is *where the value lives*. In Tomasulo it sits inside the RS until it's broadcast. In the modern approach it goes straight into the Physical Register File (PRF) when execution finishes, and reservation stations just hold an *index* into that file. This decoupling is what lets you scale to 300+ in-flight instructions — the PRF can be big without making every RS huge.

The key numbers to remember for PRAVAH:
- 32 architectural registers (what the programmer sees)
- 48 physical registers (actual hardware storage)
- 16 "spare" physical registers = the free list at any point

### The Rename Map and Free List

These two structures sit at the heart of dispatch:

**Rename Map** — a 32-entry table saying "architectural register R is currently living in physical register P." On reset it's identity (R0→P0, R1→P1, ...). Every time an instruction writes to R3, we pop a fresh physical register from the free list, point R3 at it, and note down what R3 was pointing to before (the "old physical dest").

**Free List** — a queue of physical registers nobody is using right now. On reset it holds P32 through P47 (the 16 extras). Dispatch pops from the front. Commit pushes to the back. If it's empty, the pipeline stalls.

The thing that surprised me: the rename map is *not* touched at commit time. It already reflects the speculative state from dispatch. Commit just makes that state permanent by freeing the old physical register.

### The ROB

We're not building it this week but I had to understand it because the rename unit produces an output (`disp_rd_old_phys_o`) that only exists so the ROB can use it later for rollback. Without understanding the ROB I would have had no idea why that port even exists.

Three things the ROB gives you that Tomasulo lacked:

1. **Precise exceptions** — if instruction 5 faults, instructions 6 and 7 may have already finished executing, but they haven't committed. The ROB can flush them cleanly and restore the rename map by walking backwards through the "old physical dest" fields. The processor state looks exactly like only instructions 1–4 ran.

2. **Branch recovery** — same mechanism. Flush everything younger than the mispredicted branch, restore mappings, restart fetch.

3. **In-order commit** — execution is chaotic and out-of-order, but graduation is always in program order. This is what makes the processor debuggable.

The "old physical dest" field in each ROB entry is the breadcrumb trail that makes rollback possible. If I3 maps R3 → P3 (new) and saves P6 as the old mapping, then flushing I3 means restoring R3 → P6. Without saving P6 at dispatch time, you can't go back.

### The Worked Example

Tracing through I1/I2/I3 with only 8 physical registers and 2 spares made free-list pressure feel concrete. The pipeline actually *stalled* at I3 because both spare registers were consumed and nothing had committed yet. This was not a bug — it's a real structural hazard that happens in production processors when the free list runs dry. The fix is always the same: wait for something to commit and return a register.

The WAW dissolution also became obvious here. I1 and I3 both write R3 but get P6 and P3 respectively. The rename map always points to the right one. No stall needed at issue.

---


### Verilog-2001 Rules as stated for deliverables.

The toolchain constraint is strict: Quartus + ModelSim Starter doesn't reliably handle SystemVerilog. So:
- `.v` files only, not `.sv`
- `reg` and `wire`, not `logic`
- `always @(posedge clk)` for sequential, `always @*` for combinational
- No `always_ff`, no `always_comb`, no `enum`, no packed structs

The `logic` keyword looks harmless but causes cross-tool inconsistency bugs that are genuinely hard to trace. It's not worth it.

### Blocking vs Non-blocking — This One Really Matters

In sequential blocks (`always @(posedge clk)`): use `<=` (non-blocking). All assignments schedule simultaneously; none see each other's updates within the same time step.

In combinational blocks (`always @*`): use `=` (blocking). Assignments take effect immediately in sequence, which is what you want when computing next-state logic.

Mixing these up is the most common cause of "simulation passes but synthesis breaks" or "results differ between simulators." I set a personal rule: if I'm inside a `posedge clk` block, every single assignment gets `<=`. No exceptions.

### Register File — What I Built

4 read ports, 2 write ports, 1 allocate port. Each register has a value field and a ready bit.

The design decision that tripped me up initially: why does *allocation* clear the ready bit while *writing* sets it? It felt backwards. Then it clicked  allocation happens at dispatch (the computation hasn't started yet), writing happens at execution completion. Ready = 1 means "there is a valid result here." Clearing it on allocation says "I've claimed this slot but nothing's in it yet."

The bypass logic was tedious to write (8 nearly-identical assign statements for 4 read ports × 2 write ports) but the logic is simple: if a write and a read target the same address this cycle, the read immediately returns the new data. Without this, back-to-back write-then-read to the same register would see stale data for one cycle.

### Rename Unit — The Subtle Bits

The free list is a circular FIFO, not a stack. This matters because a just-freed physical register should go to the back of the queue, not immediately be re-issued. Using a FIFO gives recently-freed registers time to "cool down" before reuse, which avoids edge cases with long-tail in-flight readers.

The `stall_o` signal is purely combinational — it's just `(fl_count == 0) & disp_valid & disp_writes_rd`. This means at the start of a cycle where fl_count is 0, stall is 1 even if a commit is also happening that cycle. The commit's +1 only registers on the next clock edge. The spec explicitly says this one-cycle bubble is acceptable.

Same-cycle dispatch and commit: the fl_count update handles both cleanly in one line:
```verilog
fl_count <= fl_count - (do_dispatch ? 1 : 0) + (do_commit ? 1 : 0);
```
If both happen, count stays the same. If only one happens, count changes by 1. Simple and correct.

---

## Problems I Hit During Compilation and Simulation

### 1. "Failed to open design unit file in read mode" in ModelSim
**What happened:** ModelSim couldn't find my `.v` files.
**Why:** I was running `vlog register_file.v` without first `cd`-ing to the folder where the files lived. ModelSim was looking in whatever directory it defaulted to on startup.
**Fix:** Always run `cd "E:/your/folder"` in the transcript before any `vlog` command. Then use `pwd` to confirm you're in the right place.

### 2. "Execution of vlib.exe failed" 
**What happened:** `vlog` crashed immediately.
**Why:** I hadn't run `vlib work` first. ModelSim needs a simulation library to compile into before it can do anything.
**Fix:** The correct order every session is: `vlib work` → `vmap work work` → `vlog` → `vsim`.

### 3. ModelSim asking "Are you sure you want to quit?"
**What happened:** The simulation finished but ModelSim popped a quit confirmation dialog.
**Why:** The testbench calls `$finish` at the end, which with the `-c` flag signals ModelSim to close entirely. ModelSim asks for confirmation before doing so.
**Fix:** Either click No (your results are already printed above in the transcript). I mistakenlu pressed yes due to which my modelsim crashed i have to reinstall it.

### 4. Quartus "Can't fit design in device" / "Can't place 242 pins"
**What happened:** Full compilation in Quartus failed with pin placement errors.
**Why:** I accidentally added the testbench (`tb_register_file.v`) to the Quartus project. Quartus tried to synthesize it as real hardware. The testbench has hundreds of signals → Quartus ran out of physical pins on the FPGA .It requires 242 pins which it could not provide because I haven't added any fitter.
**Fix:** I choose a new fitter with maximum pin capacity to be 360 after which it compiled successfully.

### 5. NativeLink error — "Can't launch ModelSim-Altera software"
**What happened:** Clicking "Run Simulation" inside Quartus gave a path error.
**Why:** Quartus didn't know where ModelSim was installed — the NativeLink path was blank.
**Fix :** Just open ModelSim directly from the Start menu and run everything from its transcript. I used the command as given in week 3 pdf.

### 6. Test 7 in tb_rename_unit failing — "expected 1, got 0"
**What happened:** The simultaneous dispatch + commit test was checking `stall` in the same cycle as both events, expecting it to be 0.
**Why:** `stall_o` is combinational and based on `fl_count` at the *start* of the cycle. When fl_count = 0 and commit arrives in the same cycle, stall is still 1 that cycle — the commit's +1 hasn't clocked in yet. This is correct RTL behaviour, not a bug.
**Fix:** The testbench was wrong. Rewrote Test 7 to check `stall` on the *next* cycle after the simultaneous event, when fl_count has properly updated to 1. The RTL needed no changes.

### 7. Latch inferred warning in combinational blocks
**What happened (potential):** Quartus warns "inferring latch for signal X."
**Why:** If an `always @*` block doesn't assign a signal in every branch, the synthesiser infers a latch to "hold" the previous value. Latches in synchronous designs are almost always bugs.
**Fix:** Assign a default value at the top of every combinational block before the `if`/`case` statements. Every signal that gets conditionally assigned must also have an unconditional default.

### 8. Reset not working
**What happened (potential):** After reset de-asserts, the rename map still shows garbage.
**Why:** Either the reset logic was inside an `always @*` block (won't work — needs to be clocked) or the for-loop inside reset wasn't iterating correctly.
**Fix:** Reset must be synchronous and inside `always @(posedge clk)`. The for-loop that initialises the rename map and free list must cover the full range (0 to NUM_ARCH_REGS-1 for the map, 0 to FREE_LIST_SZ-1 for the free list).

---

## What Actually Clicked This Week

- The equivalence between Tomasulo tags and physical register indices. 
- Why the ready bit lives in the PRF and not in the RS. The RS just holds an index; the PRF is the source of truth for both values and readiness.
- That `$display` in RTL files will silently cause synthesis to fail or misbehave. It's not just a style preference — it literally cannot become hardware.

---


