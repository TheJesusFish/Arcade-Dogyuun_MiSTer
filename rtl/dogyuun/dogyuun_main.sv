// Dogyuun MC68000 subsystem: exact clock enable, board map, local memories,
// GP9001 CPU ports, VDP status, IRQ4, and the V25 release latch.
module dogyuun_main #(
    parameter integer CPU_FIXED_WAIT = 0
) (
    input              clk,
    input              rst,
    input              halt_n,

    output             rom_cs,
    output     [17:0]  rom_addr,
    input      [15:0]  rom_data,
    input              rom_ok,

    input      [15:0]  in1_data,
    input      [15:0]  in2_data,
    input      [15:0]  sys_data,
    input      [9:0]   hcnt,
    input      [8:0]   vcnt,
    input              irq4_start,

    input              sound_clk,
    input      [14:0]  sound_shared_addr,
    input      [7:0]   sound_shared_din,
    input              sound_shared_we,
    output     [7:0]   sound_shared_dout,
    output reg [7:0]   coin_control,
    output             v25_reset_n,

    input      [12:0]  wram_scan_addr,
    output     [15:0]  wram_scan_dout,
    input              hs_ram_owned,
    input      [12:0]  hs_ram_addr,
    input      [1:0]   hs_ram_we,
    input      [15:0]  hs_ram_data,
    output     [15:0]  hs_ram_q,
    output     [1:0]   wram_cpu_we,
    input      [10:0]  palette_scan_addr,
    output     [15:0]  palette_scan_dout,
    input      [12:0]  gp0_scan_addr,
    output     [15:0]  gp0_scan_dout,
    input      [12:0]  gp1_scan_addr,
    output     [15:0]  gp1_scan_dout,
    input              gp_obj_buf_start,
    input      [9:0]   gp0_obj_scan_addr,
    output     [15:0]  gp0_obj_scan_dout,
    input      [9:0]   gp1_obj_scan_addr,
    output     [15:0]  gp1_obj_scan_dout,
    output             gp0_obj_buf_busy,
    output             gp1_obj_buf_busy,
    output             gp0_obj_buf_miss,
    output             gp1_obj_buf_miss,
    output     [127:0] gp0_scrolls,
    output     [127:0] gp1_scrolls,
    output     [7:0]   gp0_scroll_flip,
    output     [7:0]   gp1_scroll_flip,

    output             cpu_cen,
    output             cpu_cenb,
    output             cpu_bus_active,
    output             cpu_rw,
    output     [23:0]  cpu_addr_debug,
    output     [15:0]  cpu_dout_debug,
    output     [15:0]  cpu_din_debug,
    output             irq4,
    output     [12:0]  gp0_ptr,
    output     [12:0]  gp1_ptr,
    output reg [23:0]  last_program_fetch,
    output reg [31:0]  bus_count,
    output reg [31:0]  rom_read_count,
    output reg [31:0]  wram_write_count,
    output reg [31:0]  shared_write_count,
    output reg [31:0]  gp_access_count,
    output reg [31:0]  palette_write_count,
    output reg [31:0]  io_access_count,
    output reg [31:0]  unmapped_count,
    output reg [31:0]  irq_count,
    output reg [31:0]  iack_count,
    output     [15:0]  debug_events,

    input              ss_irq,
    input              ss_override,
    input              ss_reset,
    input              ss_cpu_run,
    input              ss_hold,
    input              ss_restore_enable,
    input              ss_restore_commit,
    input              ss_restore_irq4,
    input      [7:0]   ss_restore_coin_control,
    input      [63:0]  ss_reset_vector,
    output             cpu_ack_debug,
    output             cpu_iack_debug,
    output             cpu_lds_n_debug,
    output     [2:0]   cpu_fc_debug,
    output             gp_idle,

    input      [63:0]  ss_data,
    input      [31:0]  ss_addr,
    input      [7:0]   ss_select,
    input              ss_write,
    input              ss_read,
    input              ss_query,
    output     [63:0]  ss_data_out,
    output             ss_ack
);

