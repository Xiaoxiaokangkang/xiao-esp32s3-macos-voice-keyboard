#include <Arduino.h>
#include <USB.h>
#include <USBHIDKeyboard.h>
#include <driver/i2s.h>

extern "C" {
#include "tusb.h"
#include "device/usbd_pvt.h"
#include "class/audio/audio_device.h"
#include "esp32-hal-tinyusb.h"
}

namespace {

static_assert(D0 == 1 && D1 == 2 && D2 == 3 && D8 == 7 && D9 == 8 &&
                  D10 == 9,
              "Unexpected Seeed XIAO ESP32S3 pin mapping");
constexpr gpio_num_t kMicSck = static_cast<gpio_num_t>(D9);
constexpr gpio_num_t kMicWs = static_cast<gpio_num_t>(D10);
constexpr gpio_num_t kMicSd = static_cast<gpio_num_t>(D8);
constexpr int kTraeButton = D2;
constexpr int kFnButton = D1;
constexpr int kReturnButton = D0;
constexpr uint32_t kDebounceMs = 25;
constexpr uint32_t kSampleRate = 16000;
constexpr uint16_t kAudioPacketSize = 32;
constexpr size_t kSamplesPerPacket = kAudioPacketSize / sizeof(int16_t);
constexpr size_t kAudioRingSamples = 2048;
constexpr uint16_t kAudioDescriptorLength = TUD_AUDIO_MIC_ONE_CH_DESC_LEN;
constexpr bool kUsbTransportToneTest = false;

struct DebouncedButton {
  explicit DebouncedButton(int buttonPin) : pin(buttonPin) {}

