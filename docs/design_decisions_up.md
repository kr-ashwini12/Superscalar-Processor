# PRAVAH Design Decisions
---
## Pipeline width

| Parameter      | Value | Rationale |
|----------------|-------|-----------|
| Fetch width    | 2     | Matches issue width; simplifies dispatch logic |
| Decode width   | 2     | 1-to-1 with fetch |
| Rename width   | 2     | One rename per dispatched instruction |
| Dispatch width | 2     | Fills both ALU RS slots in one cycle |
| Issue width    | 2     | Fixed for PRAVAH (2 ALUs) |
| Commit width   | 2     | Prevents ROB fill-up during good runs |
---
## Register file

| Parameter             | Value | Rationale |
|-----------------------|-------|-----------|
| Architectural regs    | 32    | RV32I |
| Physical regs (PRF)   | 48    | 32 + 16 in-flight margin |
| Free list size        | 16    | = 48 − 32 |
| Read ports            | 4     | 2 for ALU0 (rs1, rs2), 2 for ALU1 |
| Write ports           | 2     | One per ALU, no contention |
| Allocate ports        | 2     | One per dispatch slot |

The PRF uses **per-register ready bits** (one bit per phys reg). Reservation stations snoop these bits combinationally to detect when their sources are ready. Write-before-read bypass returns same-cycle write data on a read.
---

## Reservation stations

| Parameter    | Value | Rationale |
|--------------|-------|-----------|
| ALU RSs      | 4     | 2× issue width; absorbs a 2-cycle dispatch bubble |
| MUL RSs      | 2     | MUL is rare; 2 entries cover typical in-flight depth |
| LSU RSs      | 2     | Blocking LSU; 2 entries sufficient |
| **Total**    | **8** | Typical small-machine ratio |

Rationale for total: 8 entries (= 4 ALU + 2 MUL + 2 LSU) matches the ROB depth of 8, ensuring no RS can become the sole bottleneck. Deeper RS arrays provide diminishing returns for our 13-instruction ISA subset and small test programs.
---

## Reorder buffer

| Parameter         | Value | Rationale |
|-------------------|-------|-----------|
| Depth             | 8     | Small but sufficient to expose OoO behaviour |
| Dispatch ports    | 2     | Matches dispatch width |
| Mark-ready ports  | 2     | Matches FU count (ALU0, ALU1) |
| Commit ports      | 2     | Matches commit width |

The ROB enforces **in-order commit** even when execution is out-of-order. Each entry stores `{valid, ready, writes_rd, arch_dest, phys_dest, old_phys}`. On commit, `old_phys` returns to the rename unit's free list.
---

## Functional units

| FU       | Count | Latency      | Notes |
|----------|-------|--------------|-------|
| ALU      | 2     | 1 cycle (combinational) | ADD/SUB/AND/OR/XOR/SLL/SRL/SLT/ADDI |
| MUL      | 1     | 3-cycle pipelined | **Module built and standalone-verified (16/16 tests). Awaiting top-level integration; see `docs/integration_plan.md`.** |
| LSU      | 1     | 1-cycle blocking | **Module built (`lsu.v` + `dmem.v`). Awaiting top-level integration; see `docs/integration_plan.md`.** |

`mul.v`, `lsu.v`, and `dmem.v` are all in `rtl/` and compile clean. They are not yet wired into `pravah_top.v` in the baseline. The integration steps are to be documented in `docs/integration_plan.md` in case you are planning to do.
---

## Branch predictor

| Parameter              | Value | Rationale |
|------------------------|-------|-----------|
| Predictor type         | 2-bit saturating counter BHT | Standard; handles loop exit without double-mispredict |
| BHT entries            | 256   | Indexed by PC[9:2]; sufficient for small test programs |
| BTB                    | None  | Omitted for simplicity; predict-taken branches pay 1 extra cycle for target computation |
| Resolution stage       | EX    | Branch outcome known after ALU compute |
| Misprediction handling | ROB flush of all younger entries; restart fetch from correct PC |

The baseline PRAVAH executes only straight-line code. Branches and JAL are decoded and ROB-allocated, but the front-end keeps fetching PC+8 regardless. **All test programs use only ALU and ADDI instructions.**
---
## ISA subset

PRAVAH supports these RV32I instructions:

**Arithmetic / Logical (executes):**
- `ADD`, `SUB`, `ADDI`
- `AND`, `OR`, `XOR`
- `SLL`, `SRL`
- `SLT`

**Memory:**
- `LW`, `SW`

**Control flow:**
- `BEQ`, `BNE`, `JAL`

---

## Memory model

| Parameter | Value |
|-----------|-------|
| Instruction memory | 1 KB (256 32-bit words), `$readmemh`-initialized in testbench |
| Data memory | 1 KB, single-port (when LSU is added) |
| Cache hierarchy | None — memories are flat |
| Memory latency | 1 cycle combinational read |
---