wire [23:1] cpu_addr;
wire [23:0] cpu_addr8 = {cpu_addr, 1'b0};
wire [15:0] cpu_dout;
reg  [15:0] cpu_din = 16'hffff;
wire        cpu_as_n;
wire        cpu_lds_n;
wire        cpu_uds_n;
wire        cpu_dtack_n;
wire        cpu_fc0;
wire        cpu_fc1;
wire        cpu_fc2;
wire        cpu_vpa_n = ~&{cpu_fc0, cpu_fc1, cpu_fc2, ~cpu_as_n};
wire        cpu_iack = !cpu_as_n && cpu_fc0 && cpu_fc1 && cpu_fc2;
wire        cpu_program_space = cpu_fc1 && !cpu_fc0;

assign cpu_bus_active = !cpu_as_n && (!cpu_uds_n || !cpu_lds_n);
wire cpu_read = cpu_bus_active && cpu_rw;
wire cpu_write = cpu_bus_active && !cpu_rw;
wire ss_handler_cs = ss_override && cpu_bus_active &&
                     (cpu_addr8[23:8] == 16'hff00);
wire ss_reset_vector_cs = ss_override && cpu_bus_active &&
                          (cpu_addr8 < 24'h000008);
wire ss_irq_vector_cs = ss_override && cpu_bus_active &&
                        ((cpu_addr8 == 24'h00007c) ||
                         (cpu_addr8 == 24'h00007e));
wire ss_special_cs = ss_handler_cs ||
                     ss_reset_vector_cs ||
                     ss_irq_vector_cs;
wire cpu_core_reset = rst || ss_reset;

function automatic [15:0] ss_irq_handler_word;
    input [3:0] index;
    begin
        case (index)
            4'h0: ss_irq_handler_word = 16'h48e7;
            4'h1: ss_irq_handler_word = 16'hfffe;
            4'h2: ss_irq_handler_word = 16'h4e6e;
            4'h3: ss_irq_handler_word = 16'h2f0e;
            4'h4: ss_irq_handler_word = 16'h4df9;
            4'h5: ss_irq_handler_word = 16'h00ff;
            4'h6: ss_irq_handler_word = 16'h0000;
            4'h7: ss_irq_handler_word = 16'h2c8f;
            4'h8: ss_irq_handler_word = 16'h2c5f;
            4'h9: ss_irq_handler_word = 16'h4e66;
            4'ha: ss_irq_handler_word = 16'h4cdf;
            4'hb: ss_irq_handler_word = 16'h7fff;
            4'hc: ss_irq_handler_word = 16'h4e73;
            default: ss_irq_handler_word = 16'h0000;
        endcase
    end
endfunction

function automatic [15:0] ss_reset_vector_word;
    input [1:0] index;
    begin
        case (index)
            2'd0: ss_reset_vector_word = ss_reset_vector[63:48];
            2'd1: ss_reset_vector_word = ss_reset_vector[47:32];
            2'd2: ss_reset_vector_word = ss_reset_vector[31:16];
            default: ss_reset_vector_word = ss_reset_vector[15:0];
        endcase
    end
endfunction

wire rom_bus_cs;
wire rom_read_cs;
wire wram_cs;
wire in1_cs;
wire in2_cs;
wire sys_cs;
wire sound_ctrl_cs;
wire shared_cs;
wire gp0_cs;
wire palette_cs;
wire gp1_cs;
wire vcount_cs;
wire io_cs;
wire gp_cs;
wire mapped_cs;
wire unmapped_cs;

dogyuun_main_decode u_decode (
    .addr          (cpu_addr8),
    .bus_active    (cpu_bus_active),
    .rw            (cpu_rw),
    .rom_cs        (rom_bus_cs),
    .rom_read_cs   (rom_read_cs),
    .wram_cs       (wram_cs),
    .in1_cs        (in1_cs),
    .in2_cs        (in2_cs),
    .sys_cs        (sys_cs),
    .sound_ctrl_cs (sound_ctrl_cs),
    .shared_cs     (shared_cs),
    .gp0_cs        (gp0_cs),
    .palette_cs    (palette_cs),
    .gp1_cs        (gp1_cs),
    .vcount_cs     (vcount_cs),
    .io_cs         (io_cs),
    .gp_cs         (gp_cs),
    .mapped_cs     (mapped_cs),
    .unmapped_cs   (unmapped_cs)
);

wire normal_rom_read_cs = rom_read_cs && !ss_special_cs;
assign rom_cs = normal_rom_read_cs;
assign rom_addr = cpu_addr8[18:1];

reg gp_bus_started = 1'b0;
reg gp_bus_done = 1'b0;
wire gp_start = gp_cs && !ss_hold &&
                !gp_bus_started && !gp_bus_done;
wire gp0_start = gp_start && gp0_cs;
wire gp1_start = gp_start && gp1_cs;
wire gp0_busy;
wire gp1_busy;
wire gp0_done;
wire gp1_done;
wire [15:0] gp0_dout;
wire [15:0] gp1_dout;
wire gp0_irq_clear;
wire gp1_irq_clear;
wire gp0_vram_write;
wire gp1_vram_write;
wire gp0_scroll_write;
wire gp1_scroll_write;
wire [7:0] gp0_scroll_select;
wire [7:0] gp1_scroll_select;
wire [63:0] ss_wram_data_out;
wire [63:0] ss_shared_data_out;
wire [63:0] ss_palette_data_out;
wire [63:0] ss_gp0_data_out;
wire [63:0] ss_gp1_data_out;
wire        ss_wram_ack;
wire        ss_shared_ack;
wire        ss_palette_ack;
wire        ss_gp0_ack;
wire        ss_gp1_ack;
wire gp_wait = gp_cs && !gp_bus_done;
wire [1:0] gp_we_mask = {!cpu_uds_n, !cpu_lds_n};

wire [9:0] vdp_status_sum = {1'b0, vcnt} + 10'd15;
wire [9:0] vdp_status_v = (vdp_status_sum >= 10'd262) ?
                          vdp_status_sum - 10'd262 : vdp_status_sum;
wire vdp_hsync_n = ~((hcnt > 10'd325) && (hcnt < 10'd380));
wire vdp_vsync_n = ~((vcnt >= 9'd232) && (vcnt <= 9'd245));
wire vdp_fblank_n = vdp_hsync_n && vdp_vsync_n;
wire [15:0] vdp_count_flags = 16'hff00 &
                              (vdp_hsync_n ? 16'hffff : 16'h7fff) &
                              (vdp_vsync_n ? 16'hffff : 16'hbfff) &
                              (vdp_fblank_n ? 16'hffff : 16'hfeff);
wire [15:0] vcount_data = vdp_count_flags |
    ((vdp_status_v < 10'd256) ? {8'h00, vdp_status_v[7:0]} : 16'h00ff);
wire gp_status = vdp_status_v >= 10'd245;

dogyuun_gp9001_cpu #(
    .SS_RAM_IDX  (8'd5),
    .SS_REG_IDX  (8'd7),
    .SS_OBJ0_IDX (8'd9),
    .SS_OBJ1_IDX (8'd10)
) u_gp0 (
    .clk               (clk),
    .rst               (rst),
    .start             (gp0_start),
    .rw                (cpu_rw),
    .addr              (cpu_addr8[3:0]),
    .din               (cpu_dout),
    .we_mask           (gp_we_mask),
    .status_bit        (gp_status),
    .busy              (gp0_busy),
    .done              (gp0_done),
    .dout              (gp0_dout),
    .irq_clear         (gp0_irq_clear),
    .scan_addr         (gp0_scan_addr),
    .scan_dout         (gp0_scan_dout),
    .obj_buf_start     (gp_obj_buf_start),
    .obj_scan_addr     (gp0_obj_scan_addr),
    .obj_scan_dout     (gp0_obj_scan_dout),
    .obj_buf_busy      (gp0_obj_buf_busy),
    .obj_buf_miss      (gp0_obj_buf_miss),
    .dbg_ptr           (gp0_ptr),
    .dbg_scroll_select (gp0_scroll_select),
    .scrolls           (gp0_scrolls),
    .scroll_flip       (gp0_scroll_flip),
    .vram_write        (gp0_vram_write),
    .scroll_write      (gp0_scroll_write),
    .ss_hold           (ss_hold),
    .ss_restore_enable (ss_restore_enable),
    .ss_data           (ss_data),
    .ss_addr           (ss_addr),
    .ss_select         (ss_select),
    .ss_write          (ss_write),
    .ss_read           (ss_read),
    .ss_query          (ss_query),
    .ss_data_out       (ss_gp0_data_out),
    .ss_ack            (ss_gp0_ack)
);

dogyuun_gp9001_cpu #(
    .SS_RAM_IDX  (8'd6),
    .SS_REG_IDX  (8'd8),
    .SS_OBJ0_IDX (8'd11),
    .SS_OBJ1_IDX (8'd12)
) u_gp1 (
    .clk               (clk),
    .rst               (rst),
    .start             (gp1_start),
    .rw                (cpu_rw),
    .addr              (cpu_addr8[3:0]),
    .din               (cpu_dout),
    .we_mask           (gp_we_mask),
    .status_bit        (gp_status),
    .busy              (gp1_busy),
    .done              (gp1_done),
    .dout              (gp1_dout),
    .irq_clear         (gp1_irq_clear),
    .scan_addr         (gp1_scan_addr),
    .scan_dout         (gp1_scan_dout),
    .obj_buf_start     (gp_obj_buf_start),
    .obj_scan_addr     (gp1_obj_scan_addr),
    .obj_scan_dout     (gp1_obj_scan_dout),
    .obj_buf_busy      (gp1_obj_buf_busy),
    .obj_buf_miss      (gp1_obj_buf_miss),
    .dbg_ptr           (gp1_ptr),
    .dbg_scroll_select (gp1_scroll_select),
    .scrolls           (gp1_scrolls),
    .scroll_flip       (gp1_scroll_flip),
    .vram_write        (gp1_vram_write),
    .scroll_write      (gp1_scroll_write),
    .ss_hold           (ss_hold),
    .ss_restore_enable (ss_restore_enable),
    .ss_data           (ss_data),
    .ss_addr           (ss_addr),
    .ss_select         (ss_select),
    .ss_write          (ss_write),
    .ss_read           (ss_read),
    .ss_query          (ss_query),
    .ss_data_out       (ss_gp1_data_out),
    .ss_ack            (ss_gp1_ack)
);

always @(posedge clk) begin
    if (cpu_core_reset || !cpu_bus_active || !gp_cs) begin
        gp_bus_started <= 1'b0;
        gp_bus_done <= 1'b0;
    end else begin
        if (gp_start)
            gp_bus_started <= 1'b1;
        if (gp0_done || gp1_done)
            gp_bus_done <= 1'b1;
    end
end

assign gp_idle = !gp0_busy && !gp1_busy &&
                 !gp0_obj_buf_busy && !gp1_obj_buf_busy;

wire cpu_bus_busy = (normal_rom_read_cs && !rom_ok) || gp_wait;
wire [15:0] cpu_fave;
wire [15:0] cpu_fworst;

jtframe_68kdtack_cen #(
    .W(8),
    .MFREQ(94500),
    .WAIT1(CPU_FIXED_WAIT)
) u_cpu_dtack (
    .rst       (cpu_core_reset),
    .clk       (clk),
    .cpu_cen   (cpu_cen),
    .cpu_cenb  (cpu_cenb),
    .bus_cs    (cpu_bus_active),
    .bus_busy  (cpu_bus_busy),
    .bus_legit (1'b0),
    .bus_ack   (1'b0),
    .ASn       (cpu_as_n),
    .DSn       ({cpu_uds_n, cpu_lds_n}),
    .num       (7'd25),
    .den       (8'd189),
    .wait2     (1'b0),
    .wait3     (1'b0),
    .DTACKn    (cpu_dtack_n),
    .fave      (cpu_fave),
    .fworst    (cpu_fworst)
);

fx68k u_main68k (
    .clk      (clk),
    .HALTn    (halt_n),
    .extReset (cpu_core_reset),
    .pwrUp    (cpu_core_reset),
    .enPhi1   (cpu_cen && ss_cpu_run),
    .enPhi2   (cpu_cenb && ss_cpu_run),
    .eRWn     (cpu_rw),
    .ASn      (cpu_as_n),
    .LDSn     (cpu_lds_n),
    .UDSn     (cpu_uds_n),
    .E        (),
    .VMAn     (),
    .FC0      (cpu_fc0),
    .FC1      (cpu_fc1),
    .FC2      (cpu_fc2),
    .BGn      (),
    .oRESETn  (),
    .oHALTEDn (),
    .DTACKn   (cpu_dtack_n),
    .VPAn     (cpu_vpa_n),
    .BERRn    (1'b1),
    .BRn      (1'b1),
    .BGACKn   (1'b1),
    .IPL0n    (~ss_irq),
    .IPL1n    (~ss_irq),
    .IPL2n    (~(ss_irq || irq4)),
    .iEdb     (cpu_din),
    .oEdb     (cpu_dout),
    .eab      (cpu_addr)
);

reg ack_seen = 1'b0;
wire ack_now = cpu_bus_active && !cpu_dtack_n && !ack_seen;
assign cpu_ack_debug = ack_now;
assign cpu_iack_debug = cpu_iack;
assign cpu_lds_n_debug = cpu_lds_n;
assign cpu_fc_debug = {cpu_fc2, cpu_fc1, cpu_fc0};
wire [1:0] wram_we = {
    ack_now && wram_cs && cpu_write && !cpu_uds_n,
    ack_now && wram_cs && cpu_write && !cpu_lds_n
};
assign wram_cpu_we = wram_we;
wire shared_we = ack_now && shared_cs && cpu_write && !cpu_lds_n;
wire [1:0] palette_we = {
    ack_now && palette_cs && cpu_write && !cpu_uds_n,
    ack_now && palette_cs && cpu_write && !cpu_lds_n
};

assign debug_events = {
    gp1_scroll_write,
    gp0_scroll_write,
    gp1_vram_write,
    gp0_vram_write,
    gp_obj_buf_start,
    irq4_start,
    ack_now && cpu_iack,
    ack_now && unmapped_cs && !ss_special_cs,
    ack_now && io_cs,
    |palette_we,
    gp1_done,
    gp0_done,
    shared_we,
    ack_now && wram_cs && cpu_write,
    ack_now && normal_rom_read_cs,
    ack_now
};

wire [15:0] wram_dout;
wire [7:0] shared_dout;
wire [15:0] palette_dout;
wire [12:0] ss_wram_addr;
wire [15:0] ss_wram_data;
wire [1:0]  ss_wram_we;

dogyuun_ss_ram_port #(
    .WIDTH        (16),
    .ADDR_WIDTH   (13),
    .WE_WIDTH     (2),
    .SS_IDX       (8'd2),
    .STREAM_WIDTH (2'd1)
) u_wram_ss (
    .clk            (clk),
    .restore_enable (ss_restore_enable),
    .normal_we      (hs_ram_owned ? hs_ram_we : 2'b00),
    .normal_addr    (hs_ram_owned ? hs_ram_addr : wram_scan_addr),
    .normal_data    (hs_ram_data),
    .ram_we         (ss_wram_we),
    .ram_addr       (ss_wram_addr),
    .ram_data       (ss_wram_data),
    .ram_q          (wram_scan_dout),
    .ss_data        (ss_data),
    .ss_addr        (ss_addr),
    .ss_select      (ss_select),
    .ss_write       (ss_write),
    .ss_read        (ss_read),
    .ss_query       (ss_query),
    .ss_data_out    (ss_wram_data_out),
    .ss_ack         (ss_wram_ack)
);

assign hs_ram_q = wram_scan_dout;

jtframe_dual_ram16 #(.AW(13)) u_wram (
    .clk0  (clk),
    .data0 (cpu_dout),
    .addr0 (cpu_addr8[13:1]),
    .we0   (wram_we),
    .q0    (wram_dout),
    .clk1  (clk),
    .data1 (ss_wram_data),
    .addr1 (ss_wram_addr),
    .we1   (ss_wram_we),
    .q1    (wram_scan_dout)
);

wire [14:0] ss_shared_addr;
wire [7:0]  ss_shared_data;
wire [0:0]  ss_shared_we;

dogyuun_ss_ram_port #(
    .WIDTH        (8),
    .ADDR_WIDTH   (15),
    .WE_WIDTH     (1),
    .SS_IDX       (8'd3),
    .STREAM_WIDTH (2'd0)
) u_shared_ss (
    .clk            (clk),
    .restore_enable (ss_restore_enable),
    .normal_we      (sound_shared_we),
    .normal_addr    (sound_shared_addr),
    .normal_data    (sound_shared_din),
    .ram_we         (ss_shared_we),
    .ram_addr       (ss_shared_addr),
    .ram_data       (ss_shared_data),
    .ram_q          (sound_shared_dout),
    .ss_data        (ss_data),
    .ss_addr        (ss_addr),
    .ss_select      (ss_select),
    .ss_write       (ss_write),
    .ss_read        (ss_read),
    .ss_query       (ss_query),
    .ss_data_out    (ss_shared_data_out),
    .ss_ack         (ss_shared_ack)
);

jtframe_dual_ram #(.DW(8), .AW(15)) u_shared_ram (
    .clk0  (clk),
    .data0 (cpu_dout[7:0]),
    .addr0 (cpu_addr8[15:1]),
    .we0   (shared_we),
    .q0    (shared_dout),
    .clk1  (sound_clk),
    .data1 (ss_shared_data),
    .addr1 (ss_shared_addr),
    .we1   (ss_shared_we[0]),
    .q1    (sound_shared_dout)
);

wire [10:0] ss_palette_addr;
wire [15:0] ss_palette_data;
wire [1:0]  ss_palette_we;

dogyuun_ss_ram_port #(
    .WIDTH        (16),
    .ADDR_WIDTH   (11),
    .WE_WIDTH     (2),
    .SS_IDX       (8'd4),
    .STREAM_WIDTH (2'd1)
) u_palette_ss (
    .clk            (clk),
    .restore_enable (ss_restore_enable),
    .normal_we      (2'b00),
    .normal_addr    (palette_scan_addr),
    .normal_data    (16'd0),
    .ram_we         (ss_palette_we),
    .ram_addr       (ss_palette_addr),
    .ram_data       (ss_palette_data),
    .ram_q          (palette_scan_dout),
    .ss_data        (ss_data),
    .ss_addr        (ss_addr),
    .ss_select      (ss_select),
    .ss_write       (ss_write),
    .ss_read        (ss_read),
    .ss_query       (ss_query),
    .ss_data_out    (ss_palette_data_out),
    .ss_ack         (ss_palette_ack)
);

jtframe_dual_ram16 #(.AW(11)) u_palette_ram (
    .clk0  (clk),
    .data0 (cpu_dout),
    .addr0 (cpu_addr8[11:1]),
    .we0   (palette_we),
    .q0    (palette_dout),
    .clk1  (clk),
    .data1 (ss_palette_data),
    .addr1 (ss_palette_addr),
    .we1   (ss_palette_we),
    .q1    (palette_scan_dout)
);

assign ss_ack = ss_wram_ack ||
                ss_shared_ack ||
                ss_palette_ack ||
                ss_gp0_ack ||
                ss_gp1_ack;
assign ss_data_out = ss_wram_ack ? ss_wram_data_out :
                     ss_shared_ack ? ss_shared_data_out :
                     ss_palette_ack ? ss_palette_data_out :
                     ss_gp0_ack ? ss_gp0_data_out :
                     ss_gp1_ack ? ss_gp1_data_out :
                     64'd0;

wire [15:0] cpu_din_mux =
    ss_handler_cs ? ss_irq_handler_word(cpu_addr8[4:1]) :
    ss_reset_vector_cs ? ss_reset_vector_word(cpu_addr8[2:1]) :
    ss_irq_vector_cs ? (cpu_addr8[1] ? 16'h0000 : 16'h00ff) :
    normal_rom_read_cs ? rom_data :
    wram_cs ? wram_dout :
    shared_cs ? {8'hff, shared_dout} :
    gp0_cs ? gp0_dout :
    gp1_cs ? gp1_dout :
    palette_cs ? palette_dout :
    in1_cs ? in1_data :
    in2_cs ? in2_data :
    sys_cs ? sys_data :
    vcount_cs ? vcount_data :
    16'hffff;

always @(posedge clk) begin
    if (cpu_core_reset)
        cpu_din <= 16'hffff;
    else if (cpu_read)
        cpu_din <= cpu_din_mux;
end

reg irq4_latch = 1'b0;
assign irq4 = irq4_latch;
always @(posedge clk) begin
    if (rst) begin
        irq4_latch <= 1'b0;
        irq_count <= 32'd0;
    end else if (ss_restore_commit) begin
        irq4_latch <= ss_restore_irq4;
    end else begin
        if (irq4_start) begin
            irq4_latch <= 1'b1;
            irq_count <= irq_count + 32'd1;
        end
        if (gp0_irq_clear || gp1_irq_clear)
            irq4_latch <= 1'b0;
    end
end

assign v25_reset_n = coin_control[5];

reg iack_seen = 1'b0;
always @(posedge clk) begin
    if (rst) begin
        ack_seen <= 1'b0;
        iack_seen <= 1'b0;
        coin_control <= 8'h00;
        last_program_fetch <= 24'h000000;
        bus_count <= 32'd0;
        rom_read_count <= 32'd0;
        wram_write_count <= 32'd0;
        shared_write_count <= 32'd0;
        gp_access_count <= 32'd0;
        palette_write_count <= 32'd0;
        io_access_count <= 32'd0;
        unmapped_count <= 32'd0;
        iack_count <= 32'd0;
    end else begin
        if (ss_reset) begin
            ack_seen <= 1'b0;
            iack_seen <= 1'b0;
        end else begin
            if (!cpu_bus_active)
                ack_seen <= 1'b0;
            else if (ack_now)
                ack_seen <= 1'b1;

            if (!cpu_iack)
                iack_seen <= 1'b0;
            else if (!iack_seen) begin
                iack_seen <= 1'b1;
                iack_count <= iack_count + 32'd1;
            end
        end

        if (ack_now) begin
            bus_count <= bus_count + 32'd1;
            if (normal_rom_read_cs) begin
                rom_read_count <= rom_read_count + 32'd1;
                if (cpu_program_space)
                    last_program_fetch <= cpu_addr8;
            end
            if (|wram_we)
                wram_write_count <= wram_write_count + 32'd1;
            if (shared_we)
                shared_write_count <= shared_write_count + 32'd1;
            if (gp_cs)
                gp_access_count <= gp_access_count + 32'd1;
            if (|palette_we)
                palette_write_count <= palette_write_count + 32'd1;
            if (io_cs)
                io_access_count <= io_access_count + 32'd1;
            if (unmapped_cs && !ss_special_cs)
                unmapped_count <= unmapped_count + 32'd1;
        end

        if (ss_restore_commit)
            coin_control <= ss_restore_coin_control;
        else if (ack_now && sound_ctrl_cs && cpu_write && !cpu_lds_n)
            coin_control <= cpu_dout[7:0];
    end
end

assign cpu_addr_debug = cpu_addr8;
assign cpu_dout_debug = cpu_dout;
assign cpu_din_debug = cpu_din;

endmodule
