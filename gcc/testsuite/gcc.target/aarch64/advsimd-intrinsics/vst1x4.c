#include <arm_neon.h>
#include "arm-neon-ref.h"

extern void abort (void);

#define TESTMETH(BASE, ELTS, SUFFIX)			\
int __attribute__ ((noinline))				\
test_vst1##SUFFIX##_x4 ()				\
{							\
  BASE##_t data[ELTS * 4];				\
  BASE##_t temp[ELTS * 4];				\
  BASE##x##ELTS##x##4##_t vectors;			\
  int i,j;						\
  for (i = 0; i < ELTS * 4; i++)			\
    data [i] = CONVERT (BASE##_t, 4*i);			\
  asm volatile ("" : : : "memory");			\
  vectors.val[0] = vld1##SUFFIX (data);			\
  vectors.val[1] = vld1##SUFFIX (&data[ELTS]);		\
  vectors.val[2] = vld1##SUFFIX (&data[ELTS * 2]);	\
  vectors.val[3] = vld1##SUFFIX (&data[ELTS * 3]);	\
  vst1##SUFFIX##_x4 (temp, vectors);			\
  asm volatile ("" : : : "memory");			\
  for (j = 0; j < ELTS * 4; j++)			\
    if (!BITEQUAL (temp[j], data[j]))			\
      return 1;						\
  return 0;						\
}

#define VARIANTS_1(VARIANT)	\
VARIANT (uint8, 8, _u8)		\
VARIANT (uint16, 4, _u16)	\
VARIANT (uint32, 2, _u32)	\
VARIANT (uint64, 1, _u64)	\
VARIANT (int8, 8, _s8)		\
VARIANT (int16, 4, _s16)	\
VARIANT (int32, 2, _s32)	\
VARIANT (int64, 1, _s64)	\
VARIANT (poly8, 8, _p8)		\
VARIANT (poly16, 4, _p16)	\
VARIANT (float32, 2, _f32)	\
VARIANT (uint8, 16, q_u8)	\
VARIANT (uint16, 8, q_u16)	\
VARIANT (uint32, 4, q_u32)	\
VARIANT (uint64, 2, q_u64)	\
VARIANT (int8, 16, q_s8)	\
VARIANT (int16, 8, q_s16)	\
VARIANT (int32, 4, q_s32)	\
VARIANT (int64, 2, q_s64)	\
VARIANT (poly8, 16, q_p8)	\
VARIANT (poly16, 8, q_p16)	\
VARIANT (float32, 4, q_f32)

#if defined (__ARM_FP16_FORMAT_IEEE)	     \
  || defined (__ARM_FP16_FORMAT_ALTERNATIVE) \
  || defined (__aarch64__)
#define VARIANTS_F16(VARIANT)			\
  VARIANT (float16, 4, _f16)			\
  VARIANT (float16, 8, q_f16)
#else
#define VARIANTS_F16(VARIANTS_F16)
#endif

#ifdef __aarch64__
#define VARIANTS(VARIANT) VARIANTS_1(VARIANT)	\
VARIANTS_F16(VARIANT)				\
VARIANT (poly64, 1, _p64)			\
VARIANT (poly64, 2, q_p64)			\
VARIANT (mfloat8, 8, _mf8)			\
VARIANT (mfloat8, 16, q_mf8)			\
VARIANT (float64, 1, _f64)			\
VARIANT (float64, 2, q_f64)
#else
#define VARIANTS(VARIANT) VARIANTS_1(VARIANT)	\
VARIANTS_F16(VARIANT)
#endif

/* Tests of vst1_x4 and vst1q_x4.  */
VARIANTS (TESTMETH)

#define CHECKS(BASE, ELTS, SUFFIX)	\
  if (test_vst1##SUFFIX##_x4 () != 0)	\
    fprintf (stderr, "test_vst1##SUFFIX##_x4"), __builtin_abort ();

int
main (int argc, char **argv)
{
  VARIANTS (CHECKS)

  return 0;
}
