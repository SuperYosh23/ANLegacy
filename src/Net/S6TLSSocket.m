#import "S6TLSSocket.h"
#import "S6Common.h"

// (the alert a server refused the handshake with is read from the context's private input buffer)
#define MBEDTLS_ALLOW_PRIVATE_ACCESS
#include "mbedtls/build_info.h"
#include "mbedtls/ssl.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/error.h"
#if defined(MBEDTLS_PSA_CRYPTO_C)
#include "psa/crypto.h"
#endif

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>

static mbedtls_x509_crt g_cacert;
static BOOL g_caLoaded = NO;
static NSInteger g_caCount = 0;
static dispatch_once_t g_caOnce;

#pragma mark - Session cache (TLS session resumption)

#define TW_SESSION_CACHE_SIZE 32
#define TW_SESSION_MAX_AGE (6 * 3600)

typedef struct {
    char key[280];
    mbedtls_ssl_session session;
    time_t savedAt;
    int used;
} S6SessionEntry;

static S6SessionEntry g_sessions[TW_SESSION_CACHE_SIZE];
static pthread_mutex_t g_sessionLock = PTHREAD_MUTEX_INITIALIZER;

static void S6SessionKey(NSString *host, int port, char *out, size_t outLen)
{
    snprintf(out, outLen, "%s:%d", [[host lowercaseString] UTF8String] ?: "", port);
}

// Installs a remembered session into the context (before the handshake). Returns YES when one was found.
static BOOL S6SessionLoad(const char *key, mbedtls_ssl_context *ssl)
{
    BOOL ok = NO;
    pthread_mutex_lock(&g_sessionLock);
    for (int i = 0; i < TW_SESSION_CACHE_SIZE; i++) {
        S6SessionEntry *e = &g_sessions[i];
        if (!e->used || strcmp(e->key, key) != 0) continue;
        if (time(NULL) - e->savedAt > TW_SESSION_MAX_AGE) {
            mbedtls_ssl_session_free(&e->session);
            e->used = 0;
            break;
        }
        ok = mbedtls_ssl_set_session(ssl, &e->session) == 0;
        break;
    }
    pthread_mutex_unlock(&g_sessionLock);
    return ok;
}

static void S6SessionStore(const char *key, mbedtls_ssl_context *ssl)
{
    mbedtls_ssl_session s;
    mbedtls_ssl_session_init(&s);
    if (mbedtls_ssl_get_session(ssl, &s) != 0) {
        mbedtls_ssl_session_free(&s);
        return;
    }
    pthread_mutex_lock(&g_sessionLock);
    int slot = -1;
    for (int i = 0; i < TW_SESSION_CACHE_SIZE; i++) {
        if (g_sessions[i].used && strcmp(g_sessions[i].key, key) == 0) { slot = i; break; }
    }
    if (slot < 0) {
        for (int i = 0; i < TW_SESSION_CACHE_SIZE; i++) {
            if (!g_sessions[i].used) { slot = i; break; }
        }
    }
    if (slot < 0) {
        slot = 0;
        for (int i = 1; i < TW_SESSION_CACHE_SIZE; i++) {
            if (g_sessions[i].savedAt < g_sessions[slot].savedAt) slot = i;
        }
    }
    S6SessionEntry *e = &g_sessions[slot];
    if (e->used) mbedtls_ssl_session_free(&e->session);
    e->session = s;   // ownership of the session's buffers moves into the table
    strlcpy(e->key, key, sizeof(e->key));
    e->savedAt = time(NULL);
    e->used = 1;
    pthread_mutex_unlock(&g_sessionLock);
}

static void S6SessionForget(const char *key)
{
    pthread_mutex_lock(&g_sessionLock);
    for (int i = 0; i < TW_SESSION_CACHE_SIZE; i++) {
        S6SessionEntry *e = &g_sessions[i];
        if (e->used && strcmp(e->key, key) == 0) {
            mbedtls_ssl_session_free(&e->session);
            e->used = 0;
        }
    }
    pthread_mutex_unlock(&g_sessionLock);
}

#pragma mark - Helpers

static NSString *S6MbedError(int ret)
{
    char buf[200];
    mbedtls_strerror(ret, buf, sizeof(buf));
    return [NSString stringWithFormat:@"%s (-0x%04x)", buf, (unsigned int)(-ret)];
}

static void S6SetError(NSError **error, NSInteger code, NSString *message)
{
    if (error) *error = S6MakeError(code, message);
}

