#include "esp_log.h"
#include "nvs_flash.h"

#include "afe.h"
#include "cmd.h"
#include "deskew.h"
#include "fpga_link.h"
#include "stream.h"

static const char *TAG = "main";

void app_main(void)
{
    ESP_LOGI(TAG, "oscilloscope esp32 stub");

    // NVS holds the ADC deskew calibration. A full or version-mismatched
    // partition is wiped rather than left blocking boot.
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    ESP_ERROR_CHECK(afe_init());
    ESP_ERROR_CHECK(fpga_link_init());

    // Before stream_init arms anything: a PLL phase change resets the FPGA's
    // capture domain. Without a saved calibration the FPGA keeps its defaults
    // (180 deg, no per-bit delay) until the host sends CALIBRATE.
    if (fpga_link_present() && deskew_load_and_apply() == ESP_ERR_NOT_FOUND) {
        ESP_LOGW(TAG, "no ADC deskew calibration saved; send CALIBRATE");
    }
    stream_init();
    cmd_init();
}
