// Private hardware diagnostics. This module is instantiated only when
// DOGYUUN_HW_DEBUG is defined and must not be present in a release build.
module dogyuun_hw_debug #(
    parameter integer AW = 22
) (
    input              clk,
    input              rst,
    input              cold_rst,
    input              ioctl_rom,
    input              dwnld_busy,
    input              prog_we,
    input              prog_rdy,
    input              prog_ack,
    input              loader_accepted,
    input              frame_tick,
    input              pixel_tick,
    input              object_swap,
    input              line_start,
    input              line_commit,
    input      [3:0]   clkdiv,
    input      [9:0]   hcnt,
    input      [8:0]   vcnt,
    input              video_epoch,
    input      [8:0]   video_target_y,
    input              video_target_epoch,
    input              video_line_ready,
    input      [3:0]   video_engine_busy,
    input      [3:0]   video_deadline_miss,
    input      [3:0]   video_deadline_latched,
    input      [15:0]  gp0_tile_cycles,
    input      [15:0]  gp0_object_cycles,
    input      [15:0]  gp1_tile_cycles,
    input      [15:0]  gp1_object_cycles,
    input      [8:0]   gp0_tile_y,
    input      [8:0]   gp0_object_y,
    input      [8:0]   gp1_tile_y,
    input      [8:0]   gp1_object_y,
    input      [3:0]   line_epoch,
    input      [3:0]   line_valid,
    input      [21:0]  gp0_tile_gfx_logical_addr,
    input      [21:0]  gp0_tile_gfx_physical_addr,
    input      [15:0]  gp0_tile_gfx_data,
    input              gp0_tile_gfx_req,
    input              gp0_tile_gfx_ok,
    input      [21:0]  gp0_object_gfx_logical_addr,
    input      [21:0]  gp0_object_gfx_physical_addr,
    input      [15:0]  gp0_object_gfx_data,
    input              gp0_object_gfx_req,
    input              gp0_object_gfx_ok,
    input      [21:0]  gp1_tile_gfx_logical_addr,
    input      [21:0]  gp1_tile_gfx_physical_addr,
    input      [15:0]  gp1_tile_gfx_data,
    input              gp1_tile_gfx_req,
    input              gp1_tile_gfx_ok,
    input      [21:0]  gp1_object_gfx_logical_addr,
    input      [21:0]  gp1_object_gfx_physical_addr,
    input      [15:0]  gp1_object_gfx_data,
    input              gp1_object_gfx_req,
    input              gp1_object_gfx_ok,
    input              main_cpu_cen,
    input              main_cpu_cenb,
    input              main_cpu_bus_active,
    input              main_cpu_rw,
    input      [23:0]  main_cpu_addr,
    input      [15:0]  main_cpu_dout,
    input      [15:0]  main_cpu_din,
    input              main_irq4,
    input      [12:0]  main_gp0_ptr,
    input      [12:0]  main_gp1_ptr,
    input      [23:0]  main_last_fetch,
    input      [31:0]  main_bus_count,
    input      [31:0]  main_rom_count,
    input      [31:0]  main_wram_count,
    input      [31:0]  main_shared_count,
    input      [31:0]  main_gp_count,
    input      [31:0]  main_palette_count,
    input      [31:0]  main_io_count,
    input      [31:0]  main_unmapped_count,
    input      [31:0]  main_irq_count,
    input      [31:0]  main_iack_count,
    input      [15:0]  main_debug_events,
    input      [7:0]   main_coin_control,
    input              main_v25_reset_n,
    input              sound_fault,
    input              sound_halted,
    input      [19:0]  sound_pc,
    input              sound_idle,
    input              sound_v25_reset_n,
    input              sound_ym_write,
    input              sound_ym_a0,
    input      [7:0]   sound_ym_data,
    input              sound_oki_write,
    input      [7:0]   sound_oki_data,
    input              sound_oki_cen,
    input      [7:0]   sound_oki_status,
    input      [14:0]  sound_shared_addr,
    input      [7:0]   sound_shared_dout,
    input              sound_shared_we,
    input      [AW-1:0] ba0_addr,
    input      [AW-1:0] ba1_addr,
    input      [AW-1:0] ba2_addr,
    input      [AW-1:0] ba3_addr,
    input      [3:0]   ba_rd,
    input      [3:0]   ba_ack,
    input      [3:0]   ba_rdy,
    input      [3:0]   ba_dst,
    input              loader_range_error,
    input              loader_overflow_error
);

