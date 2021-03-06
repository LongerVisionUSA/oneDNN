/*******************************************************************************
 * Copyright 2020-2021 Intel Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *******************************************************************************/

// This define is required before including zero_pad_struct.h to allow reuse of
// the same structure with the correct data types between OpenCL kernels and C++
// code.
#define IS_OCL_KERNEL
#include "gpu/zero_pad_struct.h"

#define DEFAULT_NELEMS_BLOCK 8

static inline void typed_ref_zero_pad(__global void *a, ulong type_size,
        ulong step_nelems, ulong nelems_block, ulong step_block, ulong nsteps,
        ulong step_size, zero_pad_mask_t step_bitmask, ulong mode) {
    const int i0 = get_global_id(0);
    const int istep = get_global_id(1) * step_block;
    const int iblock = get_global_id(2);
    int offset = iblock * step_size + (step_size - nsteps * step_nelems)
            + istep * step_nelems;

    const int step = ZERO_PAD_MASK_DT_BITS;

    // Interpret buffer differently based on type_size, this is implicitly
    // using the fact that the bit representation of 0 is the same regardless of
    // data type, e.g. int32 and f32 represent 0 the same.
    __global int *a4 = (__global int *)a;
    __global short *a2 = (__global short *)a;
    __global char *a1 = (__global char *)a;

    if (mode == ZERO_PAD_BIT_MODE) {
        // Use a bit mask to determine which elements to zero in a block

        // This allows for handling larger blocks than the lookup mode without
        // increasing the size of zero_pad_mask_t. There is a disadvantage as
        // more time is spent checking if a given piece of memory needs zeroed

        for (int k = 0; k < step_block; k++) {
            __attribute__((opencl_unroll_hint)) // attr:no-format
            for (int i = i0; i < step_nelems; i += nelems_block) {
                if (step_bitmask.mask[i / step] & (1 << (i % step))) {
                    switch (type_size) {
                        case 4: a4[offset + i] = 0; break;
                        case 2: a2[offset + i] = 0; break;
                        case 1: a1[offset + i] = 0; break;
                    }
                }
            }

            offset += step_nelems;
        }
    } else {
        // mode == ZERO_PAD_LOOKUP_MODE
        // Use a lookup table to determine which elements to zero in a block
        // Implementation requires global_work_size(0) is equal to the number of
        // elements to zero in a given block

        int i = step_bitmask.mask[i0];
        for (int k = 0; k < step_block; k++) {
            switch (type_size) {
                case 4: a4[offset + i] = 0; break;
                case 2: a2[offset + i] = 0; break;
                case 1: a1[offset + i] = 0; break;
            }
            offset += step_nelems;
        }
    }
}

static inline void sized_ref_zero_pad(__global void *a, ulong type_size,
        ulong step_nelems, ulong nelems_block, ulong step_block, ulong nsteps,
        ulong step_size, zero_pad_mask_t step_bitmask, ulong mode) {
    switch (type_size) {
        case 4:
            typed_ref_zero_pad((__global float *)a, 4, step_nelems,
                    nelems_block, step_block, nsteps, step_size, step_bitmask,
                    mode);
            break;
        case 2:
            typed_ref_zero_pad((__global float *)a, 2, step_nelems,
                    nelems_block, step_block, nsteps, step_size, step_bitmask,
                    mode);
            break;
        case 1:
            typed_ref_zero_pad((__global float *)a, 1, step_nelems,
                    nelems_block, step_block, nsteps, step_size, step_bitmask,
                    mode);
            break;
    }
}

__kernel void ref_zero_pad(__global void *a, ulong type_size, ulong step_nelems,
        ulong nelems_block, ulong step_block, ulong nsteps, ulong step_size,
        zero_pad_mask_t step_bitmask, ulong mode) {
    // Use a switch statement here to allow constant propagation optimizations to
    // remove switch statement from loop in typed_ref_zero_pad.
    switch (step_nelems) {
        case 16:
            sized_ref_zero_pad(a, type_size, 16, DEFAULT_NELEMS_BLOCK,
                    step_block, nsteps, step_size, step_bitmask, mode);
            break;
        case 32:
            sized_ref_zero_pad(a, type_size, 32, DEFAULT_NELEMS_BLOCK,
                    step_block, nsteps, step_size, step_bitmask, mode);
            break;
        case 64:
            sized_ref_zero_pad(a, type_size, 64, DEFAULT_NELEMS_BLOCK,
                    step_block, nsteps, step_size, step_bitmask, mode);
            break;
        default:
            sized_ref_zero_pad(a, type_size, step_nelems, nelems_block,
                    step_block, nsteps, step_size, step_bitmask, mode);
            break;
    }
}