static void S6LoadCABundle(void)
{
    mbedtls_x509_crt_init(&g_cacert);
#if defined(MBEDTLS_PSA_CRYPTO_C)
    psa_status_t st = psa_crypto_init();
    if (st != PSA_SUCCESS) S6Log(@"psa_crypto_init failed: %d", (int)st);
#endif
    NSString *path = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (!path) {
        S6Log(@"cacert.pem is missing from the app bundle");
        return;
    }
    NSData *pem = [NSData dataWithContentsOfFile:path];
    if (!pem.length) {
        S6Log(@"cacert.pem is empty");
        return;
    }
    NSMutableData *buf = [pem mutableCopy];
    uint8_t zero = 0;
    [buf appendBytes:&zero length:1];   // PEM input must be NUL terminated, length includes the NUL
    int ret = mbedtls_x509_crt_parse(&g_cacert, (const unsigned char *)buf.bytes, buf.length);
    if (ret < 0) {
        S6Log(@"CA bundle parse failed: %@", S6MbedError(ret));
        return;
    }
    NSInteger n = 0;
    for (mbedtls_x509_crt *c = &g_cacert; c != NULL && c->version != 0; c = c->next) n++;
    g_caCount = n;
    g_caLoaded = n > 0;
    S6Log(@"CA bundle loaded: %ld roots (%d unparsable)", (long)n, ret);
}

#pragma mark - Name resolution

// The system resolver can stall for a minute on some home routers (large CDN answers, odd AAAA
// handling), and getaddrinfo cannot be interrupted. Lookups therefore run on a helper thread
// with a deadline; once it passes, the name is asked directly from public resolvers over UDP.
// Every answer is cached so a slow lookup happens at most once per host.

#define TW_DNS_CACHE_SIZE 64
#define TW_DNS_MAX_ADDRS 8
// Legacy devices retry several YouTube clients in sequence, so a slow DNS or
// handshake on each one adds up to a minute before anything appears. Keep each
// individual attempt short; a working connection serves data well within these
// budgets on the devices that use mbedTLS.
#define TW_DNS_SYSTEM_WAIT_MS 1500        // patience with the system resolver before asking elsewhere
#define TW_DNS_FALLBACK_TIMEOUT_MS 1000   // per public resolver
#define TW_DNS_BUDGET_MS 4000             // total time for one lookup
#define TW_DNS_DEFAULT_TTL 300
#define TW_CONNECT_ATTEMPT_MS 2500        // per address when there are several
#define TW_HANDSHAKE_TIMEOUT_MS 4000

typedef struct {
    char host[256];
    struct sockaddr_storage addrs[TW_DNS_MAX_ADDRS];
    int count;
    time_t expires;
    int used;
} S6DNSEntry;

static S6DNSEntry g_dns[TW_DNS_CACHE_SIZE];
static pthread_mutex_t g_dnsLock = PTHREAD_MUTEX_INITIALIZER;

static int S6DNSCacheGet(const char *host, struct sockaddr_storage *out, int maxOut)
{
    int n = 0;
    pthread_mutex_lock(&g_dnsLock);
    for (int i = 0; i < TW_DNS_CACHE_SIZE; i++) {
        S6DNSEntry *e = &g_dns[i];
        if (!e->used || strcasecmp(e->host, host) != 0) continue;
        if (time(NULL) > e->expires) {
            e->used = 0;
            break;
        }
        n = MIN(e->count, maxOut);
        memcpy(out, e->addrs, sizeof(struct sockaddr_storage) * (size_t)n);
        break;
    }
    pthread_mutex_unlock(&g_dnsLock);
    return n;
}

static void S6DNSCachePut(const char *host, const struct sockaddr_storage *addrs, int count, time_t ttl)
{
    if (count <= 0 || strlen(host) >= sizeof(g_dns[0].host)) return;
    pthread_mutex_lock(&g_dnsLock);
    int slot = -1;
    for (int i = 0; i < TW_DNS_CACHE_SIZE; i++) {
        if (g_dns[i].used && strcasecmp(g_dns[i].host, host) == 0) { slot = i; break; }
    }
    if (slot < 0) {
        for (int i = 0; i < TW_DNS_CACHE_SIZE; i++) {
            if (!g_dns[i].used) { slot = i; break; }
        }
    }
    if (slot < 0) {
        slot = 0;
        for (int i = 1; i < TW_DNS_CACHE_SIZE; i++) {
            if (g_dns[i].expires < g_dns[slot].expires) slot = i;
        }
    }
    S6DNSEntry *e = &g_dns[slot];
    strlcpy(e->host, host, sizeof(e->host));
    e->count = MIN(count, TW_DNS_MAX_ADDRS);
    memcpy(e->addrs, addrs, sizeof(struct sockaddr_storage) * (size_t)e->count);
    e->expires = time(NULL) + ttl;
    e->used = 1;
    pthread_mutex_unlock(&g_dnsLock);
}