wire [31:0] diag_source;
reg  [127:0] diag_probe;

reg [23:0] frame_count;
reg [23:0] object_swap_count;
reg [23:0] visible_not_ready_count;
reg [23:0] rom_ack_count0;
reg [23:0] rom_ack_count1;
reg [23:0] rom_ack_count2;
reg [23:0] rom_ack_count3;
reg [23:0] ym_write_count;
reg [23:0] oki_write_count;
reg [23:0] v25_shared_write_count;
reg [7:0]  last_ym_data;
reg        last_ym_a0;
reg [7:0]  last_oki_data;
reg [14:0] last_shared_addr;
reg [7:0]  last_shared_data;
reg [15:0] max_gp0_tile_cycles;
reg [15:0] max_gp0_object_cycles;
reg [15:0] max_gp1_tile_cycles;
reg [15:0] max_gp1_object_cycles;
reg [21:0] last_gfx_logical0;
reg [21:0] last_gfx_logical1;
reg [21:0] last_gfx_logical2;
reg [21:0] last_gfx_logical3;
reg [21:0] last_gfx_physical0;
reg [21:0] last_gfx_physical1;
reg [21:0] last_gfx_physical2;
reg [21:0] last_gfx_physical3;
reg [15:0] last_gfx_data0;
reg [15:0] last_gfx_data1;
reg [15:0] last_gfx_data2;
reg [15:0] last_gfx_data3;
reg [23:0] gfx_response_count0;
reg [23:0] gfx_response_count1;
reg [23:0] gfx_response_count2;
reg [23:0] gfx_response_count3;
reg        snapshot_seen;
reg        clear_seen;

reg [31:0] sound_cycle_count;
reg [31:0] oki_cen_count;
reg [4:0]  oki_event_count;
reg [31:0] oki_event_cycle [0:15];
reg [31:0] oki_event_cen_count [0:15];
reg [7:0]  oki_event_data [0:15];
reg [19:0] oki_event_pc [0:15];
reg [7:0]  oki_event_status [0:15];
reg        oki_event_cen [0:15];

reg [23:0] snap_frame_count;
reg [23:0] snap_object_swap_count;
reg [23:0] snap_visible_not_ready_count;
reg [23:0] snap_rom_ack_count0;
reg [23:0] snap_rom_ack_count1;
reg [23:0] snap_rom_ack_count2;
reg [23:0] snap_rom_ack_count3;
reg [23:0] snap_ym_write_count;
reg [23:0] snap_oki_write_count;
reg [23:0] snap_v25_shared_write_count;
reg [7:0]  snap_last_ym_data;
reg        snap_last_ym_a0;
reg [7:0]  snap_last_oki_data;
reg [14:0] snap_last_shared_addr;
reg [7:0]  snap_last_shared_data;
reg [15:0] snap_max_gp0_tile_cycles;
reg [15:0] snap_max_gp0_object_cycles;
reg [15:0] snap_max_gp1_tile_cycles;
reg [15:0] snap_max_gp1_object_cycles;
reg [23:0] snap_main_last_fetch;
reg [23:0] snap_main_cpu_addr;
reg [15:0] snap_main_cpu_dout;
reg [15:0] snap_main_cpu_din;
reg [12:0] snap_main_gp0_ptr;
reg [12:0] snap_main_gp1_ptr;
reg [19:0] snap_sound_pc;
reg [31:0] snap_main_bus_count;
reg [31:0] snap_main_rom_count;
reg [31:0] snap_main_wram_count;
reg [31:0] snap_main_shared_count;
reg [31:0] snap_main_gp_count;
reg [31:0] snap_main_palette_count;
reg [31:0] snap_main_io_count;
reg [31:0] snap_main_unmapped_count;
reg [31:0] snap_main_irq_count;
reg [31:0] snap_main_iack_count;
reg [9:0]  snap_hcnt;
reg [8:0]  snap_vcnt;
reg [3:0]  snap_clkdiv;
reg        snap_main_cpu_bus_active;
reg        snap_main_cpu_rw;
reg        snap_main_cpu_cen;
reg        snap_main_cpu_cenb;
reg        snap_main_irq4;
reg        snap_main_v25_reset_n;
reg [7:0]  snap_main_coin_control;
reg        snap_sound_fault;
reg        snap_sound_halted;
reg        snap_sound_idle;
reg        snap_sound_v25_reset_n;
reg        snap_video_epoch;
reg        snap_video_line_ready;
reg [3:0]  snap_video_engine_busy;
reg [3:0]  snap_video_deadline_latched;
reg [15:0] snap_gp0_tile_cycles;
reg [15:0] snap_gp0_object_cycles;
reg [15:0] snap_gp1_tile_cycles;
reg [15:0] snap_gp1_object_cycles;
reg [8:0]  snap_gp0_tile_y;
reg [8:0]  snap_gp0_object_y;
reg [8:0]  snap_gp1_tile_y;
reg [8:0]  snap_gp1_object_y;
reg [3:0]  snap_line_epoch;
reg [3:0]  snap_line_valid;
reg [3:0]  snap_ba_rd;
reg [3:0]  snap_ba_ack;
reg [3:0]  snap_ba_rdy;
reg [3:0]  snap_ba_dst;
reg        snap_loader_range_error;
reg        snap_loader_overflow_error;
reg [21:0] snap_gfx_logical0;
reg [21:0] snap_gfx_logical1;
reg [21:0] snap_gfx_logical2;
reg [21:0] snap_gfx_logical3;
reg [21:0] snap_gfx_physical0;
reg [21:0] snap_gfx_physical1;
reg [21:0] snap_gfx_physical2;
reg [21:0] snap_gfx_physical3;
reg [15:0] snap_gfx_data0;
reg [15:0] snap_gfx_data1;
reg [15:0] snap_gfx_data2;
reg [15:0] snap_gfx_data3;
reg [23:0] snap_gfx_response_count0;
reg [23:0] snap_gfx_response_count1;
reg [23:0] snap_gfx_response_count2;
reg [23:0] snap_gfx_response_count3;

