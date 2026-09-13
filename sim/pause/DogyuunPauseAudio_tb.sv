`timescale 1ns/1ps

module dogyuun_v25_cpu #(
    parameter [7:0] SS_IDX = 8'd13,
    parameter integer BUS_PHASES_USE_CEN = 1,
    parameter integer BUS_BYTE_PHASES = 4,
    parameter integer SOUND_WRITE_EXTRA_PHASES = 17,
    parameter integer INSTRUCTION_GAP_PHASES = 0,
    parameter integer REGISTER_INC_GAP_PHASES = 0,
    parameter integer OPCODE_TIMING_PROFILE = 0,
    parameter integer TEST1_IMMEDIATE_DELAY = 19,
    parameter integer TEST1_MEMORY_DELAY = 0
) (
    input             clk,
    input             reset,
    input             reset_n,
    input             clock_enable,
    input      [7:0]  port0_in,
    input      [7:0]  port1_in,
    input      [7:0]  portt_in,
    output     [19:0] bus_addr,
    output     [7:0]  bus_dout,
    input      [7:0]  bus_din,
    output            bus_doe,
    output            bus_r_w,
    output            bus_mreq_n,
    output            bus_mstb_n,
    output            bus_iostb_n,
    output            halted,
    output            fault,
    output reg [19:0] debug_pc,
    output            state_idle,
    input             ss_restore_enable,
    input             ss_restore_commit,
    input      [63:0] ss_data,
    input      [31:0] ss_addr,
    input      [7:0]  ss_select,
    input             ss_write,
    input             ss_read,
    input             ss_query,
    output reg [63:0] ss_data_out,
    output reg        ss_ack
);

reg [7:0] busy_cens = 8'd0;
reg       test_write_active = 1'b0;
reg [19:0] test_write_addr = 20'd0;
reg [7:0] test_write_data = 8'd0;
reg [31:0] executed_cens = 32'd0;

assign bus_addr = test_write_addr;
assign bus_dout = test_write_data;
assign bus_doe = test_write_active;
assign bus_r_w = !test_write_active;
assign bus_mreq_n = !test_write_active;
assign bus_mstb_n = !test_write_active;
assign bus_iostb_n = 1'b1;
assign halted = 1'b0;
assign fault = 1'b0;
assign state_idle = (busy_cens == 8'd0) && !test_write_active;

always @(posedge clk) begin
    ss_ack <= 1'b0;
    if (reset || !reset_n) begin
        debug_pc <= 20'hffff0;
        executed_cens <= 32'd0;
        ss_data_out <= 64'd0;
    end else begin
        if (clock_enable) begin
            debug_pc <= debug_pc + 20'd1;
            executed_cens <= executed_cens + 32'd1;
            if (busy_cens != 8'd0)
                busy_cens <= busy_cens - 8'd1;
        end
        if (ss_query || ss_read || ss_write) begin
            ss_data_out <= {SS_IDX, 22'd0, 2'd3, 32'd1};
            ss_ack <= 1'b1;
        end
    end
end

endmodule

module dogyuun_opm (
    input                     rst,
    input                     clk,
    input                     cen,
    input                     cs_n,
    input                     wr_n,
    input                     a0,
    input              [7:0]  din,
    output             [7:0]  dout,
    output                    sample,
    output signed      [15:0] left,
    output signed      [15:0] right
);

reg [15:0] phase = 16'd0;
reg [15:0] host_write_count = 16'd0;
reg [7:0] last_host_data = 8'd0;

always @(posedge clk) begin
    if (rst) begin
        phase <= 16'd0;
        host_write_count <= 16'd0;
        last_host_data <= 8'd0;
    end else if (cen) begin
        phase <= phase + 16'd1;
        if (!cs_n && !wr_n) begin
            host_write_count <= host_write_count + 16'd1;
            last_host_data <= din;
        end
    end
end

assign dout = 8'h00;
assign sample = cen;
assign left = $signed({1'b0, phase[14:0]}) + 16'sd1000;
assign right = $signed({1'b0, phase[14:0]}) + 16'sd500;

endmodule

module jt6295 #(
    parameter INTERPOL = 0
) (
    input                    rst,
    input                    clk,
    input                    cen,
    input                    ss,
    input                    wrn,
    input      [7:0]         din,
    output     [7:0]         dout,
    output     [17:0]        rom_addr,
    input      [7:0]         rom_data,
    input                    rom_ok,
    output signed [13:0]     sound,
    output                   sample
);

reg [15:0] phase = 16'd0;
always @(posedge clk) begin
    if (rst)
        phase <= 16'd0;
    else if (cen)
        phase <= phase + 16'd1;
end

assign dout = 8'h00;
assign rom_addr = 18'd0;
assign sound = $signed({1'b0, phase[12:0]});
assign sample = cen;

endmodule

module DogyuunPauseAudio_tb;

reg clk = 1'b0;
reg reset = 1'b1;
reg v25_enable = 1'b1;
reg state_hold = 1'b0;
reg pause = 1'b0;
wire signed [15:0] snd_mono;
wire sample;
wire debug_v25_reset_n;
wire debug_v25_cen;
wire debug_ym_cen;
wire debug_ym_cen_p1;
wire debug_oki_cen;
wire [19:0] debug_pc;
wire state_idle;
wire state_held;
wire [14:0] shared_addr;
wire [7:0] shared_dout;
wire shared_we;
wire [17:0] oki_rom_addr;

integer checks = 0;
integer timeout;
integer drain_steps;
reg [19:0] held_pc;
reg [7:0] held_v25_accum;
reg [5:0] held_ym_divider;
reg [11:0] held_oki_accum;
reg [15:0] held_ym_phase;
reg [15:0] held_oki_phase;
reg signed [19:0] held_mixer_previous;
reg [5:0] held_ym_reset_count;
reg [1:0] held_oki_reset_state;
reg [3:0] held_bgm_state;
reg [15:0] held_host_write_count;

always #5 clk = ~clk;

task automatic check(input condition, input [8*120-1:0] message);
begin
    checks = checks + 1;
    if (!condition) begin
        $display("FAIL: %0s", message);
        $finish;
    end
end
endtask

dogyuun_sound dut (
    .reset               (reset),
    .clk                 (clk),
    .v25_enable          (v25_enable),
    .dip_a               (8'h00),
    .dip_b               (8'h00),
    .region              (8'h30),
    .ym_enable           (1'b1),
    .oki_enable          (1'b1),
    .state_hold          (state_hold),
    .pause               (pause),
    .ss_restore_enable   (1'b0),
    .ss_restore_commit   (1'b0),
    .ss_data             (64'd0),
    .ss_addr             (32'd0),
    .ss_select           (8'd0),
    .ss_write            (1'b0),
    .ss_read             (1'b0),
    .ss_query            (1'b0),
    .ss_data_out         (),
    .ss_ack              (),
    .shared_addr         (shared_addr),
    .shared_dout         (shared_dout),
    .shared_we           (shared_we),
    .shared_din          (8'h00),
    .oki_rom_addr        (oki_rom_addr),
    .oki_rom_data        (8'h00),
    .oki_rom_ok          (1'b1),
    .snd_mono            (snd_mono),
    .sample              (sample),
    .debug_fault         (),
    .debug_halted        (),
    .debug_pc            (debug_pc),
    .debug_state_idle    (),
    .state_idle          (state_idle),
    .state_held          (state_held),
    .debug_v25_reset_n   (debug_v25_reset_n),
    .debug_ym_write      (),
    .debug_ym_a0         (),
    .debug_ym_data       (),
    .debug_oki_write     (),
    .debug_oki_data      (),
    .debug_v25_cen       (debug_v25_cen),
    .debug_ym_cen        (debug_ym_cen),
    .debug_ym_cen_p1     (debug_ym_cen_p1),
    .debug_oki_cen       (debug_oki_cen),
    .debug_oki_status    (),
    .debug_oki_sound     ()
);

initial begin
    repeat (8) @(negedge clk);
    reset = 1'b0;

    timeout = 0;
    while ((!dut.sound_ready || !debug_v25_reset_n) && timeout < 50000) begin
        @(negedge clk);
        timeout = timeout + 1;
    end
    check(timeout < 50000, "sound domain did not complete deterministic startup");

    timeout = 0;
    while (snd_mono == 16'sd0 && timeout < 1000) begin
        @(negedge clk);
        timeout = timeout + 1;
    end
    check(timeout < 1000, "test sound never became nonzero before pause");
    check(dut.bgm_replay_state == dut.BGM_REPLAY_IDLE,
          "BGM replay was unexpectedly active before pause");

    @(negedge clk);
    dut.u_v25.busy_cens = 8'd4;
    dut.u_v25.test_write_addr = 20'h00001;
    dut.u_v25.test_write_data = 8'h5a;
    dut.u_v25.test_write_active = 1'b1;
    drain_steps = dut.u_v25.executed_cens;
    pause = 1'b1;
    #1;
    check(snd_mono === 16'sd0, "pause did not mute the digital output immediately");

    repeat (3) begin
        @(negedge clk);
        check(snd_mono === 16'sd0, "audio escaped mute while the V25 transaction drained");
    end
    dut.u_v25.test_write_active = 1'b0;

    timeout = 0;
    while (!dut.pause_held && timeout < 5000) begin
        @(negedge clk);
        timeout = timeout + 1;
        check(snd_mono === 16'sd0, "audio escaped mute before the pause boundary");
    end
    check(timeout < 5000, "pause did not reach a quiescent sound boundary");
    check(dut.u_v25.executed_cens > drain_steps,
          "pause stopped the V25 before its in-flight operation drained");
    check(dut.u_ym2151.host_write_count != 16'd0,
          "in-flight YM write was discarded instead of draining");
    check(dut.u_ym2151.last_host_data == 8'h5a,
          "drained YM write carried the wrong data");
    check(!dut.ym_write_pending && dut.ym_cs_n && dut.ym_wr_n,
          "pause boundary retained an incomplete YM host transaction");

    held_pc = debug_pc;
    held_v25_accum = dut.v25_cen_accum;
    held_ym_divider = dut.ym_divider;
    held_oki_accum = dut.oki_cen_accum;
    held_ym_phase = dut.u_ym2151.phase;
    held_oki_phase = dut.u_oki6295.phase;
    held_mixer_previous = dut.u_mixer.previous_scaled;
    held_ym_reset_count = dut.ym_reset_count;
    held_oki_reset_state = dut.oki_reset_state;
    held_bgm_state = dut.bgm_replay_state;
    held_host_write_count = dut.u_ym2151.host_write_count;

    repeat (1000) begin
        @(negedge clk);
        check(snd_mono === 16'sd0, "paused output was not digital silence");
        check(!debug_v25_cen && !debug_ym_cen && !debug_ym_cen_p1 &&
              !debug_oki_cen && !sample,
              "an audio clock enable advanced after pause acknowledgement");
        check(debug_pc == held_pc, "V25 PC changed while paused");
        check(dut.v25_cen_accum == held_v25_accum,
              "V25 fractional divider changed while paused");
        check(dut.ym_divider == held_ym_divider,
              "YM divider changed while paused");
        check(dut.oki_cen_accum == held_oki_accum,
              "OKI fractional divider changed while paused");
        check(dut.u_ym2151.phase == held_ym_phase,
              "YM playback state changed while paused");
        check(dut.u_oki6295.phase == held_oki_phase,
              "OKI playback state changed while paused");
        check(dut.u_mixer.previous_scaled == held_mixer_previous,
              "mixer filter state changed while paused");
        check(dut.ym_reset_count == held_ym_reset_count &&
              dut.oki_reset_state == held_oki_reset_state &&
              debug_v25_reset_n,
              "pause restarted a sound device");
        check(dut.bgm_replay_state == held_bgm_state,
              "BGM sequencer changed while paused");
        check(!shared_we, "sound bridge wrote shared RAM while paused");
    end

    pause = 1'b0;
    @(negedge clk);
    check(!dut.pause_held, "pause acknowledgement did not clear on release");
    check(debug_v25_reset_n, "unpause reset the V25");
    check(dut.bgm_replay_state == dut.BGM_REPLAY_IDLE,
          "unpause restarted the BGM replay sequencer");

    timeout = 0;
    while ((debug_pc == held_pc ||
            dut.u_ym2151.phase == held_ym_phase ||
            dut.u_oki6295.phase == held_oki_phase ||
            snd_mono == 16'sd0) && timeout < 5000) begin
        @(negedge clk);
        timeout = timeout + 1;
    end
    check(timeout < 5000, "sound state did not resume from the held point");
    check(dut.u_ym2151.host_write_count == held_host_write_count,
          "unpause duplicated the drained YM transaction");
    check(dut.ym_reset_count == held_ym_reset_count &&
          dut.oki_reset_state == held_oki_reset_state,
          "unpause restarted a sound device instead of resuming it");

    @(negedge clk);
    dut.u_v25.busy_cens = 8'd3;
    state_hold = 1'b1;
    timeout = 0;
    while (!state_held && timeout < 5000) begin
        @(negedge clk);
        timeout = timeout + 1;
    end
    check(timeout < 5000, "save-state hold no longer drained to idle");
    held_pc = debug_pc;
    repeat (200) begin
        @(negedge clk);
        check(state_held && debug_pc == held_pc,
              "save-state hold regressed after pause integration");
    end
    state_hold = 1'b0;
    @(negedge clk);
    check(!state_held, "save-state hold did not release");

    $display("PASS: Dogyuun pause audio boundary (%0d checks)", checks);
    $finish;
end

endmodule
