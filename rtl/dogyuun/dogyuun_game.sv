// Dogyuun integration shell: verified ROM loading, board-accurate raster,
// MC68000, encrypted V25/audio subsystem, and dual-GP9001 line renderer.
module dogyuun_game #(
    parameter integer AW = 22,
    parameter integer SS_IRQ_TIMEOUT_CYCLES = 1048576
) (
    input              rst,
    input              cold_rst,
    input              clk,
    input              clk96,
    input              rst96,
    input              clk48,
    input              rst48,
    input              clk24,
    input              rst24,

    output reg         pxl2_cen,
    output reg         pxl_cen,
    output reg [7:0]   red,
    output reg [7:0]   green,
    output reg [7:0]   blue,
    output reg         LHBL,
    output reg         LVBL,
    output reg         HS,
    output reg         VS,

    input      [3:0]   cab_1p,
    input      [3:0]   coin,
    input      [`JTFRAME_BUTTONS+3:0] joystick1,
    input      [`JTFRAME_BUTTONS+3:0] joystick2,
    input      [`JTFRAME_BUTTONS+3:0] joystick3,
    input      [`JTFRAME_BUTTONS+3:0] joystick4,
    input      [15:0]  joyana_l1,
    input      [15:0]  joyana_l2,
    input      [15:0]  joyana_l3,
    input      [15:0]  joyana_l4,
    input      [15:0]  joyana_r1,
    input      [15:0]  joyana_r2,
    input      [15:0]  joyana_r3,
    input      [15:0]  joyana_r4,
    input      [1:0]   dial_x,
    input      [1:0]   dial_y,

    input      [26:0]  ioctl_addr,
    input      [7:0]   ioctl_dout,
    input              ioctl_cart,
    input              ioctl_wr,
    input              ioctl_ram,
    output     [7:0]   ioctl_din,
    input              ioctl_rom,
    output             dwnld_busy,
    input      [15:0]  data_read,

    input              hs_reset,
    input              hs_config_download,
    input              hs_config_wr,
    input              hs_nvram_download,
    input              hs_nvram_upload,
    input              hs_nvram_wr,
    input              hs_nvram_rd,
    input      [26:0]  hs_addr,
    input      [7:0]   hs_dout,
    output     [7:0]   hs_din,
    output             hs_wait,
    output             hs_dirty,
    output             hs_active,

    output     [AW-1:0] ba0_addr,
    output     [AW-1:0] ba1_addr,
    output     [AW-1:0] ba2_addr,
    output     [AW-1:0] ba3_addr,
    output     [3:0]   ba_rd,
    output     [3:0]   ba_wr,
    input      [3:0]   ba_dst,
    input      [3:0]   ba_dok,
    input      [3:0]   ba_rdy,
    input      [3:0]   ba_ack,
    output     [15:0]  ba0_din,
    output     [1:0]   ba0_dsn,
    output     [15:0]  ba1_din,
    output     [1:0]   ba1_dsn,
    output     [15:0]  ba2_din,
    output     [1:0]   ba2_dsn,
    output     [15:0]  ba3_din,
    output     [1:0]   ba3_dsn,

    output     [1:0]   prog_ba,
    input              prog_rdy,
    input              prog_ack,
    input              prog_dok,
    input              prog_dst,
    output     [15:0]  prog_data,
    output     [AW-1:0] prog_addr,
    output             prog_rd,
    output             prog_we,
    output     [1:0]   prog_mask,

    input      [31:0]  status,
    input              dip_pause,
    inout              dip_flip,
    input              dip_test,
    input      [1:0]   dip_fxlevel,
    input              service,
    input              tilt,
    input      [31:0]  dipsw,

    output signed [15:0] snd_left,
    output signed [15:0] snd_right,
    output             sample,
    input      [5:0]   snd_en,
    input      [7:0]   snd_vol,
    output     [5:0]   snd_vu,
    output             snd_peak,

    input      [3:0]   gfx_en,
    output     [7:0]   debug_bus,
    output     [7:0]   debug_view,

    input              ss_do_save,
    input              ss_do_restore,
    input              ss_busy,
    input              ss_format_valid,
    output reg         ss_write_start,
    output reg         ss_read_start,
    output             ss_active,
    output     [3:0]   ss_state_out,
    input      [63:0]  ss_data,
    input      [31:0]  ss_addr,
    input      [7:0]   ss_select,
    input              ss_write,
    input              ss_read,
    input              ss_query,
    output     [63:0]  ss_data_out,
    output             ss_ack
);

localparam [9:0] H_TOTAL = 10'd432;
localparam [8:0] V_TOTAL = 9'd262;
localparam [7:0] SSIDX_GLOBAL = 8'd1;

localparam [3:0] SS_IDLE                = 4'd0;
localparam [3:0] SS_SAVE_WAIT_SAFE      = 4'd1;
localparam [3:0] SS_SAVE_WAIT_IRQ       = 4'd2;
localparam [3:0] SS_SAVE_WAIT_SSP       = 4'd3;
localparam [3:0] SS_SAVE_WAIT_STREAM    = 4'd4;
localparam [3:0] SS_SAVE_WAIT_EXIT      = 4'd5;
localparam [3:0] SS_RESTORE_WAIT_SAFE   = 4'd6;
localparam [3:0] SS_RESTORE_WAIT_STREAM = 4'd7;
localparam [3:0] SS_RESTORE_HOLD_RESET  = 4'd8;
localparam [3:0] SS_RESTORE_WAIT_RESET  = 4'd9;
localparam [3:0] SS_SAVE_WAIT_HOLD      = 4'd10;
localparam [3:0] SS_RESTORE_WAIT_HOLD   = 4'd11;
localparam [3:0] SS_RESTORE_WAIT_VIDEO  = 4'd12;
localparam [3:0] SS_SAVE_WAIT_VIDEO     = 4'd13;
localparam [3:0] SS_SAVE_RETRY          = 4'd14;
localparam [19:0] SS_IRQ_TIMEOUT_COUNT =
    SS_IRQ_TIMEOUT_CYCLES - 1;

reg [3:0] clkdiv;
reg [9:0] hcnt;
reg [8:0] vcnt;
reg       video_epoch;
reg [3:0] video_deadline_latched;
reg [3:0] ss_state = SS_IDLE;
reg [7:0] ss_reset_counter = 8'd0;
reg [19:0] ss_irq_wait_counter = 20'd0;
reg [2:0] ss_irq_retry_count = 3'd0;
reg [31:0] ss_saved_ssp = 32'd0;
reg [31:0] ss_restore_ssp = 32'd0;
reg [63:0] ss_restore_rom_signature = 64'd0;
reg        ss_restore_irq4 = 1'b0;
reg [7:0]  ss_restore_coin_control = 8'd0;
reg        ss_restore_commit = 1'b0;
reg        ss_video_frame_seen = 1'b0;
reg [63:0] loaded_rom_signature = 64'd0;
reg [63:0] ss_global_data_out = 64'd0;
reg        ss_global_ack = 1'b0;

wire loader_accepted;
wire loader_range_error;
wire loader_overflow_error;
wire [26:0] loader_last_addr;
wire main_reset = rst || dwnld_busy;
(* preserve *) reg [1:0] sound_reset_pipe = 2'b11;
wire sound_reset = sound_reset_pipe[1];
(* preserve *) reg [1:0] video_reset_pipe = 2'b11;
wire video_reset = video_reset_pipe[1];