wire [AW-1:0] trace_ba_addr = ba_rd[0] ? ba0_addr :
                              ba_rd[1] ? ba1_addr :
                              ba_rd[2] ? ba2_addr : ba3_addr;
wire [1:0] trace_ba_slot = ba_rd[0] ? 2'd0 :
                           ba_rd[1] ? 2'd1 :
                           ba_rd[2] ? 2'd2 : 2'd3;

(* preserve, noprune *) reg [255:0] dogyuun_trace_bus;
(* preserve, noprune *) reg [63:0] dogyuun_trace_video;

always @(posedge clk) begin
    dogyuun_trace_bus[23:0] <= main_cpu_addr;
    dogyuun_trace_bus[39:24] <= main_cpu_dout;
    dogyuun_trace_bus[55:40] <= main_cpu_din;
    dogyuun_trace_bus[68:56] <= main_gp0_ptr;
    dogyuun_trace_bus[81:69] <= main_gp1_ptr;
    dogyuun_trace_bus[101:82] <= sound_pc;
    dogyuun_trace_bus[110:102] <= vcnt;
    dogyuun_trace_bus[120:111] <= hcnt;
    dogyuun_trace_bus[124:121] <= clkdiv;
    dogyuun_trace_bus[125] <= main_cpu_bus_active;
    dogyuun_trace_bus[126] <= main_cpu_rw;
    dogyuun_trace_bus[127] <= main_cpu_cen;
    dogyuun_trace_bus[128] <= main_irq4;
    dogyuun_trace_bus[129] <= object_swap;
    dogyuun_trace_bus[130] <= line_start;
    dogyuun_trace_bus[131] <= line_commit;
    dogyuun_trace_bus[132] <= video_line_ready;
    dogyuun_trace_bus[136:133] <= video_engine_busy;
    dogyuun_trace_bus[140:137] <= video_deadline_miss;
    dogyuun_trace_bus[149:141] <= video_target_y;
    dogyuun_trace_bus[150] <= video_target_epoch;
    dogyuun_trace_bus[151] <= video_epoch;
    dogyuun_trace_bus[152] <= sound_ym_write;
    dogyuun_trace_bus[153] <= sound_ym_a0;
    dogyuun_trace_bus[161:154] <= sound_ym_data;
    dogyuun_trace_bus[162] <= sound_oki_write;
    dogyuun_trace_bus[170:163] <= sound_oki_data;
    dogyuun_trace_bus[171] <= sound_shared_we;
    dogyuun_trace_bus[186:172] <= sound_shared_addr;
    dogyuun_trace_bus[194:187] <= sound_shared_dout;
    dogyuun_trace_bus[198:195] <= ba_rd;
    dogyuun_trace_bus[202:199] <= ba_ack;
    dogyuun_trace_bus[206:203] <= ba_rdy;
    dogyuun_trace_bus[210:207] <= ba_dst;
    dogyuun_trace_bus[232:211] <= trace_ba_addr[21:0];
    dogyuun_trace_bus[234:233] <= trace_ba_slot;
    dogyuun_trace_bus[250:235] <= main_debug_events;
    dogyuun_trace_bus[251] <= sound_fault;
    dogyuun_trace_bus[252] <= sound_halted;
    dogyuun_trace_bus[253] <= sound_v25_reset_n;
    dogyuun_trace_bus[254] <= loader_range_error;
    dogyuun_trace_bus[255] <= loader_overflow_error;

    dogyuun_trace_video[8:0] <= gp0_tile_y;
    dogyuun_trace_video[9] <= line_epoch[0];
    dogyuun_trace_video[10] <= line_valid[0];
    dogyuun_trace_video[19:11] <= gp0_object_y;
    dogyuun_trace_video[20] <= line_epoch[1];
    dogyuun_trace_video[21] <= line_valid[1];
    dogyuun_trace_video[30:22] <= gp1_tile_y;
    dogyuun_trace_video[31] <= line_epoch[2];
    dogyuun_trace_video[32] <= line_valid[2];
    dogyuun_trace_video[41:33] <= gp1_object_y;
    dogyuun_trace_video[42] <= line_epoch[3];
    dogyuun_trace_video[43] <= line_valid[3];
    dogyuun_trace_video[52:44] <= video_target_y;
    dogyuun_trace_video[53] <= video_target_epoch;
    dogyuun_trace_video[54] <= video_epoch;
    dogyuun_trace_video[55] <= video_line_ready;
    dogyuun_trace_video[59:56] <= video_engine_busy;
    dogyuun_trace_video[63:60] <= video_deadline_miss;
