// math.h.c3

module c::math;

// ========== Linux ==========

module c::math @if(env::LINUX);

// Basic functions (double precision)
extern fn double sin(double x);
extern fn double cos(double x);
extern fn double tan(double x);
extern fn double asin(double x);
extern fn double acos(double x);
extern fn double atan(double x);
extern fn double atan2(double y, double x);

// Hyperbolic functions
extern fn double sinh(double x);
extern fn double cosh(double x);
extern fn double tanh(double x);
extern fn double asinh(double x);
extern fn double acosh(double x);
extern fn double atanh(double x);

// Exponential and logarithmic functions
extern fn double exp(double x);
extern fn double exp2(double x);
extern fn double expm1(double x);
extern fn double log(double x);
extern fn double log10(double x);
extern fn double log2(double x);
extern fn double log1p(double x);

// Power functions
extern fn double pow(double x, double y);
extern fn double sqrt(double x);
extern fn double cbrt(double x);
extern fn double hypot(double x, double y);

// Error and gamma functions
extern fn double erf(double x);
extern fn double erfc(double x);
extern fn double tgamma(double x);
extern fn double lgamma(double x);

// Rounding and remainder functions
extern fn double ceil(double x);
extern fn double floor(double x);
extern fn double trunc(double x);
extern fn double round(double x);
extern fn long lround(double x);
extern fn double rint(double x);
extern fn long lrint(double x);
extern fn double nearbyint(double x);

// Floating-point manipulation functions
extern fn double frexp(double x, int* exp);
extern fn double ldexp(double x, int exp);
extern fn double modf(double x, double* iiptr);
extern fn double scalbn(double x, int n);
extern fn int ilogb(double x);
extern fn double logb(double x);
extern fn double nextafter(double x, double y);
extern fn double nexttoward(double x, double y);
extern fn double copysign(double x, double y);

// Absolute value and remainders
extern fn double fabs(double x);
extern fn double fmod(double x, double y);
extern fn double remainder(double x, double y);
extern fn double remquo(double x, double y, int* quo);

// Maximum, minimum, and difference functions
extern fn double fmax(double x, double y);
extern fn double fmin(double x, double y);
extern fn double fdim(double x, double y);

// Fused multiply-add
extern fn double fma(double x, double y, double z);

// Classification and comparison
extern fn int fpclassify(double x);
extern fn int isfinite(double x);
extern fn int isinf(double x);
extern fn int isnan(double x);
extern fn int isnormal(double x);
extern fn int signbit(double x);
extern fn int isgreater(double x, double y);
extern fn int isgreaterequal(double x, double y);
extern fn int isless(double x, double y);
extern fn int islessequal(double x, double y);
extern fn int islessgreater(double x, double y);
extern fn int isunordered(double x, double y);

// Float versions (single precision)
extern fn float sinf(float x);
extern fn float cosf(float x);
extern fn float tanf(float x);
extern fn float asinf(float x);
extern fn float acosf(float x);
extern fn float atanf(float x);
extern fn float atan2f(float y, float x);
extern fn float sinhf(float x);
extern fn float coshf(float x);
extern fn float tanhf(float x);
extern fn float asinhf(float x);
extern fn float acoshf(float x);
extern fn float atanhf(float x);
extern fn float expf(float x);
extern fn float exp2f(float x);
extern fn float expm1f(float x);
extern fn float logf(float x);
extern fn float log10f(float x);
extern fn float log2f(float x);
extern fn float log1pf(float x);
extern fn float powf(float x, float y);
extern fn float sqrtf(float x);
extern fn float cbrtf(float x);
extern fn float hypotf(float x, float y);
extern fn float erff(float x);
extern fn float erfcf(float x);
extern fn float tgammaf(float x);
extern fn float lgammaf(float x);
extern fn float ceilf(float x);
extern fn float floorf(float x);
extern fn float truncf(float x);
extern fn float roundf(float x);
extern fn long lroundf(float x);
extern fn float rintf(float x);
extern fn long lrintf(float x);
extern fn float nearbyintf(float x);
extern fn float frexpf(float x, int* exp);
extern fn float ldexpf(float x, int exp);
extern fn float modff(float x, float* iiptr);
extern fn float scalbnf(float x, int n);
extern fn int ilogbf(float x);
extern fn float logbf(float x);
extern fn float nextafterf(float x, float y);
extern fn float nexttowardf(float x, double y);
extern fn float copysignf(float x, float y);
extern fn float fabsf(float x);
extern fn float fmodf(float x, float y);
extern fn float remainderf(float x, float y);
extern fn float remquof(float x, float y, int* quo);
extern fn float fmaxf(float x, float y);
extern fn float fminf(float x, float y);
extern fn float fdimf(float x, float y);
extern fn float fmaf(float x, float y, float z);