static const char *S6AddressString(const struct sockaddr_storage *sa, char *buf, size_t len)
{
    const void *src = NULL;
    if (sa->ss_family == AF_INET) src = &((const struct sockaddr_in *)sa)->sin_addr;
    else if (sa->ss_family == AF_INET6) src = &((const struct sockaddr_in6 *)sa)->sin6_addr;
    if (!src || !inet_ntop(sa->ss_family, src, buf, (socklen_t)len)) strlcpy(buf, "?", len);
    return buf;
}

// Copies an addrinfo list into sockaddr_storage slots, IPv4 first: home networks often hand out
// IPv6 addresses without a working route, and each dead address costs a connect timeout.
static int S6CopyAddrinfo(struct addrinfo *res, struct sockaddr_storage *out, int maxOut)
{
    int n = 0;
    for (int pass = 0; pass < 2 && n < maxOut; pass++) {
        for (struct addrinfo *ai = res; ai != NULL && n < maxOut; ai = ai->ai_next) {
            BOOL v4 = ai->ai_family == AF_INET;
            if ((pass == 0) != v4) continue;
            if (ai->ai_addrlen > sizeof(struct sockaddr_storage)) continue;
            memset(&out[n], 0, sizeof(out[n]));
            memcpy(&out[n], ai->ai_addr, ai->ai_addrlen);
            n++;
        }
    }
    return n;
}

@interface S6DNSJob : NSObject {
@public
    struct sockaddr_storage addrs[TW_DNS_MAX_ADDRS];
    int count;
    int gai;
}
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) dispatch_semaphore_t done;
@end

@implementation S6DNSJob
@end

static void S6SystemLookupStart(S6DNSJob *job)
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            const char *name = [job.host UTF8String] ?: "";
            struct addrinfo hints;
            memset(&hints, 0, sizeof(hints));
            hints.ai_socktype = SOCK_STREAM;
            hints.ai_protocol = IPPROTO_TCP;
            hints.ai_family = AF_INET;   // A records only first: the AAAA lookup alone can take seconds
            struct addrinfo *res = NULL;
            int gai = getaddrinfo(name, NULL, &hints, &res);
            if (gai != 0 || !res) {
                if (res) { freeaddrinfo(res); res = NULL; }
                hints.ai_family = AF_UNSPEC;
                gai = getaddrinfo(name, NULL, &hints, &res);
            }
            if (gai == 0 && res) {
                job->count = S6CopyAddrinfo(res, job->addrs, TW_DNS_MAX_ADDRS);
                if (job->count > 0) S6DNSCachePut(name, job->addrs, job->count, TW_DNS_DEFAULT_TTL);
            }
            job->gai = gai;
            if (res) freeaddrinfo(res);
            dispatch_semaphore_signal(job.done);
        }
    });
}

// Minimal DNS client: one A query over UDP to `server`. Returns the number of addresses written to
// `out` (network byte order), 0 for an authoritative "no such name", -1 when the server did not answer.
static int S6DNSEncodeName(const char *host, uint8_t *out, int maxOut)
{
    int o = 0;
    const char *p = host;
    while (*p) {
        const char *dot = strchr(p, '.');
        size_t len = dot ? (size_t)(dot - p) : strlen(p);
        if (len == 0 || len > 63 || o + (int)len + 2 >= maxOut) return -1;
        out[o++] = (uint8_t)len;
        memcpy(out + o, p, len);
        o += (int)len;
        if (!dot) break;
        p = dot + 1;
    }
    out[o++] = 0;
    return o;
}

static int S6DNSSkipName(const uint8_t *msg, int len, int off)
{
    int hops = 0;
    for (;;) {
        if (off >= len) return -1;
        uint8_t l = msg[off];
        if (l == 0) return off + 1;
        if ((l & 0xC0) == 0xC0) return off + 1 < len ? off + 2 : -1;
        off += 1 + l;
        if (++hops > 128) return -1;
    }
}

