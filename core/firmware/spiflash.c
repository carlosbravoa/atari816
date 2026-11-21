// SPI flash bit-bang driver over reg_spiflash_ctrl (0x0200_0078):
//   W: bit 0 = CS_N, bit 1 = CLK, bit 2 = MOSI
//   R: bit 0 = MISO
// Only used once at boot by cold_load() to copy ~44 KB from SPI flash to SDRAM.
#include "picorv32.h"

uint8_t flash_send(uint8_t x) {
    uint8_t r = 0;
    for (int i = 0; i < 8; i++) {
        uint32_t m = (x & 0x80) ? 4u : 0u;
        reg_spiflash_ctrl = m;          // CS=0, CLK=0, MOSI=bit
        reg_spiflash_ctrl = m | 2u;     // CS=0, CLK=1 (flash latches MOSI)
        r = (uint8_t)((r << 1) | (reg_spiflash_ctrl & 1u));
        x <<= 1;
    }
    reg_spiflash_ctrl = 0;              // CS=0, CLK=0
    return r;
}

uint8_t flash_receive(void) {
    uint8_t r = 0;
    for (int i = 0; i < 8; i++) {
        reg_spiflash_ctrl = 4u;         // CS=0, CLK=0, MOSI=1
        reg_spiflash_ctrl = 6u;         // CS=0, CLK=1
        r = (uint8_t)((r << 1) | (reg_spiflash_ctrl & 1u));
    }
    reg_spiflash_ctrl = 0;              // CS=0, CLK=0
    return r;
}

void spiflash_read(uint32_t addr, uint8_t *buf, int length) {
    reg_spiflash_ctrl = 0;              // CS_N = 0, CLK = 0
    flash_send(0x03);                   // read command
    flash_send((uint8_t)(addr >> 16));
    flash_send((uint8_t)(addr >> 8));
    flash_send((uint8_t)(addr & 0xFF));
    for (int i = 0; i < length; i++)
        buf[i] = flash_receive();
    reg_spiflash_ctrl = 1;              // CS_N = 1, CLK = 0
}
