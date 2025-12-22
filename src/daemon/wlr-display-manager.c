#define _POSIX_C_SOURCE 200809L
// Alternatively: #define _XOPEN_SOURCE 700


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <wayland-client.h>

// You'll need to generate this header from the protocol XML
// wayland-scanner client-header < wlr-output-management-unstable-v1.xml > wlr-output-management-unstable-v1-client-protocol.h
// wayland-scanner private-code < wlr-output-management-unstable-v1.xml > wlr-output-management-unstable-v1-protocol.c
#include "wlr-output-management-unstable-v1-client-protocol.h"

#define CONFIG_FILE_PATH "%s/.config/budgie-desktop/labwc/displays.conf"
#define MAX_PATH 512
#define MAX_OUTPUT 2048

typedef struct {
    struct wl_display *display;
    struct wl_registry *registry;
    struct zwlr_output_manager_v1 *output_manager;
    char config_path[MAX_PATH];
    int apply_on_start;
} AppState;

// Get full config file path
static void get_config_path(char *buf, size_t size) {
    const char *home = getenv("HOME");
    if (!home) {
        fprintf(stderr, "HOME environment variable not set\n");
        exit(1);
    }
    snprintf(buf, size, CONFIG_FILE_PATH, home);
}

// Create config directory if it doesn't exist
static void ensure_config_dir(const char *config_path) {
    char dir[MAX_PATH];
    snprintf(dir, sizeof(dir), "%s", config_path);
    
    // Find last slash to get directory
    char *last_slash = strrchr(dir, '/');
    if (last_slash) {
        *last_slash = '\0';
        mkdir(dir, 0755); // Create if doesn't exist, ignore error if exists
    }
}

// Execute wlr-randr and capture output
static char* run_wlr_randr(void) {
    FILE *fp;
    char *output = NULL;
    size_t output_size = 0;
    size_t output_len = 0;
    char buffer[256];
    
    fp = popen("wlr-randr 2>&1", "r");
    if (!fp) {
        perror("Failed to run wlr-randr");
        return NULL;
    }
    
    // Read all output
    while (fgets(buffer, sizeof(buffer), fp) != NULL) {
        size_t len = strlen(buffer);
        if (output_len + len + 1 > output_size) {
            output_size = output_size ? output_size * 2 : 4096;
            output = realloc(output, output_size);
            if (!output) {
                pclose(fp);
                return NULL;
            }
        }
        strcpy(output + output_len, buffer);
        output_len += len;
    }
    
    pclose(fp);
    return output;
}

// Save current display configuration
static int save_config(AppState *state) {
    char *config_data = run_wlr_randr();
    if (!config_data) {
        fprintf(stderr, "Failed to get display configuration\n");
        return -1;
    }
    
    ensure_config_dir(state->config_path);
    
    FILE *fp = fopen(state->config_path, "w");
    if (!fp) {
        fprintf(stderr, "Failed to open config file: %s\n", strerror(errno));
        free(config_data);
        return -1;
    }
    
    fputs(config_data, fp);
    fclose(fp);
    free(config_data);
    
    printf("Display configuration saved to %s\n", state->config_path);
    return 0;
}

// Parse a line for key-value pair
static int parse_line(const char *line, const char *key, char *value, size_t value_size) {
    const char *pos = strstr(line, key);
    if (!pos) return 0;
    
    pos += strlen(key);
    while (*pos == ' ' || *pos == ':') pos++;
    
    size_t i = 0;
    while (*pos && *pos != '\n' && i < value_size - 1) {
        value[i++] = *pos++;
    }
    value[i] = '\0';
    
    // Trim trailing whitespace
    while (i > 0 && (value[i-1] == ' ' || value[i-1] == '\r')) {
        value[--i] = '\0';
    }
    
    return 1;
}

