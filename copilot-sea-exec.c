/*
 * copilot-sea-exec.so — LD_PRELOAD exec shim for native Termux GitHub Copilot CLI.
 *
 * Problem: Copilot's in-app `/update` downloads a fresh SEA binary, renames it over
 * process.execPath (whose PT_INTERP reverts to the stock /lib/ld-linux-aarch64.so.1,
 * which does not exist in Termux), then auto-respawns it with
 *     spawn(process.execPath, args, {detached:true})
 * That raw exec bypasses the launcher's patchelf step, so the kernel cannot find the
 * ELF interpreter and reports (on a file that is right there):
 *     Failed to start: spawn <...>/copilot ENOENT
 * The DNS shim additionally scrubs LD_PRELOAD/LD_LIBRARY_PATH from the process env,
 * so even a correctly-interpreted respawn would lose its glibc lib path + DNS fix.
 *
 * Fix: interpose the exec / posix_spawn family. When the target is the copilot
 * binary (its self-respawn), rewrite the call to invoke Termux's glibc loader
 * explicitly —  ld-linux-aarch64.so.1  <copilot-bin>  <args...> — which ignores the
 * bad PT_INTERP, and re-inject LD_LIBRARY_PATH, LD_PRELOAD (these shims) and
 * SSL_CERT_FILE so the respawned copilot loads glibc, keeps DNS, and survives the
 * NEXT /update as well. Every non-copilot exec passes through untouched.
 *
 * Config (exported by the launcher; not among the vars the DNS shim scrubs):
 *   COPILOT_SEA_BIN     absolute path of the copilot binary to match
 *   COPILOT_SEA_LOADER  absolute path of the Termux glibc ld-linux loader
 *   COPILOT_SEA_LIBPATH value for the child's LD_LIBRARY_PATH
 *   COPILOT_SEA_PRELOAD value for the child's LD_PRELOAD (these shims)
 *   COPILOT_SEA_SSL     value for the child's SSL_CERT_FILE (optional)
 *
 * Header-light, mirroring resolv-shim: libc/dl symbols bind from the host glibc at
 * load. Build with the same recipe (see install.sh).
 */

typedef unsigned long size_t;
typedef int pid_t;

extern void  *dlsym(void *handle, const char *symbol);
extern char  *getenv(const char *name);
extern int    strcmp(const char *a, const char *b);
extern int    strncmp(const char *a, const char *b, size_t n);
extern size_t strlen(const char *s);
extern void  *malloc(size_t n);
extern void  *memcpy(void *d, const void *s, size_t n);
extern char **environ;

#define RTLD_NEXT ((void *) -1L)

static int str_starts(const char *s, const char *pfx) {
    return strncmp(s, pfx, strlen(pfx)) == 0;
}
static int str_ends(const char *s, const char *sfx) {
    size_t ls = strlen(s), lf = strlen(sfx);
    return ls >= lf && strcmp(s + (ls - lf), sfx) == 0;
}

/* Match only the copilot binary's own path (its self-respawn), nothing else. */
static int is_copilot(const char *path) {
    const char *bin = getenv("COPILOT_SEA_BIN");
    if (!path || !bin || !*bin) return 0;
    if (strcmp(path, bin) == 0) return 1;
    return str_ends(path, "/copilot");
}

/* Allocate a "KEY=VALUE" string (KEY must already include the '='). */
static char *kv(const char *key, const char *val) {
    size_t lk = strlen(key), lv = strlen(val);
    char *p = (char *)malloc(lk + lv + 1);
    if (!p) return 0;
    memcpy(p, key, lk);
    memcpy(p + lk, val, lv + 1);          /* value + terminating NUL */
    return p;
}

static size_t env_count(char *const *e) {
    size_t n = 0;
    if (e) while (e[n]) n++;
    return n;
}

/* Child argv: [loader, prog, original argv[1..], NULL]. */
static char **build_argv(const char *loader, const char *prog, char *const *argv) {
    size_t n = 0;
    if (argv) while (argv[n]) n++;
    size_t extra = (n > 0) ? (n - 1) : 0;
    char **out = (char **)malloc((2 + extra + 1) * sizeof(char *));
    if (!out) return 0;
    size_t i = 0;
    out[i++] = (char *)loader;
    out[i++] = (char *)prog;
    for (size_t j = 1; j < n; j++) out[i++] = argv[j];
    out[i] = 0;
    return out;
}

