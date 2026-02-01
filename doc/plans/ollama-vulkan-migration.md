# Ollama Vulkan Migration Plan

## Status: Workaround Found - Ready for Testing

## Background

Currently using IPEX-LLM with Ollama 0.9.3 (SYCL backend) on Intel Arc 130T iGPU. Intel archived the IPEX-LLM project on Jan 28, 2026, making this approach a dead-end for future updates.

## Key Discovery: Official Vulkan Support

**Ollama v0.12.11+ includes native Vulkan support** (released Nov 12, 2025). This is now in the official Docker image.

## Critical: Intel iGPU Vulkan Bug & Workaround

### The Problem

Intel iGPUs (including Arc 130T on Arrow Lake) have a **Mesa ANV driver bug** that causes:
- Gibberish/garbage output instead of coherent text
- Inference hangs (model loads but never responds)
- Issue is model-size dependent (small models may work, 3B+ fail)

**Affected hardware**: All Intel GPUs using Mesa ANV driver (12th Gen+, Iris Xe, Arc iGPU/dGPU)

### Root Cause

Bug in Mesa's Vulkan driver related to:
- Integer Dot Product operations in MMQ shaders
- FP16 code paths

**Upstream issues**:
- llama.cpp: [#17106](https://github.com/ggml-org/llama.cpp/issues/17106) (gibberish output)
- Ollama: [#13086](https://github.com/ollama/ollama/issues/13086) (gibberish), [#13964](https://github.com/ollama/ollama/issues/13964) (Arrow Lake specific)
- Mesa: [gitlab.freedesktop.org/mesa/mesa/-/issues/14652](https://gitlab.freedesktop.org/mesa/mesa/-/issues/14652)

### The Fix

**llama.cpp PR [#18814](https://github.com/ggml-org/llama.cpp/pull/18814)** merged Jan 14, 2026 - works around the bug.

**Ollama has NOT incorporated this fix yet** as of v0.15.2 (Jan 27, 2026).

### Workaround: GGML_VK_DISABLE_F16=1

**Tested and confirmed working** on Intel Arc 130T (Arrow Lake):

```bash
docker run -d \
  --device /dev/dri:/dev/dri \
  -v ollama:/root/.ollama \
  -p 11434:11434 \
  -e OLLAMA_VULKAN=1 \
  -e GGML_VK_DISABLE_F16=1 \
  --name ollama \
  ollama/ollama
```

**Alternative workarounds** (not tested):
- `GGML_VK_DISABLE_INTEGER_DOT_PRODUCT=1` - disables buggy int dot product ops

### Performance Note

Even with the fix, Vulkan on Intel iGPU is **~same speed as CPU** (only +5% faster in benchmarks). Benefits are:
- ~3.6x less power consumption
- Frees CPU cores for other tasks

### Official Docker Command

```bash
docker run -d \
  --device /dev/dri:/dev/dri \
  -v ollama:/root/.ollama \
  -p 11434:11434 \
  -e OLLAMA_VULKAN=1 \
  -e GGML_VK_DISABLE_F16=1 \
  --name ollama \
  ollama/ollama
```

Key points:
- **No special image required** - Vulkan is bundled in `ollama/ollama`
- **Enable with**: `OLLAMA_VULKAN=1` environment variable
- **REQUIRED for Intel**: `GGML_VK_DISABLE_F16=1` (until Ollama incorporates llama.cpp fix)
- **Device mapping**: `/dev/dri` (same as AMD ROCm)
- **Current version**: v0.15.2 (latest) or any v0.12.11+

## Comparison: SYCL vs Vulkan

| Aspect | IPEX-LLM (SYCL) | Official Ollama (Vulkan) |
|--------|-----------------|--------------------------|
| Ollama Version | 0.9.3 (frozen) | 0.15.2+ (latest) |
| Backend | SYCL/oneAPI | Vulkan |
| Speed | Faster (~2x) | Slower (CPU-like) |
| Maintenance | Abandoned | Actively maintained |
| New Models | Limited (no ministral) | Full support |
| Docker Image | `intelanalytics/ipex-llm-*` | `ollama/ollama` |
| Intel iGPU Support | Works out of box | Requires `GGML_VK_DISABLE_F16=1` |

## Performance Expectations

From lexiismadd/ollama-vulkan-arc benchmarks (Arc A770 16GB):
- Small models (3-8B): 50-100+ tokens/s
- Medium models (13-20B): 20-40 tokens/s
- Large models (30-70B): 5-15 tokens/s

**Note**: Arc 130T has only 7 Xe cores vs A770's 32 Xe cores, so expect ~4-5x slower performance. Actual testing needed.

## Migration Options

### Option A: Quick Test (Recommended First Step)

Test Vulkan with official Ollama on your VM without modifying existing setup:

```bash
# SSH into Incus VM
incus exec ollama-vm -- bash

# Stop existing IPEX-LLM container
docker stop ollama-ipex

# Run official Ollama with Vulkan (GGML_VK_DISABLE_F16 required for Intel!)
docker run -d \
  --device /dev/dri:/dev/dri \
  -v ollama-test:/root/.ollama \
  -p 11434:11434 \
  -e OLLAMA_VULKAN=1 \
  -e GGML_VK_DISABLE_F16=1 \
  --name ollama-vulkan-test \
  ollama/ollama

# Pull and test a model
docker exec ollama-vulkan-test ollama pull llama3.1:8b
docker exec ollama-vulkan-test ollama run llama3.1:8b "Hello"

# Check GPU detection
docker exec ollama-vulkan-test ollama ps
```

### Option B: Update tma/ollama-intel-gpu Repo

Modify your existing Docker setup to use official Ollama with Vulkan:

```yaml
# docker-compose.yml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    devices:
      - /dev/dri:/dev/dri
    ports:
      - "11434:11434"
    volumes:
      - ollama-models:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0:11434
      - OLLAMA_VULKAN=1
      - GGML_VK_DISABLE_F16=1  # REQUIRED for Intel iGPU until Ollama incorporates llama.cpp fix
      - OLLAMA_NUM_GPU=999
      - OLLAMA_NUM_CTX=8192

volumes:
  ollama-models:
```

### Option C: Build from Source (Advanced)

For bleeding-edge Vulkan support, use the whyvl/ollama-vulkan fork:
- More complex setup
- Requires build dependencies
- May have additional optimizations
- See: https://kovasky.me/blogs/ollama_vulkan_intel/

## Benchmark Script

After Vulkan is running, use existing benchmark script:

```bash
docker exec balance-devcontainer ruby script/benchmark_ollama_models.rb
```

Compare results against IPEX-LLM baseline:
| Model | IPEX-LLM (SYCL) | Vulkan | Difference |
|-------|-----------------|--------|------------|
| llama3.1:8b | 10.8s avg | ? | ? |
| gemma3:12b | 15.5s avg | ? | ? |
| ministral-3:8b | N/A (0.9.3) | ? | NEW |

## Decision Points

1. **If Vulkan is <3x slower than SYCL**: Migrate to official Ollama
   - Pros: Latest features, ministral support, maintained
   - Cons: Slower inference

2. **If Vulkan is >3x slower**: Stay with IPEX-LLM
   - Pros: Better performance
   - Cons: Frozen at Ollama 0.9.3, no new model support

3. **Hybrid approach**: 
   - Keep IPEX-LLM for production (gemma3:12b)
   - Use Vulkan for testing new models occasionally

## VM Requirements

The Incus VM needs:
- `/dev/dri` passthrough (already configured for IPEX-LLM)
- Vulkan drivers in guest (may need `mesa-vulkan-drivers` package)
- `CAP_PERFMON` capability or run as root (for some Vulkan operations)

Check Vulkan availability in VM:
```bash
# Install tools if needed
apt install vulkan-tools mesa-vulkan-drivers

# Test Vulkan
vulkaninfo | head -50
```

## Next Steps

1. [x] Research Intel Vulkan issues - Mesa ANV driver bug identified
2. [x] Find workaround - `GGML_VK_DISABLE_F16=1` confirmed working
3. [ ] Run full CSV mapping benchmark with Vulkan + workaround
4. [ ] Compare performance vs IPEX-LLM
5. [ ] Test ministral-3:8b (new model, requires Ollama 0.13.1+)
6. [ ] Make migration decision

## Timeline

- **llama.cpp fix merged**: Jan 14, 2026 (PR #18814)
- **Ollama expected to incorporate**: ~v0.16.x (Feb 2026 estimate)
- **Workaround available now**: `GGML_VK_DISABLE_F16=1`

## References

- Ollama v0.12.11 release: https://github.com/ollama/ollama/releases/tag/v0.12.11
- Official Docker docs: https://docs.ollama.com/docker
- llama.cpp Intel fix PR: https://github.com/ggml-org/llama.cpp/pull/18814
- Ollama Intel gibberish issue: https://github.com/ollama/ollama/issues/13086
- Ollama Arrow Lake issue: https://github.com/ollama/ollama/issues/13964
- Mesa bug report: https://gitlab.freedesktop.org/mesa/mesa/-/issues/14652
- lexiismadd/ollama-vulkan-arc: https://github.com/lexiismadd/ollama-vulkan-arc
- whyvl/ollama-vulkan fork: https://github.com/whyvl/ollama-vulkan
- Build guide: https://kovasky.me/blogs/ollama_vulkan_intel/