// Long double versions (extended precision)
extern fn double sinl(double x);
extern fn double cosl(double x);
extern fn double tanl(double x);
extern fn double asinl(double x);
extern fn double acosl(double x);
extern fn double atanl(double x);
extern fn double atan2l(double y, double x);
extern fn double sinhl(double x);
extern fn double coshl(double x);
extern fn double tanhl(double x);
extern fn double asinhl(double x);
extern fn double acoshl(double x);
extern fn double atanhl(double x);
extern fn double expl(double x);
extern fn double exp2l(double x);
extern fn double expm1l(double x);
extern fn double logl(double x);
extern fn double log10l(double x);
extern fn double log2l(double x);
extern fn double log1pl(double x);
extern fn double powl(double x, double y);
extern fn double sqrtl(double x);
extern fn double cbrtl(double x);
extern fn double hypotl(double x, double y);
extern fn double erfl(double x);
extern fn double erfcl(double x);
extern fn double tgammal(double x);
extern fn double lgammal(double x);
extern fn double ceill(double x);
extern fn double floorl(double x);
extern fn double truncl(double x);
extern fn double roundl(double x);
extern fn long lroundl(double x);
extern fn double rintl(double x);
extern fn long lrintl(double x);

extern fn double nearbyintl(double x);
extern fn double frexpl(double x, int* exp);
extern fn double ldexpl(double x, int exp);
extern fn double modfl(double x, double* iiptr);
extern fn double scalbnl(double x, int n);
extern fn int ilogbl(double x);
extern fn double logbl(double x);
extern fn double nextafterl(double x, double y);
extern fn double nexttowardl(double x, double y);
extern fn double copysignl(double x, double y);
extern fn double fabsl(double x);
extern fn double fmodl(double x, double y);
extern fn double remainderl(double x, double y);
extern fn double remquol(double x, double y, int* quo);
extern fn double fmaxl(double x, double y);
extern fn double fminl(double x, double y);
extern fn double fdiml(double x, double y);
extern fn double fmal(double x, double y, double z);

// Bessel functions (POSIX extension)
extern fn double j0(double x);
extern fn double j1(double x);
extern fn double jn(int n, double x);
extern fn double y0(double x);
extern fn double y1(double x);
extern fn double yn(int n, double x);

// Constants (non-standard but widely available)
const double M_E = 2.71828182845904523536;
const double M_LOG2E = 1.44269504088896340736;
const double M_LOG10E = 0.434294481903251827651;
const double M_LN2 = 0.693147180559945309417;
const double M_LN10 = 2.30258509299404568402;
const double M_PI = 3.14159265358979323846;
const double M_PI_2 = 1.57079632679489661923;
const double M_PI_4 = 0.785398163397448309616;
const double M_1_PI = 0.318309886183790671538;
const double M_2_PI = 0.636619772367581343076;
const double M_2_SQRTPI = 1.12837916709551257390;
const double M_SQRT2 = 1.41421356237309504880;
const double M_SQRT1_2 = 0.707106781186547524401;

// FP classification constants
const int FP_NAN = 0;
const int FP_INFINITE = 1;
const int FP_ZERO = 2;
const int FP_SUBNORMAL = 3;
const int FP_NORMAL = 4;

// Special values
const double HUGE_VAL = double::inf;
const float HUGE_VALF = float::inf;
const double HUGE_VALL = double::inf;
const double INFINITY = double::inf;
const double NAN = double::nan;