static int S6DNSQueryA(const char *server, const char *host, uint32_t *out, int maxOut, uint32_t *ttlOut, int timeoutMs)
{
    uint8_t q[512];
    uint16_t id = (uint16_t)(arc4random() & 0xFFFF);
    memset(q, 0, 12);
    q[0] = (uint8_t)(id >> 8);
    q[1] = (uint8_t)(id & 0xFF);
    q[2] = 0x01;   // recursion desired
    q[5] = 1;      // one question
    int n = S6DNSEncodeName(host, q + 12, (int)sizeof(q) - 12 - 4);
    if (n < 0) return -1;
    int qlen = 12 + n;
    q[qlen++] = 0; q[qlen++] = 1;   // type A
    q[qlen++] = 0; q[qlen++] = 1;   // class IN

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_len = sizeof(sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons(53);
    inet_pton(AF_INET, server, &sa.sin_addr);
    int result = -1;
    if (sendto(fd, q, (size_t)qlen, 0, (struct sockaddr *)&sa, sizeof(sa)) == qlen) {
        struct pollfd pfd;
        pfd.fd = fd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        if (poll(&pfd, 1, timeoutMs) > 0) {
            uint8_t r[2048];
            ssize_t rl = recv(fd, r, sizeof(r), 0);
            if (rl >= 12 && r[0] == q[0] && r[1] == q[1]) {
                int rcode = r[3] & 0x0F;
                int qd = (r[4] << 8) | r[5];
                int an = (r[6] << 8) | r[7];
                int off = 12;
                for (int i = 0; i < qd && off >= 0; i++) {
                    off = S6DNSSkipName(r, (int)rl, off);
                    if (off >= 0) off += 4;
                }
                int count = 0;
                uint32_t minTTL = 0;
                for (int i = 0; i < an && off >= 0; i++) {
                    off = S6DNSSkipName(r, (int)rl, off);
                    if (off < 0 || off + 10 > (int)rl) break;
                    int type = (r[off] << 8) | r[off + 1];
                    uint32_t ttl = ((uint32_t)r[off + 4] << 24) | ((uint32_t)r[off + 5] << 16) | ((uint32_t)r[off + 6] << 8) | r[off + 7];
                    int rdlen = (r[off + 8] << 8) | r[off + 9];
                    off += 10;
                    if (off + rdlen > (int)rl) break;
                    if (type == 1 && rdlen == 4 && count < maxOut) {
                        memcpy(&out[count++], r + off, 4);
                        if (!minTTL || ttl < minTTL) minTTL = ttl;
                    }
                    off += rdlen;
                }
                if (ttlOut) *ttlOut = minTTL;
                result = (rcode == 0 || rcode == 3) ? count : -1;   // NXDOMAIN counts as a real answer
            }
        }
    }
    close(fd);
    return result;
}

static void S6StoreIPv4(struct sockaddr_storage *out, uint32_t ip)
{
    struct sockaddr_in *sin = (struct sockaddr_in *)out;
    memset(out, 0, sizeof(*out));
    sin->sin_len = sizeof(*sin);
    sin->sin_family = AF_INET;
    memcpy(&sin->sin_addr, &ip, 4);
}

// Waits for the system lookup in short slices so that a cancel is noticed. Returns YES when it finished.
static BOOL S6WaitForLookup(S6DNSJob *job, int *waitedMs, int untilMs, volatile BOOL *cancelled)
{
    while (*waitedMs < untilMs) {
        if (cancelled && *cancelled) return NO;
        if (dispatch_semaphore_wait(job.done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC))) == 0) return YES;
        *waitedMs += 250;
    }
    return NO;
}

