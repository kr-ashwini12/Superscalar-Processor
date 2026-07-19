# PRAVAH — Retrospective

## What was the single hardest concept?

 Tomasulo's algorithm as a whole — specifically seeing how wakeup/select, register renaming, and in-order commit have to work together rather than as separate pieces. Or: the intra-bundle bypass, where slot B's decode must see slot A's rename result within the same cycle. Or: reasoning about the ROB's head/tail pointer arithmetic under wraparound.


>

## What was the hardest bug?

 **silent floating-port bugs at integration time.**

During Quartus synthesis and ModelSim integration, `pravah_top` was found to have several submodule ports left unconnected — `reservation_station`'s `alloc_en1_i` / `alloc_addr1_i` / `alloc_en2_i` / `alloc_addr2_i`, and `dispatch`'s `rs_full_i`. Each of these ports existed for a real reason (preventing the reservation station from prematurely marking a just-allocated destination register as ready; gating dispatch when the reservation station is full) but simply weren't wired up in the top-level instantiation.

**Symptom:** all three IPC benchmarks (independent, chain, mixed) reported `Instructions committed: 0` against an expected 16, with the simulation timing out after 400 cycles and `x16 final value: 0`.

**Root cause:** an unconnected input port in Verilog reads as `x` (unknown) in simulation. Because the reservation station's ready-bit logic and the dispatch eligibility logic both AND these floating signals into their core decision (`~alloc_en1_i & ...`, `... & ~rs_full_i`), a single `x` propagated through and poisoned every downstream ready/eligibility computation — nothing could ever cleanly resolve to "ready" or "eligible," so no instruction ever issued or committed.

**How it was found:** ModelSim's own `[TFMPC]` ("Too few port connections") warnings at elaboration time named the exact missing ports and the exact instance — `Missing connection for port 'alloc_en1_i'`, `Instance: /tb_pravah_perf/dut/u_rs`. Reading these warnings line-by-line (rather than dismissing them as noise) pointed directly at the fix: connect each floating port to the signal it was semantically supposed to observe (in this case, the same allocation signals already feeding the physical register file's alloc ports).

**Lesson:** simulator port-connection warnings are not cosmetic — an unconnected input is functionally equivalent to injecting `x` into your design, and `x` propagates through `&`/`~` operations in ways that silently defeat entire subsystems without ever throwing a hard error.

>

## What surprised you?

 how much harder integration is than building individual modules in isolation — modules that pass their own unit tests can still fail together over a single unconnected wire.
>

## What do you understand now that you didn't 8 weeks ago?

- How register renaming eliminates WAW/WAR hazards by giving every instruction's destination a fresh physical register, decoupling the architectural register namespace from physical storage.
- How Tomasulo's algorithm lets instructions execute out of program order (as soon as operands are ready) while still committing results in program order (via the ROB), which is what makes out-of-order execution invisible to software.
- Why an unconnected port is a silent, propagating failure in Verilog rather than a compile error — and why reading every synthesizer/simulator warning matters.

>