end

always @(posedge clk) begin
    if (rst) begin
        frame_count <= 24'd0;
        object_swap_count <= 24'd0;
        visible_not_ready_count <= 24'd0;
        rom_ack_count0 <= 24'd0;
        rom_ack_count1 <= 24'd0;
        rom_ack_count2 <= 24'd0;
        rom_ack_count3 <= 24'd0;
        ym_write_count <= 24'd0;
        oki_write_count <= 24'd0;
        v25_shared_write_count <= 24'd0;
        last_ym_data <= 8'h00;
        last_ym_a0 <= 1'b0;
        last_oki_data <= 8'h00;
        last_shared_addr <= 15'd0;
        last_shared_data <= 8'h00;
        max_gp0_tile_cycles <= 16'd0;
        max_gp0_object_cycles <= 16'd0;
        max_gp1_tile_cycles <= 16'd0;
        max_gp1_object_cycles <= 16'd0;
        last_gfx_logical0 <= 22'd0;
        last_gfx_logical1 <= 22'd0;
        last_gfx_logical2 <= 22'd0;
        last_gfx_logical3 <= 22'd0;
        last_gfx_physical0 <= 22'd0;
        last_gfx_physical1 <= 22'd0;
        last_gfx_physical2 <= 22'd0;
        last_gfx_physical3 <= 22'd0;
        last_gfx_data0 <= 16'd0;
        last_gfx_data1 <= 16'd0;
        last_gfx_data2 <= 16'd0;
        last_gfx_data3 <= 16'd0;
        gfx_response_count0 <= 24'd0;
        gfx_response_count1 <= 24'd0;
        gfx_response_count2 <= 24'd0;
        gfx_response_count3 <= 24'd0;
        sound_cycle_count <= 32'd0;
        oki_cen_count <= 32'd0;
        oki_event_count <= 5'd0;
        snapshot_seen <= diag_source[3];
        clear_seen <= diag_source[4];
    end else begin
        sound_cycle_count <= sound_cycle_count + 1'b1;
        if (sound_oki_cen)
            oki_cen_count <= oki_cen_count + 1'b1;
        if (sound_oki_write && (oki_event_count < 5'd16)) begin
            oki_event_cycle[oki_event_count[3:0]] <= sound_cycle_count;
            oki_event_cen_count[oki_event_count[3:0]] <= oki_cen_count;
            oki_event_data[oki_event_count[3:0]] <= sound_oki_data;
            oki_event_pc[oki_event_count[3:0]] <= sound_pc;
            oki_event_status[oki_event_count[3:0]] <= sound_oki_status;
            oki_event_cen[oki_event_count[3:0]] <= sound_oki_cen;
            oki_event_count <= oki_event_count + 1'b1;
        end
        if (frame_tick)
            frame_count <= frame_count + 1'b1;
        if (object_swap)
            object_swap_count <= object_swap_count + 1'b1;
        if (pixel_tick && (hcnt < 10'd320) && (vcnt < 9'd240) &&
            !video_line_ready)
            visible_not_ready_count <= visible_not_ready_count + 1'b1;
        if (ba_ack[0])
            rom_ack_count0 <= rom_ack_count0 + 1'b1;
        if (ba_ack[1])
            rom_ack_count1 <= rom_ack_count1 + 1'b1;
        if (ba_ack[2])
            rom_ack_count2 <= rom_ack_count2 + 1'b1;
        if (ba_ack[3])
            rom_ack_count3 <= rom_ack_count3 + 1'b1;
        if (sound_ym_write) begin
            ym_write_count <= ym_write_count + 1'b1;
            last_ym_data <= sound_ym_data;
            last_ym_a0 <= sound_ym_a0;
        end
        if (sound_oki_write) begin
            oki_write_count <= oki_write_count + 1'b1;
            last_oki_data <= sound_oki_data;
        end
        if (sound_shared_we) begin
            v25_shared_write_count <= v25_shared_write_count + 1'b1;
            last_shared_addr <= sound_shared_addr;
            last_shared_data <= sound_shared_dout;
        end
        if (line_commit) begin
            if (gp0_tile_cycles > max_gp0_tile_cycles)
                max_gp0_tile_cycles <= gp0_tile_cycles;
            if (gp0_object_cycles > max_gp0_object_cycles)
                max_gp0_object_cycles <= gp0_object_cycles;
            if (gp1_tile_cycles > max_gp1_tile_cycles)
                max_gp1_tile_cycles <= gp1_tile_cycles;
            if (gp1_object_cycles > max_gp1_object_cycles)
                max_gp1_object_cycles <= gp1_object_cycles;
        end
        if (gp0_tile_gfx_req && gp0_tile_gfx_ok) begin
            last_gfx_logical0 <= gp0_tile_gfx_logical_addr;
            last_gfx_physical0 <= gp0_tile_gfx_physical_addr;
            last_gfx_data0 <= gp0_tile_gfx_data;
            gfx_response_count0 <= gfx_response_count0 + 1'b1;
        end
        if (gp0_object_gfx_req && gp0_object_gfx_ok) begin
            last_gfx_logical1 <= gp0_object_gfx_logical_addr;
            last_gfx_physical1 <= gp0_object_gfx_physical_addr;
            last_gfx_data1 <= gp0_object_gfx_data;
            gfx_response_count1 <= gfx_response_count1 + 1'b1;
        end
        if (gp1_tile_gfx_req && gp1_tile_gfx_ok) begin
            last_gfx_logical2 <= gp1_tile_gfx_logical_addr;
            last_gfx_physical2 <= gp1_tile_gfx_physical_addr;
            last_gfx_data2 <= gp1_tile_gfx_data;
            gfx_response_count2 <= gfx_response_count2 + 1'b1;
        end
        if (gp1_object_gfx_req && gp1_object_gfx_ok) begin
            last_gfx_logical3 <= gp1_object_gfx_logical_addr;
            last_gfx_physical3 <= gp1_object_gfx_physical_addr;
            last_gfx_data3 <= gp1_object_gfx_data;
            gfx_response_count3 <= gfx_response_count3 + 1'b1;
        end

        if (diag_source[4] != clear_seen) begin
            clear_seen <= diag_source[4];
            frame_count <= 24'd0;
            object_swap_count <= 24'd0;
            visible_not_ready_count <= 24'd0;
            rom_ack_count0 <= 24'd0;
            rom_ack_count1 <= 24'd0;
            rom_ack_count2 <= 24'd0;
            rom_ack_count3 <= 24'd0;
            ym_write_count <= 24'd0;
            oki_write_count <= 24'd0;
            v25_shared_write_count <= 24'd0;
            max_gp0_tile_cycles <= 16'd0;
            max_gp0_object_cycles <= 16'd0;
            max_gp1_tile_cycles <= 16'd0;
            max_gp1_object_cycles <= 16'd0;
            sound_cycle_count <= 32'd0;
            oki_cen_count <= 32'd0;
            oki_event_count <= 5'd0;
        end

        if (diag_source[3] != snapshot_seen) begin
            snapshot_seen <= diag_source[3];
            snap_frame_count <= frame_count;
            snap_object_swap_count <= object_swap_count;
            snap_visible_not_ready_count <= visible_not_ready_count;
            snap_rom_ack_count0 <= rom_ack_count0;
            snap_rom_ack_count1 <= rom_ack_count1;
            snap_rom_ack_count2 <= rom_ack_count2;
            snap_rom_ack_count3 <= rom_ack_count3;
            snap_ym_write_count <= ym_write_count;
            snap_oki_write_count <= oki_write_count;
            snap_v25_shared_write_count <= v25_shared_write_count;
            snap_last_ym_data <= last_ym_data;
            snap_last_ym_a0 <= last_ym_a0;
            snap_last_oki_data <= last_oki_data;
            snap_last_shared_addr <= last_shared_addr;
            snap_last_shared_data <= last_shared_data;
            snap_max_gp0_tile_cycles <= max_gp0_tile_cycles;
            snap_max_gp0_object_cycles <= max_gp0_object_cycles;
            snap_max_gp1_tile_cycles <= max_gp1_tile_cycles;
            snap_max_gp1_object_cycles <= max_gp1_object_cycles;
            snap_main_last_fetch <= main_last_fetch;
            snap_main_cpu_addr <= main_cpu_addr;
            snap_main_cpu_dout <= main_cpu_dout;
            snap_main_cpu_din <= main_cpu_din;
            snap_main_gp0_ptr <= main_gp0_ptr;
            snap_main_gp1_ptr <= main_gp1_ptr;
            snap_sound_pc <= sound_pc;
            snap_main_bus_count <= main_bus_count;
            snap_main_rom_count <= main_rom_count;
            snap_main_wram_count <= main_wram_count;
            snap_main_shared_count <= main_shared_count;
            snap_main_gp_count <= main_gp_count;
            snap_main_palette_count <= main_palette_count;
            snap_main_io_count <= main_io_count;
            snap_main_unmapped_count <= main_unmapped_count;
            snap_main_irq_count <= main_irq_count;
            snap_main_iack_count <= main_iack_count;
            snap_hcnt <= hcnt;
            snap_vcnt <= vcnt;
            snap_clkdiv <= clkdiv;
            snap_main_cpu_bus_active <= main_cpu_bus_active;
            snap_main_cpu_rw <= main_cpu_rw;
            snap_main_cpu_cen <= main_cpu_cen;
            snap_main_cpu_cenb <= main_cpu_cenb;
            snap_main_irq4 <= main_irq4;
            snap_main_v25_reset_n <= main_v25_reset_n;
            snap_main_coin_control <= main_coin_control;
            snap_sound_fault <= sound_fault;
            snap_sound_halted <= sound_halted;
            snap_sound_idle <= sound_idle;
            snap_sound_v25_reset_n <= sound_v25_reset_n;
            snap_video_epoch <= video_epoch;
            snap_video_line_ready <= video_line_ready;
            snap_video_engine_busy <= video_engine_busy;
            snap_video_deadline_latched <= video_deadline_latched;
            snap_gp0_tile_cycles <= gp0_tile_cycles;
            snap_gp0_object_cycles <= gp0_object_cycles;
            snap_gp1_tile_cycles <= gp1_tile_cycles;
            snap_gp1_object_cycles <= gp1_object_cycles;
            snap_gp0_tile_y <= gp0_tile_y;
            snap_gp0_object_y <= gp0_object_y;
            snap_gp1_tile_y <= gp1_tile_y;
            snap_gp1_object_y <= gp1_object_y;
            snap_line_epoch <= line_epoch;
            snap_line_valid <= line_valid;
            snap_ba_rd <= ba_rd;
            snap_ba_ack <= ba_ack;
            snap_ba_rdy <= ba_rdy;
            snap_ba_dst <= ba_dst;
            snap_loader_range_error <= loader_range_error;
            snap_loader_overflow_error <= loader_overflow_error;
            snap_gfx_logical0 <= last_gfx_logical0;
            snap_gfx_logical1 <= last_gfx_logical1;
            snap_gfx_logical2 <= last_gfx_logical2;
            snap_gfx_logical3 <= last_gfx_logical3;
            snap_gfx_physical0 <= last_gfx_physical0;
            snap_gfx_physical1 <= last_gfx_physical1;
            snap_gfx_physical2 <= last_gfx_physical2;
            snap_gfx_physical3 <= last_gfx_physical3;
            snap_gfx_data0 <= last_gfx_data0;
            snap_gfx_data1 <= last_gfx_data1;
            snap_gfx_data2 <= last_gfx_data2;
            snap_gfx_data3 <= last_gfx_data3;
            snap_gfx_response_count0 <= gfx_response_count0;
            snap_gfx_response_count1 <= gfx_response_count1;
            snap_gfx_response_count2 <= gfx_response_count2;
            snap_gfx_response_count3 <= gfx_response_count3;
        end
    end
end

always @* begin
    diag_probe = 128'd0;
    if (diag_source[8]) begin
        if ({1'b0, diag_source[12:9]} < oki_event_count) begin
            diag_probe[31:0] = oki_event_cycle[diag_source[12:9]];
            diag_probe[63:32] = oki_event_cen_count[diag_source[12:9]];
            diag_probe[71:64] = oki_event_data[diag_source[12:9]];
            diag_probe[91:72] = oki_event_pc[diag_source[12:9]];
            diag_probe[99:92] = oki_event_status[diag_source[12:9]];
            diag_probe[100] = oki_event_cen[diag_source[12:9]];
            diag_probe[110] = 1'b1;
        end
        diag_probe[105:101] = oki_event_count;
        diag_probe[109:106] = diag_source[12:9];
        diag_probe[111] = (oki_event_count == 5'd16);
        diag_probe[127:112] = 16'hd6e0;
    end else begin
      case (diag_source[2:0])
        3'd0: begin
            diag_probe[23:0] = snap_frame_count;
            diag_probe[47:24] = snap_main_last_fetch;
            diag_probe[71:48] = snap_main_cpu_addr;
            diag_probe[81:72] = snap_hcnt;
            diag_probe[90:82] = snap_vcnt;
            diag_probe[94:91] = snap_clkdiv;
            diag_probe[95] = snap_main_cpu_rw;
            diag_probe[96] = snap_main_cpu_bus_active;
            diag_probe[97] = snap_main_irq4;
            diag_probe[98] = snap_main_v25_reset_n;
            diag_probe[99] = snap_sound_v25_reset_n;
            diag_probe[100] = snap_video_epoch;
            diag_probe[101] = snap_video_line_ready;
            diag_probe[105:102] = snap_video_engine_busy;
            diag_probe[109:106] = snap_video_deadline_latched;
            diag_probe[110] = snap_loader_range_error;
            diag_probe[111] = snap_loader_overflow_error;
        end
        3'd1: begin
            diag_probe[23:0] = snap_main_bus_count[23:0];
            diag_probe[47:24] = snap_main_rom_count[23:0];
            diag_probe[71:48] = snap_main_wram_count[23:0];
            diag_probe[95:72] = snap_main_shared_count[23:0];
            diag_probe[111:96] = snap_main_palette_count[15:0];
        end
        3'd2: begin
            diag_probe[23:0] = snap_main_gp_count[23:0];
            diag_probe[47:24] = snap_main_palette_count[23:0];
            diag_probe[71:48] = snap_main_io_count[23:0];
            diag_probe[79:72] = snap_main_unmapped_count[7:0];
            diag_probe[95:80] = snap_main_irq_count[15:0];
            diag_probe[111:96] = snap_main_iack_count[15:0];
        end
        3'd3: begin
            diag_probe[12:0] = snap_main_gp0_ptr;
            diag_probe[25:13] = snap_main_gp1_ptr;
            diag_probe[41:26] = snap_main_cpu_dout;
            diag_probe[57:42] = snap_main_cpu_din;
            diag_probe[77:58] = snap_sound_pc;
            diag_probe[78] = snap_sound_fault;
            diag_probe[79] = snap_sound_halted;
            diag_probe[80] = snap_sound_idle;
            diag_probe[81] = snap_sound_v25_reset_n;
            diag_probe[89:82] = snap_main_coin_control;
            diag_probe[90] = snap_main_cpu_cen;
            diag_probe[91] = snap_main_cpu_cenb;
            diag_probe[92] = snap_main_cpu_bus_active;
            diag_probe[93] = snap_main_cpu_rw;
            diag_probe[94] = snap_main_irq4;
            // Live download/reset state remains visible while rst is held.
            diag_probe[95] = rst;
            diag_probe[96] = cold_rst;
            diag_probe[97] = ioctl_rom;
            diag_probe[98] = dwnld_busy;
            diag_probe[99] = prog_we;
            diag_probe[100] = prog_rdy;
            diag_probe[101] = prog_ack;
            diag_probe[102] = loader_accepted;
            diag_probe[103] = pixel_tick;
        end
        3'd4: begin
            diag_probe[15:0] = snap_gp0_tile_cycles;
            diag_probe[31:16] = snap_gp0_object_cycles;
            diag_probe[47:32] = snap_gp1_tile_cycles;
            diag_probe[63:48] = snap_gp1_object_cycles;
            diag_probe[72:64] = snap_gp0_tile_y;
            diag_probe[81:73] = snap_gp0_object_y;
            diag_probe[90:82] = snap_gp1_tile_y;
            diag_probe[99:91] = snap_gp1_object_y;
            diag_probe[103:100] = snap_line_epoch;
            diag_probe[107:104] = snap_line_valid;
            diag_probe[111:108] = snap_video_engine_busy;
        end
        3'd5: begin
            diag_probe[23:0] = snap_rom_ack_count0;
            diag_probe[47:24] = snap_rom_ack_count1;
            diag_probe[71:48] = snap_rom_ack_count2;
            diag_probe[95:72] = snap_rom_ack_count3;
            diag_probe[99:96] = snap_ba_rd;
            diag_probe[103:100] = snap_ba_ack;
            diag_probe[107:104] = snap_ba_rdy;
            diag_probe[111:108] = snap_ba_dst;
        end
        3'd6: begin
            diag_probe[23:0] = snap_ym_write_count;
            diag_probe[47:24] = snap_oki_write_count;
            diag_probe[71:48] = snap_v25_shared_write_count;
            diag_probe[79:72] = snap_last_ym_data;
            diag_probe[80] = snap_last_ym_a0;
            diag_probe[88:81] = snap_last_oki_data;
            diag_probe[103:89] = snap_last_shared_addr;
            diag_probe[111:104] = snap_last_shared_data;
        end
        default: begin
            if (diag_source[5]) begin
                case (diag_source[7:6])
                    2'd0: begin
                        diag_probe[21:0] = snap_gfx_logical0;
                        diag_probe[43:22] = snap_gfx_physical0;
                        diag_probe[59:44] = snap_gfx_data0;
                        diag_probe[83:60] = snap_gfx_response_count0;
                    end
                    2'd1: begin
                        diag_probe[21:0] = snap_gfx_logical1;
                        diag_probe[43:22] = snap_gfx_physical1;
                        diag_probe[59:44] = snap_gfx_data1;
                        diag_probe[83:60] = snap_gfx_response_count1;
                    end
                    2'd2: begin
                        diag_probe[21:0] = snap_gfx_logical2;
                        diag_probe[43:22] = snap_gfx_physical2;
                        diag_probe[59:44] = snap_gfx_data2;
                        diag_probe[83:60] = snap_gfx_response_count2;
                    end
                    default: begin
                        diag_probe[21:0] = snap_gfx_logical3;
                        diag_probe[43:22] = snap_gfx_physical3;
                        diag_probe[59:44] = snap_gfx_data3;
                        diag_probe[83:60] = snap_gfx_response_count3;
                    end
                endcase
                diag_probe[85:84] = diag_source[7:6];
                diag_probe[86] = 1'b1;
            end else begin
                diag_probe[15:0] = snap_max_gp0_tile_cycles;
                diag_probe[31:16] = snap_max_gp0_object_cycles;
                diag_probe[47:32] = snap_max_gp1_tile_cycles;
                diag_probe[63:48] = snap_max_gp1_object_cycles;
                diag_probe[87:64] = snap_object_swap_count;
                diag_probe[111:88] = snap_visible_not_ready_count;
            end
        end
      endcase
      diag_probe[127:112] = 16'hd600 | {13'd0, diag_source[2:0]};
    end
end

altsource_probe #(
    .sld_auto_instance_index ("NO"),
    .sld_instance_index      (0),
    .instance_id             ("DGP"),
    .probe_width             (128),
    .source_width            (32),
    .source_initial_value    ("00000000"),
    .enable_metastability    ("NO")
) u_dogyuun_profile_jtag (
    .probe  (diag_probe),
    .source (diag_source)
);

endmodule
