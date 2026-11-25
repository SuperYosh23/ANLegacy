/*
 * mbedTLS configuration for Sixify on iOS 6 (armv7).
 *
 * The CI build renames the stock include/mbedtls/mbedtls_config.h to
 * mbedtls_config_default.h and installs this file in its place, so we start
 * from the upstream defaults and only trim what we do not need:
 *   - TLS 1.2 client only (no TLS 1.3, no DTLS, no server side)
 *   - no certificate writing, no self tests
 *   - entropy also from SecRandomCopyBytes (mbedtls_hardware_poll in mbedtls_glue.c)
 *   - mbedtls_ms_time() provided by us, because clock_gettime() does not exist on iOS < 10
 */
#ifndef MBEDTLS_CONFIG_IOS6_H
#define MBEDTLS_CONFIG_IOS6_H

#include "mbedtls/mbedtls_config_default.h"

/* --- protocol trimming ------------------------------------------------- */
#undef MBEDTLS_SSL_PROTO_TLS1_3
#undef MBEDTLS_SSL_TLS1_3_COMPATIBILITY_MODE
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_ENABLED
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_ENABLED
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_EPHEMERAL_ENABLED
#undef MBEDTLS_SSL_EARLY_DATA

#undef MBEDTLS_SSL_PROTO_DTLS
#undef MBEDTLS_SSL_DTLS_ANTI_REPLAY
#undef MBEDTLS_SSL_DTLS_HELLO_VERIFY
#undef MBEDTLS_SSL_DTLS_SRTP
#undef MBEDTLS_SSL_DTLS_CLIENT_PORT_REUSE
#undef MBEDTLS_SSL_DTLS_CONNECTION_ID
#undef MBEDTLS_SSL_DTLS_CONNECTION_ID_COMPAT

#undef MBEDTLS_SSL_SRV_C
#undef MBEDTLS_SSL_COOKIE_C
#undef MBEDTLS_SSL_TICKET_C
#undef MBEDTLS_SSL_CACHE_C

/* --- X.509: parse only -------------------------------------------------- */
#undef MBEDTLS_X509_CREATE_C
#undef MBEDTLS_X509_CRT_WRITE_C
#undef MBEDTLS_X509_CSR_WRITE_C
#undef MBEDTLS_X509_CSR_PARSE_C
#undef MBEDTLS_PK_WRITE_C
#undef MBEDTLS_PEM_WRITE_C

/* --- misc size reductions ---------------------------------------------- */
#undef MBEDTLS_SELF_TEST
#undef MBEDTLS_VERSION_FEATURES
#undef MBEDTLS_TIMING_C
#undef MBEDTLS_LMS_C
#undef MBEDTLS_LMS_PRIVATE
#undef MBEDTLS_PSA_CRYPTO_STORAGE_C
#undef MBEDTLS_PSA_ITS_FILE_C
#undef MBEDTLS_PSA_CRYPTO_SE_C

/* --- platform glue ------------------------------------------------------ */
#define MBEDTLS_ENTROPY_HARDWARE_ALT
#define MBEDTLS_PLATFORM_MS_TIME_ALT
#define MBEDTLS_THREADING_C
#define MBEDTLS_THREADING_PTHREAD

#endif /* MBEDTLS_CONFIG_IOS6_H */
