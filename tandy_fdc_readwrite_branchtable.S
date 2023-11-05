tandy_branchtable_fdc:
// WRITES
	.short     ((fdc_system_write - branchtable_fdc)/2) /* 0xFF40 */
	.short     ((fdc_system_write - branchtable_fdc)/2) /* 0xFF41 */
	.short     ((fdc_system_write - branchtable_fdc)/2) /* 0xFF42 */
	.short     ((fdc_system_write - branchtable_fdc)/2) /* 0xFF43 */
	.short     ((fdc_system_write - branchtable_fdc)/2) /* 0xFF44 */
	.short     ((fdc_system_write - branchtable_fdc)/2) /* 0xFF45 */
	.short     ((fdc_system_write - branchtable_fdc)/2) /* 0xFF46 */
	.short     ((fdc_system_write - branchtable_fdc)/2) /* 0xFF47 */

	.short     ((fdc_command_write - branchtable_fdc)/2) /* 0xFF48 Command */
	.short     ((fdc_track_write - branchtable_fdc)/2) /* 0xFF49 Track */
	.short     ((fdc_sector_write - branchtable_fdc)/2) /* 0xFF4A Sector */
	.short     ((fdc_data_write - branchtable_fdc)/2) /* 0xFF4B Data */
	.short     ((fdc_unused_write - branchtable_fdc)/2) /* 0xFF4C */
	.short     ((fdc_unused_write - branchtable_fdc)/2) /* 0xFF4D */
	.short     ((fdc_unused_write - branchtable_fdc)/2) /* 0xFF4E */
	.short     ((fdc_unused_write - branchtable_fdc)/2) /* 0xFF4F */


	.short     ((menu_ctrl_command_write - branchtable_fdc)/2) /* 0xFF50 */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF51 */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF52 */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF53 */
	.short     ((menu_ctrl_address_register_lsb_write - branchtable_fdc)/2) /* 0xFF54 */
	.short     ((menu_ctrl_address_register_msb_write - branchtable_fdc)/2) /* 0xFF55 */
	.short     ((menu_ctrl_data_register_write - branchtable_fdc)/2) /* 0xFF56 */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF57 */

	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF58 */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF59 */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF5a */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF5b */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF5d */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF5d */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF5e */
	.short     ((menu_ctrl_unused_write - branchtable_fdc)/2) /* 0xFF5f */





// READS
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF40 */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF41 */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF42 */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF43 */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF44 */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF45 */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF46 */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF47 */

	.short     ((fdc_status_read - branchtable_fdc)/2) /* 0xFF48 Status */
	.short     ((fdc_track_read - branchtable_fdc)/2) /* 0xFF49 Track */
	.short     ((fdc_sector_read - branchtable_fdc)/2) /* 0xFF4A Sector */
	.short     ((fdc_data_read - branchtable_fdc)/2) /* 0xFF4B Data */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF4C */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF4D */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF4E */
	.short     ((fdc_unused_read - branchtable_fdc)/2) /* 0xFF4F */


	.short     ((menu_ctrl_command_read - branchtable_fdc)/2) /* 0xFF50 */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF51 */
	.short     ((menu_ctrl_file_count_lsb_read - branchtable_fdc)/2) /* 0xFF52 */
	.short     ((menu_ctrl_file_count_msb_read - branchtable_fdc)/2) /* 0xFF53 */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF54 */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF55 */
	.short     ((menu_ctrl_data_register_read - branchtable_fdc)/2) /* 0xFF56 */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF57 */

	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF58 */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF59 */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF5a */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF5b */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF5d */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF5d */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF5e */
	.short     ((menu_ctrl_unused_read - branchtable_fdc)/2) /* 0xFF5f */


