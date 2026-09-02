/* Spark CUDA companion — NVML probe/memstat (no kernels, no VRAM alloc).
 * Prefer GPU 0. Never load Spark compute on the configured voice-only index.
 * Build: make spark-cuda
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <nvml.h>

static void die_nvml(const char *what, nvmlReturn_t r) {
    fprintf(stderr, "spark-cuda-probe: %s: %s\n", what, nvmlErrorString(r));
    exit(1);
}

static int is_voice_only(unsigned int i, const char *name) {
    const char *env = getenv("SPARK_CUDA_NEVER_INDEX");
    const char *needle = getenv("SPARK_CUDA_VOICE_NAME_SUBSTR");

    if (env && env[0])
        return i == (unsigned int)atoi(env);
    /* Heuristic: workstation "PRO" + high VRAM voice cards often include PRO */
    if (needle && needle[0] && name && strstr(name, needle) != NULL)
        return 1;
    if (name && strstr(name, "RTX PRO") != NULL)
        return 1;
    (void)i;
    return 0;
}

static void emit_device(unsigned int i, int as_json) {
    nvmlDevice_t dev;
    nvmlReturn_t r = nvmlDeviceGetHandleByIndex(i, &dev);
    if (r != NVML_SUCCESS)
        die_nvml("GetHandleByIndex", r);

    char name[96];
    char uuid[96];
    r = nvmlDeviceGetName(dev, name, sizeof name);
    if (r != NVML_SUCCESS)
        die_nvml("GetName", r);
    r = nvmlDeviceGetUUID(dev, uuid, sizeof uuid);
    if (r != NVML_SUCCESS)
        die_nvml("GetUUID", r);

    nvmlMemory_t mem;
    r = nvmlDeviceGetMemoryInfo(dev, &mem);
    if (r != NVML_SUCCESS)
        die_nvml("GetMemoryInfo", r);

    nvmlEnableState_t persist = NVML_FEATURE_DISABLED;
    nvmlDeviceGetPersistenceMode(dev, &persist);

    unsigned int gen = 0, width = 0, max_gen = 0, max_width = 0;
    nvmlDeviceGetCurrPcieLinkGeneration(dev, &gen);
    nvmlDeviceGetCurrPcieLinkWidth(dev, &width);
    nvmlDeviceGetMaxPcieLinkGeneration(dev, &max_gen);
    nvmlDeviceGetMaxPcieLinkWidth(dev, &max_width);

    int voice = is_voice_only(i, name);
    const char *role = voice ? "voice-only-never-spark"
                             : (i == 0 ? "spark-prefer" : "ok-secondary");

    if (as_json) {
        printf(
            "{\"index\":%u,\"name\":\"%s\",\"uuid\":\"%s\","
            "\"role\":\"%s\","
            "\"mem_total_mib\":%llu,\"mem_used_mib\":%llu,"
            "\"mem_free_mib\":%llu,"
            "\"persistence\":%s,"
            "\"pcie_gen\":%u,\"pcie_gen_max\":%u,"
            "\"pcie_width\":%u,\"pcie_width_max\":%u}",
            i, name, uuid, role,
            (unsigned long long)(mem.total / 1048576ULL),
            (unsigned long long)(mem.used / 1048576ULL),
            (unsigned long long)(mem.free / 1048576ULL),
            persist == NVML_FEATURE_ENABLED ? "true" : "false",
            gen, max_gen, width, max_width);
        return;
    }

    printf(
        "gpu %u name=%s uuid=%s role=%s "
        "mem_mib=%llu/%llu free=%llu persist=%s "
        "pcie=gen%ux%u (max gen%ux%u)\n",
        i, name, uuid, role,
        (unsigned long long)(mem.used / 1048576ULL),
        (unsigned long long)(mem.total / 1048576ULL),
        (unsigned long long)(mem.free / 1048576ULL),
        persist == NVML_FEATURE_ENABLED ? "on" : "off",
        gen, width, max_gen, max_width);
}

int main(int argc, char **argv) {
    int as_json = 0;
    for (int a = 1; a < argc; a++) {
        if (strcmp(argv[a], "--memstat") == 0 ||
            strcmp(argv[a], "--json") == 0) {
            as_json = 1;
        } else if (strcmp(argv[a], "--help") == 0) {
            fputs(
                "Usage: spark-cuda-probe [--memstat|--json]\n"
                "NVML-only; no CUDA kernels; never targets voice-only index.\n",
                stdout);
            return 0;
        }
    }

    nvmlReturn_t r = nvmlInit();
    if (r != NVML_SUCCESS)
        die_nvml("nvmlInit", r);

    unsigned int n = 0;
    r = nvmlDeviceGetCount(&n);
    if (r != NVML_SUCCESS)
        die_nvml("DeviceGetCount", r);

    if (as_json) {
        printf("{\"device_count\":%u,\"prefer_index\":0,"
               "\"never_index\":[1],\"devices\":[",
               n);
        for (unsigned int i = 0; i < n; i++) {
            if (i)
                fputc(',', stdout);
            emit_device(i, 1);
        }
        fputs("]}\n", stdout);
    } else {
        printf("spark-cuda-probe devices=%u "
               "(prefer index 0; never voice-only index)\n",
               n);
        for (unsigned int i = 0; i < n; i++)
            emit_device(i, 0);
    }

    nvmlShutdown();
    return 0;
}