// ========== Darwin (macOS) ==========

module c::math @if(env::DARWIN);

// All the same functions as Linux
extern fn double sin(double x);
extern fn double cos(double x);
extern fn double tan(double x);
extern fn double asin(double x);
extern fn double acos(double x);
extern fn double atan(double x);
extern fn double atan2(double y, double x);
extern fn double sinh(double x);
extern fn double cosh(double x);
extern fn double tanh(double x);
extern fn double asinh(double x);
extern fn double acosh(double x);
extern fn double atanh(double x);
extern fn double exp(double x);
extern fn double exp2(double x);
extern fn double expm1(double x);
extern fn double log(double x);
extern fn double log10(double x);
extern fn double log2(double x);
extern fn double log1p(double x);
extern fn double pow(double x, double y);
extern fn double sqrt(double x);
extern fn double cbrt(double x);
extern fn double hypot(double x, double y);
extern fn double erf(double x);
extern fn double erfc(double x);
extern fn double tgamma(double x);
extern fn double lgamma(double x);
extern fn double ceil(double x);
extern fn double floor(double x);
extern fn double trunc(double x);
extern fn double round(double x);
extern fn long lround(double x);

extern fn double rint(double x);
extern fn long lrint(double x);

extern fn double nearbyint(double x);
extern fn double frexp(double x, int* exp);
extern fn double ldexp(double x, int exp);
extern fn double modf(double x, double* iiptr);
extern fn double scalbn(double x, int n);
extern fn int ilogb(double x);
extern fn double logb(double x);
extern fn double nextafter(double x, double y);
extern fn double nexttoward(double x, double y);
extern fn double copysign(double x, double y);
extern fn double fabs(double x);
extern fn double fmod(double x, double y);
extern fn double remainder(double x, double y);
extern fn double remquo(double x, double y, int* quo);
extern fn double fmax(double x, double y);
extern fn double fmin(double x, double y);
extern fn double fdim(double x, double y);
extern fn double fma(double x, double y, double z);
extern fn int fpclassify(double x);
extern fn int isfinite(double x);
extern fn int isinf(double x);
extern fn int isnan(double x);
extern fn int isnormal(double x);
extern fn int signbit(double x);

// Float versions
extern fn float sinf(float x);
extern fn float cosf(float x);
extern fn float tanf(float x);
extern fn float asinf(float x);
extern fn float acosf(float x);
extern fn float atanf(float x);
extern fn float atan2f(float y, float x);
extern fn float sinhf(float x);
extern fn float coshf(float x);
extern fn float tanhf(float x);
extern fn float asinhf(float x);
extern fn float acoshf(float x);
extern fn float atanhf(float x);
extern fn float expf(float x);
extern fn float exp2f(float x);
extern fn float expm1f(float x);
extern fn float logf(float x);
extern fn float log10f(float x);
extern fn float log2f(float x);
extern fn float log1pf(float x);
extern fn float powf(float x, float y);
extern fn float sqrtf(float x);
extern fn float cbrtf(float x);
extern fn float hypotf(float x, float y);
extern fn float erff(float x);
extern fn float erfcf(float x);
extern fn float tgammaf(float x);
extern fn float lgammaf(float x);
extern fn float ceilf(float x);
extern fn float floorf(float x);
extern fn float truncf(float x);
extern fn float roundf(float x);
extern fn long lroundf(float x);

extern fn float rintf(float x);
extern fn long lrintf(float x);

extern fn float nearbyintf(float x);
extern fn float frexpf(float x, int* exp);
extern fn float ldexpf(float x, int exp);
extern fn float modff(float x, float* iiptr);
extern fn float scalbnf(float x, int n);
extern fn int ilogbf(float x);
extern fn float logbf(float x);
extern fn float nextafterf(float x, float y);
extern fn float nexttowardf(float x, double y);
extern fn float copysignf(float x, float y);
extern fn float fabsf(float x);
extern fn float fmodf(float x, float y);
extern fn float remainderf(float x, float y);
extern fn float remquof(float x, float y, int* quo);
extern fn float fmaxf(float x, float y);
extern fn float fminf(float x, float y);
extern fn float fdimf(float x, float y);
extern fn float fmaf(float x, float y, float z);

