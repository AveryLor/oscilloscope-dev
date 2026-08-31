#include "esp_log.h"

#include "afe.h"
#include "fpga_link.h"
#include "stream.h"

static const char *TAG = "main";

void app_main(void)
{
    ESP_LOGI(TAG, "oscilloscope esp32 stub");

    ESP_ERROR_CHECK(afe_init());
    ESP_ERROR_CHECK(fpga_link_init());
    stream_init();
}