// Apply saved display configuration
static int apply_config(AppState *state) {
    FILE *fp = fopen(state->config_path, "r");
    if (!fp) {
        fprintf(stderr, "No saved configuration found at %s\n", state->config_path);
        return -1;
    }
    
    char line[512];
    char output_name[128] = {0};
    char cmd[1024] = {0};
    char value[256];
    int in_output = 0;
    
    printf("Applying saved display configuration...\n");
    
    while (fgets(line, sizeof(line), fp)) {
        // New output section
        if (line[0] != ' ' && line[0] != '\n' && line[0] != '\t') {
            // Execute previous command if we have one
            if (cmd[0] != '\0') {
                printf("Executing: %s\n", cmd);
                system(cmd);
                cmd[0] = '\0';
            }
            
            // Extract output name (first word on line)
            sscanf(line, "%127s", output_name);
            snprintf(cmd, sizeof(cmd), "wlr-randr --output %s", output_name);
            in_output = 1;
            continue;
        }
        
        if (!in_output) continue;
        
        // Parse output properties
        if (parse_line(line, "Enabled:", value, sizeof(value))) {
            if (strcmp(value, "no") == 0) {
                snprintf(cmd, sizeof(cmd), "wlr-randr --output %s --off", output_name);
                system(cmd);
                cmd[0] = '\0';
                in_output = 0;
                continue;
            }
        }
        
        if (parse_line(line, "Position:", value, sizeof(value))) {
            strcat(cmd, " --pos ");
            strcat(cmd, value);
        }
        
        // Look for current mode line (contains "current")
        if (strstr(line, "current") && strstr(line, "px")) {
            int width, height;
            float refresh;
            if (sscanf(line, " %dx%d px, %f Hz", &width, &height, &refresh) == 3) {
                char mode[128];
                snprintf(mode, sizeof(mode), " --mode %dx%d@%.3fHz", width, height, refresh);
                strcat(cmd, mode);
            }
        }
        
        if (parse_line(line, "Transform:", value, sizeof(value))) {
            if (strcmp(value, "normal") != 0) {
                strcat(cmd, " --transform ");
                strcat(cmd, value);
            }
        }
        
        if (parse_line(line, "Scale:", value, sizeof(value))) {
            strcat(cmd, " --scale ");
            strcat(cmd, value);
        }
    }
    
    // Execute last command
    if (cmd[0] != '\0') {
        printf("Executing: %s\n", cmd);
        system(cmd);
    }
    
    fclose(fp);
    printf("Display configuration applied\n");
    return 0;
}

// Wayland output manager done event - fires when display config changes
static void output_manager_done(void *data,
        struct zwlr_output_manager_v1 *manager, uint32_t serial) {
    AppState *state = (AppState *)data;
    printf("Display configuration change detected\n");
    save_config(state);
}

static void output_manager_head(void *data,
        struct zwlr_output_manager_v1 *manager,
        struct zwlr_output_head_v1 *head) {
    // We don't need to track individual heads for this use case
}

static void output_manager_finished(void *data,
        struct zwlr_output_manager_v1 *manager) {
    fprintf(stderr, "Output manager finished, exiting\n");
    exit(1);
}

static const struct zwlr_output_manager_v1_listener output_manager_listener = {
    .head = output_manager_head,
    .done = output_manager_done,
    .finished = output_manager_finished,
};

// Registry handler to find the output manager
static void registry_global(void *data, struct wl_registry *registry,
        uint32_t name, const char *interface, uint32_t version) {
    AppState *state = (AppState *)data;
    
    if (strcmp(interface, zwlr_output_manager_v1_interface.name) == 0) {
        state->output_manager = wl_registry_bind(registry, name,
            &zwlr_output_manager_v1_interface, 2);
        zwlr_output_manager_v1_add_listener(state->output_manager,
            &output_manager_listener, state);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry,
        uint32_t name) {
    // Not handling removal
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static void print_usage(const char *prog) {
    printf("Usage: %s [OPTIONS]\n", prog);
    printf("Monitor and manage wlroots display configuration\n\n");
    printf("Options:\n");
    printf("  -a, --apply    Apply saved configuration and exit\n");
    printf("  -s, --save     Save current configuration and exit\n");
    printf("  -m, --monitor  Monitor for changes and auto-save (default)\n");
    printf("  -h, --help     Show this help message\n");
}

int main(int argc, char *argv[]) {
    AppState state = {0};
    int mode = 0; // 0=monitor, 1=apply, 2=save
    
    get_config_path(state.config_path, sizeof(state.config_path));
    
    // Parse arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-a") == 0 || strcmp(argv[i], "--apply") == 0) {
            mode = 1;
        } else if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "--save") == 0) {
            mode = 2;
        } else if (strcmp(argv[i], "-m") == 0 || strcmp(argv[i], "--monitor") == 0) {
            mode = 0;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }
    
    // Handle one-shot modes
    if (mode == 1) {
        return apply_config(&state);
    } else if (mode == 2) {
        return save_config(&state);
    }
    
    // Monitor mode - connect to Wayland
    printf("Starting display configuration monitor...\n");
    printf("Config file: %s\n", state.config_path);
    
    state.display = wl_display_connect(NULL);
    if (!state.display) {
        fprintf(stderr, "Failed to connect to Wayland display\n");
        return 1;
    }
    
    state.registry = wl_display_get_registry(state.display);
    wl_registry_add_listener(state.registry, &registry_listener, &state);
    
    // Initial roundtrip to get globals
    wl_display_roundtrip(state.display);
    
    if (!state.output_manager) {
        fprintf(stderr, "Compositor does not support wlr-output-management protocol\n");
        wl_display_disconnect(state.display);
        return 1;
    }
    
    printf("Connected to compositor, monitoring for display changes...\n");
    
    // Apply config on startup if it exists
    if (access(state.config_path, F_OK) == 0) {
        printf("Applying saved configuration on startup...\n");
        apply_config(&state);
    }
    
    // Event loop
    while (wl_display_dispatch(state.display) != -1) {
        // Continue processing events
    }
    
    wl_display_disconnect(state.display);
    return 0;
}
