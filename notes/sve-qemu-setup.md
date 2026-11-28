# qemu-aarch64 ＋ SVE 實跑環境（2026-11-28）

> **用途**：沒有 SVE 硬體時，在 x86 機器上實跑 `mlir/test/Integration/**/ArmSVE/` 整合測試。
> scalable 題目（[`scalable-patch-candidates.md`](scalable-patch-candidates.md)）的共同前置。
>
> **這份流程在哪裡驗過**：一個雲端容器（Ubuntu 24.04、x86-64、4 核、15 GB），
> llvm-project `a6321f2d`。**不是在 WSL 上驗的，WSL 上什麼都還沒裝。**
> 下面每一步都標了「✅ 實跑過」或「⚠️ 沒跑過」。

## 原理：需要兩個 build

SVE 整合測試的 RUN 行長這樣：

```
mlir-opt %s -test-lower-to-llvm | %mcr_aarch64_cmd -e entry ... -march=aarch64 -mattr=+sve
```

- `mlir-opt` 是 **x86 的**，跑在本機——就是平常那個 `~/llvm-project/build`。
- `%mcr_aarch64_cmd` 展開成 `qemu-aarch64 <選項> <aarch64 的 mlir-runner>`
  （`mlir/test/Integration/lit.local.cfg:7-44`）。**這個 `mlir-runner` 必須是 aarch64 執行檔**，
  JIT 出來的 SVE 指令由 qemu 模擬。
- 連同 `-shared-libs=` 要的三個 runner utils（`mlir_c_runner_utils`、`mlir_runner_utils`、
  `mlir_arm_runner_utils`）也要是 aarch64 的。

所以新增的只有**一個交叉編譯的 build 目錄**，裡面只建 `mlir-runner` 和三個 `.so`。
平常改 `mlir-opt` 這一側的 code 不必重建它。

## 步驟 1：套件

```bash
sudo apt install -y qemu-user gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
```

⚠️ **這一行沒跑過**——容器裡這三個套件本來就有。驗證時的版本：
`qemu-user 8.2.2`、`gcc-aarch64-linux-gnu 13.2.0`（實際 gcc 13.3.0）、`libc6-arm64-cross 2.39`。
Ubuntu 24.04 的 WSL 應該拿到同一版；22.04 的 qemu 是 6.2，SVE 可用但沒驗過。

✅ 裝完先確認 qemu 的 SVE 會動、vscale 可控：

```bash
cat > /tmp/vl.c <<'EOF2'
#include <arm_sve.h>
#include <stdio.h>
int main(void) { printf("vscale=%lu\n", (unsigned long)svcntb() / 16); return 0; }
EOF2
aarch64-linux-gnu-gcc -O2 -march=armv8-a+sve /tmp/vl.c -o /tmp/vl
qemu-aarch64 -cpu max,sve-max-vq=2 -L /usr/aarch64-linux-gnu /tmp/vl   # 印 vscale=2
```

實測 `sve-max-vq=1/2/4` 分別印 1／2／4。

## 步驟 2：交叉編譯 aarch64 的 `mlir-runner`

✅ 實跑過（4110 個 ninja 步驟，4 核 **75 分鐘**，build 目錄 **1.6 GB**，零失敗）。

前提：host build 已經有 `llvm-tblgen`、`llvm-min-tblgen`、`mlir-tblgen`、`mlir-pdll`、
`mlir-linalg-ods-yaml-gen`（平常的 `~/llvm-project/build/bin` 就有）。交叉 build 靠
`LLVM_NATIVE_TOOL_DIR` 借用它們，不會再建一份 x86 的 tablegen。

```bash
cd ~/llvm-project
cmake -G Ninja -S llvm -B build-aarch64 \
  -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
  -DCMAKE_FIND_ROOT_PATH=/usr/aarch64-linux-gnu \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DLLVM_HOST_TRIPLE=aarch64-unknown-linux-gnu \
  -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-unknown-linux-gnu \
  -DLLVM_TARGETS_TO_BUILD=AArch64 \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_NATIVE_TOOL_DIR="$HOME/llvm-project/build/bin" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_TERMINFO=OFF
```

```bash
ninja -C ~/llvm-project/build-aarch64 mlir-runner mlir_c_runner_utils mlir_runner_utils mlir_arm_runner_utils
```

與驗證時的差異（⚠️ 這幾點在 WSL 上要留意）：

- 驗證時路徑是容器的暫存目錄，這裡改寫成 `~/llvm-project`；`LLVM_NATIVE_TOOL_DIR` 指向的
  host build 在驗證時是 `BUILD_SHARED_LIBS=OFF`，**WSL 的 host build 是 `ON`**（`Goal.md` §7.3）。
  tablegen 工具照理不受影響，但沒驗過這個組合。
