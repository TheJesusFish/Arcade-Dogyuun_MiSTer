derive_pll_clocks
derive_clock_uncertainty

create_generated_clock -name SDRAM_CLK -source \
    [get_pins {emu|pll|raizingpll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -divide_by 1 \
    [get_ports SDRAM_CLK]

set_multicycle_path -from [get_clocks {SDRAM_CLK}] -to [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup -end 2
set_multicycle_path -from [get_clocks {SDRAM_CLK}] -to [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold -end 2

# The restored shell uses the Raizing PLL instance. Keep SDRAM/game clocks
# related and cut unrelated framework, audio, video, and HPS clock domains.
set_clock_groups -exclusive \
    -group [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk emu|pll|raizingpll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk SDRAM_CLK}] \
    -group [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] \
    -group [get_clocks {pll_audio|pll_audio_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -group [get_clocks {spi_sck}] \
    -group [get_clocks {hdmi_sck}] \
    -group [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] \
    -group [get_clocks {FPGA_CLK1_50}] \
    -group [get_clocks {FPGA_CLK2_50}] \
    -group [get_clocks {FPGA_CLK3_50}]

# SDRAM timing constraints for the inlined JTFrame/MiSTer hierarchy.
set_multicycle_path -setup -end -from [get_keepers {SDRAM_DQ[*]}] -to [get_keepers {emu:emu|jtframe_board:u_board|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|dout[*]}] 2
set_multicycle_path -hold  -end -from [get_keepers {SDRAM_DQ[*]}] -to [get_keepers {emu:emu|jtframe_board:u_board|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|dout[*]}] 2
set_multicycle_path -setup -end -from [get_keepers {emu:emu|jtframe_board:u_board|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|dq_pad[*]}] -to [get_keepers {SDRAM_DQ[*]}] 2
set_multicycle_path -hold  -end -from [get_keepers {emu:emu|jtframe_board:u_board|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|dq_pad[*]}] -to [get_keepers {SDRAM_DQ[*]}] 2
set_multicycle_path -setup -end -from [get_keepers {emu:emu|jtframe_board:u_board|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|sdram_a[12]}] -to [get_keepers {SDRAM_DQMH}] 2
set_multicycle_path -hold  -end -from [get_keepers {emu:emu|jtframe_board:u_board|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|sdram_a[12]}] -to [get_keepers {SDRAM_DQMH}] 2
set_multicycle_path -setup -end -from [get_keepers {emu:emu|jtframe_board:u_board|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|sdram_a[11]}] -to [get_keepers {SDRAM_DQML}] 2
set_multicycle_path -hold  -end -from [get_keepers {emu:emu|jtframe_board:u_board|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|sdram_a[11]}] -to [get_keepers {SDRAM_DQML}] 2

# The compact V25 advances only when its 12.5 MHz clock enable is asserted.
# At least seven 94.5 MHz clocks separate enables and every sequential element
# inside u_cpu is gated by that enable. Keep wrapper and device buses outside
# this exception so they remain single-cycle constrained.
set v25_cpu_keepers [get_keepers {emu:emu|dogyuun_game:u_game|dogyuun_sound:u_sound|dogyuun_v25_cpu:u_v25|dogyuun_z8086:u_cpu|*}]
set_multicycle_path -setup -from $v25_cpu_keepers -to $v25_cpu_keepers 5
set_multicycle_path -hold  -from $v25_cpu_keepers -to $v25_cpu_keepers 4

# The skeleton raster advances once every 14 master clocks (94.5 / 14 =
# 6.75 MHz). Constrain only its registered video outputs to that cadence.
set_multicycle_path -setup -end -from [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -to [get_keepers {emu:emu|dogyuun_game:u_game|red[*] emu:emu|dogyuun_game:u_game|green[*] emu:emu|dogyuun_game:u_game|blue[*] emu:emu|dogyuun_game:u_game|HS emu:emu|dogyuun_game:u_game|VS}] 14
set_multicycle_path -hold -end -from [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -to [get_keepers {emu:emu|dogyuun_game:u_game|red[*] emu:emu|dogyuun_game:u_game|green[*] emu:emu|dogyuun_game:u_game|blue[*] emu:emu|dogyuun_game:u_game|HS emu:emu|dogyuun_game:u_game|VS}] 13

# The fx68k core documents instruction-register to micro/nano address decode
# as a 2-cycle path; the microcode output is not needed immediately.
set fx_ir [get_keepers {emu:emu|dogyuun_game:u_game|dogyuun_main:u_main|fx68k:u_main68k|Ir[*]}]
set_multicycle_path -start -setup -from $fx_ir \
    -to [get_keepers {emu:emu|dogyuun_game:u_game|dogyuun_main:u_main|fx68k:u_main68k|microAddr[*]}] 2
set_multicycle_path -start -hold  -from $fx_ir \
    -to [get_keepers {emu:emu|dogyuun_game:u_game|dogyuun_main:u_main|fx68k:u_main68k|microAddr[*]}] 1
set_multicycle_path -start -setup -from $fx_ir \
    -to [get_keepers {emu:emu|dogyuun_game:u_game|dogyuun_main:u_main|fx68k:u_main68k|nanoAddr[*]}] 2
set_multicycle_path -start -hold  -from $fx_ir \
    -to [get_keepers {emu:emu|dogyuun_game:u_game|dogyuun_main:u_main|fx68k:u_main68k|nanoAddr[*]}] 1

# Every register in the hq2x blender advances on ce_x4i. sys/scandoubler.v
# places it at pc_in == pixsz4, pixsz2, pixsz2+pixsz4 and pixsz; with pxl_cen
# at one clock in fourteen that is 3, 7, 10 and 14, so the blender gets at
# least three master clocks between updates. Does not hold before pixsz is
# first measured, which is display-only and self-clears. Scoped to
# blender-internal paths so the other scandoubler enables stay honest.
set hq2x_keepers [get_keepers {*|Hq2x:Hq2x|Blend:blender|*}]
set_multicycle_path -setup -from $hq2x_keepers -to $hq2x_keepers 3
set_multicycle_path -hold  -from $hq2x_keepers -to $hq2x_keepers 2

# Savestate/ROM identity registers feed a 64-bit comparator (ss_restore_compatible)
# whose result gates savestate restore across the V25 register file. Every source
# is write-once per event: loaded_rom_signature only while ioctl_rom && ioctl_wr &&
# ioctl_addr < 8 (dogyuun_game.sv:487), ss_restore_rom_signature only on ss_write
# during a restore, and ss_restored_magic/version only while a savestate loads.
# None can change on consecutive clocks; claim two, far more than the path needs.
set ss_ident [get_keepers {emu:emu|dogyuun_game:u_game|loaded_rom_signature[*] \
    emu:emu|dogyuun_game:u_game|ss_restore_rom_signature[*] \
    emu:emu|ss_restored_magic[*] \
    emu:emu|ss_restored_version[*]}]
set_multicycle_path -setup -from $ss_ident 2
set_multicycle_path -hold  -from $ss_ident 1

# jtframe_reset drives game_rst from negedge clk_rom (jtframe_reset.v:88), so its
# loads get half a period. It is held for GAME_RSTW=8 shift steps and changes at
# most once per reset event, so two cycles is a conservative claim.
set game_rst_reg [get_keepers {emu:emu|jtframe_board:u_board|jtframe_reset:u_reset|game_rst}]
set_multicycle_path -setup -from $game_rst_reg 2
set_multicycle_path -hold  -from $game_rst_reg 1

# The object-line FSM latches scrolls_latched/scroll_flip_latched and the
# initial old_y in ST_IDLE, and updates old_y only in ST_DESC_PROCESS. The
# shortest route back to the next ST_DESC_PROCESS is DECIDE->CAPTURE0->WAIT1->
# CAPTURE1->WAIT2->CAPTURE2->WAIT3->CAPTURE3->PROCESS, nine clocks
# (dogyuun_gp9001_object_line.sv:448 returns to ST_DESC_CAPTURE0);
# scrolls_latched/scroll_flip_latched are stable for the whole build pass.
# Claim two, which all three trivially satisfy.
# desc_y is deliberately NOT included: ST_DESC_CAPTURE3 writes it and the very
# next state consumes it, so that path is honestly single-cycle.
set obj_slow [get_keepers {*|dogyuun_gp9001_object_line:u_gp0_object|old_y[*] \
    *|dogyuun_gp9001_object_line:u_gp0_object|scrolls_latched[*] \
    *|dogyuun_gp9001_object_line:u_gp0_object|scroll_flip_latched[*] \
    *|dogyuun_gp9001_object_line:u_gp1_object|old_y[*] \
    *|dogyuun_gp9001_object_line:u_gp1_object|scrolls_latched[*] \
    *|dogyuun_gp9001_object_line:u_gp1_object|scroll_flip_latched[*]}]
set obj_proc [get_keepers {*|dogyuun_gp9001_object_line:u_gp0_object|process_hits_line* \
    *|dogyuun_gp9001_object_line:u_gp0_object|process_line_delta[*] \
    *|dogyuun_gp9001_object_line:u_gp1_object|process_hits_line* \
    *|dogyuun_gp9001_object_line:u_gp1_object|process_line_delta[*]}]
set_multicycle_path -setup -from $obj_slow -to $obj_proc 2
set_multicycle_path -hold  -from $obj_slow -to $obj_proc 1

# JTFrame framework exceptions.
set_false_path -to [get_keepers {audio_out:audio_out|cl1[*]}]
set_false_path -to [get_keepers {audio_out:audio_out|cr1[*]}]
set_false_path -from [get_keepers {emu:emu|jtframe_board:u_board|jtframe_reset:u_reset|rst_rom[0]}] -to [get_keepers {emu:emu|jtframe_board:u_board|jtframe_reset:u_reset|rst_rom_sync}]
set_false_path -to emu:emu|jtframe_board:u_board|jtframe_reset:u_reset|rst_req_sync[0]
set_false_path -from FB_EN
set_false_path -to deb_osd[0]
set_false_path -from emu:emu|jtframe_board:u_board|jtframe_led:u_led|led
set_false_path -to [get_keepers {*altera_std_synchronizer:*|din_s1}]
