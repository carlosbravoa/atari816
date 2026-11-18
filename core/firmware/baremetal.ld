/*
 * Linker script for the PicoRV32 I/O processor firmware (Atari816 branch).
 *
 * HOT  : 32 KB block RAM at 0 (reset vector). Boot code, the cold-image loader and the
 *        time-critical paths listed below, plus ALL .data/.bss and the stack.
 * COLD : SDRAM at 0x10000 (physical 0x210000). Everything not listed as hot. Loaded from
 *        SPI flash by cold_load() in firmware.c before main_app() runs. Code there runs
 *        about 4x slower, which is fine for menus, mounting, H: and the PC Link.
 *        A function given the section ".coldtext" is cold even in a file listed as hot
 *        (sd_init, disk_initialize, sio_init: run once at boot or at card insertion).
 *
 * To move a function into block RAM, add its name to a hot list (or give it the section
 * ".text.hot", as pclink.c does). Functions the compiler inlines into a hot function are hot
 * with it.
 */
MEMORY
{
    RAM  (RWX): ORIGIN = 0x00000, LENGTH = 32K
    COLD (RWX): ORIGIN = 0x10000, LENGTH = 64K
}
ENTRY(_start)
SECTIONS
{
    .text :
    {
        start.o (.text)
        . = ALIGN(4);
        KEEP(*(.coldsig))
        *(.text.hot .text.hot.*)
        firmware.o(.text.startup .text.startup.* .rodata.main .rodata.main.*)
        picorv32.o(.text .text.* .rodata .rodata.* .srodata .srodata.*)
        spi_sd.o(.text .text.* .rodata .rodata.* .srodata .srodata.*)
        spiflash.o(.text .text.* .rodata .rodata.* .srodata .srodata.*)
        fatfs/diskio.o(.text .text.* .rodata .rodata.* .srodata .srodata.*)
        *libgcc.a:*(.text .text.* .rodata .rodata.*)
        firmware.o(.text.main .text.main.* .rodata.main .rodata.main.*)
        firmware.o(.text.cold_load .text.cold_load.* .rodata.cold_load .rodata.cold_load.*)
        firmware.o(.text.crc32_upd .text.crc32_upd.* .rodata.crc32_upd .rodata.crc32_upd.*)
        firmware.o(.text.stack_canary_arm .text.stack_canary_arm.* .rodata.stack_canary_arm .rodata.stack_canary_arm.*)
        firmware.o(.text.sio_process_command .text.sio_process_command.* .rodata.sio_process_command .rodata.sio_process_command.*)
        firmware.o(.text.sio_poll .text.sio_poll.* .rodata.sio_poll .rodata.sio_poll.*)
        firmware.o(.text.sio_poll_hwcapture .text.sio_poll_hwcapture.* .rodata.sio_poll_hwcapture .rodata.sio_poll_hwcapture.*)
        firmware.o(.text.sio_rx_data_frame .text.sio_rx_data_frame.* .rodata.sio_rx_data_frame .rodata.sio_rx_data_frame.*)
        firmware.o(.text.sio_read_response .text.sio_read_response.* .rodata.sio_read_response .rodata.sio_read_response.*)
        firmware.o(.text.sio_checksum .text.sio_checksum.* .rodata.sio_checksum .rodata.sio_checksum.*)
        firmware.o(.text.sio_tx_byte .text.sio_tx_byte.* .rodata.sio_tx_byte .rodata.sio_tx_byte.*)
        firmware.o(.text.sio_wait_tx_empty .text.sio_wait_tx_empty.* .rodata.sio_wait_tx_empty .rodata.sio_wait_tx_empty.*)
        firmware.o(.text.sio_wait_cmd_high .text.sio_wait_cmd_high.* .rodata.sio_wait_cmd_high .rodata.sio_wait_cmd_high.*)
        firmware.o(.text.sio_delay .text.sio_delay.* .rodata.sio_delay .rodata.sio_delay.*)
        firmware.o(.text.sio_rx_empty .text.sio_rx_empty.* .rodata.sio_rx_empty .rodata.sio_rx_empty.*)
        firmware.o(.text.sio_stream_file .text.sio_stream_file.* .rodata.sio_stream_file .rodata.sio_stream_file.*)
        firmware.o(.text.atr_read_sector .text.atr_read_sector.* .rodata.atr_read_sector .rodata.atr_read_sector.*)
        firmware.o(.text.atr_write_sector .text.atr_write_sector.* .rodata.atr_write_sector .rodata.atr_write_sector.*)
        firmware.o(.text.atr_sector_offset .text.atr_sector_offset.* .rodata.atr_sector_offset .rodata.atr_sector_offset.*)
        firmware.o(.text.xex_read_sector .text.xex_read_sector.* .rodata.xex_read_sector .rodata.xex_read_sector.*)
        firmware.o(.text.uart_keyboard_poll .text.uart_keyboard_poll.* .rodata.uart_keyboard_poll .rodata.uart_keyboard_poll.*)
        firmware.o(.text.delay_us .text.delay_us.* .rodata.delay_us .rodata.delay_us.*)
        firmware.o(.text.delay_ms .text.delay_ms.* .rodata.delay_ms .rodata.delay_ms.*)
        firmware.o(.text.time_millis .text.time_millis.* .rodata.time_millis .rodata.time_millis.*)
        fatfs/ff.o(.text.f_read .text.f_read.* .rodata.f_read .rodata.f_read.*)
        fatfs/ff.o(.text.f_write .text.f_write.* .rodata.f_write .rodata.f_write.*)
        fatfs/ff.o(.text.f_lseek .text.f_lseek.* .rodata.f_lseek .rodata.f_lseek.*)
        fatfs/ff.o(.text.f_sync .text.f_sync.* .rodata.f_sync .rodata.f_sync.*)
        fatfs/ff.o(.text.sync_fs .text.sync_fs.* .rodata.sync_fs .rodata.sync_fs.*)
        fatfs/ff.o(.text.sync_window .text.sync_window.* .rodata.sync_window .rodata.sync_window.*)
        fatfs/ff.o(.text.move_window .text.move_window.* .rodata.move_window .rodata.move_window.*)
        fatfs/ff.o(.text.get_fat .text.get_fat.* .rodata.get_fat .rodata.get_fat.*)
        fatfs/ff.o(.text.put_fat .text.put_fat.* .rodata.put_fat .rodata.put_fat.*)
        fatfs/ff.o(.text.create_chain .text.create_chain.* .rodata.create_chain .rodata.create_chain.*)
        fatfs/ff.o(.text.remove_chain .text.remove_chain.* .rodata.remove_chain .rodata.remove_chain.*)
        fatfs/ff.o(.text.clst2sect .text.clst2sect.* .rodata.clst2sect .rodata.clst2sect.*)
        fatfs/ff.o(.text.validate .text.validate.* .rodata.validate .rodata.validate.*)
        fatfs/ff.o(.text.ld_clust .text.ld_clust.* .rodata.ld_clust .rodata.ld_clust.*)
        fatfs/ff.o(.text.st_clust .text.st_clust.* .rodata.st_clust .rodata.st_clust.*)
        fatfs/ff.o(.text.ld_dword .text.ld_dword.* .rodata.ld_dword .rodata.ld_dword.*)
        fatfs/ff.o(.text.ld_word .text.ld_word.* .rodata.ld_word .rodata.ld_word.*)
        fatfs/ff.o(.text.st_dword .text.st_dword.* .rodata.st_dword .rodata.st_dword.*)
        fatfs/ff.o(.text.st_word .text.st_word.* .rodata.st_word .rodata.st_word.*)
        fatfs/ff.o(.text.dir_clear .text.dir_clear.* .rodata.dir_clear .rodata.dir_clear.*)
        firmware.o(.text.bridge_poll .text.bridge_poll.* .rodata.bridge_poll .rodata.bridge_poll.*)
        firmware.o(.text.a816_poll .text.a816_poll.* .rodata.a816_poll .rodata.a816_poll.*)
        firmware.o(.text.a816_mb_wanted .text.a816_mb_wanted.* .rodata.a816_mb_wanted .rodata.a816_mb_wanted.*)
        firmware.o(.text.get_fattime .text.get_fattime.* .rodata.get_fattime .rodata.get_fattime.*)
        firmware.o(.text.pc_put816 .text.pc_put816.* .rodata.pc_put816 .rodata.pc_put816.*)
        firmware.o(.text.pc_to816 .text.pc_to816.* .rodata.pc_to816 .rodata.pc_to816.*)
        firmware.o(.text.fat_from2000 .text.fat_from2000.* .rodata.fat_from2000 .rodata.fat_from2000.*)
        firmware.o(.text.prn_flush .text.prn_flush.* .rodata.prn_flush .rodata.prn_flush.*)
        firmware.o(.text.sio_hdd .text.sio_hdd.* .rodata.sio_hdd .rodata.sio_hdd.*)
        firmware.o(.text.hdd_open .text.hdd_open.* .rodata.hdd_open .rodata.hdd_open.*)
        firmware.o(.text.hdd_read .text.hdd_read.* .rodata.hdd_read .rodata.hdd_read.*)
        firmware.o(.text.hdd_write .text.hdd_write.* .rodata.hdd_write .rodata.hdd_write.*)
        firmware.o(.text.hdd_close .text.hdd_close.* .rodata.hdd_close .rodata.hdd_close.*)
        firmware.o(.text.hdd_status .text.hdd_status.* .rodata.hdd_status .rodata.hdd_status.*)
        firmware.o(.text.hdd_path .text.hdd_path.* .rodata.hdd_path .rodata.hdd_path.*)
        firmware.o(.text.hdd_drop .text.hdd_drop.* .rodata.hdd_drop .rodata.hdd_drop.*)
        firmware.o(.text.hdd_text_put .text.hdd_text_put.* .rodata.hdd_text_put .rodata.hdd_text_put.*)
        firmware.o(.text.bootwd_poll .text.bootwd_poll.* .rodata.bootwd_poll .rodata.bootwd_poll.*)
        fatfs/ff.o(.text.f_open .text.f_open.* .rodata.f_open .rodata.f_open.*)
        fatfs/ff.o(.text.f_close .text.f_close.* .rodata.f_close .rodata.f_close.*)
        fatfs/ff.o(.text.follow_path .text.follow_path.* .rodata.follow_path .rodata.follow_path.*)
        fatfs/ff.o(.text.dir_find .text.dir_find.* .rodata.dir_find .rodata.dir_find.*)
        fatfs/ff.o(.text.dir_sdi .text.dir_sdi.* .rodata.dir_sdi .rodata.dir_sdi.*)
        fatfs/ff.o(.text.dir_next .text.dir_next.* .rodata.dir_next .rodata.dir_next.*)
        fatfs/ff.o(.text.dir_read .text.dir_read.* .rodata.dir_read .rodata.dir_read.*)
        fatfs/ff.o(.text.get_fileinfo .text.get_fileinfo.* .rodata.get_fileinfo .rodata.get_fileinfo.*)
        fatfs/ff.o(.text.get_ldnumber .text.get_ldnumber.* .rodata.get_ldnumber .rodata.get_ldnumber.*)
        . = ALIGN(4);
        _end = .;
    } >RAM

    /* global and static variables with initial values */
    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data*)
        *(.sdata)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } >RAM

    /* zero-initialised globals/statics (cleared by start.S) */
    .bss :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } >RAM

    .cold :
    {
        _cold_start = .;
        *(.coldtext .coldtext.*)
        *(.text)
        *(.text*)
        *(.rodata)
        *(.rodata*)
        *(.srodata)
        *(.srodata*)
        . = ALIGN(4);
        _cold_end = .;
    } >COLD

    /* big buffers that are not speed-critical (PC link): in SDRAM after the cold image,
       not part of it (uninitialised) */
    .sdbuf (NOLOAD) :
    {
        . = ALIGN(4);
        *(.sdbuf)
    } >COLD
}

/* Guard: hot text+data+bss must leave at least 4 KB of stack below STACK_TOP (0x8000). */
ASSERT(_ebss <= 0x7000, "hot firmware too large: less than 4 KB left for the stack")