// Long double versions
extern fn double sinl(double x);
extern fn double cosl(double x);
extern fn double tanl(double x);
extern fn double asinl(double x);
extern fn double acosl(double x);
extern fn double atanl(double x);
extern fn double atan2l(double y, double x);
extern fn double sinhl(double x);
extern fn double coshl(double x);
extern fn double tanhl(double x);
extern fn double asinhl(double x);
extern fn double acoshl(double x);
extern fn double atanhl(double x);
extern fn double expl(double x);
extern fn double exp2l(double x);
extern fn double expm1l(double x);
extern fn double logl(double x);
extern fn double log10l(double x);
extern fn double log2l(double x);
extern fn double log1pl(double x);
extern fn double powl(double x, double y);
extern fn double sqrtl(double x);
extern fn double cbrtl(double x);
extern fn double hypotl(double x, double y);
extern fn double erfl(double x);
extern fn double erfcl(double x);
extern fn double tgammal(double x);
extern fn double lgammal(double x);
extern fn double ceill(double x);
extern fn double floorl(double x);
extern fn double truncl(double x);
extern fn double roundl(double x);
extern fn long lroundl(double x);

extern fn double rintl(double x);
extern fn long lrintl(double x);

extern fn double nearbyintl(double x);
extern fn double frexpl(double x, int* exp);
extern fn double ldexpl(double x, int exp);
extern fn double modfl(double x, double* iiptr);
extern fn double scalbnl(double x, int n);
extern fn int ilogbl(double x);
extern fn double logbl(double x);
extern fn double nextafterl(double x, double y);
extern fn double nexttowardl(double x, double y);
extern fn double copysignl(double x, double y);
extern fn double fabsl(double x);
extern fn double fmodl(double x, double y);
extern fn double remainderl(double x, double y);
extern fn double remquol(double x, double y, int* quo);
extern fn double fmaxl(double x, double y);
extern fn double fminl(double x, double y);
extern fn double fdiml(double x, double y);
extern fn double fmal(double x, double y, double z);

// Constants
const double M_E = 2.71828182845904523536;
const double M_LOG2E = 1.44269504088896340736;
const double M_LOG10E = 0.434294481903251827651;
const double M_LN2 = 0.693147180559945309417;
const double M_LN10 = 2.30258509299404568402;
const double M_PI = 3.14159265358979323846;
const double M_PI_2 = 1.57079632679489661923;
const double M_PI_4 = 0.785398163397448309616;
const double M_1_PI = 0.318309886183790671538;
const double M_2_PI = 0.636619772367581343076;
const double M_2_SQRTPI = 1.12837916709551257390;
const double M_SQRT2 = 1.41421356237309504880;
const double M_SQRT1_2 = 0.707106781186547524401;

const int FP_NAN = 1;
const int FP_INFINITE = 2;
const int FP_ZERO = 3;
const int FP_NORMAL = 4;
const int FP_SUBNORMAL = 5;

// Special values
const double HUGE_VAL = double.inf;
const float HUGE_VALF = float.inf;
const double HUGE_VALL = double.inf;
const double INFINITY = double.inf;
const double NAN = double.nan;


// ========== FreeBSD ==========

module c::math @if(env::FREEBSD);

// Same as Linux/Darwin - FreeBSD follows POSIX closely
extern fn double sin(double x);
extern fn double cos(double x);
extern fn double tan(double x);
extern fn double asin(double x);
extern fn double acos(double x);
extern fn double atan(double x);
extern fn double atan2(double y, double x);
extern fn double sinh(double x);
extern fn double cosh(double x);
extern fn double tanh(double x);
extern fn double asinh(double x);
extern fn double acosh(double x);
extern fn double atanh(double x);
extern fn double exp(double x);
extern fn double exp2(double x);
extern fn double expm1(double x);
extern fn double log(double x);
extern fn double log10(double x);
extern fn double log2(double x);
extern fn double log1p(double x);
extern fn double pow(double x, double y);
extern fn double sqrt(double x);
extern fn double cbrt(double x);
extern fn double hypot(double x, double y);
extern fn double erf(double x);
extern fn double erfc(double x);
extern fn double tgamma(double x);
extern fn double lgamma(double x);
extern fn double ceil(double x);
extern fn double floor(double x);
extern fn double trunc(double x);
extern fn double round(double x);
extern fn long lround(double x);

