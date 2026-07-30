// SPDX-License-Identifier: BSD-3-Clause
//
// Dogyuun TP-022 sound subsystem. All logic remains synchronous to the
// 94.5 MHz game clock; exact board rates are generated as clock enables.

module dogyuun_sound #(
    parameter integer V25_BUS_PHASES_USE_CEN = 1,
    parameter integer V25_BUS_BYTE_PHASES = 4,
    parameter integer V25_SOUND_WRITE_EXTRA_PHASES = 17,
    parameter integer V25_INSTRUCTION_GAP_PHASES = 1,
    parameter integer V25_REGISTER_INC_GAP_PHASES = 4,
    parameter integer V25_OPCODE_TIMING_PROFILE = 1,
    parameter integer V25_TEST1_IMMEDIATE_DELAY = 26,
    parameter integer V25_TEST1_MEMORY_DELAY = 4
) (
    input                       reset,
    input                       clk,
    input                       v25_enable,
    input      [7:0]            dip_a,
    input      [7:0]            dip_b,
    input      [7:0]            region,
    input                       ym_enable,
    input                       oki_enable,
    input                       state_hold,

    input                       ss_restore_enable,
    input                       ss_restore_commit,
    input      [63:0]           ss_data,
    input      [31:0]           ss_addr,
    input      [7:0]            ss_select,
    input                       ss_write,
    input                       ss_read,
    input                       ss_query,
    output     [63:0]           ss_data_out,
    output                      ss_ack,

    output     [14:0]           shared_addr,
    output     [7:0]            shared_dout,
    output                      shared_we,
    input      [7:0]            shared_din,

    output     [17:0]           oki_rom_addr,
    input      [7:0]            oki_rom_data,
    input                       oki_rom_ok,

    output signed [15:0]        snd_mono,
    output                      sample,

    output                      debug_fault,
    output                      debug_halted,
    output     [19:0]           debug_pc,
    output                      debug_state_idle,
    output                      state_idle,
    output                      state_held,
    output                      debug_v25_reset_n,
    output reg                  debug_ym_write,
    output reg                  debug_ym_a0,
    output reg [7:0]            debug_ym_data,
    output reg                  debug_oki_write,
    output reg [7:0]            debug_oki_data,
    output                      debug_v25_cen,
    output                      debug_ym_cen,
    output                      debug_ym_cen_p1,
    output                      debug_oki_cen,
    output     [7:0]            debug_oki_status,
    output signed [13:0]        debug_oki_sound
);

localparam [19:0] YM_ADDR  = 20'h00000;
localparam [19:0] YM_DATA  = 20'h00001;
localparam [19:0] OKI_DATA = 20'h00004;
wire sound_domain_reset = reset || ss_restore_commit;