/* Child envp: base minus stale loader/ssl vars, plus fresh ones from COPILOT_SEA_*. */
static char **build_envp(char *const *base) {
    const char *libp = getenv("COPILOT_SEA_LIBPATH");
    const char *prel = getenv("COPILOT_SEA_PRELOAD");
    const char *ssl  = getenv("COPILOT_SEA_SSL");
    size_t n = env_count(base);
    char **out = (char **)malloc((n + 4) * sizeof(char *));
    if (!out) return (char **)base;
    size_t i = 0;
    for (size_t j = 0; j < n; j++) {
        const char *e = base[j];
        if (str_starts(e, "LD_LIBRARY_PATH=")) continue;
        if (str_starts(e, "LD_PRELOAD="))      continue;
        if (str_starts(e, "SSL_CERT_FILE="))   continue;
        out[i++] = base[j];
    }
    if (libp && *libp) out[i++] = kv("LD_LIBRARY_PATH=", libp);
    if (prel && *prel) out[i++] = kv("LD_PRELOAD=", prel);
    if (ssl  && *ssl)  out[i++] = kv("SSL_CERT_FILE=", ssl);
    out[i] = 0;
    return out;
}

int execve(const char *path, char *const argv[], char *const envp[]) {
    static int (*real)(const char *, char *const[], char *const[]);
    if (!real) real = dlsym(RTLD_NEXT, "execve");
    if (is_copilot(path)) {
        const char *ld = getenv("COPILOT_SEA_LOADER");
        if (ld && *ld) {
            char **na = build_argv(ld, path, argv);
            char **ne = build_envp(envp);
            if (na) return real(ld, na, ne);
        }
    }
    return real(path, argv, envp);
}

int execv(const char *path, char *const argv[]) {
    if (is_copilot(path)) return execve(path, argv, environ);
    static int (*real)(const char *, char *const[]);
    if (!real) real = dlsym(RTLD_NEXT, "execv");
    return real(path, argv);
}

int execvp(const char *file, char *const argv[]) {
    if (is_copilot(file)) return execve(file, argv, environ);
    static int (*real)(const char *, char *const[]);
    if (!real) real = dlsym(RTLD_NEXT, "execvp");
    return real(file, argv);
}

int execvpe(const char *file, char *const argv[], char *const envp[]) {
    if (is_copilot(file)) return execve(file, argv, envp);
    static int (*real)(const char *, char *const[], char *const[]);
    if (!real) real = dlsym(RTLD_NEXT, "execvpe");
    return real(file, argv, envp);
}

int posix_spawn(pid_t *pid, const char *path, const void *fa, const void *attr,
                char *const argv[], char *const envp[]) {
    static int (*real)(pid_t *, const char *, const void *, const void *,
                       char *const[], char *const[]);
    if (!real) real = dlsym(RTLD_NEXT, "posix_spawn");
    if (is_copilot(path)) {
        const char *ld = getenv("COPILOT_SEA_LOADER");
        if (ld && *ld) {
            char **na = build_argv(ld, path, argv);
            char **ne = build_envp(envp ? envp : environ);
            if (na) return real(pid, ld, fa, attr, na, ne);
        }
    }
    return real(pid, path, fa, attr, argv, envp);
}

int posix_spawnp(pid_t *pid, const char *file, const void *fa, const void *attr,
                 char *const argv[], char *const envp[]) {
    static int (*real)(pid_t *, const char *, const void *, const void *,
                       char *const[], char *const[]);
    if (!real) real = dlsym(RTLD_NEXT, "posix_spawnp");
    if (is_copilot(file)) {
        const char *ld = getenv("COPILOT_SEA_LOADER");
        if (ld && *ld) {
            char **na = build_argv(ld, file, argv);
            char **ne = build_envp(envp ? envp : environ);
            if (na) return real(pid, ld, fa, attr, na, ne);
        }
    }
    return real(pid, file, fa, attr, argv, envp);
}
