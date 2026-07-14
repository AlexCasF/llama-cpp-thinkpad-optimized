# Agent-workload benchmark — 2026-07-14

## Status

The full 5-variant × 10-request matrix was intentionally not completed. With
two VMware guests active, a single long-context request reduced free physical
RAM to about 632 MB. The run was stopped to avoid paging or destabilizing the
host. Stopping the pinned server restored about 24 GB free RAM.

## Transcript-derived hypotheses

The two recipe transcripts recommended testing:

- MoE placement with `--n-cpu-moe`.
- `--no-mmap` for page-fault avoidance; excluded here because it is unsafe with
  a 21.7 GB model plus VMware on a 32 GB machine.
- Decode thread count, leaving CPU headroom for GPU scheduling.
- Physical ubatch size for prompt processing; generation speed should remain
  comparatively flat.
- Prompt-prefix caching and `--cache-reuse 256` for agent turns.
- KV compression; this pinned build supports q4/q4 but not TurboQuant q4/q3.
- `--mlock` for long-run residency; excluded because it can starve Windows and
  VMware.
- Speculative decoding; excluded because the transcript reports a regression
  for this MoE/SSM architecture.
- REAP/pruned models; excluded because the tested GGUF is not a REAP artifact.

## Planned variants

All variants keep 128K context, q4/q4 KV, mmap, one slot, 99 GPU layers,
`--cache-ram 128`, and the same request sequence.

| Variant | CPU MoE | Threads | Batch / ubatch | Flash |
|---|---:|---:|---:|---|
| baseline-1024 | 36 | 6 / 7 batch | 1024 / 1024 | on |
| threads-7 | 36 | 7 / 7 batch | 1024 / 1024 | on |
| moe35 | 35 | 6 / 7 batch | 1024 / 1024 | on |
| prefill-1536 | 36 | 6 / 7 batch | 2048 / 1536 | on |
| flash-auto | 36 | 6 / 7 batch | 1024 / 1024 | auto |

Each sequence uses nested prompts of approximately 100, 500, 1,000, 2,000,
3,000, 5,000, 7,000, 8,000, 9,000, and 10,000 tokens, with 64 generated
tokens per request. The memory-safe harness restarts the server every two
requests, preserving only a two-request cache comparison.

## Observed evidence

The initial baseline run used the intended pinned llama.cpp runtime with
VMware active. It completed eight measured requests before the host reached
about 672 MB free RAM; a ninth request was interrupted before its timing was
recorded.

| Completed request | Prompt tokens processed | Generation tok/s | Cache match log |
|---:|---:|---:|---:|
| 1 | 174 | 8.15 | first request |
| 2 | 728 | 8.91 | `f_keep=0.700` |
| 3 | 1,450 | 9.16 | `f_keep=0.913` |
| 4 | 2,474 | 8.16 | `f_keep=0.954` |
| 5 | 2,474 | 7.54 | `f_keep=0.977` |
| 6 | 3,920 | 6.63 | `f_keep=0.984` |
| 7 | 3,922 | 5.60 | `f_keep=0.990` |
| 8 | 2,472 | 5.13 | `f_keep=0.993` |

The cache match improved while generation slowed. This strongly suggests that
the slowdown is resident-memory/page pressure and/or long active context, not
failed prefix caching. The log also confirmed that `--cache-reuse 256` is
unsupported by this context and is disabled separately from normal prompt
caching.

## Reproducible harness

The harness is [benchmark-agent-workload.ps1](../scripts/benchmark-agent-workload.ps1).
The complete matrix should only be run after explicitly choosing whether the
VMware guests remain active. With the guests active, the current evidence does
not support a safe 10,000-token matrix on this 32 GB machine.