extern fn double rint(double x);
extern fn long lrint(double x);

extern fn double nearbyint(double x);
extern fn double frexp(double x, int* exp);
extern fn double ldexp(double x, int exp);
extern fn double modf(double x, double* iiptr);
extern fn double scalbn(double x, int n);
extern fn int ilogb(double x);
extern fn double logb(double x);
extern fn double nextafter(double x, double y);
extern fn double nexttoward(double x, double y);
extern fn double copysign(double x, double y);
extern fn double fabs(double x);
extern fn double fmod(double x, double y);
extern fn double remainder(double x, double y);
extern fn double remquo(double x, double y, int* quo);
extern fn double fmax(double x, double y);
extern fn double fmin(double x, double y);
extern fn double fdim(double x, double y);
extern fn double fma(double x, double y, double z);
extern fn int fpclassify(double x);
extern fn int isfinite(double x);
extern fn int isinf(double x);
extern fn int isnan(double x);
extern fn int isnormal(double x);
extern fn int signbit(double x);

// Float and long double versions (same as Linux)
extern fn float sinf(float x);
extern fn float cosf(float x);
extern fn float tanf(float x);
extern fn float sqrtf(float x);
extern fn float powf(float x, float y);
extern fn float expf(float x);
extern fn float logf(float x);
extern fn float fabsf(float x);
extern fn float ceilf(float x);
extern fn float floorf(float x);
// ... (all other float versions)

extern fn double sinl(double x);
extern fn double cosl(double x);
extern fn double tanl(double x);
extern fn double sqrtl(double x);
extern fn double powl(double x, double y);
extern fn double expl(double x);
extern fn double logl(double x);
extern fn double fabsl(double x);
extern fn double ceill(double x);
extern fn double floorl(double x);
// ... (all other long double versions)

// Constants
const double M_E = 2.71828182845904523536;
const double M_LOG2E = 1.44269504088896340736;
const double M_LOG10E = 0.434294481903251827651;
const double M_LN2 = 0.693147180559945309417;
const double M_LN10 = 2.30258509299404568402;
const double M_PI = 3.14159265358979323846;
const double M_PI_2 = 1.57079632679489661923;
const double M_PI_4 = 0.785398163397448309616;
const double M_1_PI = 0.318309886183790671538;
const double M_2_PI = 0.636619772367581343076;
const double M_2_SQRTPI = 1.12837916709551257390;
const double M_SQRT2 = 1.41421356237309504880;
const double M_SQRT1_2 = 0.707106781186547524401;

const int FP_NAN = 0;
const int FP_INFINITE = 1;
const int FP_ZERO = 2;
const int FP_SUBNORMAL = 3;
const int FP_NORMAL = 4;

// Special values
const double HUGE_VAL = double.inf;
const float HUGE_VALF = float.inf;
const double HUGE_VALL = double.inf;
const double INFINITY = double.inf;
const double NAN = double.nan;


// ========== NetBSD ==========

module c::math @if(env::NETBSD);

// Same as FreeBSD/Linux
extern fn double sin(double x);
extern fn double cos(double x);
extern fn double tan(double x);
extern fn double asin(double x);
extern fn double acos(double x);
extern fn double atan(double x);
extern fn double atan2(double y, double x);
extern fn double sinh(double x);
extern fn double cosh(double x);
extern fn double tanh(double x);
extern fn double asinh(double x);
extern fn double acosh(double x);
extern fn double atanh(double x);
extern fn double exp(double x);
extern fn double exp2(double x);
extern fn double expm1(double x);
extern fn double log(double x);
extern fn double log10(double x);
extern fn double log2(double x);
extern fn double log1p(double x);
extern fn double pow(double x, double y);
extern fn double sqrt(double x);
extern fn double cbrt(double x);
extern fn double hypot(double x, double y);
extern fn double erf(double x);
extern fn double erfc(double x);
extern fn double tgamma(double x);
extern fn double lgamma(double x);
extern fn double ceil(double x);
extern fn double floor(double x);
extern fn double trunc(double x);
extern fn double round(double x);
extern fn long lround(double x);