  int pin;
  bool rawPressed = false;
  bool pressed = false;
  bool longActionDone = false;
  uint32_t changedAt = 0;
  uint32_t pressedAt = 0;
};

DebouncedButton traeButton{kTraeButton};
DebouncedButton fnButton{kFnButton};
DebouncedButton returnButton{kReturnButton};

USBHIDKeyboard keyboard;
int32_t i2sSamples[256];
int16_t audioRing[kAudioRingSamples] = {};
size_t audioRingRead = 0;
size_t audioRingWrite = 0;
size_t audioRingCount = 0;
portMUX_TYPE audioPacketMux = portMUX_INITIALIZER_UNLOCKED;

uint8_t muteState[2] = {0, 0};
int16_t volumeState[2] = {0, 0};
uint32_t sampleRate = kSampleRate;
uint8_t clockValid = 1;

uint16_t loadAudioDescriptor(uint8_t *dst, uint8_t *interfaceNumber) {
  const uint8_t stringIndex =
      tinyusb_add_string_descriptor("XIAO Voice Keyboard Microphone");
  const uint8_t endpoint = tinyusb_get_free_in_endpoint();
  if (endpoint == 0) return 0;

  const uint8_t descriptor[] = {
      TUD_AUDIO_MIC_ONE_CH_DESCRIPTOR(
          *interfaceNumber, stringIndex, 2, 16,
          static_cast<uint8_t>(0x80 | endpoint), kAudioPacketSize)};
  memcpy(dst, descriptor, sizeof(descriptor));
  *interfaceNumber += 2;
  return sizeof(descriptor);
}

void initMicrophone() {
  const i2s_config_t config = {
      .mode = static_cast<i2s_mode_t>(I2S_MODE_MASTER | I2S_MODE_RX),
      .sample_rate = kSampleRate,
      .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
      .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
      .communication_format = I2S_COMM_FORMAT_STAND_I2S,
      .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
      .dma_buf_count = 8,
      .dma_buf_len = 128,
      .use_apll = false,
      .tx_desc_auto_clear = false,
      .fixed_mclk = 0,
  };
  const i2s_pin_config_t pins = {
      .bck_io_num = kMicSck,
      .ws_io_num = kMicWs,
      .data_out_num = I2S_PIN_NO_CHANGE,
      .data_in_num = kMicSd,
  };
  ESP_ERROR_CHECK(i2s_driver_install(I2S_NUM_0, &config, 0, nullptr));
  ESP_ERROR_CHECK(i2s_set_pin(I2S_NUM_0, &pins));
}

void audioTask(void *) {
  while (true) {
    size_t bytesRead = 0;
    if (i2s_read(I2S_NUM_0, i2sSamples, sizeof(i2sSamples), &bytesRead,
                 portMAX_DELAY) != ESP_OK) {
      continue;
    }

    const size_t stereoWords = bytesRead / sizeof(i2sSamples[0]);
    if (stereoWords < kSamplesPerPacket * 2) continue;

    // INMP441 L/R selects which I2S slot contains data. Driver/board versions
    // disagree about whether that slot appears first or second in memory, so
    // select the slot carrying more energy instead of assuming an ordering.
    uint64_t evenEnergy = 0;
    uint64_t oddEnergy = 0;
    for (size_t i = 0; i + 1 < stereoWords; i += 2) {
      evenEnergy += static_cast<uint64_t>(llabs(static_cast<int64_t>(i2sSamples[i])));
      oddEnergy += static_cast<uint64_t>(llabs(static_cast<int64_t>(i2sSamples[i + 1])));
    }
    const size_t activeSlot = oddEnergy > evenEnergy ? 1 : 0;

    const size_t frameCount = stereoWords / 2;
    int16_t converted[128];
    for (size_t n = 0; n < frameCount; ++n) {
      // INMP441 output is a left-justified 24-bit value in a 32-bit I2S word.
      // >>13 converts to signed 16-bit with 8x gain relative to the raw
      // 16-bit extraction; this gives speech recognition a healthy level.
      int32_t value = i2sSamples[n * 2 + activeSlot] >> 13;
      value = constrain(value, -32768, 32767);
      converted[n] = static_cast<int16_t>(value);
    }

    portENTER_CRITICAL(&audioPacketMux);
    for (size_t n = 0; n < frameCount; ++n) {
      // When the producer gets ahead before recording starts, discard the
      // oldest sample and retain the most recent 128 ms of microphone audio.
      if (audioRingCount == kAudioRingSamples) {
        audioRingRead = (audioRingRead + 1) % kAudioRingSamples;
        --audioRingCount;
      }
      audioRing[audioRingWrite] = converted[n];
      audioRingWrite = (audioRingWrite + 1) % kAudioRingSamples;
      ++audioRingCount;
    }
    portEXIT_CRITICAL(&audioPacketMux);
  }
}

bool updateButton(DebouncedButton &button, uint32_t now) {
  const bool rawPressed = digitalRead(button.pin) == HIGH;
  if (rawPressed != button.rawPressed) {
    button.rawPressed = rawPressed;
    button.changedAt = now;
  }
  if (rawPressed == button.pressed || now - button.changedAt < kDebounceMs) {
    return false;
  }

  button.pressed = rawPressed;
  if (button.pressed) {
    button.pressedAt = now;
    button.longActionDone = false;
  }
  return true;
}

}  // namespace

extern "C" bool tracedAudioControl(uint8_t rhport, uint8_t stage,
                                    tusb_control_request_t const *request) {
  return audiod_control_xfer_cb(rhport, stage, request);
}

extern "C" bool tud_audio_tx_done_post_load_cb(uint8_t, uint16_t bytes,
                                               uint8_t, uint8_t, uint8_t) {
  (void)bytes;
  return true;
}

