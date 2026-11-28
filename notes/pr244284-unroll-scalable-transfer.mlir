// Integration test written for the review of llvm/llvm-project#244284
// (unrolling of scalable vector.transfer_read / vector.transfer_write).
// The same checks must pass without unrolling, with unrolling, and with the
// reversed unroll order. Run it from the ArmSVE integration test directory.

// DEFINE: %{lower} = -convert-vector-to-scf -arm-sve-legalize-vector-storage -convert-vector-to-llvm="enable-arm-sve" -test-lower-to-llvm
// DEFINE: %{run} = %mcr_aarch64_cmd -e=entry -entry-point-result=void --march=aarch64 --mattr="+sve" -shared-libs=%native_mlir_c_runner_utils,%native_mlir_arm_runner_utils

// RUN: mlir-opt %s %{lower} | %{run} | FileCheck %s
// RUN: mlir-opt %s -test-vector-transfer-unrolling-patterns %{lower} | %{run} | FileCheck %s
// RUN: mlir-opt %s -test-vector-transfer-unrolling-patterns=reverse-unroll-order %{lower} | %{run} | FileCheck %s

// Read a 4 x [2] block at (%i, %j) and print its rows. Out-of-bounds elements
// read as -1.
func.func @read(%mem : memref<4x?xf32>, %i : index, %j : index) {
  %pad = arith.constant -1.0 : f32
  %v = vector.transfer_read %mem[%i, %j], %pad : memref<4x?xf32>, vector<4x[2]xf32>
  %r0 = vector.extract %v[0] : vector<[2]xf32> from vector<4x[2]xf32>
  %r1 = vector.extract %v[1] : vector<[2]xf32> from vector<4x[2]xf32>
  %r2 = vector.extract %v[2] : vector<[2]xf32> from vector<4x[2]xf32>
  %r3 = vector.extract %v[3] : vector<[2]xf32> from vector<4x[2]xf32>
  vector.print %r0 : vector<[2]xf32>
  vector.print %r1 : vector<[2]xf32>
  vector.print %r2 : vector<[2]xf32>
  vector.print %r3 : vector<[2]xf32>
  return
}

// Write a 4 x [2] block at (%i, %j). Out-of-bounds elements are dropped.
func.func @write(%v : vector<4x[2]xf32>, %mem : memref<4x?xf32>, %i : index, %j : index) {
  vector.transfer_write %v, %mem[%i, %j] : vector<4x[2]xf32>, memref<4x?xf32>
  return
}

