/*
 * Platform glue for mbedTLS on iOS 6.
 *  - mbedtls_ms_time(): upstream uses clock_gettime(), which only exists on iOS 10+.
 *  - mbedtls_hardware_poll(): extra entropy source backed by SecRandomCopyBytes().
 */
#include "mbedtls/build_info.h"
#include "mbedtls/platform_time.h"
#include "mbedtls/entropy.h"
#include "entropy_poll.h"

#include <sys/time.h>
#include <stddef.h>
#include <Security/SecRandom.h>

#if defined(MBEDTLS_PLATFORM_MS_TIME_ALT)
mbedtls_ms_time_t mbedtls_ms_time(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (mbedtls_ms_time_t)tv.tv_sec * 1000 + (mbedtls_ms_time_t)(tv.tv_usec / 1000);
}
#endif

#if defined(MBEDTLS_ENTROPY_HARDWARE_ALT)
int mbedtls_hardware_poll(void *data, unsigned char *output, size_t len, size_t *olen)
{
    (void)data;
    if (len == 0) {
        *olen = 0;
        return 0;
    }
    if (SecRandomCopyBytes(kSecRandomDefault, len, output) != 0) {
        *olen = 0;
        return MBEDTLS_ERR_ENTROPY_SOURCE_FAILED;
    }
    *olen = len;
    return 0;
}
#endif
