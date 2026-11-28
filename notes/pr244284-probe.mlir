// Scalable variants of the existing fixed-size tests that the PR does not add.

func.func @read_tensor(%t : tensor<4x?xf32>) -> vector<4x[2]xf32> {
  %c0 = arith.constant 0 : index
  %cf0 = arith.constant 0.0 : f32
  %res = vector.transfer_read %t[%c0, %c0], %cf0 : tensor<4x?xf32>, vector<4x[2]xf32>
  return %res : vector<4x[2]xf32>
}

// -----

func.func @write_tensor(%t : tensor<4x?xf32>, %vec : vector<4x[2]xf32>) -> tensor<4x?xf32> {
  %c0 = arith.constant 0 : index
  %res = vector.transfer_write %vec, %t[%c0, %c0] : vector<4x[2]xf32>, tensor<4x?xf32>
  return %res : tensor<4x?xf32>
}

// -----

func.func @read_permutation(%mem : memref<?x4xf32>) -> vector<4x[2]xf32> {
  %c0 = arith.constant 0 : index
  %cf0 = arith.constant 0.0 : f32
  %res = vector.transfer_read %mem[%c0, %c0], %cf0 {permutation_map = affine_map<(d0, d1) -> (d1, d0)>} : memref<?x4xf32>, vector<4x[2]xf32>
  return %res : vector<4x[2]xf32>
}

// -----

func.func @read_broadcast(%mem : memref<4x?xf32>) -> vector<4x[2]xf32> {
  %c0 = arith.constant 0 : index
  %cf0 = arith.constant 0.0 : f32
  %res = vector.transfer_read %mem[%c0, %c0], %cf0 {in_bounds = [true, false], permutation_map = affine_map<(d0, d1) -> (0, d1)>} : memref<4x?xf32>, vector<4x[2]xf32>
  return %res : vector<4x[2]xf32>
}

// -----

func.func @read_different_rank(%mem : memref<?x?x?xf32>) -> vector<4x[2]xf32> {
  %c0 = arith.constant 0 : index
  %cf0 = arith.constant 0.0 : f32
  %res = vector.transfer_read %mem[%c0, %c0, %c0], %cf0 {permutation_map = affine_map<(d0, d1, d2) -> (d0, d2)>} : memref<?x?x?xf32>, vector<4x[2]xf32>
  return %res : vector<4x[2]xf32>
}

// -----

func.func @read_dynamic_index(%mem : memref<4x?xf32>, %idx : index) -> vector<4x[2]xf32> {
  %cf0 = arith.constant 0.0 : f32
  %res = vector.transfer_read %mem[%idx, %idx], %cf0 : memref<4x?xf32>, vector<4x[2]xf32>
  return %res : vector<4x[2]xf32>
}

// -----

// The scalable dim is in the element type of the memref.
func.func @read_vector_element_type(%mem : memref<4xvector<[2]xf32>>) -> vector<4x[2]xf32> {
  %c0 = arith.constant 0 : index
  %pad = arith.constant dense<0.0> : vector<[2]xf32>
  %res = vector.transfer_read %mem[%c0], %pad : memref<4xvector<[2]xf32>>, vector<4x[2]xf32>
  return %res : vector<4x[2]xf32>
}

// -----

func.func @write_vector_element_type(%mem : memref<4xvector<[2]xf32>>, %vec : vector<4x[2]xf32>) {
  %c0 = arith.constant 0 : index
  vector.transfer_write %vec, %mem[%c0] : vector<4x[2]xf32>, memref<4xvector<[2]xf32>>
  return
}

// -----

// Masked, with a scalable dim that the target shape does not split.
func.func @masked_read(%mem : memref<4x?xf32>, %mask : vector<4x[2]xi1>) -> vector<4x[2]xf32> {
  %c0 = arith.constant 0 : index
  %cf0 = arith.constant 0.0 : f32
  %res = vector.mask %mask { vector.transfer_read %mem[%c0, %c0], %cf0 : memref<4x?xf32>, vector<4x[2]xf32> } : vector<4x[2]xi1> -> vector<4x[2]xf32>
  return %res : vector<4x[2]xf32>
}

// -----

func.func @masked_write(%mem : memref<4x?xf32>, %vec : vector<4x[2]xf32>, %mask : vector<4x[2]xi1>) {
  %c0 = arith.constant 0 : index
  vector.mask %mask { vector.transfer_write %vec, %mem[%c0, %c0] : vector<4x[2]xf32>, memref<4x?xf32> } : vector<4x[2]xi1>
  return
}

// -----

// A transfer with its own mask operand.
func.func @read_mask_operand(%mem : memref<4x?xf32>, %mask : vector<4x[2]xi1>) -> vector<4x[2]xf32> {
  %c0 = arith.constant 0 : index
  %cf0 = arith.constant 0.0 : f32
  %res = vector.transfer_read %mem[%c0, %c0], %cf0, %mask : memref<4x?xf32>, vector<4x[2]xf32>
  return %res : vector<4x[2]xf32>
}

// -----

// Both dims scalable.
func.func @read_all_scalable(%mem : memref<?x?xf32>) -> vector<[4]x[2]xf32> {
  %c0 = arith.constant 0 : index
  %cf0 = arith.constant 0.0 : f32
  %res = vector.transfer_read %mem[%c0, %c0], %cf0 : memref<?x?xf32>, vector<[4]x[2]xf32>
  return %res : vector<[4]x[2]xf32>
}

// -----

// Rank 3, target shape of rank 2: rank mismatch.
func.func @read_rank3(%mem : memref<4x4x?xf32>) -> vector<4x4x[2]xf32> {
  %c0 = arith.constant 0 : index
  %cf0 = arith.constant 0.0 : f32
  %res = vector.transfer_read %mem[%c0, %c0, %c0], %cf0 : memref<4x4x?xf32>, vector<4x4x[2]xf32>
  return %res : vector<4x4x[2]xf32>
}