func.func @run() {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c6 = arith.constant 6 : index
  %c7 = arith.constant 7 : index
  %pad = arith.constant -1.0 : f32

  // The source buffer. The helpers below only use rank-1 transfers, which the
  // unrolling test pass leaves alone (its target shape has rank 2).
  %row0 = arith.constant dense<[11., 12., 13., 14., 15., 16., 17., 18.]> : vector<8xf32>
  %row1 = arith.constant dense<[21., 22., 23., 24., 25., 26., 27., 28.]> : vector<8xf32>
  %row2 = arith.constant dense<[31., 32., 33., 34., 35., 36., 37., 38.]> : vector<8xf32>
  %row3 = arith.constant dense<[41., 42., 43., 44., 45., 46., 47., 48.]> : vector<8xf32>
  %src_static = memref.alloca() : memref<4x8xf32>
  vector.transfer_write %row0, %src_static[%c0, %c0] {in_bounds = [true]} : vector<8xf32>, memref<4x8xf32>
  vector.transfer_write %row1, %src_static[%c1, %c0] {in_bounds = [true]} : vector<8xf32>, memref<4x8xf32>
  vector.transfer_write %row2, %src_static[%c2, %c0] {in_bounds = [true]} : vector<8xf32>, memref<4x8xf32>
  vector.transfer_write %row3, %src_static[%c3, %c0] {in_bounds = [true]} : vector<8xf32>, memref<4x8xf32>
  %src = memref.cast %src_static : memref<4x8xf32> to memref<4x?xf32>

  // In bounds.
  vector.print str "read(0, 0)\n"
  func.call @read(%src, %c0, %c0) : (memref<4x?xf32>, index, index) -> ()
  // The last row is out of bounds, and so are the columns past 8.
  vector.print str "read(1, 6)\n"
  func.call @read(%src, %c1, %c6) : (memref<4x?xf32>, index, index) -> ()

  // The vector to write: the first [2] columns of the source buffer.
  %z = arith.constant dense<0.0> : vector<4x[2]xf32>
  %s0 = vector.transfer_read %src[%c0, %c0], %pad {in_bounds = [true]} : memref<4x?xf32>, vector<[2]xf32>
  %s1 = vector.transfer_read %src[%c1, %c0], %pad {in_bounds = [true]} : memref<4x?xf32>, vector<[2]xf32>
  %s2 = vector.transfer_read %src[%c2, %c0], %pad {in_bounds = [true]} : memref<4x?xf32>, vector<[2]xf32>
  %s3 = vector.transfer_read %src[%c3, %c0], %pad {in_bounds = [true]} : memref<4x?xf32>, vector<[2]xf32>
  %v0 = vector.insert %s0, %z[0] : vector<[2]xf32> into vector<4x[2]xf32>
  %v1 = vector.insert %s1, %v0[1] : vector<[2]xf32> into vector<4x[2]xf32>
  %v2 = vector.insert %s2, %v1[2] : vector<[2]xf32> into vector<4x[2]xf32>
  %v3 = vector.insert %s3, %v2[3] : vector<[2]xf32> into vector<4x[2]xf32>

  %zero = arith.constant dense<0.0> : vector<8xf32>
  %dst_static = memref.alloca() : memref<4x8xf32>
  vector.transfer_write %zero, %dst_static[%c0, %c0] {in_bounds = [true]} : vector<8xf32>, memref<4x8xf32>
  vector.transfer_write %zero, %dst_static[%c1, %c0] {in_bounds = [true]} : vector<8xf32>, memref<4x8xf32>
  vector.transfer_write %zero, %dst_static[%c2, %c0] {in_bounds = [true]} : vector<8xf32>, memref<4x8xf32>
  vector.transfer_write %zero, %dst_static[%c3, %c0] {in_bounds = [true]} : vector<8xf32>, memref<4x8xf32>
  %dst = memref.cast %dst_static : memref<4x8xf32> to memref<4x?xf32>

  // In bounds.
  func.call @write(%v3, %dst, %c0, %c0) : (vector<4x[2]xf32>, memref<4x?xf32>, index, index) -> ()
  // Only rows 0-1 and column 0 of the vector land in the buffer.
  func.call @write(%v3, %dst, %c2, %c7) : (vector<4x[2]xf32>, memref<4x?xf32>, index, index) -> ()

  vector.print str "write(0, 0), write(2, 7)\n"
  %d0 = vector.transfer_read %dst_static[%c0, %c0], %pad {in_bounds = [true]} : memref<4x8xf32>, vector<8xf32>
  %d1 = vector.transfer_read %dst_static[%c1, %c0], %pad {in_bounds = [true]} : memref<4x8xf32>, vector<8xf32>
  %d2 = vector.transfer_read %dst_static[%c2, %c0], %pad {in_bounds = [true]} : memref<4x8xf32>, vector<8xf32>
  %d3 = vector.transfer_read %dst_static[%c3, %c0], %pad {in_bounds = [true]} : memref<4x8xf32>, vector<8xf32>
  vector.print %d0 : vector<8xf32>
  vector.print %d1 : vector<8xf32>
  vector.print %d2 : vector<8xf32>
  vector.print %d3 : vector<8xf32>
  return
}