// Resolves `host` into up to `maxOut` addresses (IPv4 first, ports unset). Returns the count; 0 with `error` set.
static int S6ResolveHost(NSString *host, struct sockaddr_storage *out, int maxOut, volatile BOOL *cancelled, NSError **error)
{
    const char *name = [host UTF8String] ?: "";
    struct in_addr a4;
    struct in6_addr a6;
    NSString *bare = host;
    if ([bare hasPrefix:@"["] && [bare hasSuffix:@"]"] && bare.length > 2) bare = [bare substringWithRange:NSMakeRange(1, bare.length - 2)];
    if (inet_pton(AF_INET, name, &a4) == 1) {
        S6StoreIPv4(&out[0], a4.s_addr);
        return 1;
    }
    if (inet_pton(AF_INET6, [bare UTF8String] ?: "", &a6) == 1) {
        struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)&out[0];
        memset(sin6, 0, sizeof(*sin6));
        sin6->sin6_len = sizeof(*sin6);
        sin6->sin6_family = AF_INET6;
        sin6->sin6_addr = a6;
        return 1;
    }
    int n = S6DNSCacheGet(name, out, maxOut);
    if (n > 0) return n;

    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    S6DNSJob *job = [[S6DNSJob alloc] init];
    job.host = host;
    job.done = dispatch_semaphore_create(0);
    S6SystemLookupStart(job);

    // 1. the system resolver, briefly
    int waited = 0;
    BOOL finished = S6WaitForLookup(job, &waited, TW_DNS_SYSTEM_WAIT_MS, cancelled);
    if (cancelled && *cancelled) {
        S6SetError(error, S6ErrorCancelled, L(@"Cancelled"));
        return 0;
    }
    if (finished && job->count > 0) {
        n = MIN(job->count, maxOut);
        memcpy(out, job->addrs, sizeof(struct sockaddr_storage) * (size_t)n);
        return n;
    }

    // 2. public resolvers directly (also when the system resolver reported a failure: routers lie)
    static const char *servers[] = { "8.8.8.8", "1.1.1.1" };
    for (int s = 0; s < 2; s++) {
        if (cancelled && *cancelled) {
            S6SetError(error, S6ErrorCancelled, L(@"Cancelled"));
            return 0;
        }
        uint32_t ips[TW_DNS_MAX_ADDRS];
        uint32_t ttl = 0;
        int got = S6DNSQueryA(servers[s], name, ips, TW_DNS_MAX_ADDRS, &ttl, TW_DNS_FALLBACK_TIMEOUT_MS);
        if (got > 0) {
            n = MIN(got, maxOut);
            for (int i = 0; i < n; i++) S6StoreIPv4(&out[i], ips[i]);
            time_t keep = ttl ? (time_t)MIN(ttl, 3600u) : TW_DNS_DEFAULT_TTL;
            S6DNSCachePut(name, out, n, MAX(keep, (time_t)30));
            S6Log(@"DNS: %@ resolved via %s in %ld ms (%d addresses; system resolver %@)", host, servers[s],
                  (long)((CFAbsoluteTimeGetCurrent() - started) * 1000), n, finished ? @"failed" : @"still busy");
            return n;
        }
        if (got == 0) {
            S6SetError(error, S6ErrorDNS, [NSString stringWithFormat:L(@"Could not resolve %@ (%s). Is the device online?"), host, "no such host"]);
            return 0;
        }
    }

    // 3. maybe the system resolver is merely slow: give it the rest of the budget
    if (!finished) finished = S6WaitForLookup(job, &waited, TW_DNS_BUDGET_MS, cancelled);
    if (cancelled && *cancelled) {
        S6SetError(error, S6ErrorCancelled, L(@"Cancelled"));
        return 0;
    }
    if (finished && job->count > 0) {
        n = MIN(job->count, maxOut);
        memcpy(out, job->addrs, sizeof(struct sockaddr_storage) * (size_t)n);
        S6Log(@"DNS: %@ resolved by the system resolver after %ld ms", host, (long)((CFAbsoluteTimeGetCurrent() - started) * 1000));
        return n;
    }
    const char *why = !finished ? "timed out" : (job->gai != 0 ? gai_strerror(job->gai) : "no addresses");
    S6Log(@"DNS: %@ failed after %ld ms: %s", host, (long)((CFAbsoluteTimeGetCurrent() - started) * 1000), why);
    S6SetError(error, S6ErrorDNS, [NSString stringWithFormat:L(@"Could not resolve %@ (%s). Is the device online?"), host, why]);
    return 0;
}

#pragma mark - TCP connect with timeout

