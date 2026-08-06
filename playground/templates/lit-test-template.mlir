// 寫 lit test 的範本。複製到 mlir/test/Dialect/Arith/ 底下再改。
//
// 「沒有 test 的 PR 不會 merge」是硬規定，沒有例外（Goal.md §8.2）。

// RUN: mlir-opt %s -canonicalize | FileCheck %s
//   ↑ 實際執行的指令。%s 會被換成本檔的路徑。
//     跑起來就是 mlir-opt <本檔> -canonicalize，輸出交給 FileCheck 比對。

// -----------------------------------------------------------------------
// 情境一：預期「會」被折疊
// -----------------------------------------------------------------------

// CHECK-LABEL: func @fold_happens
//       CHECK:   %[[C:.*]] = arith.constant 4 : i8
//       CHECK:   return %[[C]]
func.func @fold_happens() -> i8 {
  %a = arith.constant 7 : i8
  %b = arith.constant 2 : i8
  %0 = arith.ceildivsi %a, %b : i8
  return %0 : i8
}

// -----

// -----------------------------------------------------------------------
// 情境二：預期「不會」被折疊
//
// 這種要斷言「原本的 op 還在」。很容易寫成假通過——
// 如果只寫 CHECK: return，那不管有沒有折疊都會過。
// 一定要明確 CHECK 到那個 op 本身還在。
// -----------------------------------------------------------------------

// CHECK-LABEL: func @fold_does_not_happen
//       CHECK:   arith.ceildivsi
func.func @fold_does_not_happen() -> i8 {
  %min = arith.constant -128 : i8
  %m1 = arith.constant -1 : i8
  // ceil(-128 / -1) = 128，放不進 i8，所以必須維持原樣
  %0 = arith.ceildivsi %min, %m1 : i8
  return %0 : i8
}

// -----------------------------------------------------------------------
// 常用的 FileCheck 指令
//
//   CHECK-LABEL:  區塊的起點，用來把各個 func 的檢查隔開（強烈建議每個 func 都加）
//   CHECK:        往下找到符合的一行
//   CHECK-NEXT:   必須是「緊接著的下一行」，順序敏感
//   CHECK-DAG:    連續幾條 DAG 之間不要求順序（constant 被重排時很好用）
//   CHECK-NOT:    這個模式不可以出現（斷言某個 op 被消掉了）
//   CHECK-SAME:   接續上一條的同一行
//
//   %[[NAME:.*]]  抓一個變數名存起來，後面用 %[[NAME]] 引用
//
// 「// -----」會把檔案切成互相獨立的小單元，各自跑一次。
// 一個 func 掛掉不會影響其他的，除錯容易很多。
// -----------------------------------------------------------------------