func.func @entry() {
  // CHECK-LABEL: VL128
  // CHECK-NEXT: read(0, 0)
  // CHECK-NEXT: ( 11, 12 )
  // CHECK-NEXT: ( 21, 22 )
  // CHECK-NEXT: ( 31, 32 )
  // CHECK-NEXT: ( 41, 42 )
  // CHECK-NEXT: read(1, 6)
  // CHECK-NEXT: ( 27, 28 )
  // CHECK-NEXT: ( 37, 38 )
  // CHECK-NEXT: ( 47, 48 )
  // CHECK-NEXT: ( -1, -1 )
  // CHECK-NEXT: write(0, 0), write(2, 7)
  // CHECK-NEXT: ( 11, 12, 0, 0, 0, 0, 0, 0 )
  // CHECK-NEXT: ( 21, 22, 0, 0, 0, 0, 0, 0 )
  // CHECK-NEXT: ( 31, 32, 0, 0, 0, 0, 0, 11 )
  // CHECK-NEXT: ( 41, 42, 0, 0, 0, 0, 0, 21 )
  vector.print str "VL128\n"
  %c128 = arith.constant 128 : i32
  func.call @setArmVLBits(%c128) : (i32) -> ()
  func.call @run() : () -> ()

  // CHECK-LABEL: VL256
  // CHECK-NEXT: read(0, 0)
  // CHECK-NEXT: ( 11, 12, 13, 14 )
  // CHECK-NEXT: ( 21, 22, 23, 24 )
  // CHECK-NEXT: ( 31, 32, 33, 34 )
  // CHECK-NEXT: ( 41, 42, 43, 44 )
  // CHECK-NEXT: read(1, 6)
  // CHECK-NEXT: ( 27, 28, -1, -1 )
  // CHECK-NEXT: ( 37, 38, -1, -1 )
  // CHECK-NEXT: ( 47, 48, -1, -1 )
  // CHECK-NEXT: ( -1, -1, -1, -1 )
  // CHECK-NEXT: write(0, 0), write(2, 7)
  // CHECK-NEXT: ( 11, 12, 13, 14, 0, 0, 0, 0 )
  // CHECK-NEXT: ( 21, 22, 23, 24, 0, 0, 0, 0 )
  // CHECK-NEXT: ( 31, 32, 33, 34, 0, 0, 0, 11 )
  // CHECK-NEXT: ( 41, 42, 43, 44, 0, 0, 0, 21 )
  vector.print str "VL256\n"
  %c256 = arith.constant 256 : i32
  func.call @setArmVLBits(%c256) : (i32) -> ()
  func.call @run() : () -> ()

  // CHECK-LABEL: VL512
  // CHECK-NEXT: read(0, 0)
  // CHECK-NEXT: ( 11, 12, 13, 14, 15, 16, 17, 18 )
  // CHECK-NEXT: ( 21, 22, 23, 24, 25, 26, 27, 28 )
  // CHECK-NEXT: ( 31, 32, 33, 34, 35, 36, 37, 38 )
  // CHECK-NEXT: ( 41, 42, 43, 44, 45, 46, 47, 48 )
  // CHECK-NEXT: read(1, 6)
  // CHECK-NEXT: ( 27, 28, -1, -1, -1, -1, -1, -1 )
  // CHECK-NEXT: ( 37, 38, -1, -1, -1, -1, -1, -1 )
  // CHECK-NEXT: ( 47, 48, -1, -1, -1, -1, -1, -1 )
  // CHECK-NEXT: ( -1, -1, -1, -1, -1, -1, -1, -1 )
  // CHECK-NEXT: write(0, 0), write(2, 7)
  // CHECK-NEXT: ( 11, 12, 13, 14, 15, 16, 17, 18 )
  // CHECK-NEXT: ( 21, 22, 23, 24, 25, 26, 27, 28 )
  // CHECK-NEXT: ( 31, 32, 33, 34, 35, 36, 37, 11 )
  // CHECK-NEXT: ( 41, 42, 43, 44, 45, 46, 47, 21 )
  vector.print str "VL512\n"
  %c512 = arith.constant 512 : i32
  func.call @setArmVLBits(%c512) : (i32) -> ()
  func.call @run() : () -> ()
  return
}

func.func private @setArmVLBits(%bits : i32)