extern fn double rint(double x);
extern fn long lrint(double x);

extern fn double nearbyint(double x);
extern fn double frexp(double x, int* exp);
extern fn double ldexp(double x, int exp);
extern fn double modf(double x, double* iiptr);
extern fn double scalbn(double x, int n);
extern fn int ilogb(double x);
extern fn double logb(double x);
extern fn double nextafter(double x, double y);
extern fn double copysign(double x, double y);
extern fn double fabs(double x);
extern fn double fmod(double x, double y);
extern fn double remainder(double x, double y);
extern fn double fmax(double x, double y);
extern fn double fmin(double x, double y);
extern fn double fma(double x, double y, double z);
extern fn int isfinite(double x);
extern fn int isinf(double x);
extern fn int isnan(double x);
extern fn int signbit(double x);

// Float versions
extern fn float sinf(float x);
extern fn float cosf(float x);
extern fn float sqrtf(float x);
extern fn float fabsf(float x);
// ... (other float versions)

// Constants
const double M_E = 2.71828182845904523536;
const double M_LOG2E = 1.44269504088896340736;
const double M_LOG10E = 0.434294481903251827651;
const double M_LN2 = 0.693147180559945309417;
const double M_LN10 = 2.30258509299404568402;
const double M_PI = 3.14159265358979323846;
const double M_PI_2 = 1.57079632679489661923;
const double M_PI_4 = 0.785398163397448309616;
const double M_1_PI = 0.318309886183790671538;
const double M_2_PI = 0.636619772367581343076;
const double M_2_SQRTPI = 1.12837916709551257390;
const double M_SQRT2 = 1.41421356237309504880;
const double M_SQRT1_2 = 0.707106781186547524401;

// Special values
const double HUGE_VAL = double.inf;
const float HUGE_VALF = float.inf;
const double HUGE_VALL = double.inf;
const double INFINITY = double.inf;
const double NAN = double.nan;

// ========== OpenBSD ==========

module c::math @if(env::OPENBSD);

// Same as other BSDs
extern fn double sin(double x);
extern fn double cos(double x);
extern fn double tan(double x);
extern fn double asin(double x);
extern fn double acos(double x);
extern fn double atan(double x);
extern fn double atan2(double y, double x);
extern fn double sinh(double x);
extern fn double cosh(double x);
extern fn double tanh(double x);
extern fn double asinh(double x);
extern fn double acosh(double x);
extern fn double atanh(double x);
extern fn double exp(double x);
extern fn double exp2(double x);
extern fn double expm1(double x);
extern fn double log(double x);
extern fn double log10(double x);
extern fn double log2(double x);
extern fn double log1p(double x);
extern fn double pow(double x, double y);
extern fn double sqrt(double x);
extern fn double cbrt(double x);
extern fn double hypot(double x, double y);
extern fn double erf(double x);
extern fn double erfc(double x);
extern fn double tgamma(double x);
extern fn double lgamma(double x);
extern fn double ceil(double x);
extern fn double floor(double x);
extern fn double trunc(double x);
extern fn double round(double x);
extern fn long lround(double x);

extern fn double rint(double x);
extern fn long lrint(double x);

extern fn double nearbyint(double x);
extern fn double frexp(double x, int* exp);
extern fn double ldexp(double x, int exp);
extern fn double modf(double x, double* iiptr);
extern fn double scalbn(double x, int n);
extern fn int ilogb(double x);
extern fn double logb(double x);
extern fn double nextafter(double x, double y);
extern fn double copysign(double x, double y);
extern fn double fabs(double x);
extern fn double fmod(double x, double y);
extern fn double remainder(double x, double y);
extern fn double fmax(double x, double y);
extern fn double fmin(double x, double y);
extern fn double fma(double x, double y, double z);
extern fn int isfinite(double x);
extern fn int isinf(double x);
extern fn int isnan(double x);
extern fn int signbit(double x);