extern "C" bool tud_audio_tx_done_pre_load_cb(uint8_t, uint8_t, uint8_t,
                                               uint8_t) {
  // TinyUSB 0.15 expects microphone data to be supplied synchronously as it
  // prepares each isochronous packet. Always write a complete packet so the
  // host never sees a zero-length transfer during its lock-delay window.
  int16_t packet[kSamplesPerPacket];
  if (kUsbTransportToneTest) {
    // Temporary deterministic signal used to isolate USB transport from I2S.
    // Alternating samples are deliberately large and cannot be mistaken for
    // microphone noise or a formatting/rounding artifact on the Mac.
    static bool phase = false;
    for (size_t i = 0; i < kSamplesPerPacket; ++i) {
      phase = !phase;
      packet[i] = phase ? 12000 : -12000;
    }
  } else {
    portENTER_CRITICAL(&audioPacketMux);
    for (size_t i = 0; i < kSamplesPerPacket; ++i) {
      if (audioRingCount != 0) {
        packet[i] = audioRing[audioRingRead];
        audioRingRead = (audioRingRead + 1) % kAudioRingSamples;
        --audioRingCount;
      } else {
        packet[i] = 0;
      }
    }
    portEXIT_CRITICAL(&audioPacketMux);
  }
  const uint16_t written = tud_audio_write(packet, sizeof(packet));
  return written == kAudioPacketSize;
}

extern "C" usbd_class_driver_t const *usbd_app_driver_get_cb(
    uint8_t *driverCount) {
  static const usbd_class_driver_t audioDriver[] = {{
#if CFG_TUSB_DEBUG >= CFG_TUD_LOG_LEVEL
      .name = "AUDIO",
#endif
      .init = audiod_init,
      .reset = audiod_reset,
      .open = audiod_open,
      .control_xfer_cb = tracedAudioControl,
      .xfer_cb = audiod_xfer_cb,
      .sof = audiod_sof_isr,
  }};
  *driverCount = 1;
  return audioDriver;
}

extern "C" bool tud_audio_get_req_entity_cb(
    uint8_t rhport, tusb_control_request_t const *request) {
  const uint8_t channel = TU_U16_LOW(request->wValue);
  const uint8_t control = TU_U16_HIGH(request->wValue);
  const uint8_t entity = TU_U16_HIGH(request->wIndex);

  if (entity == 1 && control == AUDIO_TE_CTRL_CONNECTOR &&
      request->bRequest == AUDIO_CS_REQ_CUR) {
    audio_desc_channel_cluster_t cluster = {
        1, AUDIO_CHANNEL_CONFIG_NON_PREDEFINED, 0};
    return tud_audio_buffer_and_schedule_control_xfer(
        rhport, request, &cluster, sizeof(cluster));
  }
  if (entity == 2 && channel < 2) {
    if (control == AUDIO_FU_CTRL_MUTE &&
        request->bRequest == AUDIO_CS_REQ_CUR) {
      return tud_control_xfer(rhport, request, &muteState[channel],
                              sizeof(muteState[channel]));
    }
    if (control == AUDIO_FU_CTRL_VOLUME) {
      if (request->bRequest == AUDIO_CS_REQ_CUR) {
        return tud_control_xfer(rhport, request, &volumeState[channel],
                                sizeof(volumeState[channel]));
      }
      if (request->bRequest == AUDIO_CS_REQ_RANGE) {
        struct __attribute__((packed)) {
          uint16_t count;
          int16_t min;
          int16_t max;
          int16_t resolution;
        } range = {tu_htole16(1), static_cast<int16_t>(tu_htole16(-50 * 256)),
                   static_cast<int16_t>(tu_htole16(0)),
                   static_cast<int16_t>(tu_htole16(256))};
        return tud_audio_buffer_and_schedule_control_xfer(
            rhport, request, &range, sizeof(range));
      }
    }
  }
  if (entity == 4) {
    if (control == AUDIO_CS_CTRL_SAM_FREQ) {
      if (request->bRequest == AUDIO_CS_REQ_CUR) {
        return tud_control_xfer(rhport, request, &sampleRate,
                                sizeof(sampleRate));
      }
      if (request->bRequest == AUDIO_CS_REQ_RANGE) {
        struct __attribute__((packed)) {
          uint16_t count;
          uint32_t min;
          uint32_t max;
          uint32_t resolution;
        } range = {1, kSampleRate, kSampleRate, 0};
        return tud_audio_buffer_and_schedule_control_xfer(
            rhport, request, &range, sizeof(range));
      }
    }
    if (control == AUDIO_CS_CTRL_CLK_VALID &&
        request->bRequest == AUDIO_CS_REQ_CUR) {
      return tud_control_xfer(rhport, request, &clockValid,
                              sizeof(clockValid));
    }
  }
  return false;
}