static int S6ConnectTCP(NSString *host, int port, int timeoutMs, volatile BOOL *cancelled, NSError **error)
{
    struct sockaddr_storage addrs[TW_DNS_MAX_ADDRS];
    int n = S6ResolveHost(host, addrs, TW_DNS_MAX_ADDRS, cancelled, error);
    if (n <= 0) return -1;

    // Several candidates: each one gets a short slice of the budget so that a dead address does
    // not exhaust WebKit's patience; the poll runs in short steps so that a cancel is noticed.
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + timeoutMs / 1000.0;
    int fd = -1;
    int lastErr = 0;
    char abuf[64];
    for (int idx = 0; idx < n; idx++) {
        struct sockaddr_storage sa = addrs[idx];
        socklen_t salen;
        if (sa.ss_family == AF_INET) {
            ((struct sockaddr_in *)&sa)->sin_port = htons((uint16_t)port);
            salen = sizeof(struct sockaddr_in);
        } else if (sa.ss_family == AF_INET6) {
            ((struct sockaddr_in6 *)&sa)->sin6_port = htons((uint16_t)port);
            salen = sizeof(struct sockaddr_in6);
        } else {
            continue;
        }
        int remainingMs = (int)((deadline - CFAbsoluteTimeGetCurrent()) * 1000);
        if (remainingMs <= 0) {
            lastErr = ETIMEDOUT;
            break;
        }
        int attemptMs = idx < n - 1 ? MIN(remainingMs, TW_CONNECT_ATTEMPT_MS) : remainingMs;
        fd = socket(sa.ss_family, SOCK_STREAM, IPPROTO_TCP);
        if (fd < 0) { lastErr = errno; continue; }
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        int rc = connect(fd, (struct sockaddr *)&sa, salen);
        if (rc != 0 && errno != EINPROGRESS) {
            lastErr = errno;
            close(fd);
            fd = -1;
            continue;
        }
        if (rc != 0) {
            int elapsed = 0, pr = 0;
            while (elapsed < attemptMs) {
                if (cancelled && *cancelled) {
                    close(fd);
                    S6SetError(error, S6ErrorCancelled, L(@"Cancelled"));
                    return -1;
                }
                int slice = MIN(250, attemptMs - elapsed);
                struct pollfd pfd;
                pfd.fd = fd;
                pfd.events = POLLOUT;
                pfd.revents = 0;
                pr = poll(&pfd, 1, slice);
                if (pr != 0) break;
                elapsed += slice;
            }
            if (pr <= 0) {
                lastErr = (pr == 0) ? ETIMEDOUT : errno;
                S6Log(@"connect %@ [%s]:%d: %s after %d ms", host, S6AddressString(&sa, abuf, sizeof(abuf)), port,
                      pr == 0 ? "timed out" : strerror(lastErr), attemptMs);
                close(fd);
                fd = -1;
                continue;
            }
            int soerr = 0;
            socklen_t slen = sizeof(soerr);
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen);
            if (soerr != 0) {
                lastErr = soerr;
                S6Log(@"connect %@ [%s]:%d: %s", host, S6AddressString(&sa, abuf, sizeof(abuf)), port, strerror(soerr));
                close(fd);
                fd = -1;
                continue;
            }
        }
        fcntl(fd, F_SETFL, flags);   // back to blocking mode
        break;
    }
    if (fd < 0) {
        NSString *why = lastErr == ETIMEDOUT ? L(@"connection timed out") : [NSString stringWithUTF8String:strerror(lastErr)];
        S6SetError(error, lastErr == ETIMEDOUT ? S6ErrorTimeout : S6ErrorConnect,
                   [NSString stringWithFormat:L(@"Could not connect to %@: %@"), host, why]);
    }
    return fd;
}

@implementation S6TLSSocket {
    mbedtls_net_context _net;
    mbedtls_ssl_context _ssl;
    mbedtls_ssl_config _conf;
    mbedtls_entropy_context _entropy;
    mbedtls_ctr_drbg_context _ctr;
    BOOL _initialized;
    BOOL _connected;
    volatile BOOL _cancelled;
    uint32_t _readTimeoutMs;
    char _sessionKey[280];
}

+ (void)ensureCALoaded
{
    dispatch_once(&g_caOnce, ^{ S6LoadCABundle(); });
}

+ (void)warmUp
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [S6TLSSocket ensureCALoaded];
    });
}

+ (BOOL)caBundleAvailable
{
    [self ensureCALoaded];
    return g_caLoaded;
}