// Float versions
extern fn float sinf(float x);
extern fn float cosf(float x);
extern fn float sqrtf(float x);
extern fn float fabsf(float x);
// ... (other float versions)

// Constants
const double M_E = 2.71828182845904523536;
const double M_LOG2E = 1.44269504088896340736;
const double M_LOG10E = 0.434294481903251827651;
const double M_LN2 = 0.693147180559945309417;
const double M_LN10 = 2.30258509299404568402;
const double M_PI = 3.14159265358979323846;
const double M_PI_2 = 1.57079632679489661923;
const double M_PI_4 = 0.785398163397448309616;
const double M_1_PI = 0.318309886183790671538;
const double M_2_PI = 0.636619772367581343076;
const double M_2_SQRTPI = 1.12837916709551257390;
const double M_SQRT2 = 1.41421356237309504880;
const double M_SQRT1_2 = 0.707106781186547524401;

// Special values
const double HUGE_VAL = double.inf;
const float HUGE_VALF = float.inf;
const double HUGE_VALL = double.inf;
const double INFINITY = double.inf;
const double NAN = double.nan;


// ========== Windows ==========

module c::math @if(env::WIN32);

// Standard C math functions (available on Windows)
extern fn double sin(double x);
extern fn double cos(double x);
extern fn double tan(double x);
extern fn double asin(double x);
extern fn double acos(double x);
extern fn double atan(double x);
extern fn double atan2(double y, double x);
extern fn double sinh(double x);
extern fn double cosh(double x);
extern fn double tanh(double x);
extern fn double exp(double x);
extern fn double log(double x);
extern fn double log10(double x);
extern fn double pow(double x, double y);
extern fn double sqrt(double x);
extern fn double ceil(double x);
extern fn double floor(double x);
extern fn double fabs(double x);
extern fn double fmod(double x, double y);
extern fn double frexp(double x, int* exp);
extern fn double ldexp(double x, int exp);
extern fn double modf(double x, double* iiptr);

// C99 functions (Visual Studio 2013+)
extern fn double asinh(double x);
extern fn double acosh(double x);
extern fn double atanh(double x);
extern fn double exp2(double x);
extern fn double expm1(double x);
extern fn double log2(double x);
extern fn double log1p(double x);
extern fn double cbrt(double x);
extern fn double hypot(double x, double y);
extern fn double erf(double x);
extern fn double erfc(double x);
extern fn double tgamma(double x);
extern fn double lgamma(double x);
extern fn double trunc(double x);
extern fn double round(double x);
extern fn long lround(double x);

extern fn double rint(double x);
extern fn long lrint(double x);

extern fn double nearbyint(double x);
extern fn double remainder(double x, double y);
extern fn double remquo(double x, double y, int* quo);
extern fn double copysign(double x, double y);
extern fn double nan(char* tagp);
extern fn double nextafter(double x, double y);
extern fn double scalbn(double x, int n);
extern fn int ilogb(double x);
extern fn double logb(double x);
extern fn double fmax(double x, double y);
extern fn double fmin(double x, double y);
extern fn double fdim(double x, double y);
extern fn double fma(double x, double y, double z);

// Float versions
extern fn float sinf(float x);
extern fn float cosf(float x);
extern fn float tanf(float x);
extern fn float asinf(float x);
extern fn float acosf(float x);
extern fn float atanf(float x);
extern fn float atan2f(float y, float x);
extern fn float sinhf(float x);
extern fn float coshf(float x);
extern fn float tanhf(float x);
extern fn float asinhf(float x);
extern fn float acoshf(float x);
extern fn float atanhf(float x);
extern fn float expf(float x);
extern fn float exp2f(float x);
extern fn float expm1f(float x);
extern fn float logf(float x);
extern fn float log10f(float x);
extern fn float log2f(float x);
extern fn float log1pf(float x);
extern fn float powf(float x, float y);
extern fn float sqrtf(float x);
extern fn float cbrtf(float x);
extern fn float hypotf(float x, float y);
extern fn float erff(float x);
extern fn float erfcf(float x);
extern fn float tgammaf(float x);
extern fn float lgammaf(float x);
extern fn float ceilf(float x);
extern fn float floorf(float x);
extern fn float truncf(float x);
extern fn float roundf(float x);
extern fn long lroundf(float x);

