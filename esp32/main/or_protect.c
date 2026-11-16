#include "or_protect.h"

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "afe.h"
#include "fpga_link.h"
#include "scope_proto.h"

static const char *TAG = "or_protect";

// Fallback poll period when no alarm edge arrives (jumper not fitted).
#define OR_POLL_MS         20
// Minimum time between gain steps: longer than a few OR windows (~10.5 ms
// each by default) plus relay settle, so each step is judged on samples taken
// at the new gain rather than ones already in flight.
#define OR_STEP_HOLDOFF_MS 100

static void or_protect_task(void *arg) {
    (void)arg;
    TickType_t last_step = 0;
    bool       have_step = false;
    for (;;) {
        (void)scope_wait_alarm(OR_POLL_MS);

        uint8_t alarm = 0;
        if (scope_alarm_read(&alarm) != ESP_OK || !(alarm & ALARM_OR_TRIP)) {
            continue;
        }
        const TickType_t now = xTaskGetTickCount();
        if (have_step && (now - last_step) < pdMS_TO_TICKS(OR_STEP_HOLDOFF_MS)) {
            // Leave the alarm latched and wait out the holdoff; the line stays
            // high, so sleep instead of spinning on it.
            vTaskDelay(pdMS_TO_TICKS(OR_STEP_HOLDOFF_MS) - (now - last_step));
            continue;
        }
        esp_err_t err = afe_protect_step();
        if (err == ESP_ERR_NOT_FOUND) {
            ESP_LOGW(TAG, "over-range but front end already at minimum gain");
        } else if (err != ESP_OK) {
            ESP_LOGE(TAG, "gain step failed: %s", esp_err_to_name(err));
        } else {
            ESP_LOGW(TAG, "sustained over-range: front-end gain reduced one step");
        }
        (void)scope_alarm_clear();
        last_step = now;
        have_step = true;
    }
}

esp_err_t or_protect_init(void) {
    BaseType_t ok = xTaskCreate(or_protect_task, "or_protect", 3072, NULL, 6, NULL);
    return ok == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}