extern "C" bool tud_audio_set_req_entity_cb(
    uint8_t, tusb_control_request_t const *request, uint8_t *buffer) {
  const uint8_t channel = TU_U16_LOW(request->wValue);
  const uint8_t control = TU_U16_HIGH(request->wValue);
  const uint8_t entity = TU_U16_HIGH(request->wIndex);
  if (entity == 2 && channel < 2 && request->bRequest == AUDIO_CS_REQ_CUR) {
    if (control == AUDIO_FU_CTRL_MUTE) {
      muteState[channel] = buffer[0];
      return true;
    }
    if (control == AUDIO_FU_CTRL_VOLUME) {
      memcpy(&volumeState[channel], buffer, sizeof(volumeState[channel]));
      return true;
    }
  }
  return false;
}

extern "C" bool tud_audio_get_req_ep_cb(
    uint8_t, tusb_control_request_t const *) {
  return false;
}
extern "C" bool tud_audio_set_req_ep_cb(
    uint8_t, tusb_control_request_t const *, uint8_t *) {
  return false;
}
extern "C" bool tud_audio_get_req_itf_cb(
    uint8_t, tusb_control_request_t const *) {
  return false;
}
extern "C" bool tud_audio_set_req_itf_cb(
    uint8_t, tusb_control_request_t const *, uint8_t *) {
  return false;
}
extern "C" bool tud_audio_set_itf_close_EP_cb(
    uint8_t, tusb_control_request_t const *) {
  return true;
}

void setup() {
  // This keyboard's three buttons drive 3.3 V when pressed.
  pinMode(kTraeButton, INPUT_PULLDOWN);
  pinMode(kFnButton, INPUT_PULLDOWN);
  pinMode(kReturnButton, INPUT_PULLDOWN);
  initMicrophone();

  keyboard.begin();
  ESP_ERROR_CHECK(tinyusb_enable_interface(
      USB_INTERFACE_CUSTOM, kAudioDescriptorLength, loadAudioDescriptor));
  // This final build intentionally exposes only HID + Audio. The legacy
  // ESP32-S3 USB driver assumes IN endpoint numbers match TX FIFO numbers;
  // adding CDC reserves endpoints out of order and breaks isochronous audio.
  USB.PID(0x005D);
  USB.firmwareVersion(0x0300);
  USB.productName("XIAO Voice Keyboard V3 TraeWork");
  USB.manufacturerName("Seeed Studio");
  USB.begin();

  xTaskCreatePinnedToCore(audioTask, "usb_audio", 4096, nullptr, 3, nullptr, 0);
}

void loop() {
  const uint32_t now = millis();
  const bool traeChanged = updateButton(traeButton, now);
  const bool fnChanged = updateButton(fnButton, now);
  const bool returnChanged = updateButton(returnButton, now);

  // K1 is an internal transport key consumed by TraeWork Bridge. One complete
  // F16 press is enough to launch/raise TraeWork and focus its conversation box.
  if (traeChanged && traeButton.pressed) keyboard.write(KEY_F16);

  // K2 preserves key-down duration. macOS maps this device's F13 to a genuine
  // Apple Fn key, so a tap and a hold retain their distinct system meanings.
  if (fnChanged) {
    if (fnButton.pressed) keyboard.press(KEY_F13);
    else keyboard.release(KEY_F13);
  }

  // K3 is a standard Return key and therefore works in every foreground app.
  if (returnChanged) {
    if (returnButton.pressed) keyboard.press(KEY_RETURN);
    else keyboard.release(KEY_RETURN);
  }

  delay(2);
}