extern fn float rintf(float x);
extern fn long lrintf(float x);

extern fn float nearbyintf(float x);
extern fn float frexpf(float x, int* exp);
extern fn float ldexpf(float x, int exp);
extern fn float modff(float x, float* iiptr);
extern fn float remainderf(float x, float y);
extern fn float remquof(float x, float y, int* quo);
extern fn float copysignf(float x, float y);
extern fn float nanf(char* tagp);
extern fn float nextafterf(float x, float y);
extern fn float scalbnf(float x, int n);
extern fn int ilogbf(float x);
extern fn float logbf(float x);
extern fn float fmaxf(float x, float y);
extern fn float fminf(float x, float y);
extern fn float fdimf(float x, float y);
extern fn float fmaf(float x, float y, float z);
extern fn float fabsf(float x);
extern fn float fmodf(float x, float y);

// Long double versions (often same as double on Windows)
extern fn double sinl(double x);
extern fn double cosl(double x);
extern fn double tanl(double x);
extern fn double sqrtl(double x);
extern fn double powl(double x, double y);
extern fn double fabsl(double x);
extern fn double ceill(double x);
extern fn double floorl(double x);

// Windows-specific functions (underscore versions)
extern fn int _isnan(double x);
extern fn int _finite(double x);
extern fn int _fpclass(double x);
extern fn double _copysign(double x, double y);
extern fn double _chgsign(double x);
extern fn double _scalb(double x, long exp);
extern fn double _logb(double x);
extern fn double _nextafter(double x, double y);
extern fn int _isnanf(float x);
extern fn int _finitef(float x);

// Classification (C99 macros - may need alternative implementation)
extern fn int fpclassify(double x);
extern fn int isfinite(double x);
extern fn int isinf(double x);
extern fn int isnan(double x);
extern fn int isnormal(double x);
extern fn int signbit(double x);

// FP classification constants
const int _FPCLASS_SNAN = 0x0001;  // Signaling NaN
const int _FPCLASS_QNAN = 0x0002;  // Quiet NaN
const int _FPCLASS_NINF = 0x0004;  // Negative infinity
const int _FPCLASS_NN = 0x0008;    // Negative normal
const int _FPCLASS_ND = 0x0010;    // Negative denormal
const int _FPCLASS_NZ = 0x0020;    // Negative zero
const int _FPCLASS_PZ = 0x0040;    // Positive zero
const int _FPCLASS_PD = 0x0080;    // Positive denormal
const int _FPCLASS_PN = 0x0100;    // Positive normal
const int _FPCLASS_PINF = 0x0200;  // Positive infinity

const int FP_NAN = 0;
const int FP_INFINITE = 1;
const int FP_ZERO = 2;
const int FP_SUBNORMAL = 3;
const int FP_NORMAL = 4;

// Constants (non-standard but often available)
const double M_E = 2.71828182845904523536;
const double M_LOG2E = 1.44269504088896340736;
const double M_LOG10E = 0.434294481903251827651;
const double M_LN2 = 0.693147180559945309417;
const double M_LN10 = 2.30258509299404568402;
const double M_PI = 3.14159265358979323846;
const double M_PI_2 = 1.57079632679489661923;
const double M_PI_4 = 0.785398163397448309616;
const double M_1_PI = 0.318309886183790671538;
const double M_2_PI = 0.636619772367581343076;
const double M_2_SQRTPI = 1.12837916709551257390;
const double M_SQRT2 = 1.41421356237309504880;
const double M_SQRT1_2 = 0.707106781186547524401;

