# Astra skill evaluation

Observed 54 trial records. Planned total: 54. Model: gpt-6-astra. Reasoning: high.

This accepted sample includes 3 separate retries of invalid original runs. The [original records](original-results.json) and [retry records](retry-results.json) are preserved separately. The table below describes the accepted sample only.

Each cell is **passed / observed (valid runs)**. Missing runs are shown below.

| Case | Baseline | Corrected | Pruned |
|---|---:|---:|---:|
| chaining | 3/3 (3 valid) | 3/3 (3 valid) | 3/3 (3 valid) |
| channel | 3/3 (3 valid) | 3/3 (3 valid) | 3/3 (3 valid) |
| otp | 3/3 (3 valid) | 3/3 (3 valid) | 3/3 (3 valid) |
| polling | 3/3 (3 valid) | 3/3 (3 valid) | 3/3 (3 valid) |
| refactor | 3/3 (3 valid) | 3/3 (3 valid) | 3/3 (3 valid) |
| sandbox | 3/3 (3 valid) | 3/3 (3 valid) | 3/3 (3 valid) |

Medians below include valid runs only. Metric sample counts and per-case medians are in [evidence.json](evidence.json).

| Condition | Passed / valid | Invalid or unknown | Missing | Median seconds | Median input tokens | Median output tokens | Median total tokens |
|---|---:|---:|---:|---:|---:|---:|---:|
| baseline | 18/18 | 0 | 0 | 66.8 | 91,667.5 | 1,054.5 | 93,117 |
| corrected | 18/18 | 0 | 0 | 86.3 | 143,342.5 | 1,286.5 | 145,310 |
| pruned | 18/18 | 0 | 0 | 103.5 | 149,225 | 1,610 | 151,319 |

Controls:

| Case | Seed failed and reference passed with tests observed |
|---|---|
| chaining | yes |
| channel | yes |
| otp | yes |
| polling | yes |
| refactor | yes |
| sandbox | yes |

Limitations:

- Six audit-selected tasks and three planned repetitions per condition give limited evidence, not a held-out generalization result.
- Guidance was loaded explicitly. These trials do not measure skill discovery or routing.
- Baseline has common task and verification instructions. It is not an instruction-free model.
- Missing records are not counted as failures. Invalid agent runs are reported separately from valid-run pass counts.
- Time and token medians use valid runs with available metrics, including valid runs that failed grading. Total tokens are input plus output, without subtracting cached input. They are not a billing estimate.
- Hidden checks cover the stated cases, not every possible implementation defect. Controls establish that these checks distinguish the seed from the reference.

Input provenance:

- [results](<results.json>) SHA-256 `18c41f651821f37a27597f961ffc07f52389e493392e89ea4d9e00a1b5c1c6ae`
- [controls](<controls.json>) SHA-256 `a9eca3de29afea6e9830f967df93cd3ca329dd44e9385d567a544b1784591f48`
- [protocol](<protocol.json>) SHA-256 `b753a9b029c05e7bd721eb7f11d470c9a8abe21fa80c3d50a03b2ffac551fa2e`
- [frozen_inputs](<manifest.json>) SHA-256 `56921906c667d593b9f27dd2e9d4183348e64e88c77a4e0d1deb7aee0a63e785`
- [control_inputs](<controls_manifest.json>) SHA-256 `e22a26e983b2076f6c26e0bce8b6fc980666e40999bffda0b9efb84197510d81`

[Machine-readable evidence](evidence.json) includes individual trial records, control records, and the recorded protocol.
