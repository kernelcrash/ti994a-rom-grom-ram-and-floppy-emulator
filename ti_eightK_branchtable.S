eightK_branchtable:
        .short     ((block_unused - eightK_branchtable)/2) /* 0x0000 */
        .short     ((ram_expansion - eightK_branchtable)/2) /* 0x2000 */
        .short     ((dsr_block - eightK_branchtable)/2) /* 0x4000 */
        .short     ((rom_cartridge - eightK_branchtable)/2) /* 0x6000 */
        .short     ((misc_peripherals - eightK_branchtable)/2) /* 0x8000 */
        .short     ((ram_expansion - eightK_branchtable)/2) /* 0xA000 */
        .short     ((ram_expansion - eightK_branchtable)/2) /* 0xC000 */
        .short     ((ram_expansion - eightK_branchtable)/2) /* 0xE000 */