wire [15:0] main_in1_data;
wire [15:0] main_in2_data;
wire [15:0] main_sys_data;
wire        main_rom_cs;
wire [17:0] main_rom_addr;
wire [15:0] main_rom_data;
wire        main_rom_ok;
wire        main_rom_rd;
wire        main_cpu_cen;
wire        main_cpu_cenb;
wire        main_cpu_bus_active;
wire        main_cpu_rw;
wire        main_cpu_ack;
wire        main_cpu_iack;
wire        main_cpu_lds_n;
wire [2:0]  main_cpu_fc;
wire        main_gp_idle;
wire [23:0] main_cpu_addr;
wire [15:0] main_cpu_dout;
wire [15:0] main_cpu_din;
wire [1:0]  main_wram_we;
wire        main_irq4;
wire [12:0] main_gp0_ptr;
wire [12:0] main_gp1_ptr;
wire [23:0] main_last_program_fetch;
wire [31:0] main_bus_count;
wire [31:0] main_rom_read_count;
wire [31:0] main_wram_write_count;
wire [31:0] main_shared_write_count;
wire [31:0] main_gp_access_count;
wire [31:0] main_palette_write_count;
wire [31:0] main_io_access_count;
wire [31:0] main_unmapped_count;
wire [31:0] main_irq_count;
wire [31:0] main_iack_count;
wire [15:0] main_debug_events;
wire [7:0]  main_coin_control;
wire        main_v25_reset_n;
wire [63:0] main_ss_data_out;
wire        main_ss_ack;
wire [14:0] sound_shared_addr;
wire [7:0]  sound_shared_dout;
wire [7:0]  sound_shared_din;
wire        sound_shared_we;
wire [17:0] sound_oki_rom_addr;
wire [7:0]  sound_oki_rom_data;
wire        sound_oki_rom_ok;
wire        sound_oki_rom_rd;
wire [AW-1:0] sound_oki_sdram_addr;
wire signed [15:0] sound_mono;
wire        sound_sample;
wire        sound_debug_fault;
wire        sound_debug_halted;
wire [19:0] sound_debug_pc;
wire        sound_debug_state_idle;
wire        sound_state_idle;
wire        sound_state_held;
wire [63:0] sound_ss_data_out;
wire        sound_ss_ack;
wire        sound_debug_v25_reset_n;
wire        sound_debug_ym_write;
wire        sound_debug_ym_a0;
wire [7:0]  sound_debug_ym_data;
wire        sound_debug_oki_write;
wire [7:0]  sound_debug_oki_data;
wire        sound_debug_oki_cen;
wire [7:0]  sound_debug_oki_status;
wire signed [13:0] sound_debug_oki_sound;
wire [12:0] video_gp0_vram_addr;
wire [15:0] video_gp0_vram_data;
wire [12:0] video_gp1_vram_addr;
wire [15:0] video_gp1_vram_data;
wire [12:0] gp0_snapshot_addr;
wire [15:0] gp0_snapshot_data;
wire [12:0] gp1_snapshot_addr;
wire [15:0] gp1_snapshot_data;
wire [9:0]  video_gp0_object_addr;
wire [15:0] video_gp0_object_data;
wire [9:0]  video_gp1_object_addr;
wire [15:0] video_gp1_object_data;
wire [15:0] main_gp0_object_data;
wire [15:0] main_gp1_object_data;
wire        main_gp0_obj_buf_busy;
wire        main_gp1_obj_buf_busy;
wire [127:0] video_gp0_scrolls;
wire [127:0] video_gp1_scrolls;
wire [7:0] video_gp0_scroll_flip;
wire [7:0] video_gp1_scroll_flip;
wire [127:0] main_gp0_scrolls;
wire [127:0] main_gp1_scrolls;
wire [7:0] main_gp0_scroll_flip;
wire [7:0] main_gp1_scroll_flip;
wire [10:0] video_palette_addr;
wire [15:0] video_palette_data;
wire [10:0] palette_snapshot_addr;
wire [15:0] palette_snapshot_data;
wire video_line_ready;
wire [10:0] video_gp0_color;
wire [10:0] video_gp1_color;
wire [3:0] video_engine_busy;
wire [3:0] video_deadline_miss;
wire [15:0] video_gp0_tile_cycles;
wire [15:0] video_gp0_object_cycles;
wire [15:0] video_gp1_tile_cycles;
wire [15:0] video_gp1_object_cycles;
wire [8:0] video_debug_gp0_tile_y;
wire [8:0] video_debug_gp0_object_y;
wire [8:0] video_debug_gp1_tile_y;
wire [8:0] video_debug_gp1_object_y;
wire [3:0] video_debug_line_epoch;
wire [3:0] video_debug_line_valid;
wire video_gp0_tile_req;
wire [21:0] video_gp0_tile_addr;
wire [15:0] video_gp0_tile_data;
wire video_gp0_tile_ok;
wire video_gp0_object_req;
wire [21:0] video_gp0_object_gfx_addr;
wire [15:0] video_gp0_object_gfx_data;
wire video_gp0_object_ok;
wire video_gp1_tile_req;
wire [21:0] video_gp1_tile_addr;
wire [15:0] video_gp1_tile_data;
wire video_gp1_tile_ok;
wire video_gp1_object_req;
wire [21:0] video_gp1_object_gfx_addr;
wire [15:0] video_gp1_object_gfx_data;
wire video_gp1_object_ok;
wire video_gp0_rom_rd;
wire video_gp1_rom_rd;
wire [21:0] video_gp0_tile_physical_addr;
wire [21:0] video_gp0_object_physical_addr;
wire [21:0] video_gp1_tile_physical_addr;
wire [21:0] video_gp1_object_physical_addr;
wire        main_irq4_start = (clkdiv == 4'd13) &&
                              (hcnt == 10'd0) && (vcnt == 9'd230);
wire        main_obj_buf_start = (clkdiv == 4'd13) &&
                                 (hcnt == H_TOTAL - 1'b1) &&
                                 (vcnt == 9'd239);
wire video_line_event = (clkdiv == 4'd13) && (hcnt == H_TOTAL - 1'b1);
wire video_line_start = video_line_event &&
                        ((vcnt < 9'd238) || (vcnt >= 9'd260));
wire video_line_commit = (clkdiv == 4'd13) && (hcnt == H_TOTAL - 1'b1) &&
                         ((vcnt < 9'd239) || (vcnt == V_TOTAL - 1'b1));
wire [8:0] video_target_y = (vcnt >= 9'd260) ?
                            vcnt - 9'd260 : vcnt + 9'd2;
wire video_target_epoch = (vcnt >= 9'd260) ?
                          ~video_epoch : video_epoch;

wire ss_irq = ss_state == SS_SAVE_WAIT_IRQ;
wire ss_override = (ss_state == SS_SAVE_WAIT_SSP) ||
                   (ss_state == SS_SAVE_WAIT_EXIT) ||
                   (ss_state == SS_RESTORE_HOLD_RESET) ||
                   (ss_state == SS_RESTORE_WAIT_RESET);
wire ss_reset = ss_state == SS_RESTORE_HOLD_RESET;
wire ss_cpu_run = (ss_state != SS_SAVE_WAIT_STREAM) &&
                  (ss_state != SS_RESTORE_WAIT_STREAM) &&
                  (ss_state != SS_SAVE_WAIT_HOLD) &&
                  (ss_state != SS_RESTORE_WAIT_HOLD) &&
                  (ss_state != SS_SAVE_WAIT_VIDEO) &&
                  (ss_state != SS_RESTORE_WAIT_VIDEO);
wire ss_device_hold = (ss_state != SS_IDLE) &&
                      (ss_state != SS_SAVE_WAIT_SAFE) &&
                      (ss_state != SS_SAVE_WAIT_IRQ) &&
                      (ss_state != SS_SAVE_RETRY) &&
                      (ss_state != SS_RESTORE_WAIT_SAFE);
wire ss_sound_hold = ss_device_hold;
wire ss_video_reset = (ss_state == SS_SAVE_WAIT_SSP) ||
                      (ss_state == SS_SAVE_WAIT_HOLD) ||
                      (ss_state == SS_SAVE_WAIT_STREAM) ||
                      (ss_state == SS_RESTORE_WAIT_HOLD) ||
                      (ss_state == SS_RESTORE_WAIT_STREAM);
// The V25 has an architectural save-state port and resumes against restored
// shared RAM. Keep the sound domain alive while the 68000 alone takes reset.
wire sound_reset_request = main_reset;
wire video_reset_request = main_reset || ss_video_reset;
wire [63:0] ss_current_rom_signature = loaded_rom_signature;
wire ss_restore_compatible =
    ss_format_valid &&
    (ss_restore_rom_signature == ss_current_rom_signature);
wire ss_safe_point =
    !main_reset &&
    (vcnt == 9'd240) &&
    !main_cpu_bus_active &&
    main_gp_idle &&
    sound_state_idle &&
    !(|video_engine_busy) &&
    !main_gp0_obj_buf_busy &&
    !main_gp1_obj_buf_busy;
wire ss_video_release_point =
    ss_video_frame_seen &&
    (clkdiv == 4'd0) &&
    (hcnt == 10'd0) &&
    (vcnt == 9'd240);
`ifdef DOGYUUN_SS_PROBE
wire ss_probe_source;
(* async_reg = "true" *) reg [1:0] ss_probe_source_sync = 2'b00;
reg ss_probe_source_d = 1'b0;

always @(posedge clk) begin
    ss_probe_source_sync <= {ss_probe_source_sync[0], ss_probe_source};
    ss_probe_source_d <= ss_probe_source_sync[1];
end

wire ss_probe_save_pulse =
    ss_probe_source_sync[1] && !ss_probe_source_d;
`else
wire ss_probe_save_pulse = 1'b0;
`endif
wire ss_save_request = ss_do_save || ss_probe_save_pulse;
wire [63:0] ss_cpu_reset_vector = {
    ss_restore_ssp[31:16],
    ss_restore_ssp[15:0],
    16'h00ff,
    16'h0008
};

dogyuun_rom_loader #(.AW(AW)) u_rom_loader (
    .clk            ( clk                   ),
    // game_rst is asserted throughout an MRA download. The loader must use
    // the framework reset so it remains alive while ioctl_rom is active.
    .rst            ( cold_rst              ),
    .ioctl_rom      ( ioctl_rom             ),
    .ioctl_addr     ( ioctl_addr            ),
    .ioctl_dout     ( ioctl_dout            ),
    .ioctl_wr       ( ioctl_wr              ),
    .dwnld_busy     ( dwnld_busy            ),
    .prog_ba        ( prog_ba               ),
    .prog_addr      ( prog_addr             ),
    .prog_data      ( prog_data             ),
    .prog_mask      ( prog_mask             ),
    .prog_rd        ( prog_rd               ),
    .prog_we        ( prog_we               ),
    .prog_rdy       ( prog_rdy              ),
    .prog_ack       ( prog_ack              ),
    .accepted       ( loader_accepted       ),
    .range_error    ( loader_range_error    ),
    .overflow_error ( loader_overflow_error ),
    .last_addr      ( loader_last_addr      )
);

assign ioctl_din = 8'h00;

assign ba_rd = {sound_oki_rom_rd, video_gp1_rom_rd,
                video_gp0_rom_rd, main_rom_rd};
assign ba_wr = 4'b0000;
assign ba0_din = 16'h0000;
assign ba1_din = 16'h0000;
assign ba2_din = 16'h0000;
assign ba3_din = 16'h0000;
assign ba0_dsn = 2'b11;
assign ba1_dsn = 2'b11;
assign ba2_dsn = 2'b11;
assign ba3_dsn = 2'b11;
assign ba3_addr = sound_oki_sdram_addr;

dogyuun_gfx_repack #(.GP_INDEX(0)) u_gp0_tile_repack (
    .logical_addr  (video_gp0_tile_addr),
    .physical_addr (video_gp0_tile_physical_addr)
);

dogyuun_gfx_repack #(.GP_INDEX(0)) u_gp0_object_repack (
    .logical_addr  (video_gp0_object_gfx_addr),
    .physical_addr (video_gp0_object_physical_addr)
);

dogyuun_gfx_repack #(.GP_INDEX(1)) u_gp1_tile_repack (
    .logical_addr  (video_gp1_tile_addr),
    .physical_addr (video_gp1_tile_physical_addr)
);

dogyuun_gfx_repack #(.GP_INDEX(1)) u_gp1_object_repack (
    .logical_addr  (video_gp1_object_gfx_addr),
    .physical_addr (video_gp1_object_physical_addr)
);

// Dogyuun has no framework-level flip output. Keep the rotation polarity
// deterministic; the game's own Flip Screen DIP remains in dipsw[1].
assign dip_flip = 1'b0;
assign snd_left = sound_mono;
assign snd_right = sound_mono;
assign sample = sound_sample;
assign snd_vu = 6'd0;
assign snd_peak = 1'b0;

assign ss_active = ss_state != SS_IDLE;
assign ss_state_out = ss_state;
assign ss_ack = ss_global_ack || main_ss_ack || sound_ss_ack;
assign ss_data_out = ss_global_ack ? ss_global_data_out :
                     main_ss_ack ? main_ss_data_out :
                     sound_ss_ack ? sound_ss_data_out :
                     64'd0;

// Keep a compact identity for the loaded set in every state. Address zero
// starts a fresh signature so a later MRA download cannot inherit old bytes.
always @(posedge clk) begin
    if (cold_rst) begin
        loaded_rom_signature <= 64'd0;
    end else if (ioctl_rom && ioctl_wr && (ioctl_addr < 27'd8)) begin
        case (ioctl_addr[2:0])
            3'd0: loaded_rom_signature <= {ioctl_dout, 56'd0};
            3'd1: loaded_rom_signature[55:48] <= ioctl_dout;
            3'd2: loaded_rom_signature[47:40] <= ioctl_dout;
            3'd3: loaded_rom_signature[39:32] <= ioctl_dout;
            3'd4: loaded_rom_signature[31:24] <= ioctl_dout;
            3'd5: loaded_rom_signature[23:16] <= ioctl_dout;
            3'd6: loaded_rom_signature[15:8] <= ioctl_dout;
            default: loaded_rom_signature[7:0] <= ioctl_dout;
        endcase
    end
end

// Chunk 1 stores the architectural supervisor stack pointer, the two board
// latches that survive a frame boundary, and the loaded-ROM identity.
always @(posedge clk) begin
    ss_global_ack <= 1'b0;

    if (rst || dwnld_busy || ioctl_rom) begin
        ss_global_data_out <= 64'd0;
        ss_restore_ssp <= 32'd0;
        ss_restore_irq4 <= 1'b0;
        ss_restore_coin_control <= 8'd0;
        ss_restore_rom_signature <= 64'd0;
    end else if (ss_do_restore) begin
        ss_restore_ssp <= 32'd0;
        ss_restore_irq4 <= 1'b0;
        ss_restore_coin_control <= 8'd0;
        ss_restore_rom_signature <= 64'd0;
    end else if (ss_select == SSIDX_GLOBAL) begin
        if (ss_query) begin
            ss_global_data_out <= {SSIDX_GLOBAL, 22'd0, 2'd3, 32'd2};
            ss_global_ack <= 1'b1;
        end else if (ss_read) begin
            if (ss_addr[0])
                ss_global_data_out <= ss_current_rom_signature;
            else
                ss_global_data_out <= {
                    23'd0,
                    main_coin_control,
                    main_irq4,
                    ss_saved_ssp
                };
            ss_global_ack <= 1'b1;
        end else if (ss_write) begin
            if (ss_addr[0]) begin
                ss_restore_rom_signature <= ss_data;
            end else begin
                ss_restore_ssp <= ss_data[31:0];
                ss_restore_irq4 <= ss_data[32];
                ss_restore_coin_control <= ss_data[40:33];
            end
            ss_global_ack <= 1'b1;
        end
    end
end

// Enter at a quiet vertical-blank boundary, preserve all MC68000 registers in
// a private IRQ7 handler, then stream state while every mutable client is held.
always @(posedge clk) begin
    if (rst || dwnld_busy || ioctl_rom) begin
        ss_state <= SS_IDLE;
        ss_write_start <= 1'b0;
        ss_read_start <= 1'b0;
        ss_reset_counter <= 8'd0;
        ss_irq_wait_counter <= 20'd0;
        ss_irq_retry_count <= 3'd0;
        ss_saved_ssp <= 32'd0;
        ss_restore_commit <= 1'b0;
        ss_video_frame_seen <= 1'b0;
    end else begin
        ss_restore_commit <= 1'b0;

        if (ss_active && video_line_event && (vcnt == V_TOTAL - 1'b1))
            ss_video_frame_seen <= 1'b1;

        case (ss_state)
            SS_IDLE: begin
                ss_write_start <= 1'b0;
                ss_read_start <= 1'b0;
                ss_irq_wait_counter <= 20'd0;
                ss_irq_retry_count <= 3'd0;
                if (ss_save_request) begin
                    ss_video_frame_seen <= 1'b0;
                    ss_state <= SS_SAVE_WAIT_SAFE;
                end else if (ss_do_restore) begin
                    ss_video_frame_seen <= 1'b0;
                    ss_state <= SS_RESTORE_WAIT_SAFE;
                end
            end

            SS_SAVE_WAIT_SAFE: begin
                if (ss_safe_point) begin
                    ss_irq_wait_counter <= 20'd0;
                    ss_state <= SS_SAVE_WAIT_IRQ;
                end
            end

            SS_SAVE_WAIT_IRQ: begin
                if (main_cpu_iack && (main_cpu_addr[3:1] == 3'b111) &&
                    !main_cpu_lds_n) begin
                    ss_irq_wait_counter <= 20'd0;
                    ss_state <= SS_SAVE_WAIT_SSP;
                end else if (ss_irq_wait_counter ==
                             SS_IRQ_TIMEOUT_COUNT) begin
                    ss_irq_wait_counter <= 20'd0;
                    if (&ss_irq_retry_count) begin
                        ss_state <= SS_IDLE;
                    end else begin
                        ss_irq_retry_count <= ss_irq_retry_count + 3'd1;
                        ss_state <= SS_SAVE_RETRY;
                    end
                end else begin
                    ss_irq_wait_counter <= ss_irq_wait_counter + 20'd1;
                end
            end

            SS_SAVE_RETRY: begin
                // Drop IRQ7 long enough for fx68k to observe a fresh edge.
                if (vcnt != 9'd240)
                    ss_state <= SS_SAVE_WAIT_SAFE;
            end

            SS_SAVE_WAIT_SSP: begin
                if (main_cpu_ack && !main_cpu_rw &&
                    (main_cpu_addr == 24'hff0000))
                    ss_saved_ssp[31:16] <= main_cpu_dout;

                if (main_cpu_ack && !main_cpu_rw &&
                    (main_cpu_addr == 24'hff0002)) begin
                    ss_saved_ssp[15:0] <= main_cpu_dout;
                    ss_state <= SS_SAVE_WAIT_HOLD;
                end
            end

            SS_SAVE_WAIT_HOLD: begin
                if (sound_state_held) begin
                    ss_write_start <= 1'b1;
                    ss_state <= SS_SAVE_WAIT_STREAM;
                end
            end

            SS_SAVE_WAIT_STREAM: begin
                if (ss_busy && ss_write_start) begin
                    ss_write_start <= 1'b0;
                end else if (!ss_busy && !ss_write_start) begin
                    ss_video_frame_seen <= 1'b0;
                    ss_state <= SS_SAVE_WAIT_EXIT;
                end
            end

            SS_SAVE_WAIT_EXIT: begin
                if (main_cpu_ack && main_cpu_rw &&
                    (main_cpu_fc == 3'b110) &&
                    (main_cpu_addr[23:8] != 16'hff00))
                    ss_state <= SS_SAVE_WAIT_VIDEO;
            end

            SS_SAVE_WAIT_VIDEO: begin
                if (ss_video_release_point)
                    ss_state <= SS_IDLE;
            end

            SS_RESTORE_WAIT_SAFE: begin
                if (ss_safe_point)
                    ss_state <= SS_RESTORE_WAIT_HOLD;
            end

            SS_RESTORE_WAIT_HOLD: begin
                if (sound_state_held) begin
                    ss_read_start <= 1'b1;
                    ss_state <= SS_RESTORE_WAIT_STREAM;
                end
            end

            SS_RESTORE_WAIT_STREAM: begin
                if (ss_busy && ss_read_start) begin
                    ss_read_start <= 1'b0;
                end else if (!ss_busy && !ss_read_start) begin
                    ss_video_frame_seen <= 1'b0;
                    if (ss_restore_compatible) begin
                        ss_reset_counter <= 8'd0;
                        ss_restore_commit <= 1'b1;
                        ss_state <= SS_RESTORE_HOLD_RESET;
                    end else begin
                        ss_state <= SS_RESTORE_WAIT_VIDEO;
                    end
                end
            end

            SS_RESTORE_HOLD_RESET: begin
                ss_reset_counter <= ss_reset_counter + 8'd1;
                if (&ss_reset_counter)
                    ss_state <= SS_RESTORE_WAIT_RESET;
            end

            SS_RESTORE_WAIT_RESET: begin
                if (main_cpu_ack && main_cpu_rw &&
                    (main_cpu_fc == 3'b110) &&
                    (main_cpu_addr[23:8] != 16'hff00) &&
                    (main_cpu_addr >= 24'h000008))
                    ss_state <= SS_RESTORE_WAIT_VIDEO;
            end

            SS_RESTORE_WAIT_VIDEO: begin
                if (ss_video_release_point && sound_state_held)
                    ss_state <= SS_IDLE;
            end

            default: begin
                ss_state <= SS_IDLE;
                ss_write_start <= 1'b0;
                ss_read_start <= 1'b0;
            end
        endcase
    end
end

`ifdef DOGYUUN_SS_PROBE
reg [14:0] ss_probe_state_seen = 15'd0;
reg [3:0]  ss_probe_state_d = SS_IDLE;
reg [31:0] ss_probe_state_cycles = 32'd0;
reg        ss_probe_busy_d = 1'b0;
reg        ss_probe_save_request_seen = 1'b0;
reg        ss_probe_busy_seen = 1'b0;
reg        ss_probe_busy_done_seen = 1'b0;
reg        ss_probe_ssp_hi_seen = 1'b0;
reg        ss_probe_ssp_lo_seen = 1'b0;
reg        ss_probe_exit_seen = 1'b0;
reg        ss_probe_video_seen = 1'b0;
reg        ss_probe_complete_seen = 1'b0;
reg        ss_probe_irq_iack_seen = 1'b0;
reg        ss_probe_hold_seen = 1'b0;
reg [31:0] ss_probe_read_ack_count = 32'd0;
reg [15:0] ss_probe_query_ack_count = 16'd0;
reg [15:0] ss_probe_write_ack_count = 16'd0;
reg [23:0] ss_probe_last_cpu_addr = 24'd0;
reg [15:0] ss_probe_last_cpu_data = 16'd0;
reg [3:0]  ss_probe_last_cpu_state = SS_IDLE;
reg [2:0]  ss_probe_last_cpu_fc = 3'd0;
reg        ss_probe_last_cpu_rw = 1'b0;

always @(posedge clk) begin
    if (rst || dwnld_busy || ioctl_rom) begin
        ss_probe_state_seen <= 15'd0;
        ss_probe_state_d <= SS_IDLE;
        ss_probe_state_cycles <= 32'd0;
        ss_probe_busy_d <= 1'b0;
        ss_probe_save_request_seen <= 1'b0;
        ss_probe_busy_seen <= 1'b0;
        ss_probe_busy_done_seen <= 1'b0;
        ss_probe_ssp_hi_seen <= 1'b0;
        ss_probe_ssp_lo_seen <= 1'b0;
        ss_probe_exit_seen <= 1'b0;
        ss_probe_video_seen <= 1'b0;
        ss_probe_complete_seen <= 1'b0;
        ss_probe_irq_iack_seen <= 1'b0;
        ss_probe_hold_seen <= 1'b0;
        ss_probe_read_ack_count <= 32'd0;
        ss_probe_query_ack_count <= 16'd0;
        ss_probe_write_ack_count <= 16'd0;
        ss_probe_last_cpu_addr <= 24'd0;
        ss_probe_last_cpu_data <= 16'd0;
        ss_probe_last_cpu_state <= SS_IDLE;
        ss_probe_last_cpu_fc <= 3'd0;
        ss_probe_last_cpu_rw <= 1'b0;
    end else if (ss_save_request) begin
        ss_probe_state_seen <= 15'b000_0000_0000_0001;
        ss_probe_state_d <= ss_state;
        ss_probe_state_cycles <= 32'd0;
        ss_probe_busy_d <= ss_busy;
        ss_probe_save_request_seen <= 1'b1;
        ss_probe_busy_seen <= 1'b0;
        ss_probe_busy_done_seen <= 1'b0;
        ss_probe_ssp_hi_seen <= 1'b0;
        ss_probe_ssp_lo_seen <= 1'b0;
        ss_probe_exit_seen <= 1'b0;
        ss_probe_video_seen <= 1'b0;
        ss_probe_complete_seen <= 1'b0;
        ss_probe_irq_iack_seen <= 1'b0;
        ss_probe_hold_seen <= 1'b0;
        ss_probe_read_ack_count <= 32'd0;
        ss_probe_query_ack_count <= 16'd0;
        ss_probe_write_ack_count <= 16'd0;
        ss_probe_last_cpu_addr <= main_cpu_addr;
        ss_probe_last_cpu_data <= main_cpu_din;
        ss_probe_last_cpu_state <= ss_state;
        ss_probe_last_cpu_fc <= main_cpu_fc;
        ss_probe_last_cpu_rw <= main_cpu_rw;
    end else begin
        ss_probe_busy_d <= ss_busy;

        if (ss_state < 4'd15)
            ss_probe_state_seen[ss_state] <= 1'b1;

        if (ss_state != ss_probe_state_d) begin
            ss_probe_state_d <= ss_state;
            ss_probe_state_cycles <= 32'd0;
        end else if (!(&ss_probe_state_cycles)) begin
            ss_probe_state_cycles <= ss_probe_state_cycles + 32'd1;
        end

        if (ss_busy)
            ss_probe_busy_seen <= 1'b1;
        if (ss_probe_busy_d && !ss_busy)
            ss_probe_busy_done_seen <= 1'b1;
        if (main_cpu_iack)
            ss_probe_irq_iack_seen <= 1'b1;
        if ((ss_state == SS_SAVE_WAIT_HOLD) && sound_state_held)
            ss_probe_hold_seen <= 1'b1;
        if (ss_state == SS_SAVE_WAIT_EXIT)
            ss_probe_exit_seen <= 1'b1;
        if (ss_state == SS_SAVE_WAIT_VIDEO)
            ss_probe_video_seen <= 1'b1;
        if ((ss_state == SS_SAVE_WAIT_VIDEO) && ss_video_release_point)
            ss_probe_complete_seen <= 1'b1;

        if (main_cpu_ack && !main_cpu_rw &&
            (main_cpu_addr == 24'hff0000))
            ss_probe_ssp_hi_seen <= 1'b1;
        if (main_cpu_ack && !main_cpu_rw &&
            (main_cpu_addr == 24'hff0002))
            ss_probe_ssp_lo_seen <= 1'b1;

        if (ss_query && ss_ack && !(&ss_probe_query_ack_count))
            ss_probe_query_ack_count <= ss_probe_query_ack_count + 16'd1;
        if (ss_read && ss_ack && !(&ss_probe_read_ack_count))
            ss_probe_read_ack_count <= ss_probe_read_ack_count + 32'd1;
        if (ss_write && ss_ack && !(&ss_probe_write_ack_count))
            ss_probe_write_ack_count <= ss_probe_write_ack_count + 16'd1;

        if (main_cpu_ack) begin
            ss_probe_last_cpu_addr <= main_cpu_addr;
            ss_probe_last_cpu_data <= main_cpu_rw ?
                main_cpu_din : main_cpu_dout;
            ss_probe_last_cpu_state <= ss_state;
            ss_probe_last_cpu_fc <= main_cpu_fc;
            ss_probe_last_cpu_rw <= main_cpu_rw;
        end
    end
end

wire [15:0] ss_probe_live_flags = {
    ss_busy,
    ss_write_start,
    ss_read_start,
    ss_query,
    ss_read,
    ss_write,
    ss_ack,
    ss_safe_point,
    ss_cpu_run,
    ss_device_hold,
    sound_state_idle,
    sound_state_held,
    ss_video_frame_seen,
    ss_video_release_point,
    ss_irq,
    ss_override
};
wire [31:0] ss_probe_word19 = {
    16'hd955,
    4'd2,
    ss_state,
    ss_probe_save_request_seen,
    ss_probe_busy_seen,
    ss_probe_busy_done_seen,
    ss_probe_ssp_hi_seen,
    ss_probe_ssp_lo_seen,
    ss_probe_exit_seen,
    ss_probe_video_seen,
    ss_probe_complete_seen
};
wire [31:0] ss_probe_word18 = {17'd0, ss_probe_state_seen};
wire [31:0] ss_probe_word17 = ss_probe_state_cycles;
wire [31:0] ss_probe_word16 = ss_saved_ssp;
wire [31:0] ss_probe_word15 = {
    ss_irq_retry_count,
    ss_irq_wait_counter,
    ss_reset_counter,
    ss_video_frame_seen
};
wire [31:0] ss_probe_word14 = {
    main_cpu_addr,
    main_cpu_fc,
    main_cpu_rw,
    main_cpu_ack,
    main_cpu_iack,
    main_cpu_lds_n,
    main_cpu_bus_active
};
wire [31:0] ss_probe_word13 = {main_cpu_dout, main_cpu_din};
wire [31:0] ss_probe_word12 = {
    main_last_program_fetch,
    ss_probe_last_cpu_state,
    ss_probe_last_cpu_fc,
    ss_probe_last_cpu_rw
};
wire [31:0] ss_probe_word11 = {
    ss_probe_last_cpu_addr,
    ss_probe_irq_iack_seen,
    ss_probe_hold_seen,
    6'd0
};
wire [31:0] ss_probe_word10 = {
    ss_probe_last_cpu_data,
    hcnt,
    clkdiv,
    2'd0
};
wire [31:0] ss_probe_word9 = {vcnt, ss_select, ss_addr[14:0]};
wire [31:0] ss_probe_word8 = ss_probe_read_ack_count;
wire [31:0] ss_probe_word7 = {
    ss_probe_query_ack_count,
    ss_probe_write_ack_count
};
wire [31:0] ss_probe_word6 = {16'h5a5e, ss_probe_live_flags};
wire [31:0] ss_probe_word5 = {
    5'd0,
    sound_state_idle,
    sound_state_held,
    sound_debug_state_idle,
    sound_debug_v25_reset_n,
    sound_debug_halted,
    sound_debug_fault,
    main_v25_reset_n,
    sound_debug_pc
};
wire [479:0] ss_probe_data = {
    ss_probe_word19,
    ss_probe_word18,
    ss_probe_word17,
    ss_probe_word16,
    ss_probe_word15,
    ss_probe_word14,
    ss_probe_word13,
    ss_probe_word12,
    ss_probe_word11,
    ss_probe_word10,
    ss_probe_word9,
    ss_probe_word8,
    ss_probe_word7,
    ss_probe_word6,
    ss_probe_word5
};

altsource_probe #(
    .sld_auto_instance_index ("NO"),
    .sld_instance_index      (0),
    .instance_id             ("DSS"),
    .probe_width             (480),
    .source_width            (1),
    .source_initial_value    ("0"),
    .enable_metastability    ("NO")
) u_ss_probe (
    .probe  (ss_probe_data),
    .source (ss_probe_source)
);
`endif

assign debug_bus = dwnld_busy ?
    {loader_range_error, loader_overflow_error, loader_accepted,
     prog_we, dwnld_busy, 3'b000} : main_last_program_fetch[15:8];
assign debug_view = dwnld_busy ? loader_last_addr[7:0] :
    {|video_deadline_latched, video_line_ready, video_engine_busy,
     main_irq4, main_v25_reset_n};

wire        hs_hold_request;
reg         hs_hold_ack = 1'b0;
wire        hs_ram_owned;
wire [12:0] hs_ram_addr;
wire [1:0]  hs_ram_we;
wire [15:0] hs_ram_data;
wire [15:0] hs_ram_q;
// Drain an in-flight 68000 transfer and stop the next phase enable on the
// idle boundary that acknowledges high-score ownership.
wire hs_cpu_run = !hs_hold_request ||
                  (main_cpu_bus_active && !hs_hold_ack);

always @(posedge clk) begin
    if (rst96 || !hs_hold_request || ss_active)
        hs_hold_ack <= 1'b0;
    else if (!main_cpu_bus_active)
        hs_hold_ack <= 1'b1;
end

dogyuun_highscore u_highscore (
    .clk             (clk),
    .reset           (hs_reset),
    .cpu_reset       (rst96),
    .config_download (hs_config_download),
    .config_wr       (hs_config_wr),
    .config_addr     (hs_addr),
    .config_data     (hs_dout),
    .nvram_download  (hs_nvram_download),
    .nvram_upload    (hs_nvram_upload),
    .nvram_wr        (hs_nvram_wr),
    .nvram_rd        (hs_nvram_rd),
    .nvram_addr      (hs_addr),
    .nvram_data      (hs_dout),
    .nvram_q         (hs_din),
    .nvram_wait      (hs_wait),
    .ss_active       (ss_active),
    .normal_ram_addr (main_cpu_addr[13:1]),
    .normal_ram_we   (main_wram_we),
    .normal_ram_data (main_cpu_dout),
    .hold_request    (hs_hold_request),
    .hold_ack        (hs_hold_ack),
    .ram_owned       (hs_ram_owned),
    .ram_addr        (hs_ram_addr),
    .ram_we          (hs_ram_we),
    .ram_data        (hs_ram_data),
    .ram_q           (hs_ram_q),
    .dirty           (hs_dirty),
    .active          (hs_active),
    .config_valid    ()
);

dogyuun_inputs u_inputs (
    .joy1_n    (joystick1[6:0]),
    .joy2_n    (joystick2[6:0]),
    .start_n   (cab_1p),
    .coin_n    (coin),
    .service_n (service),
    .tilt_n    (tilt),
    .test_n    (dip_test),
    .in1       (main_in1_data),
    .in2       (main_in2_data),
    .sys       (main_sys_data)
);

dogyuun_main u_main (
    .clk                 (clk),
    .rst                 (main_reset),
    .halt_n              (dip_pause || ss_active),
    .rom_cs              (main_rom_cs),
    .rom_addr            (main_rom_addr),
    .rom_data            (main_rom_data),
    .rom_ok              (main_rom_ok),
    .in1_data            (main_in1_data),
    .in2_data            (main_in2_data),
    .sys_data            (main_sys_data),
    .hcnt                (hcnt),
    .vcnt                (vcnt),
    .irq4_start          (main_irq4_start),
    .sound_clk           (clk),
    .sound_shared_addr   (sound_shared_addr),
    .sound_shared_din    (sound_shared_dout),
    .sound_shared_we     (sound_shared_we),
    .sound_shared_dout   (sound_shared_din),
    .coin_control        (main_coin_control),
    .v25_reset_n         (main_v25_reset_n),
    .wram_scan_addr      (13'd0),
    .wram_scan_dout      (),
    .hs_ram_owned        (hs_ram_owned),
    .hs_ram_addr         (hs_ram_addr),
    .hs_ram_we           (hs_ram_we),
    .hs_ram_data         (hs_ram_data),
    .hs_ram_q            (hs_ram_q),
    .wram_cpu_we         (main_wram_we),
    .palette_scan_addr   (palette_snapshot_addr),
    .palette_scan_dout   (palette_snapshot_data),
    .gp0_scan_addr       (gp0_snapshot_addr),
    .gp0_scan_dout       (gp0_snapshot_data),
    .gp1_scan_addr       (gp1_snapshot_addr),
    .gp1_scan_dout       (gp1_snapshot_data),
    .gp_obj_buf_start    (main_obj_buf_start),
    .gp0_obj_scan_addr   (video_gp0_object_addr),
    .gp0_obj_scan_dout   (main_gp0_object_data),
    .gp1_obj_scan_addr   (video_gp1_object_addr),
    .gp1_obj_scan_dout   (main_gp1_object_data),
    .gp0_obj_buf_busy    (main_gp0_obj_buf_busy),
    .gp1_obj_buf_busy    (main_gp1_obj_buf_busy),
    .gp0_obj_buf_miss    (),
    .gp1_obj_buf_miss    (),
    .gp0_scrolls         (main_gp0_scrolls),
    .gp1_scrolls         (main_gp1_scrolls),
    .gp0_scroll_flip     (main_gp0_scroll_flip),
    .gp1_scroll_flip     (main_gp1_scroll_flip),
    .cpu_cen             (main_cpu_cen),
    .cpu_cenb            (main_cpu_cenb),
    .cpu_bus_active      (main_cpu_bus_active),
    .cpu_rw              (main_cpu_rw),
    .cpu_addr_debug      (main_cpu_addr),
    .cpu_dout_debug      (main_cpu_dout),
    .cpu_din_debug       (main_cpu_din),
    .irq4                (main_irq4),
    .gp0_ptr             (main_gp0_ptr),
    .gp1_ptr             (main_gp1_ptr),
    .last_program_fetch  (main_last_program_fetch),
    .bus_count           (main_bus_count),
    .rom_read_count      (main_rom_read_count),
    .wram_write_count    (main_wram_write_count),
    .shared_write_count  (main_shared_write_count),
    .gp_access_count     (main_gp_access_count),
    .palette_write_count (main_palette_write_count),
    .io_access_count     (main_io_access_count),
    .unmapped_count      (main_unmapped_count),
    .irq_count           (main_irq_count),
    .iack_count          (main_iack_count),
    .debug_events        (main_debug_events),
    .ss_irq              (ss_irq),
    .ss_override         (ss_override),
    .ss_reset            (ss_reset),
    .ss_cpu_run          (ss_cpu_run && hs_cpu_run),
    .ss_hold             (ss_device_hold),
    .ss_restore_enable   (ss_restore_compatible),
    .ss_restore_commit   (ss_restore_commit),
    .ss_restore_irq4     (ss_restore_irq4),
    .ss_restore_coin_control(ss_restore_coin_control),
    .ss_reset_vector     (ss_cpu_reset_vector),
    .cpu_ack_debug       (main_cpu_ack),
    .cpu_iack_debug      (main_cpu_iack),
    .cpu_lds_n_debug     (main_cpu_lds_n),
    .cpu_fc_debug        (main_cpu_fc),
    .gp_idle             (main_gp_idle),
    .ss_data             (ss_data),
    .ss_addr             (ss_addr),
    .ss_select           (ss_select),
    .ss_write            (ss_write),
    .ss_read             (ss_read),
    .ss_query            (ss_query),
    .ss_data_out         (main_ss_data_out),
    .ss_ack              (main_ss_ack)
);

dogyuun_sound u_sound (
    .reset               (sound_reset),
    .clk                 (clk),
    .v25_enable          (main_v25_reset_n),
    .state_hold          (ss_sound_hold),
    .ss_restore_enable   (ss_restore_compatible),
    .ss_restore_commit   (ss_restore_commit),
    .ss_data             (ss_data),
    .ss_addr             (ss_addr),
    .ss_select           (ss_select),
    .ss_write            (ss_write),
    .ss_read             (ss_read),
    .ss_query            (ss_query),
    .ss_data_out         (sound_ss_data_out),
    .ss_ack              (sound_ss_ack),
    .dip_a               (dipsw[7:0]),
    .dip_b               (dipsw[15:8]),
    .region              (dipsw[23:16]),
    .ym_enable           (snd_en[0]),
    .oki_enable          (snd_en[1]),
    .pause               (!dip_pause),
    .shared_addr         (sound_shared_addr),
    .shared_dout         (sound_shared_dout),
    .shared_we           (sound_shared_we),
    .shared_din          (sound_shared_din),
    .oki_rom_addr        (sound_oki_rom_addr),
    .oki_rom_data        (sound_oki_rom_data),
    .oki_rom_ok          (sound_oki_rom_ok),
    .snd_mono            (sound_mono),
    .sample              (sound_sample),
    .debug_fault         (sound_debug_fault),
    .debug_halted        (sound_debug_halted),
    .debug_pc            (sound_debug_pc),
    .debug_state_idle    (sound_debug_state_idle),
    .debug_v25_reset_n   (sound_debug_v25_reset_n),
    .debug_ym_write      (sound_debug_ym_write),
    .debug_ym_a0         (sound_debug_ym_a0),
    .debug_ym_data       (sound_debug_ym_data),
    .debug_oki_write     (sound_debug_oki_write),
    .debug_oki_data      (sound_debug_oki_data),
    .debug_v25_cen       (),
    .debug_ym_cen        (),
    .debug_ym_cen_p1     (),
    .debug_oki_cen       (sound_debug_oki_cen),
    .debug_oki_status    (sound_debug_oki_status),
    .debug_oki_sound     (sound_debug_oki_sound),
    .state_idle          (sound_state_idle),
    .state_held          (sound_state_held)
);

jtframe_rom_1slot #(
    .SDRAMW        (AW),
    .SLOT0_DW      (16),
    .SLOT0_AW      (18),
    .SLOT0_LATCH   (0),
    .SLOT0_OKLATCH (0),
    .SLOT0_OFFSET  ({AW{1'b0}})
) u_main_rom (
    .rst        (main_reset),
    .clk        (clk),
    .slot0_addr (main_rom_addr),
    .slot0_dout (main_rom_data),
    .slot0_cs   (main_rom_cs),
    .slot0_ok   (main_rom_ok),
    .sdram_ack  (ba_ack[0]),
    .sdram_rd   (main_rom_rd),
    .sdram_addr (ba0_addr),
    .data_dst   (ba_dst[0]),
    .data_rdy   (ba_rdy[0]),
    .data_read  (data_read)
);

dogyuun_gp9001_snapshot u_gp0_snapshot (
    .clk                 (clk),
    .rst                 (video_reset),
    .snapshot_start      (main_obj_buf_start),
    .source_addr         (gp0_snapshot_addr),
    .source_data         (gp0_snapshot_data),
    .source_scrolls      (main_gp0_scrolls),
    .source_scroll_flip  (main_gp0_scroll_flip),
    .display_addr        (video_gp0_vram_addr),
    .display_data        (video_gp0_vram_data),
    .object_addr         (video_gp0_object_addr),
    .object_data         (video_gp0_object_data),
    .display_scrolls     (video_gp0_scrolls),
    .display_scroll_flip (video_gp0_scroll_flip),
    .copy_busy           (),
    .copy_miss           ()
);

dogyuun_gp9001_snapshot u_gp1_snapshot (
    .clk                 (clk),
    .rst                 (video_reset),
    .snapshot_start      (main_obj_buf_start),
    .source_addr         (gp1_snapshot_addr),
    .source_data         (gp1_snapshot_data),
    .source_scrolls      (main_gp1_scrolls),
    .source_scroll_flip  (main_gp1_scroll_flip),
    .display_addr        (video_gp1_vram_addr),
    .display_data        (video_gp1_vram_data),
    .object_addr         (video_gp1_object_addr),
    .object_data         (video_gp1_object_data),
    .display_scrolls     (video_gp1_scrolls),
    .display_scroll_flip (video_gp1_scroll_flip),
    .copy_busy           (),
    .copy_miss           ()
);

dogyuun_gp9001_video u_video (
    .clk                 (clk),
    .rst                 (video_reset),
    .line_start          (video_line_start),
    .line_commit         (video_line_commit),
    .target_y            (video_target_y),
    .target_epoch        (video_target_epoch),
    .display_x           (hcnt[8:0]),
    .display_y           (vcnt),
    .display_epoch       (video_epoch),
    .gp0_scrolls         (video_gp0_scrolls),
    .gp1_scrolls         (video_gp1_scrolls),
    .gp0_scroll_flip     (video_gp0_scroll_flip),
    .gp1_scroll_flip     (video_gp1_scroll_flip),
    .gp0_vram_addr       (video_gp0_vram_addr),
    .gp0_vram_data       (video_gp0_vram_data),
    .gp1_vram_addr       (video_gp1_vram_addr),
    .gp1_vram_data       (video_gp1_vram_data),
    .gp0_object_addr     (video_gp0_object_addr),
    .gp0_object_data     (video_gp0_object_data),
    .gp1_object_addr     (video_gp1_object_addr),
    .gp1_object_data     (video_gp1_object_data),
    .gp0_tile_gfx_req    (video_gp0_tile_req),
    .gp0_tile_gfx_addr   (video_gp0_tile_addr),
    .gp0_tile_gfx_data   (video_gp0_tile_data),
    .gp0_tile_gfx_ok     (video_gp0_tile_ok),
    .gp0_object_gfx_req  (video_gp0_object_req),
    .gp0_object_gfx_addr (video_gp0_object_gfx_addr),
    .gp0_object_gfx_data (video_gp0_object_gfx_data),
    .gp0_object_gfx_ok   (video_gp0_object_ok),
    .gp1_tile_gfx_req    (video_gp1_tile_req),
    .gp1_tile_gfx_addr   (video_gp1_tile_addr),
    .gp1_tile_gfx_data   (video_gp1_tile_data),
    .gp1_tile_gfx_ok     (video_gp1_tile_ok),
    .gp1_object_gfx_req  (video_gp1_object_req),
    .gp1_object_gfx_addr (video_gp1_object_gfx_addr),
    .gp1_object_gfx_data (video_gp1_object_gfx_data),
    .gp1_object_gfx_ok   (video_gp1_object_ok),
    .line_ready          (video_line_ready),
    .gp0_color           (video_gp0_color),
    .gp1_color           (video_gp1_color),
    .final_color         (video_palette_addr),
    .engine_busy         (video_engine_busy),
    .deadline_miss       (video_deadline_miss),
    .gp0_tile_cycles     (video_gp0_tile_cycles),
    .gp0_object_cycles   (video_gp0_object_cycles),
    .gp1_tile_cycles     (video_gp1_tile_cycles),
    .gp1_object_cycles   (video_gp1_object_cycles),
    .debug_gp0_tile_y    (video_debug_gp0_tile_y),
    .debug_gp0_object_y  (video_debug_gp0_object_y),
    .debug_gp1_tile_y    (video_debug_gp1_tile_y),
    .debug_gp1_object_y  (video_debug_gp1_object_y),
    .debug_line_epoch    (video_debug_line_epoch),
    .debug_line_valid    (video_debug_line_valid)
);

dogyuun_palette_snapshot u_palette_snapshot (
    .clk            (clk),
    .rst            (video_reset),
    .snapshot_start (main_obj_buf_start),
    .source_addr    (palette_snapshot_addr),
    .source_data    (palette_snapshot_data),
    .display_addr   (video_palette_addr),
    .display_data   (video_palette_data)
);

`ifdef DOGYUUN_HW_DEBUG
dogyuun_hw_debug #(.AW(AW)) u_hw_debug (
    .clk                    (clk),
    .rst                    (main_reset),
    .cold_rst               (cold_rst),
    .ioctl_rom              (ioctl_rom),
    .dwnld_busy             (dwnld_busy),
    .prog_we                (prog_we),
    .prog_rdy               (prog_rdy),
    .prog_ack               (prog_ack),
    .loader_accepted        (loader_accepted),
    .frame_tick             (video_line_event && (vcnt == V_TOTAL - 1'b1)),
    .pixel_tick             (clkdiv == 4'd13),
    .object_swap            (main_obj_buf_start),
    .line_start             (video_line_start),
    .line_commit            (video_line_commit),
    .clkdiv                 (clkdiv),
    .hcnt                   (hcnt),
    .vcnt                   (vcnt),
    .video_epoch            (video_epoch),
    .video_target_y         (video_target_y),
    .video_target_epoch     (video_target_epoch),
    .video_line_ready       (video_line_ready),
    .video_engine_busy      (video_engine_busy),
    .video_deadline_miss    (video_deadline_miss),
    .video_deadline_latched (video_deadline_latched),
    .gp0_tile_cycles        (video_gp0_tile_cycles),
    .gp0_object_cycles      (video_gp0_object_cycles),
    .gp1_tile_cycles        (video_gp1_tile_cycles),
    .gp1_object_cycles      (video_gp1_object_cycles),
    .gp0_tile_y             (video_debug_gp0_tile_y),
    .gp0_object_y           (video_debug_gp0_object_y),
    .gp1_tile_y             (video_debug_gp1_tile_y),
    .gp1_object_y           (video_debug_gp1_object_y),
    .line_epoch             (video_debug_line_epoch),
    .line_valid             (video_debug_line_valid),
    .gp0_tile_gfx_logical_addr   (video_gp0_tile_addr),
    .gp0_tile_gfx_physical_addr  (video_gp0_tile_physical_addr),
    .gp0_tile_gfx_data           (video_gp0_tile_data),
    .gp0_tile_gfx_req            (video_gp0_tile_req),
    .gp0_tile_gfx_ok             (video_gp0_tile_ok),
    .gp0_object_gfx_logical_addr (video_gp0_object_gfx_addr),
    .gp0_object_gfx_physical_addr(video_gp0_object_physical_addr),
    .gp0_object_gfx_data         (video_gp0_object_gfx_data),
    .gp0_object_gfx_req          (video_gp0_object_req),
    .gp0_object_gfx_ok           (video_gp0_object_ok),
    .gp1_tile_gfx_logical_addr   (video_gp1_tile_addr),
    .gp1_tile_gfx_physical_addr  (video_gp1_tile_physical_addr),
    .gp1_tile_gfx_data           (video_gp1_tile_data),
    .gp1_tile_gfx_req            (video_gp1_tile_req),
    .gp1_tile_gfx_ok             (video_gp1_tile_ok),
    .gp1_object_gfx_logical_addr (video_gp1_object_gfx_addr),
    .gp1_object_gfx_physical_addr(video_gp1_object_physical_addr),
    .gp1_object_gfx_data         (video_gp1_object_gfx_data),
    .gp1_object_gfx_req          (video_gp1_object_req),
    .gp1_object_gfx_ok           (video_gp1_object_ok),
    .main_cpu_cen           (main_cpu_cen),
    .main_cpu_cenb          (main_cpu_cenb),
    .main_cpu_bus_active    (main_cpu_bus_active),
    .main_cpu_rw            (main_cpu_rw),
    .main_cpu_addr          (main_cpu_addr),
    .main_cpu_dout          (main_cpu_dout),
    .main_cpu_din           (main_cpu_din),
    .main_irq4              (main_irq4),
    .main_gp0_ptr           (main_gp0_ptr),
    .main_gp1_ptr           (main_gp1_ptr),
    .main_last_fetch        (main_last_program_fetch),
    .main_bus_count         (main_bus_count),
    .main_rom_count         (main_rom_read_count),
    .main_wram_count        (main_wram_write_count),
    .main_shared_count      (main_shared_write_count),
    .main_gp_count          (main_gp_access_count),
    .main_palette_count     (main_palette_write_count),
    .main_io_count          (main_io_access_count),
    .main_unmapped_count    (main_unmapped_count),
    .main_irq_count         (main_irq_count),
    .main_iack_count        (main_iack_count),
    .main_debug_events      (main_debug_events),
    .main_coin_control      (main_coin_control),
    .main_v25_reset_n       (main_v25_reset_n),
    .sound_fault            (sound_debug_fault),
    .sound_halted           (sound_debug_halted),
    .sound_pc               (sound_debug_pc),
    .sound_idle             (sound_debug_state_idle),
    .sound_v25_reset_n      (sound_debug_v25_reset_n),
    .sound_ym_write         (sound_debug_ym_write),
    .sound_ym_a0            (sound_debug_ym_a0),
    .sound_ym_data          (sound_debug_ym_data),
    .sound_oki_write        (sound_debug_oki_write),
    .sound_oki_data         (sound_debug_oki_data),
    .sound_oki_cen          (sound_debug_oki_cen),
    .sound_oki_status       (sound_debug_oki_status),
    .sound_shared_addr      (sound_shared_addr),
    .sound_shared_dout      (sound_shared_dout),
    .sound_shared_we        (sound_shared_we),
    .ba0_addr               (ba0_addr),
    .ba1_addr               (ba1_addr),
    .ba2_addr               (ba2_addr),
    .ba3_addr               (ba3_addr),
    .ba_rd                  (ba_rd),
    .ba_ack                 (ba_ack),
    .ba_rdy                 (ba_rdy),
    .ba_dst                 (ba_dst),
    .loader_range_error     (loader_range_error),
    .loader_overflow_error  (loader_overflow_error)
);
`endif

jtframe_rom_2slots #(
    .SDRAMW        (AW),
    .SLOT0_DW      (16),
    .SLOT1_DW      (16),
    .SLOT0_AW      (22),
    .SLOT1_AW      (22),
    .SLOT0_LATCH   (0),
    .SLOT1_LATCH   (0),
    .SLOT0_OKLATCH (0),
    .SLOT1_OKLATCH (0)
) u_gp0_rom (
    .rst        (video_reset),
    .clk        (clk),
    .slot0_addr (video_gp0_tile_physical_addr),
    .slot1_addr (video_gp0_object_physical_addr),
    .slot0_dout (video_gp0_tile_data),
    .slot1_dout (video_gp0_object_gfx_data),
    .slot0_cs   (video_gp0_tile_req),
    .slot1_cs   (video_gp0_object_req),
    .slot0_ok   (video_gp0_tile_ok),
    .slot1_ok   (video_gp0_object_ok),
    .sdram_ack  (ba_ack[1]),
    .sdram_rd   (video_gp0_rom_rd),
    .sdram_addr (ba1_addr),
    .data_dst   (ba_dst[1]),
    .data_rdy   (ba_rdy[1]),
    .data_read  (data_read)
);

jtframe_rom_2slots #(
    .SDRAMW        (AW),
    .SLOT0_DW      (16),
    .SLOT1_DW      (16),
    .SLOT0_AW      (22),
    .SLOT1_AW      (22),
    .SLOT0_LATCH   (0),
    .SLOT1_LATCH   (0),
    .SLOT0_OKLATCH (0),
    .SLOT1_OKLATCH (0)
) u_gp1_rom (
    .rst        (video_reset),
    .clk        (clk),
    .slot0_addr (video_gp1_tile_physical_addr),
    .slot1_addr (video_gp1_object_physical_addr),
    .slot0_dout (video_gp1_tile_data),
    .slot1_dout (video_gp1_object_gfx_data),
    .slot0_cs   (video_gp1_tile_req),
    .slot1_cs   (video_gp1_object_req),
    .slot0_ok   (video_gp1_tile_ok),
    .slot1_ok   (video_gp1_object_ok),
    .sdram_ack  (ba_ack[2]),
    .sdram_rd   (video_gp1_rom_rd),
    .sdram_addr (ba2_addr),
    .data_dst   (ba_dst[2]),
    .data_rdy   (ba_rdy[2]),
    .data_read  (data_read)
);

jtframe_rom_1slot #(
    .SDRAMW        (AW),
    .SLOT0_DW      (8),
    .SLOT0_AW      (18),
    .SLOT0_LATCH   (0),
    .SLOT0_OKLATCH (0),
    .SLOT0_OFFSET  ({AW{1'b0}})
) u_oki_rom (
    .rst        (sound_reset),
    .clk        (clk),
    .slot0_addr (sound_oki_rom_addr),
    .slot0_dout (sound_oki_rom_data),
    .slot0_cs   (1'b1),
    .slot0_ok   (sound_oki_rom_ok),
    .sdram_ack  (ba_ack[3]),
    .sdram_rd   (sound_oki_rom_rd),
    .sdram_addr (sound_oki_sdram_addr),
    .data_dst   (ba_dst[3]),
    .data_rdy   (ba_rdy[3]),
    .data_read  (data_read)
);

// Assert with the board reset and release in this clock domain. This keeps
// the sound cores' reset fanout off their active arithmetic paths.
always @(posedge clk or posedge sound_reset_request) begin
    if (sound_reset_request)
        sound_reset_pipe <= 2'b11;
    else
        sound_reset_pipe <= {sound_reset_pipe[0], 1'b0};
end

// Keep the renderer's high-fanout reset tree local. Assertion remains
// asynchronous; release is synchronized before any line build can begin.
always @(posedge clk or posedge video_reset_request) begin
    if (video_reset_request)
        video_reset_pipe <= 2'b11;
    else
        video_reset_pipe <= {video_reset_pipe[0], 1'b0};
end

// The board reset sequencer advances on pxl_cen, so this divider must keep
// running while the game reset is asserted. Only the cold reset may stop it.
always @(posedge clk) begin
    if (cold_rst) begin
        clkdiv   <= 4'd0;
        pxl2_cen <= 1'b0;
        pxl_cen  <= 1'b0;
    end else begin
        pxl2_cen <= (clkdiv == 4'd6) || (clkdiv == 4'd13);
        pxl_cen  <= clkdiv == 4'd13;

        if (clkdiv == 4'd13)
            clkdiv <= 4'd0;
        else
            clkdiv <= clkdiv + 1'b1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        hcnt    <= 10'd0;
        vcnt    <= 9'd0;
        video_epoch <= 1'b0;
        video_deadline_latched <= 4'd0;
        red     <= 8'h00;
        green   <= 8'h00;
        blue    <= 8'h00;
        LHBL    <= 1'b0;
        LVBL    <= 1'b0;
        HS      <= 1'b1;
        VS      <= 1'b1;
    end else begin
        video_deadline_latched <= video_deadline_latched |
                                  video_deadline_miss;

        if (clkdiv == 4'd13) begin
            LHBL <= hcnt < 10'd320;
            LVBL <= vcnt < 9'd240;
            HS <= !((hcnt >= 10'd340) && (hcnt < 10'd376));
            VS <= !((vcnt >= 9'd244) && (vcnt < 9'd248));

            if (dwnld_busy || (hcnt >= 10'd320) || (vcnt >= 9'd240)) begin
                red   <= 8'h00;
                green <= 8'h00;
                blue  <= 8'h00;
            end else if (!video_line_ready) begin
                red   <= 8'h00;
                green <= 8'h00;
                blue  <= 8'h00;
            end else begin
                red   <= {video_palette_data[4:0], video_palette_data[4:2]};
                green <= {video_palette_data[9:5], video_palette_data[9:7]};
                blue  <= {video_palette_data[14:10], video_palette_data[14:12]};
            end

            if (hcnt == H_TOTAL - 1'b1) begin
                hcnt <= 10'd0;
                if (vcnt == V_TOTAL - 1'b1)
                begin
                    vcnt <= 9'd0;
                    video_epoch <= ~video_epoch;
                end
                else
                    vcnt <= vcnt + 1'b1;
            end else begin
                hcnt <= hcnt + 1'b1;
            end
        end
    end
end

endmodule
