# PRAVAH — Week 7 Performance Report

## 1. IPC Results

| Benchmark    | Instructions Committed | First Commit Cycle  | Last Commit Cycle  | End-to-End IPC  | Steady-State IPC |
|--------------|:----------------------:|:-------------------:|:------------------:|:---------------:|:------------------:|
| Independent  |       16 / 16          |        3            |        10          |       1.6       |     2.0            |
| Chain        |       16 / 16          |        3            |        18          |       0.889     |     1.0            |
| Mixed        |       16 / 16          |        3            |        11          |       1.4545    |     1.7778         |

- End-to-end IPC = committed / last_commit_cycle
- Steady-state IPC = committed / (last_commit_cycle − first_commit_cycle + 1)

---

## 2. Quartus Synthesis Summary

| Metric                    | Value |
|---------------------------|-------|
| Target device             | MAX 10 (10M50DAF484C7G) |
| Clock constraint (.sdc)   | 20.000 ns (50 MHz) |
| Fmax (Slow 1200mV 85C)    |  85.8  |
| Total logic elements      |  332   |
| Total registers           |  139   |
| Total pins                |  125   |


---

## 3. Gap Analysis

The independent benchmark’s IPC of _1.6____ falls short of the 2.0 ceiling primarily due to the single commit port : when both ROB slots become committable together, only one physical register is freed per cycle, throttling the rate at which the free list can supply new destinations to dispatch. The chain’s IPC of __0.889___ sits close to the expected 1.0 floor — since every instruction depends on its immediate predecessor, the second issue slot is never used regardless of machine width, and the small shortfall below 1.0 is attributable to the 1-cycle wakeup-to-issue latency (a producer’s result written back in cycle T can only wake its consumer in cycle T+1). The mixed benchmark’s IPC of __1.7778___ reflects the program’s partial instruction-level parallelism — some sections behave like the independent case, others like the chain case.
