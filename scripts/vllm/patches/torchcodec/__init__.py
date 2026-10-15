# Stub: vllm/vllm-openai:v0.31.0-cu129 ships a CUDA-13 torchcodec that fails to load
# (OSError: libnvrtc.so.13) and crashes vLLM at import. Raising ImportError makes vLLM
# fall back to "torchcodec unavailable" (only affects audio/video input, not text).
raise ImportError("torchcodec disabled on Tempest: CUDA 13 build inside CUDA 12.9 image")