+ (NSInteger)caCertificateCount
{
    [self ensureCALoaded];
    return g_caCount;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        mbedtls_net_init(&_net);
        mbedtls_ssl_init(&_ssl);
        mbedtls_ssl_config_init(&_conf);
        mbedtls_entropy_init(&_entropy);
        mbedtls_ctr_drbg_init(&_ctr);
        _initialized = YES;
        _sessionKey[0] = 0;
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

#pragma mark - TLS

- (BOOL)connectToHost:(NSString *)host port:(int)port verify:(BOOL)verify
     connectTimeoutMs:(int)connectMs readTimeoutMs:(int)readMs error:(NSError **)error
{
    _readTimeoutMs = (uint32_t)readMs;
    if (self.plain) {
        int fd = S6ConnectTCP(host, port, connectMs, &_cancelled, error);
        if (fd < 0) return NO;
        @synchronized (self) {
            _net.fd = fd;
        }
        _connected = YES;
        return YES;
    }

    [S6TLSSocket ensureCALoaded];
    int ret;
    const char *pers = "Sixify-ios6";

    if ((ret = mbedtls_ctr_drbg_seed(&_ctr, mbedtls_entropy_func, &_entropy, (const unsigned char *)pers, strlen(pers))) != 0) {
        S6SetError(error, S6ErrorTLS, [NSString stringWithFormat:@"RNG seed failed: %@", S6MbedError(ret)]);
        return NO;
    }
    if ((ret = mbedtls_ssl_config_defaults(&_conf, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT)) != 0) {
        S6SetError(error, S6ErrorTLS, [NSString stringWithFormat:@"TLS config failed: %@", S6MbedError(ret)]);
        return NO;
    }
    mbedtls_ssl_conf_min_tls_version(&_conf, MBEDTLS_SSL_VERSION_TLS1_2);
    if (verify) {
        if (!g_caLoaded) {
            S6SetError(error, S6ErrorCertificate, L(@"The certificate bundle is missing, cannot verify the server."));
            return NO;
        }
        mbedtls_ssl_conf_authmode(&_conf, MBEDTLS_SSL_VERIFY_REQUIRED);
        mbedtls_ssl_conf_ca_chain(&_conf, &g_cacert, NULL);
    } else {
        mbedtls_ssl_conf_authmode(&_conf, MBEDTLS_SSL_VERIFY_NONE);
    }
    mbedtls_ssl_conf_rng(&_conf, mbedtls_ctr_drbg_random, &_ctr);
    // A server that accepts the TCP connection but never answers the ClientHello must not hold
    // the load for the whole read timeout; the real read timeout is applied after the handshake.
    mbedtls_ssl_conf_read_timeout(&_conf, (uint32_t)MIN(readMs, TW_HANDSHAKE_TIMEOUT_MS));
#if defined(MBEDTLS_SSL_SESSION_TICKETS)
    mbedtls_ssl_conf_session_tickets(&_conf, MBEDTLS_SSL_SESSION_TICKETS_ENABLED);
#endif

    if ((ret = mbedtls_ssl_setup(&_ssl, &_conf)) != 0) {
        S6SetError(error, S6ErrorTLS, [NSString stringWithFormat:@"TLS setup failed: %@", S6MbedError(ret)]);
        return NO;
    }
    if ((ret = mbedtls_ssl_set_hostname(&_ssl, [host UTF8String])) != 0) {
        S6SetError(error, S6ErrorTLS, [NSString stringWithFormat:@"TLS hostname failed: %@", S6MbedError(ret)]);
        return NO;
    }
    S6SessionKey(host, port, _sessionKey, sizeof(_sessionKey));
    BOOL resuming = S6SessionLoad(_sessionKey, &_ssl);

    int fd = S6ConnectTCP(host, port, connectMs, &_cancelled, error);
    if (fd < 0) return NO;
    @synchronized (self) {
        _net.fd = fd;
    }
    if (_cancelled) {
        S6SetError(error, S6ErrorCancelled, L(@"Cancelled"));
        return NO;
    }
    mbedtls_ssl_set_bio(&_ssl, &_net, mbedtls_net_send, NULL, mbedtls_net_recv_timeout);

    while ((ret = mbedtls_ssl_handshake(&_ssl)) != 0) {
        if (_cancelled) {
            S6SetError(error, S6ErrorCancelled, L(@"Cancelled"));
            return NO;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (resuming) S6SessionForget(_sessionKey);
        if (ret == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED) {
            uint32_t flags = mbedtls_ssl_get_verify_result(&_ssl);
            char vbuf[512];
            mbedtls_x509_crt_verify_info(vbuf, sizeof(vbuf), "", flags);
            NSString *info = [[NSString stringWithUTF8String:vbuf] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *hint = (flags & (MBEDTLS_X509_BADCERT_EXPIRED | MBEDTLS_X509_BADCERT_FUTURE)) ?
                L(@"Check the date and time of this device.") : L(@"Certificate verification can be turned off in Settings.");
            S6SetError(error, S6ErrorCertificate, [NSString stringWithFormat:L(@"Server certificate rejected: %@. %@"), info, hint]);
            return NO;
        }
        if (ret == MBEDTLS_ERR_SSL_TIMEOUT) {
            S6SetError(error, S6ErrorTimeout, L(@"TLS handshake timed out."));
            return NO;
        }
        NSString *what = S6MbedError(ret);
        if (ret == MBEDTLS_ERR_SSL_FATAL_ALERT_MESSAGE && _ssl.in_msg) {
            // which alert the server sent (40 handshake_failure, 47 illegal_parameter, 70 protocol_version,
            // 71 insufficient_security, 80 internal_error, 112 unrecognized_name ...)
            what = [what stringByAppendingFormat:@" (alert %d)", (int)_ssl.in_msg[1]];
        }
        S6SetError(error, S6ErrorTLS, [NSString stringWithFormat:L(@"TLS handshake failed: %@"), what]);
        return NO;
    }
    _connected = YES;
    mbedtls_ssl_conf_read_timeout(&_conf, (uint32_t)readMs);
    S6SessionStore(_sessionKey, &_ssl);
    return YES;
}

- (NSString *)cipherSuite
{
    if (!_connected || self.plain) return nil;
    const char *cs = mbedtls_ssl_get_ciphersuite(&_ssl);
    return cs ? [NSString stringWithUTF8String:cs] : nil;
}

- (NSString *)tlsVersion
{
    if (!_connected) return nil;
    if (self.plain) return @"plain";
    const char *v = mbedtls_ssl_get_version(&_ssl);
    return v ? [NSString stringWithUTF8String:v] : nil;
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    const unsigned char *p = (const unsigned char *)data.bytes;
    size_t left = data.length;
    while (left > 0) {
        if (_cancelled) {
            S6SetError(error, S6ErrorCancelled, L(@"Cancelled"));
            return NO;
        }
        int ret = self.plain ? mbedtls_net_send(&_net, p, left) : mbedtls_ssl_write(&_ssl, p, left);
        if (ret > 0) {
            p += ret;
            left -= (size_t)ret;
            continue;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        S6SetError(error, S6ErrorConnectionLost, [NSString stringWithFormat:L(@"Sending the request failed: %@"), S6MbedError(ret)]);
        return NO;
    }
    return YES;
}

- (NSInteger)readIntoBuffer:(void *)buffer maxLength:(NSUInteger)maxLength error:(NSError **)error
{
    for (;;) {
        if (_cancelled) {
            S6SetError(error, S6ErrorCancelled, L(@"Cancelled"));
            return -1;
        }
        int ret = self.plain ? mbedtls_net_recv_timeout(&_net, (unsigned char *)buffer, maxLength, _readTimeoutMs)
                             : mbedtls_ssl_read(&_ssl, (unsigned char *)buffer, maxLength);
        if (ret > 0) return ret;
        if (ret == 0 || ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) return 0;
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (ret == MBEDTLS_ERR_NET_CONN_RESET) return 0;   // abrupt close without close_notify
        if (ret == MBEDTLS_ERR_SSL_TIMEOUT) {
            S6SetError(error, S6ErrorTimeout, L(@"The server stopped responding (timeout)."));
            return -1;
        }
        S6SetError(error, S6ErrorConnectionLost, [NSString stringWithFormat:L(@"Receiving the response failed: %@"), S6MbedError(ret)]);
        return -1;
    }
}

- (BOOL)isConnected
{
    return _connected && !_cancelled;
}

- (BOOL)isLikelyAlive
{
    int fd;
    @synchronized (self) {
        fd = _net.fd;
    }
    if (fd < 0 || !_connected || _cancelled) return NO;
    char c;
    ssize_t n = recv(fd, &c, 1, MSG_PEEK | MSG_DONTWAIT);
    if (n == 0) return NO;                                       // orderly close by the peer
    if (n < 0) return errno == EAGAIN || errno == EWOULDBLOCK;   // nothing pending: open and idle
    return NO;   // unexpected bytes on an idle connection (e.g. a TLS close_notify): do not reuse
}

- (int)fileDescriptor
{
    @synchronized (self) {
        return _net.fd;
    }
}

- (BOOL)hasBufferedData
{
    if (self.plain || !_connected || !_initialized) return NO;
    return mbedtls_ssl_get_bytes_avail(&_ssl) > 0 || mbedtls_ssl_check_pending(&_ssl);
}

- (void)setReadTimeoutMs:(uint32_t)ms
{
    _readTimeoutMs = ms;
    if (!self.plain && _initialized) mbedtls_ssl_conf_read_timeout(&_conf, ms);
}

- (void)cancel
{
    _cancelled = YES;
    @synchronized (self) {
        if (_net.fd >= 0) shutdown(_net.fd, SHUT_RDWR);
    }
}

- (void)close
{
    if (!_initialized) return;
    if (_connected && !_cancelled && !self.plain) {
        mbedtls_ssl_close_notify(&_ssl);
    }
    @synchronized (self) {
        mbedtls_net_free(&_net);
    }
    mbedtls_ssl_free(&_ssl);
    mbedtls_ssl_config_free(&_conf);
    mbedtls_ctr_drbg_free(&_ctr);
    mbedtls_entropy_free(&_entropy);
    _initialized = NO;
    _connected = NO;
}

@end