reg [7:0] v25_cen_accum = 8'd0;
reg       v25_cen = 1'b0;
always @(posedge clk) begin
    if (sound_domain_reset) begin
        v25_cen_accum <= 8'd0;
        v25_cen <= 1'b0;
    end else if (v25_cen_accum >= 8'd164) begin
        v25_cen_accum <= v25_cen_accum + 8'd25 - 8'd189;
        v25_cen <= 1'b1;
    end else begin
        v25_cen_accum <= v25_cen_accum + 8'd25;
        v25_cen <= 1'b0;
    end
end

reg [5:0] ym_divider = 6'd0;
reg       ym_cen = 1'b0;
reg       ym_cen_p1 = 1'b0;
always @(posedge clk) begin
    ym_cen <= 1'b0;
    ym_cen_p1 <= 1'b0;
    if (sound_domain_reset) begin
        ym_divider <= 6'd0;
    end else if (ym_divider == 6'd55) begin
        ym_divider <= 6'd0;
        ym_cen <= 1'b1;
        ym_cen_p1 <= 1'b1;
    end else begin
        ym_divider <= ym_divider + 6'd1;
        if (ym_divider == 6'd27)
            ym_cen <= 1'b1;
    end
end

// 94.5 MHz * 25 / 2268 = 25 MHz / 24 exactly.
reg [11:0] oki_cen_accum = 12'd0;
reg        oki_cen = 1'b0;
always @(posedge clk) begin
    oki_cen <= 1'b0;
    if (sound_domain_reset) begin
        oki_cen_accum <= 12'd0;
    end else if (oki_cen_accum >= 12'd2243) begin
        oki_cen_accum <= oki_cen_accum + 12'd25 - 12'd2268;
        oki_cen <= 1'b1;
    end else begin
        oki_cen_accum <= oki_cen_accum + 12'd25;
    end
end

// Hold reset through a complete OPM slot rotation before releasing the chip.
reg [5:0] ym_reset_count = 6'd0;
always @(posedge clk or posedge sound_domain_reset) begin
    if (sound_domain_reset)
        ym_reset_count <= 6'd0;
    else if (!ym_reset_count[5] && ym_cen_p1)
        ym_reset_count <= ym_reset_count + 6'd1;
end
wire ym_reset = sound_domain_reset || !ym_reset_count[5];
wire ym_ready = !ym_reset;

// JT6295's channel acknowledge shift register has no reset. Prime one full
// rotation, assert decoder reset, then release from a known state.
reg [1:0]  oki_reset_state = 2'd0;
reg [13:0] oki_reset_timer = 14'd0;
reg        oki_reset = 1'b1;
reg        oki_ready = 1'b0;
always @(posedge clk or posedge sound_domain_reset) begin
    if (sound_domain_reset) begin
        oki_reset_state <= 2'd0;
        oki_reset_timer <= 14'd0;
        oki_reset <= 1'b1;
        oki_ready <= 1'b0;
    end else begin
        case (oki_reset_state)
            2'd0: begin
                oki_reset <= 1'b0;
                if (&oki_reset_timer) begin
                    oki_reset_state <= 2'd1;
                    oki_reset_timer <= 14'd0;
                    oki_reset <= 1'b1;
                end else begin
                    oki_reset_timer <= oki_reset_timer + 14'd1;
                end
            end
            2'd1: begin
                oki_reset <= 1'b1;
                if (oki_reset_timer == 14'd15) begin
                    oki_reset_state <= 2'd2;
                    oki_reset_timer <= 14'd0;
                    oki_reset <= 1'b0;
                    oki_ready <= 1'b1;
                end else begin
                    oki_reset_timer <= oki_reset_timer + 14'd1;
                end
            end
            default: begin
                oki_reset <= 1'b0;
                oki_ready <= 1'b1;
            end
        endcase
    end
end

wire sound_ready = ym_ready && oki_ready;
// Qualify only the initial V25 release with device readiness. Once the V25
// has started, a save-state chip restart must not feed an asynchronous reset
// through a commit-to-flag combinational handoff.
reg v25_started = 1'b0;
always @(posedge clk or posedge reset) begin
    if (reset)
        v25_started <= 1'b0;
    else if (!v25_enable)
        v25_started <= 1'b0;
    else if (sound_ready)
        v25_started <= 1'b1;
end

wire v25_reset_async = reset ||
                       !v25_enable ||
                       !v25_started;
reg [1:0] v25_reset_pipe = 2'b11;
always @(posedge clk or posedge v25_reset_async) begin
    if (v25_reset_async)
        v25_reset_pipe <= 2'b11;
    else
        v25_reset_pipe <= {v25_reset_pipe[0], 1'b0};
end
wire v25_reset_n = !v25_reset_pipe[1];

wire [19:0] v25_bus_addr;
wire [7:0]  v25_bus_dout;
reg  [7:0]  v25_bus_din;
wire        v25_bus_doe;
wire        v25_bus_r_w;
wire        v25_bus_mreq_n;
wire        v25_bus_mstb_n;
wire        v25_bus_iostb_n;
wire        v25_state_idle;
wire [63:0] v25_ss_data_out;
wire        v25_ss_ack;
wire        restored_bgm_valid;
wire [7:0]  restored_bgm_command;
wire [7:0]  restored_bgm_argument;

localparam [3:0]
    BGM_REPLAY_IDLE               = 4'd0,
    BGM_REPLAY_WAIT_READY         = 4'd1,
    BGM_REPLAY_WRITE_STOP_ARG     = 4'd2,
    BGM_REPLAY_WRITE_STOP_COMMAND = 4'd3,
    BGM_REPLAY_RELEASE_STOP       = 4'd4,
    BGM_REPLAY_WAIT_STOP_ACK      = 4'd5,
    BGM_REPLAY_WRITE_ARG          = 4'd6,
    BGM_REPLAY_WRITE_COMMAND      = 4'd7,
    BGM_REPLAY_RELEASE            = 4'd8,
    BGM_REPLAY_WAIT_ACK           = 4'd9;

reg [3:0] bgm_replay_state = BGM_REPLAY_IDLE;
reg [7:0] bgm_replay_command = 8'h00;
reg [7:0] bgm_replay_argument = 8'h00;
reg [3:0] bgm_replay_wait_count = 4'd0;
wire bgm_replay_write_stop_argument =
    bgm_replay_state == BGM_REPLAY_WRITE_STOP_ARG;
wire bgm_replay_write_stop_command =
    bgm_replay_state == BGM_REPLAY_WRITE_STOP_COMMAND;
wire bgm_replay_write_argument =
    bgm_replay_state == BGM_REPLAY_WRITE_ARG;
wire bgm_replay_write_command =
    bgm_replay_state == BGM_REPLAY_WRITE_COMMAND;
wire bgm_replay_hold_v25 =
    (bgm_replay_state == BGM_REPLAY_WAIT_READY) ||
    (bgm_replay_state == BGM_REPLAY_WRITE_STOP_ARG) ||
    (bgm_replay_state == BGM_REPLAY_WRITE_STOP_COMMAND) ||
    (bgm_replay_state == BGM_REPLAY_RELEASE_STOP) ||
    (bgm_replay_state == BGM_REPLAY_WRITE_ARG) ||
    (bgm_replay_state == BGM_REPLAY_WRITE_COMMAND) ||
    (bgm_replay_state == BGM_REPLAY_RELEASE);
wire bgm_replay_active = bgm_replay_state != BGM_REPLAY_IDLE;
wire v25_hold_boundary =
    state_hold && v25_state_idle && !bgm_replay_active;

dogyuun_v25_cpu #(
    .BUS_PHASES_USE_CEN (V25_BUS_PHASES_USE_CEN),
    .BUS_BYTE_PHASES    (V25_BUS_BYTE_PHASES),
    .SOUND_WRITE_EXTRA_PHASES (V25_SOUND_WRITE_EXTRA_PHASES),
    .INSTRUCTION_GAP_PHASES (V25_INSTRUCTION_GAP_PHASES),
    .REGISTER_INC_GAP_PHASES (V25_REGISTER_INC_GAP_PHASES),
    .OPCODE_TIMING_PROFILE (V25_OPCODE_TIMING_PROFILE),
    .TEST1_IMMEDIATE_DELAY (V25_TEST1_IMMEDIATE_DELAY),
    .TEST1_MEMORY_DELAY (V25_TEST1_MEMORY_DELAY)
) u_v25 (
    .clk               (clk),
    .reset             (reset),
    .reset_n           (v25_reset_n),
    // A hold request may arrive in the middle of an instruction or bus cycle.
    // Let that operation drain, then stop before the next instruction starts.
    .clock_enable      (v25_cen && !v25_hold_boundary &&
                        !bgm_replay_hold_v25),
    .port0_in          (~dip_a),
    .port1_in          (~region),
    .portt_in          (~dip_b),
    .bus_addr          (v25_bus_addr),
    .bus_dout          (v25_bus_dout),
    .bus_din           (v25_bus_din),
    .bus_doe           (v25_bus_doe),
    .bus_r_w           (v25_bus_r_w),
    .bus_mreq_n        (v25_bus_mreq_n),
    .bus_mstb_n        (v25_bus_mstb_n),
    .bus_iostb_n       (v25_bus_iostb_n),
    .halted            (debug_halted),
    .fault             (debug_fault),
    .debug_pc          (debug_pc),
    .state_idle        (v25_state_idle),
    .ss_restore_enable (ss_restore_enable),
    .ss_restore_commit (ss_restore_commit),
    .ss_data           (ss_data),
    .ss_addr           (ss_addr),
    .ss_select         (ss_select),
    .ss_write          (ss_write),
    .ss_read           (ss_read),
    .ss_query          (ss_query),
    .ss_data_out       (v25_ss_data_out),
    .ss_ack            (v25_ss_ack)
);

wire v25_mem_active = !v25_bus_mreq_n && !v25_bus_mstb_n;
wire v25_write_active = v25_mem_active && !v25_bus_r_w && v25_bus_doe;
reg  v25_write_active_d = 1'b0;
wire v25_write_start = v25_write_active && !v25_write_active_d;
wire v25_shared_cs = v25_bus_addr[19];
wire v25_mailbox_ready_write =
    v25_write_start && v25_shared_cs &&
    (v25_bus_addr[14:0] == 15'h7800) &&
    (v25_bus_dout == 8'hff);
wire v25_shared_read_active =
    v25_mem_active && v25_bus_r_w && v25_shared_cs;
reg v25_shared_read_active_d = 1'b0;
reg [14:0] v25_shared_read_addr_d = 15'd0;
wire v25_shared_read_stable =
    v25_shared_read_active &&
    v25_shared_read_active_d &&
    (v25_bus_addr[14:0] == v25_shared_read_addr_d);

reg [7:0] bgm_pending_command = 8'h00;
reg [7:0] bgm_pending_argument = 8'h00;
reg       bgm_pending_valid = 1'b0;
reg       bgm_pending_argument_valid = 1'b0;
reg [7:0] sound_bgm_command = 8'h00;
reg [7:0] sound_bgm_argument = 8'h00;
reg       sound_bgm_valid = 1'b0;

function automatic dogyuun_music_command;
    input [7:0] command;
    begin
        dogyuun_music_command =
            (command >= 8'h01 && command <= 8'h06) ||
            (command >= 8'h40 && command <= 8'h45);
    end
endfunction

// Observe the command and argument as the V25 consumes them. This is after
// the synchronous shared-RAM read has settled, so an SFX write cannot replace
// the saved music intent merely because it was the latest 68000 transaction.
always @(posedge clk) begin
    if (reset) begin
        v25_shared_read_active_d <= 1'b0;
        v25_shared_read_addr_d <= 15'd0;
        bgm_pending_command <= 8'h00;
        bgm_pending_argument <= 8'h00;
        bgm_pending_valid <= 1'b0;
        bgm_pending_argument_valid <= 1'b0;
        sound_bgm_command <= 8'h00;
        sound_bgm_argument <= 8'h00;
        sound_bgm_valid <= 1'b0;
    end else begin
        v25_shared_read_active_d <= v25_shared_read_active;
        v25_shared_read_addr_d <= v25_bus_addr[14:0];

        if (ss_restore_commit && ss_restore_enable) begin
            bgm_pending_command <= 8'h00;
            bgm_pending_argument <= 8'h00;
            bgm_pending_valid <= 1'b0;
            bgm_pending_argument_valid <= 1'b0;
            sound_bgm_command <= restored_bgm_command;
            sound_bgm_argument <= restored_bgm_argument;
            sound_bgm_valid <= restored_bgm_valid;
        end else begin
            if (v25_shared_read_stable &&
                v25_bus_addr[14:0] == 15'h7800 &&
                !bgm_pending_valid &&
                shared_din != 8'hff && shared_din != 8'haa) begin
                bgm_pending_command <= shared_din;
                bgm_pending_argument <= 8'h00;
                bgm_pending_valid <= 1'b1;
                bgm_pending_argument_valid <= 1'b0;
            end else if (v25_shared_read_stable &&
                         v25_bus_addr[14:0] == 15'h7801 &&
                         bgm_pending_valid) begin
                bgm_pending_argument <= shared_din;
                bgm_pending_argument_valid <= 1'b1;
            end

            // Commit exactly once when the V25 acknowledges the mailbox.
            // A command may be read repeatedly before this FF write.
            if (v25_mailbox_ready_write) begin
                if (bgm_pending_valid && bgm_pending_argument_valid &&
                    bgm_pending_command == 8'h00 &&
                    bgm_pending_argument == 8'h01) begin
                    sound_bgm_valid <= 1'b0;
                end else if (bgm_pending_valid &&
                             bgm_pending_argument_valid &&
                             dogyuun_music_command(bgm_pending_command) &&
                             bgm_pending_argument == 8'h00) begin
                    sound_bgm_command <= bgm_pending_command;
                    sound_bgm_argument <= bgm_pending_argument;
                    sound_bgm_valid <= 1'b1;
                end
                bgm_pending_valid <= 1'b0;
                bgm_pending_argument_valid <= 1'b0;
            end
        end
    end
end

// The external chips restart on load, while the held V25 architecture,
// internal RAM, and shared RAM resume coherently. Repeating an active BGM
// command does not make the retained driver rewrite all OPM instruments.
// Stop the driver first, wait for its acknowledgement, then restart the
// restored BGM so the freshly reset OPM receives complete channel state.
always @(posedge clk or posedge reset) begin
    if (reset) begin
        bgm_replay_state <= BGM_REPLAY_IDLE;
        bgm_replay_command <= 8'h00;
        bgm_replay_argument <= 8'h00;
        bgm_replay_wait_count <= 4'd0;
    end else if (ss_restore_commit && ss_restore_enable) begin
        bgm_replay_state <= restored_bgm_valid ?
                            BGM_REPLAY_WAIT_READY : BGM_REPLAY_IDLE;
        bgm_replay_command <= restored_bgm_command;
        bgm_replay_argument <= restored_bgm_argument;
        bgm_replay_wait_count <= 4'd0;
    end else begin
        case (bgm_replay_state)
            BGM_REPLAY_WAIT_READY: begin
                if (!sound_ready) begin
                    bgm_replay_wait_count <= 4'd0;
                end else if (bgm_replay_wait_count == 4'd8) begin
                    bgm_replay_state <= BGM_REPLAY_WRITE_STOP_ARG;
                    bgm_replay_wait_count <= 4'd0;
                end else begin
                    bgm_replay_wait_count <=
                        bgm_replay_wait_count + 4'd1;
                end
            end
            BGM_REPLAY_WRITE_STOP_ARG:
                bgm_replay_state <= BGM_REPLAY_WRITE_STOP_COMMAND;
            BGM_REPLAY_WRITE_STOP_COMMAND:
                bgm_replay_state <= BGM_REPLAY_RELEASE_STOP;
            BGM_REPLAY_RELEASE_STOP:
                bgm_replay_state <= BGM_REPLAY_WAIT_STOP_ACK;
            BGM_REPLAY_WAIT_STOP_ACK: begin
                if (v25_mailbox_ready_write)
                    bgm_replay_state <= BGM_REPLAY_WRITE_ARG;
            end
            BGM_REPLAY_WRITE_ARG:
                bgm_replay_state <= BGM_REPLAY_WRITE_COMMAND;
            BGM_REPLAY_WRITE_COMMAND:
                bgm_replay_state <= BGM_REPLAY_RELEASE;
            BGM_REPLAY_RELEASE:
                bgm_replay_state <= BGM_REPLAY_WAIT_ACK;
            BGM_REPLAY_WAIT_ACK: begin
                if (v25_mailbox_ready_write)
                    bgm_replay_state <= BGM_REPLAY_IDLE;
            end
            default:
                bgm_replay_state <= BGM_REPLAY_IDLE;
        endcase
    end
end

assign shared_addr = (bgm_replay_write_stop_argument ||
                      bgm_replay_write_argument) ? 15'h7801 :
                     (bgm_replay_write_stop_command ||
                      bgm_replay_write_command) ? 15'h7800 :
                     v25_bus_addr[14:0];
assign shared_dout = bgm_replay_write_stop_argument ? 8'h01 :
                     bgm_replay_write_stop_command ? 8'h00 :
                     bgm_replay_write_argument ? bgm_replay_argument :
                     bgm_replay_write_command ? bgm_replay_command :
                     v25_bus_dout;
assign shared_we = bgm_replay_write_stop_argument ||
                   bgm_replay_write_stop_command ||
                   bgm_replay_write_argument ||
                   bgm_replay_write_command ||
                   (v25_write_start && v25_shared_cs);

wire [7:0] ym_dout;
wire [7:0] oki_dout;
always @(*) begin
    v25_bus_din = 8'h00;
    if (v25_mem_active && v25_bus_r_w) begin
        if (v25_shared_cs)
            v25_bus_din = shared_din;
        else if (v25_bus_addr == YM_DATA)
            v25_bus_din = ym_dout;
        else if (v25_bus_addr == OKI_DATA)
            v25_bus_din = oki_dout;
    end
end

reg       ym_cs_n = 1'b1;
reg       ym_wr_n = 1'b1;
reg       ym_host_a0 = 1'b0;
reg [7:0] ym_host_data = 8'h00;
reg       ym_write_pending = 1'b0;
reg       oki_wr_n = 1'b1;
reg [7:0] oki_host_data = 8'h00;

wire [63:0] restore_ss_data_out;
wire        restore_ss_ack;

dogyuun_sound_restore u_sound_restore (
    .clk                 (clk),
    .reset               (reset),
    .live_bgm_valid      (sound_bgm_valid),
    .live_bgm_command    (sound_bgm_command),
    .live_bgm_argument   (sound_bgm_argument),
    .restored_bgm_valid  (restored_bgm_valid),
    .restored_bgm_command(restored_bgm_command),
    .restored_bgm_argument(restored_bgm_argument),
    .ss_restore_enable   (ss_restore_enable),
    .ss_data             (ss_data),
    .ss_addr             (ss_addr),
    .ss_select           (ss_select),
    .ss_write            (ss_write),
    .ss_read             (ss_read),
    .ss_query            (ss_query),
    .ss_data_out         (restore_ss_data_out),
    .ss_ack              (restore_ss_ack)
);

assign ss_data_out = restore_ss_ack ? restore_ss_data_out : v25_ss_data_out;
assign ss_ack = restore_ss_ack || v25_ss_ack;

always @(posedge clk) begin
    if (!v25_reset_n) begin
        v25_write_active_d <= 1'b0;
        ym_cs_n <= 1'b1;
        ym_wr_n <= 1'b1;
        ym_host_a0 <= 1'b0;
        ym_host_data <= 8'h00;
        ym_write_pending <= 1'b0;
        oki_wr_n <= 1'b1;
        oki_host_data <= 8'h00;
        debug_ym_write <= 1'b0;
        debug_ym_a0 <= 1'b0;
        debug_ym_data <= 8'h00;
        debug_oki_write <= 1'b0;
        debug_oki_data <= 8'h00;
    end else begin
        v25_write_active_d <= v25_write_active;
        oki_wr_n <= 1'b1;
        debug_ym_write <= 1'b0;
        debug_oki_write <= 1'b0;

        // Hold each V25 write through cen_p1 so the fully synchronous OPM
        // host synchronizer cannot lose a transaction between phiM ticks.
        if (ym_write_pending) begin
            ym_cs_n <= 1'b0;
            ym_wr_n <= 1'b0;
            if (ym_cen_p1) begin
                ym_cs_n <= 1'b1;
                ym_wr_n <= 1'b1;
                ym_write_pending <= 1'b0;
            end
        end else begin
            ym_cs_n <= 1'b1;
            ym_wr_n <= 1'b1;
        end

        if (v25_write_start && !v25_shared_cs) begin
            if (v25_bus_addr == YM_ADDR ||
                v25_bus_addr == YM_DATA) begin
                ym_cs_n <= 1'b0;
                ym_wr_n <= 1'b0;
                ym_host_a0 <= v25_bus_addr[0];
                ym_host_data <= v25_bus_dout;
                ym_write_pending <= 1'b1;
                debug_ym_write <= 1'b1;
                debug_ym_a0 <= v25_bus_addr[0];
                debug_ym_data <= v25_bus_dout;
            end else if (v25_bus_addr == OKI_DATA) begin
                oki_wr_n <= 1'b0;
                oki_host_data <= v25_bus_dout;
                debug_oki_write <= 1'b1;
                debug_oki_data <= v25_bus_dout;
            end
        end
    end
end

wire ym_sample;
wire signed [15:0] ym_left;
wire signed [15:0] ym_right;
wire ym_chip_reset = ym_reset;

dogyuun_opm u_ym2151 (
    .rst    (ym_chip_reset),
    .clk    (clk),
    .cen    (ym_cen),
    .cs_n   (ym_cs_n),
    .wr_n   (ym_wr_n),
    .a0     (ym_host_a0),
    .din    (ym_host_data),
    .dout   (ym_dout),
    .sample (ym_sample),
    .left   (ym_left),
    .right  (ym_right)
);

wire signed [13:0] oki_sound;
wire oki_sample;
wire oki_chip_reset = oki_reset;
jt6295 #(.INTERPOL(0)) u_oki6295 (
    .rst      (oki_chip_reset),
    .clk      (clk),
    .cen      (oki_cen),
    .ss       (1'b1),
    .wrn      (oki_wr_n),
    .din      (oki_host_data),
    .dout     (oki_dout),
    .rom_addr (oki_rom_addr),
    .rom_data (oki_rom_data),
    .rom_ok   (oki_rom_ok),
    .sound    (oki_sound),
    .sample   (oki_sample)
);

dogyuun_sound_mixer u_mixer (
    .clk        (clk),
    .reset      (ym_chip_reset),
    .sample     (ym_sample),
    .ym_left    (ym_left),
    .ym_right   (ym_right),
    .oki        (oki_sound),
    .ym_enable  (ym_enable),
    .oki_enable (oki_enable),
    .oki_ready  (oki_ready),
    .mono       (snd_mono)
);

assign sample = ym_sample;
assign debug_state_idle = v25_state_idle;
assign state_idle = v25_state_idle &&
                    !v25_write_active &&
                    !ym_write_pending &&
                    !bgm_replay_active &&
                    ym_cs_n && ym_wr_n && oki_wr_n;
assign state_held = state_hold && state_idle;
assign debug_v25_reset_n = v25_reset_n;
assign debug_v25_cen = v25_cen;
assign debug_ym_cen = ym_cen;
assign debug_ym_cen_p1 = ym_cen_p1;
assign debug_oki_cen = oki_cen;
assign debug_oki_status = oki_dout;
assign debug_oki_sound = oki_sound;

endmodule

module dogyuun_sound_restore #(
    parameter [7:0] SS_IDX = 8'd14
) (
    input             clk,
    input             reset,
    input             live_bgm_valid,
    input      [7:0]  live_bgm_command,
    input      [7:0]  live_bgm_argument,
    output reg        restored_bgm_valid,
    output reg [7:0]  restored_bgm_command,
    output reg [7:0]  restored_bgm_argument,

    input             ss_restore_enable,
    input      [63:0] ss_data,
    input      [31:0] ss_addr,
    input      [7:0]  ss_select,
    input             ss_write,
    input             ss_read,
    input             ss_query,
    output reg [63:0] ss_data_out,
    output reg        ss_ack
);

// Keep index 14 at its established 258-word geometry so existing states and
// the stream controller remain compatible. Legacy YM image words are accepted
// and read as zero; word 257 uses previously-zero bits for music intent.
localparam [31:0] SS_WORD_COUNT = 32'd258;
wire ss_selected = ss_select == SS_IDX;

always @(posedge clk) begin
    ss_ack <= 1'b0;

    if (reset) begin
        ss_data_out <= 64'd0;
        restored_bgm_valid <= 1'b0;
        restored_bgm_command <= 8'h00;
        restored_bgm_argument <= 8'h00;
    end else if (ss_selected) begin
        if (ss_query) begin
            ss_data_out <= {SS_IDX, 22'd0, 2'd3, SS_WORD_COUNT};
            ss_ack <= 1'b1;
        end else if (ss_write) begin
            if (ss_restore_enable && ss_addr == 32'd0) begin
                restored_bgm_valid <= 1'b0;
                restored_bgm_command <= 8'h00;
                restored_bgm_argument <= 8'h00;
            end
            if (ss_restore_enable && ss_addr == 32'd257) begin
                restored_bgm_command <= ss_data[31:24];
                restored_bgm_argument <= ss_data[39:32];
                restored_bgm_valid <= ss_data[40];
            end
            ss_ack <= 1'b1;
        end else if (ss_read) begin
            if (ss_addr == 32'd257) begin
                ss_data_out <= {
                    23'd0,
                    live_bgm_valid,
                    live_bgm_argument,
                    live_bgm_command,
                    24'd0
                };
            end else begin
                ss_data_out <= 64'd0;
            end
            ss_ack <= 1'b1;
        end
    end
end

endmodule
