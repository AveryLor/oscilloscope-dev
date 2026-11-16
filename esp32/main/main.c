#include "esp_log.h"

#include "afe.h"
#include "cmd.h"
#include "fpga_link.h"
#include "or_protect.h"
#include "stream.h"
#include "vknob.h"

static const char *TAG = "main";

void app_main(void)
{
    ESP_LOGI(TAG, "oscilloscope esp32 stub");

    ESP_ERROR_CHECK(afe_init());
    ESP_ERROR_CHECK(fpga_link_init());
    stream_init();
    cmd_init();
    ESP_ERROR_CHECK(or_protect_init());
    // The knob is a convenience: the GUI can still set the vertical scale, so
    // a failure here must not take the scope down.
    esp_err_t knob = vknob_init();
    if (knob != ESP_OK) {
        ESP_LOGW(TAG, "vertical-scale knob disabled: %s", esp_err_to_name(knob));
    }
}