- 交叉 build **刻意不開** `BUILD_SHARED_LIBS`、assertions、ccache、lld：它只是一個不常重建的執行器。
- 關掉 zlib／zstd／libxml2／terminfo 是因為 aarch64 sysroot 裡沒有這些函式庫，不關會在 configure 找到 x86 的版本。
- ⚠️ **不要與 host build 同時跑 ninja**（`TODO.md` 的坑 2）：兩邊都是 4000 步等級，會把記憶體吃光。

✅ 建完直接驗 aarch64 的 JIT ＋ SVE，不需要 host 的 `mlir-opt`：

```bash
cat > /tmp/vscale.mlir <<'EOF2'
llvm.func @main() -> i64 {
  %0 = "llvm.intr.vscale"() : () -> i64
  llvm.return %0 : i64
}
EOF2
qemu-aarch64 -cpu max,sve-max-vq=2 -L /usr/aarch64-linux-gnu \
  ~/llvm-project/build-aarch64/bin/mlir-runner /tmp/vscale.mlir \
  -e main -entry-point-result=i64 -march=aarch64 -mattr=+sve        # 印 2
```

實測 `sve-max-vq=1/2/4` 印 1／2／4。

## 步驟 3：把 host build 接上模擬器

在既有的 host build 目錄**重新 configure**（只加選項，不必清掉重建）：

```bash
cmake -S ~/llvm-project/llvm -B ~/llvm-project/build \
  -DMLIR_INCLUDE_INTEGRATION_TESTS=ON \
  -DMLIR_RUN_ARM_SVE_TESTS=ON \
  -DARM_EMULATOR_EXECUTABLE=/usr/bin/qemu-aarch64 \
  -DARM_EMULATOR_OPTIONS="-cpu max -L /usr/aarch64-linux-gnu" \
  -DARM_EMULATOR_MLIR_RUNNER_EXECUTABLE="$HOME/llvm-project/build-aarch64/bin/mlir-runner" \
  -DARM_EMULATOR_UTILS_LIB_DIR="$HOME/llvm-project/build-aarch64/lib"
```

```bash
cd ~/llvm-project/build && ./bin/llvm-lit -v ../mlir/test/Integration/Dialect/Vector/CPU/ArmSVE
```

⏳ **驗證進行中**：寫這份筆記時 host 的 `mlir-opt` 還在建，ArmSVE 整合測試還沒實際跑過。
結果補在本檔最後的「驗證紀錄」。

選項的出處：`mlir/test/CMakeLists.txt:20-48`。host 沒有 SVE 時，`MLIR_RUN_ARM_SVE_TESTS=ON`
而 `ARM_EMULATOR_EXECUTABLE` 沒設會直接 configure 失敗（`MLIRCheckHardwareFeatures.cmake` 的 `check_emulator`）。

## 已知的坑

1. **qemu-user 的預設向量長度上限是 512 bit（vscale = 4）。**
   實測 `-cpu max,sve-max-vq=16` 仍然印 vscale = 4；要加 `sve-default-vector-length=-1` 才拿得到 16。
   上游的測試用 `setArmVLBits`（`mlir_arm_runner_utils` 裡，走 `prctl`）自己設長度，
   所以 `ARM_EMULATOR_OPTIONS` 用 `-cpu max` 就夠；手動跑的時候才需要注意這個上限。
2. **`-L /usr/aarch64-linux-gnu` 不能省**：`mlir-runner` 是動態連結的，
   qemu 要靠它找到 aarch64 的 `ld-linux-aarch64.so.1` 與 `libstdc++`。
3. **同一份測試換 vscale 跑**：正確性與 vscale 無關才算對。手動驗 patch 時至少跑
   `sve-max-vq=1`、`2`、`4` 三種。

## 驗證紀錄

| 項目 | 結果 |
|---|---|
| qemu 跑 SVE C 程式，vscale 隨 `sve-max-vq` 變 | ✅ 1／2／4 |
| 交叉編譯 `mlir-runner` ＋ 三個 runner utils | ✅ 4110 步、75 分鐘、零失敗 |
| aarch64 `mlir-runner` 在 qemu 下 JIT `llvm.intr.vscale` | ✅ 1／2／4；加 `sve-default-vector-length=-1` 得 16 |
| host `mlir-opt` 接上模擬器後跑 `ArmSVE/` 整合測試 | ⏳ 進行中 |
| 在 WSL 上重跑以上全部 | ❌ 沒做 |
