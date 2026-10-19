#!/bin/bash
# Build of the Strata 0.1.45 engine for sm_70 (V100) in ~/strata185/dl/Strata-0.1.45.
# Same flags as for 0.1.41/0.1.42/0.1.43/0.1.44.1: a private CUDA 12.8 and a private gcc-14,
# no system packages are installed. .venv and third_party/llama.cpp (pinned 3cf03257, requirements.txt
# unchanged in 0.1.45) are taken from the running install - the build does not touch the live server.
# Run: setsid nohup ~/strata185/bin/build-0.1.45.sh >> ~/strata185/run/build-0.1.45.log 2>&1 &
D="$HOME/strata185"
S="$D/dl/Strata-0.1.45"
PY="$D/Strata/.venv/bin"
export LD_LIBRARY_PATH="$D/cuda-12.8/lib64"
CC="$D/gcc185/usr/bin/gcc-14"; CXX="$D/gcc185/usr/bin/g++-14"
say(){ echo "[$(date "+%Y-%m-%d %H:%M:%S")] $*"; }

common=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_CUDA_ARCHITECTURES=70 -DSTRATA_EXPERIMENTAL_SM60=ON
  -DCMAKE_CUDA_COMPILER="$D/cuda-12.8/bin/nvcc" -DCUDAToolkit_ROOT="$D/cuda-12.8"
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX"
  -DCMAKE_CUDA_HOST_COMPILER="$CXX"
)

say "clean configure (no old build directories must remain)"
rm -rf "$S/build-cuda12/CMakeCache.txt" "$S/build-cuda12/CMakeFiles"
say "=== configure engine"
"$PY/cmake" -S "$S" -B "$S/build-cuda12" \
  "${common[@]}" -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_TESTS=OFF \
  -DFETCHCONTENT_SOURCE_DIR_STRATA_LLAMACPP="$D/Strata/third_party/llama.cpp" || { say "BUILD_FAILED configure"; exit 1; }

say "=== build engine"
"$PY/cmake" --build "$S/build-cuda12" --target strata -j20 || { say "BUILD_FAILED engine"; exit 1; }

say "=== configure+build vision"
"$PY/cmake" -S "$S/tools/vision" -B "$S/build-vision-cuda12" \
  "${common[@]}" -DSTRATA_ENABLE_CUDA=ON || { say "BUILD_FAILED vision configure"; exit 1; }
"$PY/cmake" --build "$S/build-vision-cuda12" --target strata-vision -j20 || { say "BUILD_FAILED vision"; exit 1; }

say "=== versions"
"$S/build-cuda12/strata" --version
"$S/build-vision-cuda12/bin/strata-vision" --help 2>&1 | head -3
md5sum "$S/build-cuda12/strata" "$S/build-vision-cuda12/bin/strata-vision"
say "BUILD_DONE"
