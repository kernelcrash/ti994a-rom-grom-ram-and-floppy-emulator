ti_branchtable_fdc:
// READS
	.short     ((menu_ctrl_command_read - ti_branchtable_fdc)/2) /* 0x5fe0 Menu Command Read */
	.short     ((menu_ctrl_file_count_lsb_read - ti_branchtable_fdc)/2) /* 0x5fe2 Menu File Count LSB */
	.short     ((menu_ctrl_file_count_msb_read - ti_branchtable_fdc)/2) /* 0x5fe4 Menu File Count MSB */
	.short     ((menu_ctrl_data_register_read - ti_branchtable_fdc)/2) /* 0x5fe6 Menu Data Read */

// WRITES
	.short     ((menu_ctrl_command_write - ti_branchtable_fdc)/2) /* 0x5fe8 Menu Command Write */
	.short     ((menu_ctrl_address_register_lsb_write - ti_branchtable_fdc)/2) /* 0x5fea Menu Adress register LSB write */
	.short     ((menu_ctrl_address_register_msb_write - ti_branchtable_fdc)/2) /* 0x5fec Menu Address register MSB write */
	.short     ((menu_ctrl_data_register_write - ti_branchtable_fdc)/2) /* 0x5fee Menu Data register write */

// READS
	.short     ((fdc_status_read - ti_branchtable_fdc)/2) /* 0x5ff0 Status */
	.short     ((fdc_track_read - ti_branchtable_fdc)/2) /* 0x5ff2 Track */
	.short     ((fdc_sector_read - ti_branchtable_fdc)/2) /* 0x5ff4 Sector */
	.short     ((fdc_data_read - ti_branchtable_fdc)/2) /* 0x5ff6 Data */
// WRITES
	.short     ((fdc_command_write - ti_branchtable_fdc)/2) /* 0x5ff8 Command */
	.short     ((fdc_track_write - ti_branchtable_fdc)/2) /* 0x5ffa Track */
	.short     ((fdc_sector_write - ti_branchtable_fdc)/2) /* 0x5ffc Sector */
	.short     ((fdc_data_write - ti_branchtable_fdc)/2) /* 0x5ffe Data */
